import Foundation
import XCTest

@testable import OpenCodexDesktop

/// Subagent selection rules: at most five, ordered, and refusing rather than silently dropping.
@MainActor
final class SubagentSelectionTests: XCTestCase {
    private func makeModel() -> AppModel {
        let suiteName = "SubagentSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let model = AppModel(
            defaults: defaults,
            client: OpenCodexAPIClient(host: "127.0.0.1", port: 1),
            eventStore: .scratch()
        )
        // The write itself is a transport concern; these tests cover the selection rules.
        model.setSubagentSelectionOperation = { _ in }
        return model
    }

    /// A full selection must refuse a sixth entry instead of letting the Core truncate it.
    func testSelectingBeyondTheCapIsRefusedWithAReason() async {
        let model = makeModel()
        model.subagentModels = ["a", "b", "c", "d", "e"]

        await model.toggleSubagentModel("f")

        XCTAssertEqual(model.subagentModels, ["a", "b", "c", "d", "e"])
        XCTAssertEqual(model.subagentErrorMessage?.contains("5"), true)
    }

    func testDeselectingIsAlwaysAllowed() async {
        let model = makeModel()
        model.subagentModels = ["a", "b"]

        await model.toggleSubagentModel("a")

        XCTAssertEqual(model.subagentModels, ["b"])
    }

    func testSelectedModelsAreReportedForTheAvailableList() {
        let model = makeModel()
        model.subagentModels = ["gpt-5.5"]

        XCTAssertTrue(model.isSubagentModelSelected("gpt-5.5"))
        XCTAssertFalse(model.isSubagentModelSelected("gpt-5.6-terra"))
    }

}

/// Channel credential handling: session-only storage, and no key echoed back to the UI.
@MainActor
final class ChannelKeyHandlingTests: XCTestCase {
    private func makeModel() -> AppModel {
        let suiteName = "ChannelKeyHandlingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppModel(defaults: defaults, client: OpenCodexAPIClient(host: "127.0.0.1", port: 1))
    }

    func testTypedKeysStayInMemoryOnly() {
        let model = makeModel()

        model.setChannelKey("sk-test-value", for: "new-api")

        XCTAssertEqual(model.channelKey(for: "new-api"), "sk-test-value")
        // Nothing may reach preferences: the key exists only in the session dictionary.
        XCTAssertNil(model.defaults.string(forKey: "sk-test-value"))
        let stored = model.defaults.dictionaryRepresentation().values.compactMap { $0 as? String }
        XCTAssertFalse(stored.contains("sk-test-value"), "a channel key reached UserDefaults")
    }

    func testClearingAKeyRemovesItFromMemory() {
        let model = makeModel()
        model.setChannelKey("sk-test-value", for: "new-api")

        model.setChannelKey("", for: "new-api")

        XCTAssertEqual(model.channelKey(for: "new-api"), "")
        XCTAssertTrue(model.pendingChannelKeys.isEmpty)
    }

}
