import XCTest

@testable import OpenCodexDesktop

final class AdminTokenProviderTests: XCTestCase {
    func testEnvironmentTokenWins() {
        let provider = AdminTokenProvider(
            environment: ["OPENCODEX_ADMIN_AUTH_TOKEN": "test-token"],
            homeDirectory: URL(fileURLWithPath: "/tmp/test-home")
        )

        XCTAssertEqual(provider.load(), "test-token")
    }

    func testCustomHomeSelectsExpectedTokenFile() {
        let provider = AdminTokenProvider(
            environment: ["OPENCODEX_HOME": "/tmp/custom-ocx"],
            homeDirectory: URL(fileURLWithPath: "/tmp/test-home")
        )

        XCTAssertEqual(provider.tokenFileURL.path, "/tmp/custom-ocx/admin-api-token")
    }

    func testRejectsSymbolicLinkTokenFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("real-token")
        let link = directory.appendingPathComponent("admin-api-token")
        try Data("ocx_admin_\(String(repeating: "a", count: 43))".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let provider = AdminTokenProvider(environment: ["OPENCODEX_HOME": directory.path])

        XCTAssertNil(provider.load())
    }
}

final class APIClientBoundaryTests: XCTestCase {
    func testClientRejectsRemoteHostBeforeSendingAdminToken() async {
        let client = OpenCodexAPIClient(host: "example.com", port: 10100)

        do {
            _ = try await client.baseURL()
            XCTFail("Expected remote management to be rejected")
        } catch let error as OpenCodexAPIError {
            XCTAssertEqual(error, .remoteManagementUnsupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientAcceptsLoopbackHosts() async throws {
        let client = OpenCodexAPIClient(host: "localhost", port: 10100)

        let url = try await client.baseURL()

        XCTAssertEqual(url.absoluteString, "http://localhost:10100")
    }
}
