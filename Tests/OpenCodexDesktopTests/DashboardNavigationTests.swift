import XCTest

@testable import OpenCodexDesktop

@MainActor
final class DashboardNavigationTests: XCTestCase {
    func testDashboardURLPointsToCoreWebApplication() {
        let suiteName = "DashboardNavigationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("127.0.0.1", forKey: "connectionHost")
        defaults.set(10_100, forKey: "connectionPort")

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.dashboardURL?.absoluteString, "http://127.0.0.1:10100/v1")
    }

    func testDashboardURLSupportsIPv6Loopback() {
        let suiteName = "DashboardNavigationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("::1", forKey: "connectionHost")
        defaults.set(10_100, forKey: "connectionPort")

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.dashboardURL?.absoluteString, "http://[::1]:10100/v1")
    }

    func testSidebarContainsOnlyNativeSurfacesAndEmbeddedDashboard() {
        XCTAssertEqual(SidebarDestination.allCases, [.overview, .diagnostics, .dashboard, .settings])
        XCTAssertEqual(SidebarDestination.diagnostics.title, "诊断与修复")
        XCTAssertEqual(SidebarDestination.dashboard.title, "OpenCodex 控制台")
    }

    func testEmbeddedDashboardAllowsOnlyItsExactLoopbackOrigin() {
        let dashboard = URL(string: "http://127.0.0.1:10100/v1")!

        XCTAssertTrue(
            DashboardNavigationPolicy.allows(
                URL(string: "http://127.0.0.1:10100/v1#providers")!,
                dashboardURL: dashboard
            )
        )
        XCTAssertFalse(
            DashboardNavigationPolicy.allows(
                URL(string: "http://127.0.0.1:10101/v1")!,
                dashboardURL: dashboard
            )
        )
        XCTAssertFalse(
            DashboardNavigationPolicy.allows(
                URL(string: "https://github.com/lidge-jun/opencodex")!,
                dashboardURL: dashboard
            )
        )
    }
}
