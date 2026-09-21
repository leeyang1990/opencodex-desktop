import Foundation
import XCTest

@testable import OpenCodexDesktop

@MainActor
final class ModelCatalogTests: XCTestCase {
    private func makeModel() -> AppModel {
        let suiteName = "ModelCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppModel(defaults: defaults, client: OpenCodexAPIClient(host: "127.0.0.1", port: 1))
    }

    private func model(
        provider: String,
        id: String,
        disabled: Bool = false,
        native: Bool? = nil,
        modalities: [String]? = ["text"]
    ) -> ManagedModel {
        ManagedModel(
            provider: provider,
            id: id,
            namespaced: native == true ? id : "\(provider)/\(id)",
            disabled: disabled,
            native: native,
            inputModalities: modalities
        )
    }

    func testModelsAreGroupedByProviderInListingOrder() {
        let model = makeModel()
        model.models = [
            self.model(provider: "openai", id: "gpt-5.5", native: true),
            self.model(provider: "new-api", id: "claude-sonnet"),
            self.model(provider: "openai", id: "gpt-5.4", native: true),
        ]

        let groups = model.modelsByProvider

        XCTAssertEqual(groups.map(\.provider), ["openai", "new-api"])
        XCTAssertEqual(groups[0].models.map(\.id), ["gpt-5.5", "gpt-5.4"])
        XCTAssertEqual(groups[1].models.map(\.id), ["claude-sonnet"])
    }

    func testEnabledCountIgnoresHiddenModels() {
        let model = makeModel()
        model.models = [
            self.model(provider: "openai", id: "gpt-5.5", native: true),
            self.model(provider: "new-api", id: "hidden", disabled: true),
        ]

        XCTAssertEqual(model.enabledModelCount, 1)
    }

    /// The visibility endpoint stores `provider/<id>` and compares against that, so a routed row
    /// must be addressed by its bare `id`. Sending `namespaced` persists a doubled prefix that no
    /// later read matches — a switch that reports success and changes nothing.
    func testSelectorUsesTheBareIdForRoutedRows() {
        let routed = self.model(provider: "new-api", id: "claude-haiku-4-5")
        XCTAssertEqual(routed.namespaced, "new-api/claude-haiku-4-5")
        XCTAssertEqual(routed.selector.id, "claude-haiku-4-5")
        XCTAssertFalse(routed.selector.native)

        let native = self.model(provider: "openai", id: "gpt-5.4", native: true)
        XCTAssertEqual(native.selector.id, "gpt-5.4")
        XCTAssertTrue(native.selector.native)
    }

    func testImageSupportIsReadFromModalities() {
        let withImage = self.model(provider: "openai", id: "a", native: true, modalities: ["text", "image"])
        let textOnly = self.model(provider: "openai", id: "b", native: true, modalities: ["text"])
        let unknown = self.model(provider: "openai", id: "c", native: true, modalities: nil)

        XCTAssertTrue(withImage.supportsImages)
        XCTAssertFalse(textOnly.supportsImages)
        XCTAssertFalse(unknown.supportsImages)
    }

    func testProviderSummariesPutTheDefaultProviderFirst() {
        let json = """
            {
              "port": 10100,
              "defaultProvider": "openai",
              "providers": {
                "new-api": {"adapter": "openai-chat", "baseUrl": "https://example.test/v1", "hasApiKey": true},
                "openai": {"adapter": "openai-responses", "authMode": "forward", "codexAccountMode": "pool"}
              }
            }
            """
        let config = try! JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

        let summaries = AppModel.summaries(from: config)

        XCTAssertEqual(summaries.map(\.id), ["openai", "new-api"])
        XCTAssertTrue(summaries[0].isDefault)
        XCTAssertEqual(summaries[0].codexAccountMode, "pool")
        XCTAssertEqual(summaries[1].adapter, "openai-chat")
        XCTAssertTrue(summaries[1].hasAPIKey)
        // Credentials are never surfaced, only their presence.
        XCTAssertFalse(summaries[0].hasAPIKey)
    }

    func testProviderSummarySurvivesConfigWithoutProviders() {
        let config = try! JSONDecoder().decode(CoreConfig.self, from: Data(#"{"port":10100}"#.utf8))

        XCTAssertTrue(AppModel.summaries(from: config).isEmpty)
    }

    /// A row without the `native` key is a routed model, not a native one.
    func testRoutedRowsAreNotNative() throws {
        let json = #"{"provider":"new-api","id":"claude","namespaced":"new-api/claude","disabled":false}"#
        let decoded = try JSONDecoder().decode(ManagedModel.self, from: Data(json.utf8))

        XCTAssertFalse(decoded.isNative)
        XCTAssertFalse(decoded.selector.native)
        XCTAssertFalse(decoded.disabled)
    }
}
