#if os(iOS) || os(macOS)
import Foundation
import MetricKit
import Observation
import OSLog

/// Crash reports from MetricKit, sent to the HK Softworks feedback service only when the person agrees.
///
/// Create one when the app launches and call ``start()`` straight away: MetricKit hands over a crash's report on the
/// next launch, and never one from before the app subscribed. While ``isAsking`` is `true`, present
/// ``CrashReportView`` once nothing else is on screen. Reports nobody answers are dropped when the app quits.
@MainActor
@Observable
public final class CrashReporter {
    /// Whether this device can send reports: it needs App Attest, which a Mac has from macOS 27. When `false`,
    /// ``start()`` does nothing and nothing is ever asked; hide the setting for ``alwaysSends``.
    public let canSend: Bool
    /// Whether reports are waiting for the person's answer.
    public private(set) var isAsking = false
    /// Whether every report is sent without asking. Always Send turns it on; give the person a switch to turn it off.
    public var alwaysSends: Bool {
        didSet { self.defaults.set(self.alwaysSends, forKey: self.alwaysSendsKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let alwaysSendsKey: String
    @ObservationIgnored private let deliver: @MainActor (CrashReport) async -> Void
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var waiting: [CrashReport] = []
    @ObservationIgnored private var subscriber: Subscriber?
    @ObservationIgnored private var isStarted = false

    /// Creates a reporter that sends to the HK Softworks feedback service.
    ///
    /// - Parameters:
    ///   - serviceURL: The service's base URL, the one `FeedbackView` sends to.
    ///   - appID: The bundle ID the service knows the app by. Defaults to the main bundle's.
    public convenience init(serviceURL: URL, appID: String = Bundle.main.bundleIdentifier ?? "") {
        let client = FeedbackClient(serviceURL: serviceURL, appID: appID)
        let logger = Logger(subsystem: appID, category: "FeedbackKit")
        self.init(appID: appID, canSend: client.isSupported, defaults: .standard) { report in
            do {
                try await client.send(report)
            } catch {
                logger.notice("A crash report was dropped: \(String(describing: error), privacy: .public)")
            }
        }
    }

    init(appID: String, canSend: Bool, defaults: UserDefaults, deliver: @escaping @MainActor (CrashReport) async -> Void) {
        let key = "\(appID).feedbackKit.alwaysSendCrashReports"
        self.canSend = canSend
        self.defaults = defaults
        self.alwaysSendsKey = key
        self.alwaysSends = defaults.bool(forKey: key)
        self.deliver = deliver
        self.logger = Logger(subsystem: appID, category: "FeedbackKit")
    }

    /// Starts listening for MetricKit's crash reports. Call it once, early in launch.
    public func start() {
        guard self.canSend, !self.isStarted else { return }
        self.isStarted = true
        let appBinaries = Self.appBinaries
        if #available(iOS 27, macOS 27, *) {
            let manager = MetricManager()
            Task { [weak self] in
                for await report in manager.diagnosticReports {
                    guard case let .crash(diagnostic) = report.result else { continue }
                    let environment = report.environment
                    let os = environment.osVersion
                    let crash = CrashReport(
                        diagnostic,
                        appBinaries: appBinaries,
                        appVersion: "\(environment.applicationVersion) (\(environment.applicationBuildVersion))",
                        system: "\(os.platform) \(os.number) (\(os.buildNumber))",
                        device: environment.deviceType)
                    self?.receive([crash])
                }
            }
        } else {
            let subscriber = Subscriber(appBinaries: appBinaries, logger: self.logger) { [weak self] reports in
                self?.receive(reports)
            }
            MXMetricManager.shared.add(subscriber)
            self.subscriber = subscriber
        }
    }

    /// Sends the reports waiting for an answer, and with `always`, every later one without asking.
    public func send(always: Bool = false) {
        if always {
            self.alwaysSends = true
        }
        let reports = self.waiting
        self.decline()
        self.post(reports)
    }

    /// Drops the reports waiting for an answer.
    public func decline() {
        self.waiting = []
        self.isAsking = false
    }

    func receive(_ reports: [CrashReport]) {
        guard self.canSend, !reports.isEmpty else { return }
        if self.alwaysSends {
            self.post(reports)
        } else {
            self.waiting += reports
            self.isAsking = true
        }
    }

    private func post(_ reports: [CrashReport]) {
        guard !reports.isEmpty else { return }
        Task {
            for report in reports {
                await self.deliver(report)
            }
        }
    }

    /// The executables in the app's own bundle: the app's, and its frameworks' unless they're merged into it.
    private static var appBinaries: Set<String> {
        let app = Bundle.main.bundleURL.standardizedFileURL.path
        let bundles = Bundle.allFrameworks.filter { $0.bundleURL.standardizedFileURL.path.hasPrefix(app) } + [Bundle.main]
        return Set(bundles.compactMap { $0.executableURL?.lastPathComponent })
    }

    /// MetricKit's subscriber before iOS and macOS 27, which hands over payloads on a queue of its own.
    private final class Subscriber: NSObject, MXMetricManagerSubscriber, Sendable {
        let appBinaries: Set<String>
        let logger: Logger
        let receive: @MainActor @Sendable ([CrashReport]) -> Void

        init(appBinaries: Set<String>, logger: Logger, receive: @escaping @MainActor @Sendable ([CrashReport]) -> Void) {
            self.appBinaries = appBinaries
            self.logger = logger
            self.receive = receive
        }

        nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
            let reports = payloads.flatMap { $0.crashDiagnostics ?? [] }.compactMap { diagnostic -> CrashReport? in
                do {
                    return try CrashReport(diagnostic, appBinaries: self.appBinaries)
                } catch {
                    self.logger.error("A crash report couldn't be read")
                    return nil
                }
            }
            let receive = self.receive
            Task { @MainActor in receive(reports) }
        }
    }
}
#endif
