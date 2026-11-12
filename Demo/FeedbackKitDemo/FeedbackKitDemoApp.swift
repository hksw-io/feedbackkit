import FeedbackKit
import SwiftUI

@main
struct FeedbackKitDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoView()
        }
    }
}

struct DemoView: View {
    enum Sheet: String, Identifiable {
        case feedback
        case problem
        case crashReport

        var id: Self {
            self
        }
    }

    @State private var sheet = UserDefaults.standard.string(forKey: "demoSheet").flatMap(Sheet.init)
    @State private var outcome = UserDefaults.standard.string(forKey: "demoOutcome").flatMap(DemoSender.Outcome.init)
        ?? .success
    @State private var crashReporter = CrashReporter(serviceURL: URL(filePath: "/"))

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Send Feedback") { self.sheet = .feedback }
                    Button("Report a Problem") { self.sheet = .problem }
                    Button("Crash Report") { self.sheet = .crashReport }
                }
                Section("Fake Service") {
                    Picker("Outcome", selection: self.$outcome) {
                        ForEach(DemoSender.Outcome.allCases, id: \.self) { outcome in
                            Text(outcome.rawValue.capitalized).tag(outcome)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("FeedbackKit")
        }
        .sheet(item: self.$sheet) { sheet in
            if sheet == .crashReport {
                CrashReportView(
                    reporter: self.crashReporter,
                    privacyURL: URL(string: "https://example.com/privacy")!,
                    strings: crashReportText)
            } else {
                FeedbackView(
                    sender: DemoSender(outcome: self.outcome),
                    icon: Image(systemName: "bubble.left.and.text.bubble.right.fill"),
                    strings: feedbackText,
                    title: sheet == .feedback ? .feedbackTitle : .problemTitle,
                    prompt: sheet == .feedback ? .feedbackPrompt : .problemPrompt,
                    context: sheet == .feedback ? [] : ["Action: Couldn’t Save Card", "Error: card.save"],
                    onDismiss: { self.sheet = nil })
            }
        }
    }
}

struct DemoSender: FeedbackSender {
    enum Outcome: String, CaseIterable {
        case success
        case failure
        case offline
        case unsupported
    }

    let outcome: Outcome

    var isSupported: Bool {
        self.outcome != .unsupported
    }

    func send(_: FeedbackSubmission) async throws(FeedbackError) {
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            throw .failed
        }
        switch self.outcome {
        case .success: return
        case .failure: throw .failed
        case .offline: throw .offline
        case .unsupported: throw .unsupported
        }
    }
}

func feedbackText(_ string: FeedbackString) -> String {
    switch string {
    case .feedbackTitle: String(localized: "Send Feedback")
    case .problemTitle: String(localized: "Report a Problem")
    case .feedbackPrompt: String(localized: "Request a feature or describe a problem")
    case .problemPrompt: String(localized: "What happened?")
    case .contentPrompt: String(localized: "What’s wrong with this card?")
    case .messageLabel: String(localized: "Message")
    case .diagnosticsFooter:
        String(localized: "Your app version, system version, device model and language are sent with your message.")
    case .messageTooLong: String(localized: "Your message is too long. Shorten it to 5,000 characters or fewer.")
    case .thanks: String(localized: "Thanks for Your Feedback")
    case .thanksRead: String(localized: "We read all feedback.")
    case .thanksMayReply: String(localized: "We read all feedback and try to reply to every message.")
    case .unsupported: String(localized: "This device can’t send feedback.")
    case .emailLabel: String(localized: "Email")
    case .emailPlaceholder: String(localized: "Email (Optional)")
    case .emailFooter: String(localized: "Add your email if you’d like a reply.")
    case .emailInvalid: String(localized: "Enter a full email address, like name@example.com.")
    case .send: String(localized: "Send")
    case .cancel: String(localized: "Cancel")
    case .sending: String(localized: "Sending")
    case .complete: String(localized: "Complete")
    case .failedTitle: String(localized: "Couldn’t Send Feedback")
    case .failedMessage: String(localized: "Something went wrong. Try again in a moment.")
    case .offlineMessage: String(localized: "You’re offline. Connect to the internet, then try again.")
    case .tryAgain: String(localized: "Try Again")
    case .ok: String(localized: "OK")
    case .discardTitle: String(localized: "Discard Changes?")
    case .discardMessage: String(localized: "Your changes won’t be saved.")
    case .discard: String(localized: "Discard Changes")
    case .keepEditing: String(localized: "Keep Editing")
    }
}

func crashReportText(_ string: CrashReportString) -> String {
    switch string {
    case .title: String(localized: "Example Closed Unexpectedly")
    case .message:
        String(localized: "Send a report to the developer? It says where the app closed, with the app and system versions and the device model. Nothing you wrote is in it.")
    case .privacyLink: String(localized: "About Crash Reports")
    case .send: String(localized: "Send")
    case .alwaysSend: String(localized: "Always Send")
    case .dontSend: String(localized: "Don’t Send")
    }
}
