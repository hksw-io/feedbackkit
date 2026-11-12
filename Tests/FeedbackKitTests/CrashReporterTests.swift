#if os(iOS) || os(macOS)
import Foundation
import Testing
@testable import FeedbackKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
final class CrashReporterTests {
    private let suiteName = "io.hksw.example.\(UUID().uuidString)"
    private let sent: AsyncStream<CrashReport>
    private let continuation: AsyncStream<CrashReport>.Continuation

    init() {
        (self.sent, self.continuation) = AsyncStream.makeStream(of: CrashReport.self)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: self.suiteName)
    }

    private func makeReporter(canSend: Bool = true) -> CrashReporter {
        let continuation = self.continuation
        return CrashReporter(
            appID: "io.hksw.example",
            canSend: canSend,
            defaults: UserDefaults(suiteName: self.suiteName) ?? .standard)
        { continuation.yield($0) }
    }

    private static func report(_ offset: UInt64) -> CrashReport {
        let frame = CrashReport.Frame(binary: "Swiftflip", uuid: CrashReportTests.app, offset: offset)
        return CrashReport(
            threads: [CrashReport.Thread(crashed: true, frames: [frame])],
            appBinaries: ["Swiftflip"],
            appVersion: "1.23.0 (295)",
            system: "iOS 26.1",
            device: "iPhone17,2",
            exceptionType: 1,
            exceptionCode: 0,
            signal: 11,
            exceptionName: nil,
            className: nil)
    }

    @Test
    func `reports wait for the person's answer, and Send sends them`() async throws {
        let (first, second) = (Self.report(1), Self.report(2))
        let reporter = self.makeReporter()
        reporter.receive([first, second])
        try #require(reporter.isAsking)

        reporter.send()

        #expect(!reporter.isAsking)
        #expect(!reporter.alwaysSends)
        var sent = self.sent.makeAsyncIterator()
        #expect(await sent.next() == first)
        #expect(await sent.next() == second)
    }

    @Test
    func `Don't Send drops the reports that were waiting`() async throws {
        let (first, second) = (Self.report(1), Self.report(2))
        let reporter = self.makeReporter()
        reporter.receive([first])
        try #require(reporter.isAsking)

        reporter.decline()

        #expect(!reporter.isAsking)
        reporter.receive([second])
        reporter.send()
        var sent = self.sent.makeAsyncIterator()
        #expect(await sent.next() == second, "the first report was never sent")
    }

    @Test
    func `Always Send sends these and every later report without asking, and is remembered`() async throws {
        let (first, second) = (Self.report(1), Self.report(2))
        let reporter = self.makeReporter()
        reporter.receive([first])
        try #require(reporter.isAsking)

        reporter.send(always: true)
        reporter.receive([second])

        #expect(!reporter.isAsking)
        #expect(self.makeReporter().alwaysSends, "a reporter made at the next launch")
        var sent = self.sent.makeAsyncIterator()
        #expect(await sent.next() == first)
        #expect(await sent.next() == second)
    }

    @Test
    func `turning Always Send off asks again`() throws {
        let reporter = self.makeReporter()
        reporter.alwaysSends = true

        reporter.alwaysSends = false
        reporter.receive([Self.report(1)])

        #expect(reporter.isAsking)
        #expect(!self.makeReporter().alwaysSends)
    }

    @Test
    func `a device that can't send never asks`() throws {
        let reporter = self.makeReporter(canSend: false)

        reporter.receive([Self.report(1)])

        #expect(!reporter.isAsking)
    }
}
#endif
