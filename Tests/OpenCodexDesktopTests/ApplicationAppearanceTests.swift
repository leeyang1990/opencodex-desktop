import AppKit
import Foundation
import XCTest

@testable import OpenCodexDesktop

@MainActor
final class FrostedWindowMaterialTests: XCTestCase {
    func testMaterialSamplesBehindWindowRatherThanAnInAppGradient() {
        let view = FrostedWindowMaterialView()
        XCTAssertEqual(view.material, .underWindowBackground)
        XCTAssertEqual(view.blendingMode, .behindWindow)
        XCTAssertEqual(view.state, .active)
        XCTAssertEqual(view.appearance?.name, .aqua)
        XCTAssertFalse(view.isOpaque)
    }

    func testAttachingAndReattachingConfiguresTransparentWindow() {
        let view = FrostedWindowMaterialView()
        for _ in 0..<2 {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = view
            XCTAssertFalse(window.isOpaque)
            XCTAssertEqual(window.backgroundColor, .clear)
            XCTAssertEqual(window.appearance?.name, .aqua)
            XCTAssertTrue(window.titlebarAppearsTransparent)
            XCTAssertEqual(window.titleVisibility, .hidden)
            view.removeFromSuperview()
            window.close()
        }
    }
}

@MainActor
final class DockVisibilityReconciliationTests: XCTestCase {
    private final class ActivationStub: ApplicationActivationControlling {
        var policy: NSApplication.ActivationPolicy = .regular
        var acceptsChange = true
        var appliesChange = true
        var requestedPolicies: [NSApplication.ActivationPolicy] = []
        var activationCount = 0

        func setPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool {
            requestedPolicies.append(policy)
            if acceptsChange && appliesChange { self.policy = policy }
            return acceptsChange
        }
        func activate() { activationCount += 1 }
    }

    private func withAppearance(_ body: (ApplicationAppearance, ActivationStub, UserDefaults) throws -> Void) throws {
        let name = "DockVisibilityReconciliationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        DockVisibilityPreference.save(false, to: defaults)
        let activation = ActivationStub()
        try body(ApplicationAppearance(defaults: defaults, activation: activation), activation, defaults)
    }

    func testSavedHiddenPreferenceRepairsRuntimeEvenWhenToggleIsAlreadyOff() throws {
        try withAppearance { appearance, activation, _ in
            XCTAssertFalse(appearance.showsDockIcon)
            try appearance.setDockIconVisible(false)
            XCTAssertEqual(activation.policy, .accessory)
            XCTAssertEqual(activation.requestedPolicies, [.accessory])
        }
    }

    func testReconcilesLaunchOrReopenOverrideWithoutActivatingAgain() throws {
        try withAppearance { appearance, activation, _ in
            appearance.applyStoredPreference()
            activation.policy = .regular  // Simulate a scene/LaunchServices override.
            appearance.applyStoredPreference()
            appearance.applyStoredPreference()
            XCTAssertEqual(activation.requestedPolicies, [.accessory, .accessory])
            XCTAssertEqual(activation.activationCount, 0)
            XCTAssertFalse(appearance.showsDockIcon)
        }
    }

    func testFailedChangeShowsActualStateAndPreservesPreferenceForRetry() throws {
        try withAppearance { appearance, activation, defaults in
            activation.acceptsChange = false
            XCTAssertThrowsError(try appearance.setDockIconVisible(false))
            XCTAssertTrue(appearance.showsDockIcon)
            XCTAssertFalse(DockVisibilityPreference.load(from: defaults))
            activation.acceptsChange = true
            appearance.applyStoredPreference()
            XCTAssertFalse(appearance.showsDockIcon)
            XCTAssertEqual(activation.policy, .accessory)
        }
    }

    func testSuccessfulReturnMustAlsoMatchReadBackPolicy() throws {
        try withAppearance { appearance, activation, _ in
            activation.appliesChange = false
            XCTAssertThrowsError(try appearance.setDockIconVisible(false))
            XCTAssertTrue(appearance.showsDockIcon)
        }
    }

    func testVisiblePreferenceActivatesOnlyOnActualTransition() throws {
        try withAppearance { appearance, activation, defaults in
            appearance.applyStoredPreference()
            try appearance.setDockIconVisible(true)
            appearance.applyStoredPreference()
            XCTAssertEqual(activation.policy, .regular)
            XCTAssertTrue(appearance.showsDockIcon)
            XCTAssertTrue(DockVisibilityPreference.load(from: defaults))
            XCTAssertEqual(activation.activationCount, 1)
        }
    }
}

@MainActor
final class ApplicationAppearanceToggleTests: XCTestCase {
    /// The launcher is a single-window app: switching the Dock preference may only change the
    /// activation policy. It must never create a second main window, and showing the Dock icon
    /// again must not re-show windows the user already closed.
    func testTogglingDockIconKeepsMainWindowCountStable() throws {
        let suiteName = "ApplicationAppearanceToggleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appearance = ApplicationAppearance(defaults: defaults)
        defer { NSApplication.shared.setActivationPolicy(.regular) }

        let windowsBefore = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let visibleBefore = visibleMainWindows()

        // Hiding the Dock icon always succeeds; showing it again can only succeed in a process
        // that is allowed to become a regular app (a plain `swift test` process is not).
        try appearance.setDockIconVisible(false)
        XCTAssertEqual(NSApplication.shared.activationPolicy(), .accessory)
        do {
            try appearance.setDockIconVisible(true)
            XCTAssertTrue(appearance.showsDockIcon)
        } catch {
            XCTAssertEqual(NSApplication.shared.activationPolicy(), .accessory)
            XCTAssertFalse(appearance.showsDockIcon)
        }

        XCTAssertEqual(Set(NSApplication.shared.windows.map(ObjectIdentifier.init)), windowsBefore)
        XCTAssertEqual(visibleMainWindows(), visibleBefore)
    }

    /// Counts real on-screen main windows, ignoring panels, menus, and hidden windows.
    private func visibleMainWindows() -> Int {
        guard
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return 0 }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return info.filter { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) == ownPID
                && (window[kCGWindowLayer as String] as? Int) == 0
                && ((window[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) > 200
        }.count
    }
}

final class DockVisibilityPreferenceTests: XCTestCase {
    func testBundleStartsAsAgentBeforeApplyingUserPreference() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

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
