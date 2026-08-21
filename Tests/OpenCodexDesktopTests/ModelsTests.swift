import XCTest

@testable import OpenCodexDesktop

final class ModelsTests: XCTestCase {
    func testProviderDecodesRedactedManagementResponse() throws {
        let data = Data(
            #"""
            {
              "name": "openrouter",
              "adapter": "openai-chat",
              "baseUrl": "https://openrouter.ai/api/v1",
              "defaultModel": "openai/gpt-5",
              "hasApiKey": true,
              "allowPrivateNetwork": false,
              "liveModels": true,
              "models": [],
              "authMode": "key",
              "disabled": false
            }
            """#.utf8)

        let provider = try JSONDecoder().decode(Provider.self, from: data)

        XCTAssertEqual(provider.name, "openrouter")
        XCTAssertTrue(provider.hasApiKey)
        XCTAssertEqual(provider.displayAuth, "API Key")
        XCTAssertEqual(provider.displayModel, "openai/gpt-5")
    }

    func testProviderDraftValidationRejectsUnsafeName() {
        var draft = ProviderDraft()
        draft.name = "bad/name"
        draft.baseUrl = "https://example.com/v1"

        XCTAssertNotNil(draft.validationMessage)
    }

    func testProviderDraftValidationAcceptsHTTPSProvider() {
        var draft = ProviderDraft()
        draft.name = "my-provider"
        draft.baseUrl = "https://example.com/v1"

        XCTAssertNil(draft.validationMessage)
    }

    func testPresetAppliesKnownFields() throws {
        let data = Data(
            #"""
            {
              "id": "anthropic",
              "label": "Anthropic",
              "adapter": "anthropic",
              "baseUrl": "https://api.anthropic.com/v1",
              "auth": "key",
              "defaultModel": "claude-sonnet-4"
            }
            """#.utf8)
        let preset = try JSONDecoder().decode(ProviderPreset.self, from: data)
        var draft = ProviderDraft()

        draft.apply(preset)

        XCTAssertEqual(draft.name, "anthropic")
        XCTAssertEqual(draft.adapter, "anthropic")
        XCTAssertEqual(draft.defaultModel, "claude-sonnet-4")
    }

    func testCodexAccountDecodesMaskedManagementResponse() throws {
        let data = Data(
            #"""
            {
              "id": "__main__",
              "email": "l***0@gmail.com",
              "plan": "pro",
              "isMain": true,
              "paused": false,
              "priority": 0,
              "hasCredential": true,
              "needsReauth": false,
              "quota": { "weeklyPercent": 14, "weeklyResetAt": 1787011132 },
              "health": { "status": "healthy" },
              "healthLabel": "Healthy"
            }
            """#.utf8)

        let account = try JSONDecoder().decode(CodexAccount.self, from: data)

        XCTAssertTrue(account.isMain)
        XCTAssertEqual(account.effectiveID, "__main__")
        XCTAssertEqual(account.quota?.weeklyPercent, 14)
        XCTAssertTrue(account.isHealthy)
    }

    func testAccountPoolStatusDecodesRotationStrategy() throws {
        let data = Data(
            #"""
            {
              "activeCodexAccountId": "__main__",
              "pinned": false,
              "pinnedAccountId": null,
              "autoSwitchThreshold": 80,
              "upstreamFailoverThreshold": 3,
              "accountPoolStrategy": "round-robin",
              "accountPoolStickyLimit": 1
            }
            """#.utf8)

        let status = try JSONDecoder().decode(CodexAccountPoolStatus.self, from: data)

        XCTAssertEqual(status.accountPoolStrategy, .roundRobin)
        XCTAssertEqual(status.autoSwitchThreshold, 80)
    }

    func testManagedModelDecodesCatalogCapabilities() throws {
        let data = Data(
            #"""
            {
              "provider": "openrouter",
              "id": "anthropic/claude-sonnet-4.5",
              "namespaced": "openrouter/anthropic%2Fclaude-sonnet-4.5",
              "disabled": false,
              "custom": true,
              "customId": "model-1",
              "displayName": "Claude Sonnet 4.5",
              "contextWindow": 200000,
              "inputModalities": ["text", "image"],
              "reasoningEfforts": ["low", "high"]
            }
            """#.utf8)

        let item = try JSONDecoder().decode(ManagedModel.self, from: data)

        XCTAssertEqual(item.provider, "openrouter")
        XCTAssertEqual(item.title, "Claude Sonnet 4.5")
        XCTAssertEqual(item.contextWindow, 200_000)
        XCTAssertTrue(item.custom)
        XCTAssertTrue(item.supportsVision)
        XCTAssertFalse(item.supportsAudio)
    }

    func testCustomModelDraftValidatesAndBuildsModalities() {
        var draft = CustomModelDraft()
        draft.provider = "openrouter"
        draft.modelID = "test-model"
        draft.contextWindow = "128,000"
        draft.supportsImage = true

        XCTAssertNil(draft.validationMessage)
        XCTAssertEqual(draft.parsedContextWindow, 128_000)
        XCTAssertEqual(draft.modalities, ["text", "image"])

        draft.modelID = "bad/model"
        XCTAssertNotNil(draft.validationMessage)
    }

    func testProviderMutationDecodesCatalogRefreshFailure() throws {
        let data = Data(
            #"""
            {
              "success": true,
              "name": "litellm-local",
              "disabled": true,
              "catalogRefresh": {
                "status": "failed",
                "reason": "disk",
                "phase": "gather",
                "retryable": false,
                "partialWrite": false
              }
            }
            """#.utf8)

        let response = try JSONDecoder().decode(APIAcknowledgement.self, from: data)

        XCTAssertEqual(response.catalogRefresh?.status, "failed")
        XCTAssertFalse(response.catalogRefresh?.isCommitted ?? true)
    }

    func testCommittedCatalogRefreshDoesNotNeedFallback() throws {
        let data = Data(
            #"""
            {
              "success": true,
              "catalogRefresh": {
                "status": "committed",
                "changed": true,
                "degraded": false,
                "notices": []
              }
            }
            """#.utf8)

        let response = try JSONDecoder().decode(APIAcknowledgement.self, from: data)

        XCTAssertTrue(response.catalogRefresh?.isCommitted == true)
    }
}

final class AdminTokenProviderTests: XCTestCase {
    func testEnvironmentTokenWins() {
        let provider = AdminTokenProvider(
            environment: ["OPENCODEX_ADMIN_AUTH_TOKEN": "test-token"],
            homeDirectory: URL(fileURLWithPath: "/tmp/test-home")
        )

        XCTAssertEqual(provider.load(), "test-token")
    }

    func testCustomHomeSelectsExpectedTokenFile() {
        let provider = AdminTokenProvider(
            environment: ["OPENCODEX_HOME": "/tmp/custom-ocx"],
            homeDirectory: URL(fileURLWithPath: "/tmp/test-home")
        )

        XCTAssertEqual(provider.tokenFileURL.path, "/tmp/custom-ocx/admin-api-token")
    }

    func testRejectsSymbolicLinkTokenFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("real-token")
        let link = directory.appendingPathComponent("admin-api-token")
        try Data("ocx_admin_\(String(repeating: "a", count: 43))".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let provider = AdminTokenProvider(environment: ["OPENCODEX_HOME": directory.path])

        XCTAssertNil(provider.load())
    }
}

final class APIClientBoundaryTests: XCTestCase {
    func testClientRejectsRemoteHostBeforeSendingAdminToken() async {
        let client = OpenCodexAPIClient(host: "example.com", port: 10100)

        do {
            _ = try await client.baseURL()
            XCTFail("Expected remote management to be rejected")
        } catch let error as OpenCodexAPIError {
            XCTAssertEqual(error, .remoteManagementUnsupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientAcceptsLoopbackHosts() async throws {
        let client = OpenCodexAPIClient(host: "localhost", port: 10100)

        let url = try await client.baseURL()

        XCTAssertEqual(url.absoluteString, "http://localhost:10100")
    }
}
