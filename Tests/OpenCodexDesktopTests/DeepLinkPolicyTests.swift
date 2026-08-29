import Foundation
import XCTest

@testable import OpenCodexDesktop

final class DeepLinkPolicyTests: XCTestCase {
    func testMapsNavigationOnlyRoutes() throws {
        XCTAssertEqual(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://status"))), .overview)
        XCTAssertEqual(
            DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex:///diagnostics"))),
            .diagnostics
        )
        XCTAssertEqual(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://console"))), .dashboard)
        XCTAssertEqual(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://settings"))), .settings)
    }

    func testRejectsUnknownAndForeignRoutes() throws {
        XCTAssertNil(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://restart"))))
        XCTAssertNil(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "https://example.com/diagnostics"))))
    }
}
