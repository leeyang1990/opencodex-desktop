import Foundation
import XCTest

@testable import OpenCodexDesktop

final class DesktopPreferencesTests: XCTestCase {
    func testCoreAutoStartDefaultsToDisabled() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertFalse(DesktopPreferences.startsCoreWithApp(in: defaults))
    }

    @MainActor
    func testCoreAutoStartLoadsAndPersistsBothStates() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(true, forKey: DesktopPreferences.startsCoreWithAppKey)
        let model = AppModel(defaults: defaults)
        XCTAssertTrue(model.startsCoreWithApp)

        model.startsCoreWithApp = false
        XCTAssertFalse(DesktopPreferences.startsCoreWithApp(in: defaults))

        model.startsCoreWithApp = true
        XCTAssertTrue(DesktopPreferences.startsCoreWithApp(in: defaults))
    }

    func testCoreStartsWithAppOnlyWhenEnabledInstalledAndOffline() {
        XCTAssertTrue(
            DesktopPreferences.shouldStartCoreWithApp(
                preferenceEnabled: true,
                connectionState: .offline,
                isCoreInstalled: true
            )
        )
        XCTAssertFalse(
            DesktopPreferences.shouldStartCoreWithApp(
                preferenceEnabled: false,
                connectionState: .offline,
                isCoreInstalled: true
            )
        )
        XCTAssertFalse(
            DesktopPreferences.shouldStartCoreWithApp(
                preferenceEnabled: true,
                connectionState: .offline,
                isCoreInstalled: false
            )
        )
        XCTAssertFalse(
            DesktopPreferences.shouldStartCoreWithApp(
                preferenceEnabled: true,
                connectionState: .online,
                isCoreInstalled: true
            )
        )
        XCTAssertFalse(
            DesktopPreferences.shouldStartCoreWithApp(
                preferenceEnabled: true,
                connectionState: .unauthorized,
                isCoreInstalled: true
            )
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "DesktopPreferencesTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }
}
