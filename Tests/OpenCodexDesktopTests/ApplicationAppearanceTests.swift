import Foundation
import XCTest

@testable import OpenCodexDesktop

final class DockVisibilityPreferenceTests: XCTestCase {
    func testDockIconIsVisibleByDefault() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertTrue(DockVisibilityPreference.load(from: defaults))
    }

    func testDockVisibilityPreferencePersistsBothStates() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        DockVisibilityPreference.save(false, to: defaults)
        XCTAssertFalse(DockVisibilityPreference.load(from: defaults))

        DockVisibilityPreference.save(true, to: defaults)
        XCTAssertTrue(DockVisibilityPreference.load(from: defaults))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "ApplicationAppearanceTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }
}
