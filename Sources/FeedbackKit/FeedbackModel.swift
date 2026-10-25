#if os(iOS) || os(macOS)
import Foundation
import Observation

@MainActor
@Observable
final class FeedbackModel {
    static let maximumMessageLength = 5000
    static let maximumEmailLength = 254
    static let maximumFieldLength = 100
    static let maximumContextLines = 10
    static let maximumContextLineLength = 500
    static let thanksHold: Duration = .milliseconds(1500)

    @ObservationIgnored let sender: any FeedbackSender
    @ObservationIgnored let context: [String]
    @ObservationIgnored let diagnostics: Diagnostics
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    private(set) var message = ""
    private(set) var email = ""
    private(set) var isEmailErrorVisible = false
    private(set) var emailErrorCount = 0
    private(set) var isSending = false
    private(set) var didSucceed = false
    private(set) var isUnsupported: Bool
    private(set) var shouldDismiss = false
    var alert: FeedbackError?
    var isDiscardConfirmationPresented = false

    init(
        sender: any FeedbackSender,
        context: [String],
        diagnostics: Diagnostics = .current,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })
    {
        self.sender = sender
        self.context = context
        self.diagnostics = diagnostics
        self.sleep = sleep
        self.isUnsupported = !sender.isSupported
    }

    var hasMessage: Bool {
        !self.trimmedMessage.isEmpty
    }

    var canSend: Bool {
        self.hasMessage && !self.isUnsupported
    }

    var isEmailValid: Bool {
        let email = self.trimmedEmail
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        return email.isEmpty
            || (email.count <= Self.maximumEmailLength
                && parts.count == 2
                && parts.allSatisfy { !$0.isEmpty }
                && !email.contains(where: \.isWhitespace))
    }

    var preventsInteractiveDismissal: Bool {
        self.hasDraft || self.isSending || self.didSucceed
    }

    var messageFooter: FeedbackString {
        if self.didSucceed {
            .thanks
        } else if self.isUnsupported {
            .unsupported
        } else {
            .diagnosticsFooter
        }
    }

    var emailFooter: FeedbackString {
        self.isEmailErrorVisible ? .emailInvalid : .emailFooter
    }

    var submission: FeedbackSubmission {
        FeedbackSubmission(
            message: self.trimmedMessage,
            email: self.trimmedEmail.isEmpty ? nil : self.trimmedEmail,
            appVersion: String(self.diagnostics.appVersion.prefix(Self.maximumFieldLength)),
            system: String(self.diagnostics.system.prefix(Self.maximumFieldLength)),
            device: String(self.diagnostics.device.prefix(Self.maximumFieldLength)),
            language: String(self.diagnostics.language.prefix(Self.maximumFieldLength)),
            context: self.context.prefix(Self.maximumContextLines).map {
                String($0.prefix(Self.maximumContextLineLength))
            })
    }

    static func message(for error: FeedbackError) -> FeedbackString {
        switch error {
        case .offline: .offlineMessage
        case .failed: .failedMessage
        case .unsupported: .unsupported
        }
    }

    func messageChanged(_ message: String) {
        self.message = String(message.prefix(Self.maximumMessageLength))
    }

    func emailChanged(_ email: String) {
        self.email = email
        if self.isEmailValid {
            self.isEmailErrorVisible = false
        }
    }

    func emailEditingEnded() {
        guard !self.isEmailValid, !self.isEmailErrorVisible else { return }
        self.showEmailError()
    }

    func sendTapped() async {
        guard self.isEmailValid else {
            self.showEmailError()
            return
        }
        await self.send()
    }

    func tryAgain() async {
        self.alert = nil
        await self.send()
    }

    func cancelTapped() {
        guard !self.isSending, !self.didSucceed else { return }
        if self.hasDraft {
            self.isDiscardConfirmationPresented = true
        } else {
            self.shouldDismiss = true
        }
    }

    func discard() {
        self.isDiscardConfirmationPresented = false
        self.shouldDismiss = true
    }

    private var hasDraft: Bool {
        self.hasMessage || !self.trimmedEmail.isEmpty
    }

    private var trimmedMessage: String {
        self.message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        self.email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func showEmailError() {
        self.isEmailErrorVisible = true
        self.emailErrorCount += 1
    }

    private func send() async {
        guard self.canSend, self.isEmailValid, !self.isSending, !self.didSucceed else { return }
        self.isSending = true
        do throws(FeedbackError) {
            try await self.sender.send(self.submission)
        } catch {
            self.isSending = false
            self.isUnsupported = self.isUnsupported || error == .unsupported
            self.alert = error
            return
        }
        self.isSending = false
        self.didSucceed = true
        do {
            try await self.sleep(Self.thanksHold)
        } catch {
            return
        }
        self.shouldDismiss = true
    }
}
#endif
