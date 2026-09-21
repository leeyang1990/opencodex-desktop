import Foundation
import XCTest

@testable import OpenCodexDesktop

final class ChannelDraftTests: XCTestCase {
    private var valid: ChannelDraft {
        var draft = ChannelDraft()
        draft.name = "test-channel"
        draft.baseURL = "https://example.test/v1"
        return draft
    }

    func testProtocolIDsMatchCoreRegistry() {
        XCTAssertEqual(
            ChannelProtocol.allCases.map(\.rawValue), ["openai-chat", "openai-responses", "anthropic", "google"])
    }

    func testGoogleDoesNotDoubleVersionAndBaseURLTrimsTrailingSlash() {
        var draft = valid
        draft.transport = .google
        draft.baseURL = ChannelProtocol.google.placeholder + "/v1beta"
        XCTAssertNotNil(draft.validationError(key: "fixture", existingNames: []))
        draft.baseURL = ChannelProtocol.google.placeholder + "/"
        XCTAssertNil(draft.validationError(key: "fixture", existingNames: []))
        XCTAssertEqual(draft.payload.baseUrl, ChannelProtocol.google.placeholder)
    }

    func testNameConstraintsAndReservedNames() {
        for name in [
            "", "a b", "渠道", "-test", "test_", String(repeating: "a", count: 65),
            "constructor", "POLICY", "openai", "chatgpt", "openai-multi",
        ] {
            var draft = valid
            draft.name = name
            XCTAssertNotNil(draft.validationError(key: "fixture", existingNames: []), name)
        }
        for name in ["a", " A.test_channel-1 ", String(repeating: "a", count: 64)] {
            var draft = valid
            draft.name = name
            XCTAssertNil(draft.validationError(key: "fixture", existingNames: []), name)
        }
    }

    func testDuplicateIsRejectedAfterTrimming() {
        var draft = valid
        draft.name = " test-channel "
        XCTAssertNotNil(draft.validationError(key: "fixture", existingNames: ["test-channel"]))
    }

    func testUnsafeOrNonBaseURLsAreRejected() {
        for url in [
            "", "example.test", "file:///tmp/file", "ftp://example.test", "https://",
            "https://user:password@example.test/v1", "https://example.test?key=secret",
            "https://example.test#secret", "https://example.test:99999", "https://exam ple.test",
            "https://example.test/v1/chat/completions/", "https://example.test/v1/responses",
            "https://example.test/v1/messages", "https://example.test/v1/models",
        ] {
            var draft = valid
            draft.baseURL = url
            XCTAssertNotNil(draft.validationError(key: "fixture", existingNames: []), url)
        }
    }

    func testKeyRequiredUnlessLocalAuthenticationExplicit() {
        var draft = valid
        XCTAssertNotNil(draft.validationError(key: " \n ", existingNames: []))
        draft.requiresKey = false
        draft.allowPrivateNetwork = true
        draft.baseURL = "http://127.0.0.1:11434/v1"
        XCTAssertNil(draft.validationError(key: "", existingNames: []))
        XCTAssertEqual(draft.payload.authMode, "local")
        XCTAssertEqual(draft.payload.allowPrivateNetwork, true)
        draft.transport = .anthropic
        XCTAssertNotNil(draft.validationError(key: "", existingNames: []))
    }

    func testManualModelsDeduplicateAndValidateDefault() {
        var draft = valid
        draft.automaticModels = false
        XCTAssertNotNil(draft.validationError(key: "fixture", existingNames: []))
        draft.modelText = " model-a\nmodel-b,model-a，model-c "
        XCTAssertEqual(draft.payload.models, ["model-a", "model-b", "model-c"])
        draft.defaultModel = "not-in-list"
        XCTAssertNotNil(draft.validationError(key: "fixture", existingNames: []))
        draft.defaultModel = " model-b "
        XCTAssertNil(draft.validationError(key: "fixture", existingNames: []))
        XCTAssertEqual(draft.payload.defaultModel, "model-b")
        XCTAssertEqual(draft.payload.liveModels, false)
    }

    func testAutomaticModelsDoNotSendStaleManualListOrCredentials() throws {
        var draft = valid
        draft.modelText = "stale-model"
        draft.note = "  optional note  "
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.payload)) as? [String: Any])
        XCTAssertEqual(object["liveModels"] as? Bool, true)
        XCTAssertEqual(object["authMode"] as? String, "key")
        XCTAssertEqual(object["note"] as? String, "optional note")
        XCTAssertNil(object["models"])
        XCTAssertNil(object["apiKey"])
        XCTAssertNil(object["key"])
    }
}

@MainActor
final class ChannelCreatorTests: XCTestCase {
    private var draft: ChannelDraft {
        var draft = ChannelDraft()
        draft.name = "test-channel"
        draft.baseURL = "https://example.test/v1"
        draft.setDefault = true
        return draft
    }

    func testCreationOrderStoresKeyBeforeSwitchingDefault() async {
        var steps: [String] = []
        let creator = ChannelCreator(
            existingNames: {
                steps.append("check"); return []
            },
            create: { name, payload in
                steps.append("create")
                XCTAssertEqual(name, "test-channel")
                XCTAssertEqual(payload.adapter, "openai-chat")
            },
            addKey: { _, key in
                steps.append("key"); XCTAssertEqual(key, "fixture")
            },
            makeDefault: { _ in steps.append("default") }
        )
        let result = await creator.save(draft, key: " fixture ")
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(steps, ["check", "create", "key", "default"])
    }

    func testFreshDuplicateCheckPreventsUpsert() async {
        let creator = ChannelCreator(
            existingNames: { ["test-channel"] },
            create: { _, _ in XCTFail("Must not overwrite") },
            addKey: { _, _ in XCTFail("Must not add credential") },
            makeDefault: { _ in XCTFail("Must not change default") }
        )
        let result = await creator.save(draft, key: "fixture")
        XCTAssertFalse(result.didCreate)
        guard case .failed(let message) = result else { return XCTFail("Expected duplicate failure") }
        XCTAssertEqual(message, L10n.tr("同名渠道已存在，请换一个名称。"))
    }

    func testOfflineNameCheckDoesNotCreateBlindly() async {
        let creator = ChannelCreator(
            existingNames: { throw URLError(.cannotConnectToHost) },
            create: { _, _ in XCTFail("Must not write") },
            addKey: { _, _ in XCTFail("Must not write") },
            makeDefault: { _ in XCTFail("Must not write") }
        )
        let result = await creator.save(draft, key: "fixture")
        XCTAssertFalse(result.didCreate)
    }

    func testKeyFailureReportsPartialWithoutDefaultOrLeakingError() async {
        let creator = ChannelCreator(
            existingNames: { [] }, create: { _, _ in },
            addKey: { _, _ in throw OpenCodexAPIError.operationFailed("sensitive-fixture") },
            makeDefault: { _ in XCTFail("Must not switch without key") }
        )
        let result = await creator.save(draft, key: "fixture")
        XCTAssertTrue(result.didCreate)
        guard case .partial(let message) = result else { return XCTFail("Expected partial completion") }
        XCTAssertEqual(message, L10n.tr("渠道已创建，但密钥写入未确认，未切换默认渠道。请关闭后检查该渠道的 Key 状态，必要时点「添加 Key」。"))
        XCTAssertFalse(message.contains("sensitive-fixture"))
    }

    func testDefaultFailurePreservesCreatedChannel() async {
        let creator = ChannelCreator(
            existingNames: { [] }, create: { _, _ in }, addKey: { _, _ in },
            makeDefault: { _ in throw URLError(.timedOut) }
        )
        let result = await creator.save(draft, key: "fixture")
        guard case .partial = result else { return XCTFail("Expected partial completion") }
    }

    func testLostCreateAcknowledgementDoesNotOverwriteOnRetry() async {
        var names: [String] = []
        var creates = 0
        let creator = ChannelCreator(
            existingNames: { names },
            create: { name, _ in
                names.append(name)
                creates += 1
                throw URLError(.timedOut)
            },
            addKey: { _, _ in XCTFail("Must not continue") },
            makeDefault: { _ in XCTFail("Must not continue") }
        )
        let first = await creator.save(draft, key: "fixture")
        let second = await creator.save(draft, key: "fixture")
        XCTAssertFalse(first.didCreate)
        XCTAssertFalse(second.didCreate)
        XCTAssertEqual(creates, 1)
    }

    func testLocalAuthenticationNeverSendsStaleKey() async {
        var local = draft
        local.requiresKey = false
        local.setDefault = false
        let creator = ChannelCreator(
            existingNames: { [] },
            create: { _, payload in XCTAssertEqual(payload.authMode, "local") },
            addKey: { _, _ in XCTFail("Must not send key") },
            makeDefault: { _ in XCTFail("Not requested") }
        )
        let result = await creator.save(local, key: "stale-fixture")
        XCTAssertEqual(result, .saved)
    }
}

final class ChannelWriteContractTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    private func client(reply: String) -> OpenCodexAPIClient {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data(reply.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return OpenCodexAPIClient(
            host: "localhost", port: 1,
            session: URLSession(configuration: configuration),
            tokenProvider: AdminTokenProvider(environment: ["OPENCODEX_ADMIN_AUTH_TOKEN": "fixture-token"]))
    }

    func testCreateRequiresPositiveAcknowledgement() async {
        for reply in ["{}", #"{"success":false}"#] {
            do {
                try await client(reply: reply).createChannel(
                    name: "fixture",
                    payload: ChannelPayload(adapter: "google", baseUrl: "https://example.test"), setDefault: false)
                XCTFail("Unconfirmed save must not succeed")
            } catch { XCTAssertTrue(error is OpenCodexAPIError) }
        }
    }

    func testKeyRequiresPositiveAcknowledgement() async {
        for reply in ["{}", #"{"ok":false}"#] {
            do {
                try await client(reply: reply).addChannelKey(name: "fixture", key: "fixture-key")
                XCTFail("Unconfirmed key write must not succeed")
            } catch { XCTAssertTrue(error is OpenCodexAPIError) }
        }
    }

    func testDefaultRequiresPositiveAcknowledgement() async {
        do {
            try await client(reply: #"{"success":false}"#).setDefaultChannel(name: "fixture")
            XCTFail("Unconfirmed default must not succeed")
        } catch { XCTAssertTrue(error is OpenCodexAPIError) }
    }

    func testPositiveAcknowledgements() async throws {
        try await client(reply: #"{"success":true}"#).createChannel(
            name: "fixture",
            payload: ChannelPayload(adapter: "openai-chat", baseUrl: "https://example.test/v1"), setDefault: false)
        try await client(reply: #"{"ok":true}"#).addChannelKey(name: "fixture", key: "fixture-key")
        try await client(reply: #"{"success":true}"#).setDefaultChannel(name: "fixture")
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
