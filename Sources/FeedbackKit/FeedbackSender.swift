#if os(iOS) || os(macOS)
import Foundation

/// Delivers a submission for `FeedbackView`.
///
/// Pass your own sender to `FeedbackView(sender:strings:...)` to send feedback to your own backend, or to
/// drive the form in previews, demos and UI tests.
@MainActor
public protocol FeedbackSender {
    /// Whether this device can send at all. When `false`, the form shows `.unsupported` and disables Send.
    var isSupported: Bool { get }

    /// Sends one submission. Throw `.offline` or `.failed` to offer Try Again, or `.unsupported` when the
    /// device turns out unable to send.
    func send(_ submission: FeedbackSubmission) async throws(FeedbackError)
}

/// What the person wrote, with the diagnostics the form's footer names. It encodes to the JSON body the
/// HK Softworks feedback service expects; `email` is left out when empty.
public struct FeedbackSubmission: Encodable, Equatable, Sendable {
    /// The trimmed message, 1 to 5,000 characters.
    public let message: String
    /// The trimmed email address, or `nil` when none was entered.
    public let email: String?
    /// The app's version and build, such as `1.4.0 (212)`.
    public let appVersion: String
    /// The system name and version, such as `iOS 26.1`.
    public let system: String
    /// The hardware model identifier, such as `iPhone17,2` or `Mac15,3`.
    public let device: String
    /// The language code, such as `sv`.
    public let language: String
    /// The `context` lines the app passed to `FeedbackView`.
    public let context: [String]
}

/// Why a send failed.
public enum FeedbackError: Error, Equatable, Sendable {
    /// No connection. The form shows `.offlineMessage` and offers Try Again.
    case offline
    /// Anything else that may work on a retry. The form shows `.failedMessage` and offers Try Again.
    case failed
    /// This device can't send. The form shows `.unsupported` and disables Send.
    case unsupported
}

/// Every piece of copy in the form. The kit ships no strings: the app returns its own localized text for each
/// case through the `strings` closure. `.messageLabel` and `.emailLabel` are VoiceOver labels, and `.complete`
/// labels the checkmark after a send.
public enum FeedbackString: Hashable, Sendable {
    case feedbackTitle
    case problemTitle
    case feedbackPrompt
    case problemPrompt
    case contentPrompt
    case messageLabel
    case diagnosticsFooter
    case thanks
    case unsupported
    case emailLabel
    case emailPlaceholder
    case emailFooter
    case emailInvalid
    case send
    case cancel
    case complete
    case failedTitle
    case failedMessage
    case offlineMessage
    case tryAgain
    case ok
    case discardTitle
    case discardMessage
    case discard
    case keepEditing
}
#endif
