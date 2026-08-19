import Foundation
import XCTest
@testable import OpenCodexDesktop

final class ImageGenerationSettingsTests: XCTestCase {
    func testRoundTripCustomProviderPreservesExistingConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        try #"{"providers":{"new-api":{"adapter":"openai-chat","authMode":"key","apiKey":"secret","baseUrl":"https://example.com/v1"}},"port":10100}"#.data(using: .utf8)!.write(to: url)
        let store = ImageGenerationSettingsStore(configURL: url)

        try store.save(ImageGenerationSettings(
            usesCustomProvider: true,
            provider: "new-api",
            timeoutMs: 120_000
        ))

        XCTAssertEqual(try store.load(), ImageGenerationSettings(
            usesCustomProvider: true,
            provider: "new-api",
            timeoutMs: 120_000
        ))
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let providers = root["providers"] as! [String: Any]
        let originalProvider = providers["new-api"] as! [String: Any]
        XCTAssertEqual(originalProvider["adapter"] as? String, "openai-chat")
        XCTAssertEqual(originalProvider["apiKey"] as? String, "secret")
        let imageProvider = providers["new-api.images"] as! [String: Any]
        XCTAssertEqual(imageProvider["adapter"] as? String, "openai-responses")
        XCTAssertEqual(imageProvider["apiKey"] as? String, "secret")
    }

    func testVisionRoutingToggleAddsAndRemovesForcedModels() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.json")
        let stateURL = directory.appendingPathComponent("vision-routing.json")
        try #"{"providers":{"new-api":{"adapter":"openai-chat","models":["vision-model"]},"openai":{"adapter":"openai-responses"}}}"#.data(using: .utf8)!.write(to: configURL)
        let store = VisionRoutingSettingsStore(configURL: configURL, stateURL: stateURL)

        try store.save(forceGPTVision: true)
        XCTAssertTrue(store.load())
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        var providers = root["providers"] as! [String: Any]
        var newAPI = providers["new-api"] as! [String: Any]
        XCTAssertEqual(newAPI["noVisionModels"] as? [String], ["vision-model"])

        try store.save(forceGPTVision: false)
        XCTAssertFalse(store.load())
        root = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        providers = root["providers"] as! [String: Any]
        newAPI = providers["new-api"] as! [String: Any]
        XCTAssertNil(newAPI["noVisionModels"])
    }

    func testAutomaticRoutingRemovesOnlyExplicitProvider() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        try #"{"images":{"provider":"custom","bridgeEnabled":true,"timeoutMs":60000}}"#.data(using: .utf8)!.write(to: url)
        let store = ImageGenerationSettingsStore(configURL: url)

        try store.save(ImageGenerationSettings(usesCustomProvider: false, provider: "custom", timeoutMs: 300_000))

        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let images = root["images"] as! [String: Any]
        XCTAssertNil(images["provider"])
        XCTAssertEqual(images["bridgeEnabled"] as? Bool, true)
        XCTAssertEqual(images["timeoutMs"] as? Int, 300_000)
    }
}
