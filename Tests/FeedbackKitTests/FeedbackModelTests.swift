#if os(iOS) || os(macOS)
import Foundation
import Synchronization
import Testing
@testable import FeedbackKit

@MainActor
final class FakeSender: FeedbackSender {
    var isSupported = true
    var failures: [FeedbackError] = []
    var sent: [FeedbackSubmission] = []
    var whileSending: (() -> Void)?

    func send(_ submission: FeedbackSubmission) async throws(FeedbackError) {
        self.sent.append(submission)
        self.whileSending?()
        if !self.failures.isEmpty {
            throw self.failures.removeFirst()
        }
    }
}

final class SleepLog: Sendable {
    private let log = Mutex<[Duration]>([])

    var durations: [Duration] {
        self.log.withLock { $0 }
    }

    func sleep(_ duration: Duration) async throws {
        self.log.withLock { $0.append(duration) }
    }
}

@MainActor
struct FeedbackModelTests {
    private static let diagnostics = Diagnostics(
        appVersion: "1.23.0 (284)",
        system: "iOS 26.1",
        device: "iPhone17,2",
        language: "sv")

    private let sender = FakeSender()
    private let sleeps = SleepLog()

    private func makeModel(context: [String] = [], message: String = "", email: String = "") -> FeedbackModel {
        let sleeps = self.sleeps
        let model = FeedbackModel(sender: self.sender, context: context, diagnostics: Self.diagnostics) {
            try await sleeps.sleep($0)
        }
        model.messageChanged(message)
        model.emailChanged(email)
        return model
    }

    @Test
    func `sending posts the trimmed feedback and holds the thanks before closing`() async {
        let model = self.makeModel(
            context: ["Action: Couldn’t Save Card", "Error: card.save"],
            message: "  The card vanished.\n",
            email: " reader@example.com ")
        var wasSending = false
        self.sender.whileSending = {
            wasSending = model.isSending
            model.cancelTapped()
        }

        await model.sendTapped()

        #expect(wasSending)
        #expect(self.sender.sent == [
            FeedbackSubmission(
                message: "The card vanished.",
                email: "reader@example.com",
                appVersion: "1.23.0 (284)",
                system: "iOS 26.1",
                device: "iPhone17,2",
                language: "sv",
                context: ["Action: Couldn’t Save Card", "Error: card.save"]),
        ])
        #expect(!model.isSending)
        #expect(model.didSucceed)
        #expect(model.isThanking)
        #expect(model.thanksDetail == .thanksMayReply)
        #expect(!model.isDiscardConfirmationPresented)
        #expect(self.sleeps.durations == [FeedbackModel.thanksLead, FeedbackModel.thanksDwell])
        #expect(model.shouldDismiss)
    }

    @Test
    func `plain feedback sends no reply address and no context`() async {
        let model = self.makeModel(message: "Love it")

        await model.sendTapped()

        #expect(self.sender.sent.first?.email == nil)
        #expect(self.sender.sent.first?.context == [])
        #expect(model.thanksDetail == .thanksRead, "no address, so nothing about replies")
    }

    @Test
    func `the thanks only mentions a reply when an address that will be sent was left`() {
        #expect(self.makeModel(message: "Hi", email: "   ").thanksDetail == .thanksRead)
        #expect(self.makeModel(message: "Hi", email: "a@b.co").thanksDetail == .thanksMayReply)
    }

    @Test(arguments: [
        (FeedbackModel.thanksLead, false),
        (FeedbackModel.thanksDwell, true),
    ])
    func `the thank-you screen can be closed early, but not the moment before it`(
        stoppedAt: Duration,
        closes: Bool) async
    {
        let model = FeedbackModel(sender: self.sender, context: [], diagnostics: Self.diagnostics) { duration in
            if duration == stoppedAt {
                throw CancellationError()
            }
        }
        model.messageChanged("Hi")

        await model.sendTapped()
        #expect(model.didSucceed)
        #expect(model.isThanking == closes)
        #expect(!model.shouldDismiss)

        model.cancelTapped()
        #expect(model.shouldDismiss == closes)
        #expect(!model.isDiscardConfirmationPresented)
    }

    @Test(arguments: ["", "  \n "] as [String])
    func `empty feedback cannot be sent`(message: String) async {
        let model = self.makeModel(message: message)

        #expect(!model.canSend)
        await model.sendTapped()

        #expect(self.sender.sent.isEmpty)
        #expect(model.messageFooter == .diagnosticsFooter)
    }

    @Test
    func `an incomplete reply address blocks sending and says why on every tap`() async {
        let model = self.makeModel(message: "Hello", email: "reader@")

        #expect(model.canSend)
        #expect(model.emailFooter == .emailFooter)
        await model.sendTapped()
        #expect(model.isEmailErrorVisible)
        #expect(model.emailFooter == .emailInvalid)
        #expect(model.emailErrorCount == 1)
        await model.sendTapped()

        #expect(model.emailErrorCount == 2)
        #expect(self.sender.sent.isEmpty)
    }

    @Test
    func `the email error waits until the field is left and clears once the address is complete`() {
        let model = self.makeModel(message: "Hello")

        model.emailChanged("reader@")
        #expect(!model.isEmailErrorVisible)
        model.emailEditingEnded()
        #expect(model.isEmailErrorVisible)
        #expect(model.emailErrorCount == 1)
        model.emailChanged("reader@example.com")
        #expect(!model.isEmailErrorVisible)
        model.emailChanged("reader@")
        #expect(!model.isEmailErrorVisible)
        model.emailEditingEnded()
        model.emailEditingEnded()

        #expect(model.isEmailErrorVisible)
        #expect(model.emailErrorCount == 2)
    }

    @Test(arguments: [(.offline, .offlineMessage), (.failed, .failedMessage)] as [(FeedbackError, FeedbackString)])
    func `a failed send keeps the draft and offers to try again`(error: FeedbackError, message: FeedbackString) async {
        self.sender.failures = [error]
        let model = self.makeModel(message: "Hello")

        await model.sendTapped()
        #expect(model.alert == error)
        #expect(FeedbackModel.message(for: error) == message)
        #expect(model.message == "Hello")
        #expect(!model.isSending)
        #expect(!model.didSucceed)
        #expect(model.canSend)

        await model.tryAgain()

        #expect(model.alert == nil)
        #expect(self.sender.sent.count == 2)
        #expect(model.didSucceed)
        #expect(model.shouldDismiss)
    }

    @Test
    func `a device without App Attest says it cannot send`() async {
        self.sender.isSupported = false
        let model = self.makeModel(message: "Hello")

        #expect(model.isUnsupported)
        #expect(model.messageFooter == .unsupported)
        #expect(!model.canSend)
        await model.sendTapped()

        #expect(self.sender.sent.isEmpty)
    }

    @Test
    func `attestation failing for good turns the form into the cannot-send state`() async {
        self.sender.failures = [.unsupported]
        let model = self.makeModel(message: "Hello")

        await model.sendTapped()

        #expect(model.alert == .unsupported)
        #expect(FeedbackModel.message(for: .unsupported) == .unsupported)
        #expect(model.messageFooter == .unsupported)
        #expect(!model.canSend)
        #expect(model.message == "Hello")
    }

    @Test
    func `cancel closes an empty form at once`() {
        let model = self.makeModel()

        #expect(!model.preventsInteractiveDismissal)
        model.cancelTapped()

        #expect(model.shouldDismiss)
        #expect(!model.isDiscardConfirmationPresented)
    }

    @Test(arguments: [("Half a thought", ""), ("", "reader@example.com")] as [(String, String)])
    func `cancel asks before discarding a draft`(message: String, email: String) {
        let model = self.makeModel(message: message, email: email)

        #expect(model.preventsInteractiveDismissal)
        model.cancelTapped()
        #expect(model.isDiscardConfirmationPresented)
        #expect(!model.shouldDismiss)
        model.discard()

        #expect(!model.isDiscardConfirmationPresented)
        #expect(model.shouldDismiss)
    }

    @Test
    func `a message longer than the server takes is cut at the limit`() {
        let model = self.makeModel(message: String(repeating: "a", count: 5010))

        #expect(model.message.count == 5000)
    }

    @Test
    func `context is cut to what the server takes`() {
        let model = self.makeModel(context: Array(repeating: String(repeating: "x", count: 600), count: 12))

        #expect(model.submission.context == Array(repeating: String(repeating: "x", count: 500), count: 10))
    }

    @Test
    func `diagnostics name the system, the hardware and the language`() {
        let diagnostics = Diagnostics.current

        #if os(iOS)
            #expect(diagnostics.system.hasPrefix("iOS ") || diagnostics.system.hasPrefix("iPadOS "))
        #else
            #expect(diagnostics.system.hasPrefix("macOS "))
        #endif
        #expect(!diagnostics.device.isEmpty)
        #expect(diagnostics.device != "Unknown")
        #expect(!diagnostics.language.contains("_"))
        #expect(diagnostics.appVersion.hasSuffix(")"))
    }
}
#endif
