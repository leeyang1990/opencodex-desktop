import Foundation
import XCTest

@testable import OpenCodexDesktop

/// Decoding coverage for the three configuration surfaces, pinned to payloads taken from a live
/// Core so a shape change fails here instead of showing an empty page.
final class ConfigurationPayloadTests: XCTestCase {
    func testDecodesAggregatedUsageWithoutRequestContent() throws {
        let json = """
            {"range":"7d","generatedAt":1789746163678,
             "summary":{"requests":896,"measuredRequests":635,"totalTokens":53627104,
             "coverageRatio":0.7087,"estimatedCostUsd":41.28},
             "days":[{"date":"2026-09-18","requests":335,"measuredRequests":319,
             "totalTokens":29520954}],
             "models":[{"provider":"openai","model":"gpt-5.6-sol","requests":72,
             "totalTokens":11607785}]}
            """
        let report = try JSONDecoder().decode(UsageReport.self, from: Data(json.utf8))

        XCTAssertEqual(report.summary.requests, 896)
        XCTAssertEqual(report.summary.totalTokens, 53_627_104)
        XCTAssertEqual(report.days.first?.shortDate, "9/18")
        XCTAssertEqual(report.models.first?.id, "openai/gpt-5.6-sol")
        XCTAssertFalse(json.contains("prompt"))
        XCTAssertFalse(json.contains("response"))
    }

    func testDecodesCodexAccountPoolRow() throws {
        let json = """
            {"accounts":[{"id":"__main__","email":"t***t@example.test","plan":"pro","logLabel":"main",
            "isMain":true,"paused":false,"priority":0,"hasCredential":true,"needsReauth":false,
            "quota":{"weeklyPercent":49,"weeklyResetAt":1789813012,"resetCredits":0},
            "health":{"status":"healthy"},"healthLabel":"Healthy","healthSummary":"codex main account: healthy"}]}
            """
        let decoded = try JSONDecoder().decode(CodexAccountListProbe.self, from: Data(json.utf8))
        let account = try XCTUnwrap(decoded.accounts.first)

        XCTAssertEqual(account.id, CodexAccount.mainID)
        XCTAssertEqual(account.displayName, "main")
        XCTAssertEqual(account.plan, "pro")
        XCTAssertFalse(account.isPaused)
        XCTAssertTrue(account.isHealthy)
        XCTAssertEqual(account.quota?.weeklyPercent, 49)
        XCTAssertEqual(account.healthLabel, "Healthy")
    }

    func testDecodesSchedulingState() throws {
        let json = """
            {"activeCodexAccountId":"__main__","pinned":false,"pinnedAccountId":null,
            "autoSwitchThreshold":80,"upstreamFailoverThreshold":3,
            "accountPoolStrategy":"quota","accountPoolStickyLimit":1}
            """
        let scheduling = try JSONDecoder().decode(CodexAccountScheduling.self, from: Data(json.utf8))

        XCTAssertTrue(scheduling.isAutoSwitchEnabled)
        XCTAssertEqual(scheduling.upstreamFailoverThreshold, 3)
        XCTAssertEqual(CodexAccountScheduling.strategyTitle(scheduling.accountPoolStrategy), L10n.tr("按额度"))
    }

    /// Threshold 0 is how the Core expresses "do not switch automatically".
    func testZeroThresholdMeansAutoSwitchIsOff() throws {
        let json = #"{"activeCodexAccountId":"__main__","autoSwitchThreshold":0}"#
        let scheduling = try JSONDecoder().decode(CodexAccountScheduling.self, from: Data(json.utf8))

        XCTAssertFalse(scheduling.isAutoSwitchEnabled)
    }

    func testDecodesChannelsIncludingForwardingAndDiscovery() throws {
        let json = """
            [{"name":"new-api","adapter":"openai-chat","baseUrl":"https://example.test/v1","hasApiKey":true,
            "hasHeaders":false,"allowPrivateNetwork":true,"liveModels":true,"authMode":"key",
            "disabled":false,"models":["a","b"],"discovery":{"status":"failed","reason":"http","httpStatus":530}},
            {"name":"openai","adapter":"openai-responses","baseUrl":"https://chatgpt.com/backend-api/codex",
            "hasApiKey":false,"authMode":"forward","disabled":false,"codexAccountMode":"pool"}]
            """
        let channels = try JSONDecoder().decode([APIChannel].self, from: Data(json.utf8))

        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].modelCount, 2)
        XCTAssertFalse(channels[0].usesCredentialForwarding)
        XCTAssertEqual(channels[0].discovery?.httpStatus, 530)
        XCTAssertTrue(channels[1].usesCredentialForwarding)
        XCTAssertEqual(channels[1].codexAccountMode, "pool")
        // A channel without a `models` array must not read as having zero-configured models.
        XCTAssertEqual(channels[1].modelCount, 0)
    }

    func testDecodesSubagentSelection() throws {
        let selectionJSON = """
            {"chosen":["gpt-5.5","gpt-5.6-terra"],
             "available":["gpt-5.5","gpt-5.6-terra","new-api/x"]}
            """
        let selection = try JSONDecoder().decode(SubagentSelection.self, from: Data(selectionJSON.utf8))
        XCTAssertEqual(selection.chosen.count, 2)
        XCTAssertEqual(selection.available.count, 3)
    }

    /// The Core keeps only the first five silently, so the client caps before sending.
    func testSubagentCapMatchesTheCoreContract() {
        XCTAssertEqual(SubagentSelection.maximumChosen, 5)
    }

    /// A PATCH is a flat field mask: the Core rejects a nested `provider` object outright with
    /// "no recognized fields to update", so the wire shape is pinned here.
    func testChannelPatchIsAFlatFieldMask() throws {
        let patch = ChannelPatch(disabled: true)
        let encoded = try JSONEncoder().encode(patch)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["disabled"] as? Bool, true)
        XCTAssertNil(object["provider"], "a nested provider object is not a recognized patch field")
        XCTAssertNil(object["adapter"], "unset fields must stay absent from the mask")
        XCTAssertFalse(patch.isEmpty)
    }

    func testEmptyChannelPatchIsNotSent() {
        XCTAssertTrue(ChannelPatch().isEmpty)
    }

    /// Key material never travels in a channel create/patch body; it goes to the key endpoint.
    func testChannelPayloadCarriesNoKeyField() throws {
        let payload = ChannelPayload(adapter: "openai-chat", baseUrl: "https://example.test/v1")
        let encoded = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["adapter"] as? String, "openai-chat")
        XCTAssertNil(object["apiKey"])
        XCTAssertNil(object["key"])
    }

    /// The Core masks credentials; the shell must decode that shape rather than expecting a value.
    func testDecodesMaskedProviderKeyPool() throws {
        let json = #"{"activeId":"a0e62070","keys":[{"id":"a0e62070","masked":"sk-Q****Jpbm","active":true}]}"#
        let pool = try JSONDecoder().decode(ProviderKeyPool.self, from: Data(json.utf8))

        XCTAssertEqual(pool.activeId, "a0e62070")
        XCTAssertEqual(pool.keys.first?.masked, "sk-Q****Jpbm")
        XCTAssertTrue(pool.keys.first?.active == true)
    }

    func testProbeResultDecodesLiveResponse() throws {
        let json = #"{"ok":true,"latencyMs":634,"models":18,"message":"Connected — 18 models available."}"#
        let probe = try JSONDecoder().decode(ChannelProbeResult.self, from: Data(json.utf8))

        XCTAssertTrue(probe.ok == true)
        XCTAssertEqual(probe.message?.contains("18 models"), true)
    }
}

/// Local mirror of the private envelope so the test can decode the Core's account payload.
private struct CodexAccountListProbe: Decodable {
    let accounts: [CodexAccount]
}
