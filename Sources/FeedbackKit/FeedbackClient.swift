#if os(iOS) || os(macOS)
import CryptoKit
import DeviceCheck
import Foundation
import OSLog
import StoreKit

@MainActor
protocol AppAttesting {
    var isSupported: Bool { get }

    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

struct DeviceAppAttest: AppAttesting {
    var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}

@MainActor
final class FeedbackClient: FeedbackSender {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let deviceCheckRetryDelay: Duration = .seconds(2)

    struct HTTPStatus: Error {
        let code: Int
        let errorCode: String?

        var asksForRegistration: Bool {
            (self.code == 428 && self.errorCode == "app-attest-key-unregistered")
                || self.rejectsRegistrationChallenge
        }

        var rejectsRegistrationChallenge: Bool {
            self.code == 401 && self.errorCode == "app-attest-registration-challenge-rejected"
        }
    }

    struct InvalidKey: Error {}

    struct Key {
        let id: String
        let raw: Data

        init?(_ id: String) {
            guard let raw = Data(base64Encoded: id), raw.count == 32 else { return nil }
            self.id = id
            self.raw = raw
        }

        var wire: String {
            self.raw.base64URL
        }
    }

    private struct Challenge {
        let id: String
        let bytes: Data
    }

    private struct ChallengeRequest: Encodable {
        let purpose: String
        let keyID: String
        let bodySHA256: String?
    }

    private struct ChallengeResponse: Decodable {
        let challengeID: String
        let challenge: String
    }

    private struct Registration: Encodable {
        let keyID: String
        let attestationObject: String
    }

    private let serviceURL: URL
    private let appID: String
    private let transport: Transport
    private let attestation: any AppAttesting
    private let appTransaction: @Sendable () async throws -> String
    private let sleep: @Sendable (Duration) async throws -> Void
    private let logger: Logger
    private var pendingSubmit: (digest: Data, idempotencyKey: String)?

    init(
        serviceURL: URL,
        appID: String,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
        attestation: any AppAttesting = DeviceAppAttest(),
        appTransaction: @escaping @Sendable () async throws -> String = {
            try await AppTransaction.shared.jwsRepresentation
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })
    {
        self.serviceURL = serviceURL
        self.appID = appID
        self.transport = transport
        self.attestation = attestation
        self.appTransaction = appTransaction
        self.sleep = sleep
        self.logger = Logger(subsystem: appID, category: "FeedbackKit")
    }

    var isSupported: Bool {
        self.attestation.isSupported
    }

    func send(_ submission: FeedbackSubmission) async throws(FeedbackError) {
        do {
            try await self.deliver(submission)
        } catch let error as FeedbackError {
            throw error
        } catch is InvalidKey {
            throw .unsupported
        } catch let error as URLError where Self.isOffline(error) {
            throw .offline
        } catch StoreKitError.networkError(_) {
            throw .offline
        } catch {
            self.logger.error("Feedback was not sent: \(Self.describe(error), privacy: .public)")
            throw .failed
        }
    }

    static func clientData(
        challenge: Data,
        bodySHA256: Data,
        idempotencyKey: String,
        appTransaction: String,
        keyID: Data) -> Data
    {
        let fields = [
            challenge,
            Data("POST".utf8),
            Data("/v1/feedback".utf8),
            bodySHA256,
            Data(idempotencyKey.utf8),
            Data(SHA256.hash(data: Data(appTransaction.utf8))),
            keyID,
        ]
        return fields.reduce(into: Data("HKF1".utf8)) { data, field in
            withUnsafeBytes(of: UInt32(field.count).bigEndian) { data.append(contentsOf: $0) }
            data.append(field)
        }
    }

    private func deliver(_ submission: FeedbackSubmission) async throws {
        guard self.attestation.isSupported else { throw FeedbackError.unsupported }
        let body = try Self.encode(submission)
        let appTransaction = try await self.appTransaction()
        var canRotate = true
        var canRegisterAgain = true
        while true {
            let key = try await self.registeredKey(appTransaction: appTransaction, canRotate: &canRotate)
            do {
                try await self.submit(body, key: key, appTransaction: appTransaction)
                return
            } catch is InvalidKey where canRotate {
                canRotate = false
                self.storedKey = nil
            } catch let status as HTTPStatus where canRegisterAgain && status.asksForRegistration {
                canRegisterAgain = false
                self.storedKey = (key.id, false)
            }
        }
    }

    private func registeredKey(appTransaction: String, canRotate: inout Bool) async throws -> Key {
        while true {
            let key: Key
            if let stored = self.storedKey, let storedKey = Key(stored.id) {
                if stored.isRegistered {
                    return storedKey
                }
                key = storedKey
            } else {
                guard let generated = try await Key(self.deviceCheck { try await self.attestation.generateKey() })
                else { throw FeedbackError.failed }
                key = generated
                self.storedKey = (key.id, false)
            }
            do {
                try await self.register(key, appTransaction: appTransaction)
                self.storedKey = (key.id, true)
                return key
            } catch is InvalidKey where canRotate {
                canRotate = false
                self.storedKey = nil
            }
        }
    }

    private func register(_ key: Key, appTransaction: String) async throws {
        var canRetryChallenge = true
        while true {
            let idempotencyKey = Self.newIdempotencyKey()
            let challenge = try await self.challenge(
                ChallengeRequest(purpose: "registerKey", keyID: key.wire, bodySHA256: nil),
                idempotencyKey: idempotencyKey,
                appTransaction: appTransaction)
            let attestation = try await self.deviceCheck {
                try await self.attestation.attestKey(key.id, clientDataHash: challenge.bytes)
            }
            do {
                try await self.post(
                    "v1/app-attest/keys",
                    body: Self.encode(Registration(keyID: key.wire, attestationObject: attestation.base64URL)),
                    idempotencyKey: idempotencyKey,
                    appTransaction: appTransaction,
                    headers: ["X-Feedback-App-Attest-Challenge-ID": challenge.id],
                    expecting: 204)
                return
            } catch let status as HTTPStatus where canRetryChallenge && status.rejectsRegistrationChallenge {
                canRetryChallenge = false
            }
        }
    }

    private func submit(_ body: Data, key: Key, appTransaction: String) async throws {
        let digest = Data(SHA256.hash(data: body))
        let idempotencyKey = self.pendingSubmit.flatMap { $0.digest == digest ? $0.idempotencyKey : nil }
            ?? Self.newIdempotencyKey()
        self.pendingSubmit = (digest, idempotencyKey)
        do {
            let challenge = try await self.challenge(
                ChallengeRequest(purpose: "submit", keyID: key.wire, bodySHA256: digest.base64URL),
                idempotencyKey: idempotencyKey,
                appTransaction: appTransaction)
            let clientData = Self.clientData(
                challenge: challenge.bytes,
                bodySHA256: digest,
                idempotencyKey: idempotencyKey,
                appTransaction: appTransaction,
                keyID: key.raw)
            let assertion = try await self.deviceCheck {
                try await self.attestation.generateAssertion(
                    key.id,
                    clientDataHash: Data(SHA256.hash(data: clientData)))
            }
            try await self.post(
                "v1/feedback",
                body: body,
                idempotencyKey: idempotencyKey,
                appTransaction: appTransaction,
                headers: [
                    "X-Feedback-App-Attest-Key-ID": key.wire,
                    "X-Feedback-App-Attest-Challenge-ID": challenge.id,
                    "X-Feedback-App-Attest-Assertion": assertion.base64URL,
                ],
                expecting: 204)
            self.pendingSubmit = nil
        } catch {
            if !Self.isAmbiguous(error) {
                self.pendingSubmit = nil
            }
            throw error
        }
    }

    private func challenge(
        _ request: ChallengeRequest,
        idempotencyKey: String,
        appTransaction: String) async throws -> Challenge
    {
        let data = try await self.post(
            "v1/app-attest/challenges",
            body: Self.encode(request),
            idempotencyKey: idempotencyKey,
            appTransaction: appTransaction,
            expecting: 200)
        let response = try JSONDecoder().decode(ChallengeResponse.self, from: data)
        guard let bytes = Data(base64URL: response.challenge), bytes.count == 32 else {
            throw FeedbackError.failed
        }
        return Challenge(id: response.challengeID, bytes: bytes)
    }

    @discardableResult
    private func post(
        _ path: String,
        body: Data,
        idempotencyKey: String,
        appTransaction: String,
        headers: [String: String] = [:],
        expecting expected: Int) async throws -> Data
    {
        var request = URLRequest(url: self.serviceURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.appID, forHTTPHeaderField: "X-Feedback-App")
        request.setValue(appTransaction, forHTTPHeaderField: "X-Feedback-App-Transaction")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await self.transport(request)
        guard let response = response as? HTTPURLResponse else { throw FeedbackError.failed }
        guard response.statusCode == expected else {
            throw HTTPStatus(
                code: response.statusCode,
                errorCode: response.value(forHTTPHeaderField: "X-Feedback-Error-Code"))
        }
        return data
    }

    private func deviceCheck<T>(retrying: Bool = true, _ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch let error as DCError {
            switch error.code {
            case .serverUnavailable where retrying:
                try await self.sleep(Self.deviceCheckRetryDelay)
                return try await self.deviceCheck(retrying: false, call)
            case .featureUnsupported:
                throw FeedbackError.unsupported
            case .invalidKey:
                throw InvalidKey()
            default:
                throw error
            }
        }
    }

    private var storedKey: (id: String, isRegistered: Bool)? {
        get {
            UserDefaults.standard.string(forKey: self.keyIDDefault).map {
                ($0, UserDefaults.standard.bool(forKey: self.keyRegisteredDefault))
            }
        }
        set {
            UserDefaults.standard.set(newValue?.id, forKey: self.keyIDDefault)
            UserDefaults.standard.set(newValue?.isRegistered == true, forKey: self.keyRegisteredDefault)
        }
    }

    private var keyIDDefault: String {
        "\(self.appID).feedbackKit.appAttestKeyID"
    }

    private var keyRegisteredDefault: String {
        "\(self.appID).feedbackKit.appAttestKeyRegistered"
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private static func newIdempotencyKey() -> String {
        UUID().uuidString
    }

    private static func isAmbiguous(_ error: any Error) -> Bool {
        error is URLError || ((error as? HTTPStatus)?.code ?? 0) >= 500
    }

    private static func isOffline(_ error: URLError) -> Bool {
        [
            .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
        ].contains(error.code)
    }

    private static func describe(_ error: any Error) -> String {
        if let status = error as? HTTPStatus {
            return "status \(status.code) \(status.errorCode ?? "")"
        }
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}

extension Data {
    var base64URL: String {
        self.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }

    init?(base64URL: String) {
        let base64 = base64URL.replacing("-", with: "+").replacing("_", with: "/")
        self.init(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4))
    }
}
#endif
