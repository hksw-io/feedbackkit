#if os(iOS) || os(macOS)
import SwiftUI

/// Every piece of copy in ``CrashReportView``. The kit ships no strings: the app returns its own localized text for
/// each case through the `strings` closure. `.title` says the app closed unexpectedly, `.message` asks whether to
/// send a report and says what is in it, and `.privacyLink` labels the link to the privacy policy.
public enum CrashReportString: Hashable, Sendable {
    case title
    case message
    case privacyLink
    case send
    case alwaysSend
    case dontSend
}

/// Asks whether to send the crash reports a ``CrashReporter`` holds: Send, Always Send or Don't Send, none of them
/// the default. Present it in a sheet while ``CrashReporter/isAsking`` is `true`; the sheet fits its content.
/// Closing it any other way, by swiping it down or pressing Escape, is Don't Send.
public struct CrashReportView: View {
    private let reporter: CrashReporter
    private let privacyURL: URL
    private let strings: (CrashReportString) -> String
    @State private var height: CGFloat?
    @Environment(\.dismiss) private var dismiss

    /// Creates the prompt for `reporter`'s waiting reports.
    ///
    /// - Parameters:
    ///   - reporter: The reporter whose reports the answer is for.
    ///   - privacyURL: The privacy policy `.privacyLink` opens, which says what a report holds and how long it's kept.
    ///   - strings: The app's text for every ``CrashReportString``.
    public init(reporter: CrashReporter, privacyURL: URL, strings: @escaping (CrashReportString) -> String) {
        self.reporter = reporter
        self.privacyURL = privacyURL
        self.strings = strings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(self.strings(.title))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(self.strings(.message))
                    .foregroundStyle(.secondary)
                Link(self.strings(.privacyLink), destination: self.privacyURL)
                VStack(spacing: 12) {
                    self.button(.send) { self.reporter.send() }
                    self.button(.alwaysSend) { self.reporter.send(always: true) }
                    self.button(.dontSend) { self.reporter.decline() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 12)
            }
            .padding(24)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // The bottom inset is the home indicator's safe area, which the detent adds again
            geometry.contentSize.height + geometry.contentInsets.top
        } action: { _, height in
            self.height = height
        }
        .frame(idealHeight: self.height)
        #if os(iOS)
            .presentationDetents([self.height.map { .height($0) } ?? .large])
        #endif
        .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        .accessibilityIdentifier("feedback.crashReport")
        .onDisappear { self.reporter.decline() }
    }

    private func button(_ string: CrashReportString, action: @escaping () -> Void) -> some View {
        Button {
            action()
            self.dismiss()
        } label: {
            Text(self.strings(string))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}
#endif
