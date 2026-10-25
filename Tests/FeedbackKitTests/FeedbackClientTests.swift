#if os(iOS) || os(macOS)
import CryptoKit
import DeviceCheck
import Foundation
import Testing
@testable import FeedbackKit

@MainActor
final class FakeTransport {
    enum Reply {
        case status(Int, errorCode: String?)
        case error(URLError)
    }

    var replies: [String: [Reply]] = [:]
    private(set) var requests: [URLRequest] = []
    private(set) var challenges: [(id: String, bytes: Data)] = []

    var paths: [String] {
        self.requests.map { $0.url?.path ?? "" }
    }

    func requests(to path: String) -> [URLRequest] {
        self.requests.filter { $0.url?.path == path }
    }

    func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        self.requests.append(request)
        let url = request.url ?? URL(filePath: "/")
        let reply = self.replies[url.path]?.isEmpty == false ? self.replies[url.path]?.removeFirst() : nil
        switch reply {
        case let .error(error):
            throw error
        case let .status(code, errorCode):
            return (Data(), Self.response(url, code, errorCode.map { ["X-Feedback-Error-Code": $0] } ?? [:]))
        case nil:
            guard url.path == "/v1/app-attest/challenges" else {
                return (Data(), Self.response(url, 204, [:]))
            }
            let seed = UInt8(self.challenges.count + 1)
            let challenge = (id: Data(repeating: seed, count: 24).base64URL, bytes: Data(repeating: seed, count: 32))
            self.challenges.append(challenge)
            let body = try JSONSerialization.data(withJSONObject: [
                "challengeID": challenge.id,
                "challenge": challenge.bytes.base64URL,
                "expiresInSeconds": 300,
            ])
            return (body, Self.response(url, 200, ["Content-Type": "application/json"]))
        }
    }

    private static func response(_ url: URL, _ code: Int, _ headers: [String: String]) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: headers) ?? URLResponse()
    }
}

@MainActor
final class FakeAttestation: AppAttesting {
    struct Call: Equatable {
        let keyID: String
        let clientDataHash: Data
    }

    var isSupported = true
    var keyFailures: [Int: DCError.Code] = [:]
    var attestFailures: [Int: DCError.Code] = [:]
    var assertionFailures: [Int: DCError.Code] = [:]
    private(set) var keys: [String] = []
    private(set) var attestCalls: [Call] = []
    private(set) var assertionCalls: [Call] = []

    func generateKey() async throws -> String {
        let key = Data(repeating: UInt8(0xA0 + self.keys.count), count: 32).base64EncodedString()
        if let code = self.keyFailures[self.keys.count + 1] {
            throw DCError(code)
        }
        self.keys.append(key)
        return key
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        self.attestCalls.append(Call(keyID: keyID, clientDataHash: clientDataHash))
        if let code = self.attestFailures[self.attestCalls.count] {
            throw DCError(code)
        }
        return Data("attestation-\(self.attestCalls.count)".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        self.assertionCalls.append(Call(keyID: keyID, clientDataHash: clientDataHash))
        if let code = self.assertionFailures[self.assertionCalls.count] {
            throw DCError(code)
        }
        return Data("assertion-\(self.assertionCalls.count)".utf8)
    }
}

extension URLRequest {
    subscript(header: String) -> String? {
        self.value(forHTTPHeaderField: header)
    }

    var json: NSDictionary? {
        self.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? NSDictionary }
    }
}

@MainActor
final class FeedbackClientTests {
    private nonisolated static let appTransaction = "eyJhbGciOiJFUzI1NiJ9.eyJidW5kbGVJZCI6ImlvLmhrc3cuZXhhbXBsZSJ9.c2lnbmF0dXJl"
    private static let challenges = "/v1/app-attest/challenges"
    private static let keys = "/v1/app-attest/keys"
    private static let feedback = "/v1/feedback"
    private static let submission = FeedbackSubmission(
        message: "The export button does nothing.",
        email: nil,
        appVersion: "1.23.0 (284)",
        system: "iOS 26.1",
        device: "iPhone17,2",
        language: "sv",
        context: [])

    private let transport = FakeTransport()
    private let attestation = FakeAttestation()
    private let sleeps = SleepLog()
    private let appID = "io.hksw.example.\(UUID().uuidString)"

    deinit {
        UserDefaults.standard.removeObject(forKey: "\(self.appID).feedbackKit.appAttestKeyID")
        UserDefaults.standard.removeObject(forKey: "\(self.appID).feedbackKit.appAttestKeyRegistered")
    }

    private func makeClient() -> FeedbackClient {
        let transport = self.transport
        let sleeps = self.sleeps
        return FeedbackClient(
            serviceURL: URL(string: "https://feedback.example.com")!,
            appID: self.appID,
            transport: { try await transport.handle($0) },
            attestation: self.attestation,
            appTransaction: { Self.appTransaction },
            sleep: { try await sleeps.sleep($0) })
    }

    private static func wire(_ keyID: String) -> String {
        Data(base64Encoded: keyID)?.base64URL ?? ""
    }

    @Test
    func `the client data is HKF1 and each field with its big-endian length`() throws {
        let body = Data(#"{"message":"Hi"}"#.utf8)
        let clientData = FeedbackClient.clientData(
            challenge: Data(0 ..< 32),
            bodySHA256: Data(SHA256.hash(data: body)),
            idempotencyKey: "feedback-0001-abcdef",
            appTransaction: Self.appTransaction,
            keyID: Data(0xA0 ..< 0xC0))

        let expected = [
            "484b463100000020000102030405060708090a0b0c0d0e0f1011121314151617",
            "18191a1b1c1d1e1f00000004504f53540000000c2f76312f666565646261636b",
            "00000020aedb816a79ec559730bb9c4376036c77f9e31a329f996c58ebc4ae51",
            "6788192e00000014666565646261636b2d303030312d61626364656600000020",
            "8942246f88b0b3aa4e68124c9492281876e90f58c9f079bda8b010efe02efd30",
            "00000020a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babb",
            "bcbdbebf",
        ].joined()
        #expect(clientData.map { String(format: "%02x", $0) }.joined() == expected)
        #expect(
            SHA256.hash(data: clientData).map { String(format: "%02x", $0) }.joined()
                == "bb40f19015d48aa186013c45b3e448d2a608bf195bcd2b37b1f3d23c03ab6937")
    }

    @Test
    func `a first send registers a key and then submits the feedback with an assertion`() async throws {
        try await self.makeClient().send(Self.submission)

        #expect(self.transport.paths == [Self.challenges, Self.keys, Self.challenges, Self.feedback])
        let requests = self.transport.requests
        for request in requests {
            #expect(request.httpMethod == "POST")
            #expect(request["Content-Type"] == "application/json")
            #expect(request["X-Feedback-App"] == self.appID)
            #expect(request["X-Feedback-App-Transaction"] == Self.appTransaction)
            let idempotencyKey = try #require(request["Idempotency-Key"])
            #expect((16 ... 128).contains(idempotencyKey.count))
            #expect(idempotencyKey.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) })
        }

        let keyID = try #require(self.attestation.keys.first)
        let registration = try #require(self.transport.challenges.first)
        #expect(requests[0].json == ["purpose": "registerKey", "keyID": Self.wire(keyID)])
        #expect(self.attestation.attestCalls == [.init(keyID: keyID, clientDataHash: registration.bytes)])
        #expect(requests[1].json == [
            "keyID": Self.wire(keyID),
            "attestationObject": Data("attestation-1".utf8).base64URL,
        ])
        #expect(requests[1]["X-Feedback-App-Attest-Challenge-ID"] == registration.id)
        #expect(requests[1]["Idempotency-Key"] == requests[0]["Idempotency-Key"])

        let body = try #require(requests[3].httpBody)
        let bodySHA256 = Data(SHA256.hash(data: body))
        let submit = self.transport.challenges[1]
        let idempotencyKey = try #require(requests[3]["Idempotency-Key"])
        #expect(requests[2].json == ["purpose": "submit", "keyID": Self.wire(keyID), "bodySHA256": bodySHA256.base64URL])
        #expect(requests[2]["Idempotency-Key"] == idempotencyKey)
        #expect(requests[0]["Idempotency-Key"] != idempotencyKey)
        #expect(requests[3]["X-Feedback-App-Attest-Key-ID"] == Self.wire(keyID))
        #expect(requests[3]["X-Feedback-App-Attest-Challenge-ID"] == submit.id)
        #expect(requests[3]["X-Feedback-App-Attest-Assertion"] == Data("assertion-1".utf8).base64URL)
        let clientData = FeedbackClient.clientData(
            challenge: submit.bytes,
            bodySHA256: bodySHA256,
            idempotencyKey: idempotencyKey,
            appTransaction: Self.appTransaction,
            keyID: try #require(Data(base64Encoded: keyID)))
        #expect(self.attestation.assertionCalls == [
            .init(keyID: keyID, clientDataHash: Data(SHA256.hash(data: clientData))),
        ])
        #expect(requests[3].json == [
            "message": "The export button does nothing.",
            "appVersion": "1.23.0 (284)",
            "system": "iOS 26.1",
            "device": "iPhone17,2",
            "language": "sv",
            "context": [String](),
        ])
    }

    @Test
    func `a registered key is reused without registering again`() async throws {
        let client = self.makeClient()
        try await client.send(Self.submission)
        try await client.send(Self.submission)
        try await self.makeClient().send(Self.submission)

        #expect(self.transport.paths == [
            Self.challenges, Self.keys, Self.challenges, Self.feedback,
            Self.challenges, Self.feedback,
            Self.challenges, Self.feedback,
        ])
        #expect(self.attestation.keys.count == 1)
        #expect(self.attestation.attestCalls.count == 1)
    }

    @Test
    func `an unregistered key is registered again before the feedback is resent`() async throws {
        self.transport.replies[Self.feedback] = [.status(428, errorCode: "app-attest-key-unregistered")]

        try await self.makeClient().send(Self.submission)

        #expect(self.transport.paths == [
            Self.challenges, Self.keys, Self.challenges, Self.feedback,
            Self.challenges, Self.keys, Self.challenges, Self.feedback,
        ])
        #expect(self.attestation.keys.count == 1)
        #expect(self.attestation.attestCalls.map(\.keyID) == [self.attestation.keys[0], self.attestation.keys[0]])
        let submissions = self.transport.requests(to: Self.feedback)
        #expect(submissions[0]["Idempotency-Key"] != submissions[1]["Idempotency-Key"])
    }

    @Test
    func `a key DeviceCheck calls invalid is replaced once`() async throws {
        self.transport.replies[Self.feedback] = [.status(428, errorCode: "app-attest-key-unregistered")]
        self.attestation.attestFailures = [2: .invalidKey]

        try await self.makeClient().send(Self.submission)

        #expect(self.transport.paths == [
            Self.challenges, Self.keys, Self.challenges, Self.feedback,
            Self.challenges, Self.challenges, Self.keys, Self.challenges, Self.feedback,
        ])
        #expect(self.attestation.keys.count == 2)
        let replacement = Self.wire(self.attestation.keys[1])
        #expect(self.transport.requests(to: Self.keys).last?.json?["keyID"] as? String == replacement)
        #expect(self.transport.requests(to: Self.feedback).last?["X-Feedback-App-Attest-Key-ID"] == replacement)
    }

    @Test
    func `a rejected registration challenge is replaced with a new one`() async throws {
        self.transport.replies[Self.keys] = [.status(401, errorCode: "app-attest-registration-challenge-rejected")]

        try await self.makeClient().send(Self.submission)

        #expect(self.transport.paths == [
            Self.challenges, Self.keys, Self.challenges, Self.keys, Self.challenges, Self.feedback,
        ])
        #expect(self.attestation.keys.count == 1)
        #expect(self.attestation.attestCalls == [
            .init(keyID: self.attestation.keys[0], clientDataHash: self.transport.challenges[0].bytes),
            .init(keyID: self.attestation.keys[0], clientDataHash: self.transport.challenges[1].bytes),
        ])
        let registrations = self.transport.requests(to: Self.keys)
        #expect(registrations[0]["Idempotency-Key"] != registrations[1]["Idempotency-Key"])
        #expect(registrations[1]["X-Feedback-App-Attest-Challenge-ID"] == self.transport.challenges[1].id)
    }

    @Test
    func `a device without App Attest sends nothing`() async {
        self.attestation.isSupported = false
        let client = self.makeClient()

        #expect(!client.isSupported)
        await #expect(throws: FeedbackError.unsupported) {
            try await client.send(Self.submission)
        }
        #expect(self.transport.requests.isEmpty)
    }

    @Test
    func `DeviceCheck reporting App Attest unsupported means this device cannot send`() async {
        self.attestation.keyFailures = [1: .featureUnsupported]

        await #expect(throws: FeedbackError.unsupported) {
            try await self.makeClient().send(Self.submission)
        }
        #expect(self.transport.requests.isEmpty)
    }

    @Test
    func `a key DeviceCheck keeps calling invalid means this device cannot send`() async {
        self.attestation.assertionFailures = [1: .invalidKey, 2: .invalidKey]

        await #expect(throws: FeedbackError.unsupported) {
            try await self.makeClient().send(Self.submission)
        }
        #expect(self.attestation.keys.count == 2)
        #expect(self.transport.requests(to: Self.feedback).isEmpty)
    }

    @Test
    func `DeviceCheck being briefly unavailable is retried once after a pause`() async throws {
        self.attestation.attestFailures = [1: .serverUnavailable]

        try await self.makeClient().send(Self.submission)

        #expect(self.attestation.attestCalls.count == 2)
        #expect(self.sleeps.durations == [.seconds(2)])
        #expect(self.transport.paths.last == Self.feedback)
    }

    @Test
    func `a lost connection reports offline and the retry reuses the idempotency key`() async throws {
        self.transport.replies[Self.feedback] = [.error(URLError(.networkConnectionLost))]
        let client = self.makeClient()

        await #expect(throws: FeedbackError.offline) {
            try await client.send(Self.submission)
        }
        try await client.send(Self.submission)

        let submissions = self.transport.requests(to: Self.feedback)
        #expect(submissions.count == 2)
        #expect(submissions[0]["Idempotency-Key"] == submissions[1]["Idempotency-Key"])
        #expect(self.transport.requests(to: Self.challenges).last?["Idempotency-Key"] == submissions[1]["Idempotency-Key"])
    }

    @Test(arguments: [(400, false), (401, false), (429, false), (503, true)] as [(Int, Bool)])
    func `a refused submission fails and only a server error keeps the idempotency key`(
        status: Int,
        reusesKey: Bool) async throws
    {
        self.transport.replies[Self.feedback] = [.status(status, errorCode: nil)]
        let client = self.makeClient()

        await #expect(throws: FeedbackError.failed) {
            try await client.send(Self.submission)
        }
        try await client.send(Self.submission)

        let submissions = self.transport.requests(to: Self.feedback)
        #expect((submissions[0]["Idempotency-Key"] == submissions[1]["Idempotency-Key"]) == reusesKey)
        #expect(self.attestation.keys.count == 1)
    }

    @Test
    func `the App Attest key is stored under the app's own bundle ID`() async throws {
        try await self.makeClient().send(Self.submission)

        #expect(UserDefaults.standard.string(forKey: "\(self.appID).feedbackKit.appAttestKeyID") == self.attestation.keys[0])
        #expect(UserDefaults.standard.bool(forKey: "\(self.appID).feedbackKit.appAttestKeyRegistered"))
    }
}
#endif
