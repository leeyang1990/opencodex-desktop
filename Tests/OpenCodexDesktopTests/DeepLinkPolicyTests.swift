import Foundation
import XCTest

@testable import OpenCodexDesktop

final class DeepLinkPolicyTests: XCTestCase {
    func testMapsMainWindowPages() throws {
        XCTAssertEqual(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://status"))), .home)
        XCTAssertEqual(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://accounts"))), .accounts)
        XCTAssertEqual(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://providers"))), .channels)
        XCTAssertEqual(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://subagents"))), .subagents)
        XCTAssertEqual(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://settings"))), .settings)
    }

    func testRejectsUnknownAndForeignRoutes() throws {
        XCTAssertNil(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://restart"))))
        XCTAssertNil(DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "https://example.com/accounts"))))
    }

    /// Surfaces that moved out of the tab strip must not resolve to a page that no longer exists.
    func testRejectsRetiredRoutes() throws {
        for route in ["console", "dashboard", "diagnostics", "models"] {
            XCTAssertNil(
                DeepLinkPolicy.destination(for: try XCTUnwrap(URL(string: "opencodex://\(route)"))),
                "\(route) should no longer map to a surface"
            )
        }
    }
}
