import XCTest

@testable import OpenCodexDesktop

/// The shell includes settings and opens the Core console in the browser instead of embedding a
/// WebKit copy of a page the Core already serves.
@MainActor
final class ShellNavigationTests: XCTestCase {
    private func makeModel(host: String = "127.0.0.1", port: Int = 10_100) -> AppModel {
        let suiteName = "ShellNavigationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(host, forKey: "connectionHost")
        defaults.set(port, forKey: "connectionPort")
        return AppModel(defaults: defaults)
    }

    func testConsoleURLPointsAtTheCoreServedConsole() {
        XCTAssertEqual(makeModel().consoleURL()?.absoluteString, "http://127.0.0.1:10100")
    }

    func testConsoleURLSupportsIPv6Loopback() {
        XCTAssertEqual(makeModel(host: "::1").consoleURL()?.absoluteString, "http://[::1]:10100")
    }

    func testAdvancedChannelConfigurationTargetsProvidersWithoutCredentials() throws {
        let url = try XCTUnwrap(makeModel(port: 12345).consoleURL(page: .providers))
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:12345#providers")
        XCTAssertNil(url.user)
        XCTAssertNil(url.password)
        XCTAssertNil(url.query)
    }

    func testProviderConsoleURLSupportsIPv6AndRejectsForeignHosts() {
        XCTAssertEqual(
            makeModel(host: "::1").consoleURL(page: .providers)?.absoluteString,
            "http://[::1]:10100#providers")
        XCTAssertEqual(makeModel(host: "example.com").consoleURL(page: .providers)?.host, "127.0.0.1")
    }

    /// The management token must never be sent off-host, so the console link cannot either.
    func testConsoleURLFallsBackToLoopbackForForeignHosts() {
        XCTAssertEqual(makeModel(host: "example.com").consoleURL()?.absoluteString, "http://127.0.0.1:10100")
    }

    func testShellContainsOnlyTheConfigurationSurfaces() {
        XCTAssertEqual(SidebarDestination.allCases, [.home, .accounts, .channels, .subagents, .settings])
        XCTAssertEqual(SidebarDestination.accounts.title, L10n.tr("账号"))
        XCTAssertEqual(SidebarDestination.channels.title, L10n.tr("渠道"))
        XCTAssertEqual(SidebarDestination.subagents.title, L10n.tr("子代理"))
        XCTAssertEqual(SidebarDestination.settings.title, L10n.tr("设置"))
    }
}
