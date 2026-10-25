#if os(iOS) || os(macOS)
import Foundation

@MainActor
public protocol FeedbackSender {
    var isSupported: Bool { get }

    func send(_ submission: FeedbackSubmission) async throws(FeedbackError)
}

public struct FeedbackSubmission: Encodable, Equatable, Sendable {
    public let message: String
    public let email: String?
    public let appVersion: String
    public let system: String
    public let device: String
    public let language: String
    public let context: [String]
}

public enum FeedbackError: Error, Equatable, Sendable {
    case offline
    case failed
    case unsupported
}

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
