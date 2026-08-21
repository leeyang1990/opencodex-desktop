import Foundation
import XCTest

@testable import OpenCodexDesktop

final class ExternalURLPolicyTests: XCTestCase {
    func testAllowsOfficialHTTPSLoginURLs() {
        XCTAssertEqual(
            ExternalURLPolicy.trustedLoginURL(from: "https://auth.openai.com/authorize")?.host,
            "auth.openai.com"
        )
        XCTAssertEqual(
            ExternalURLPolicy.trustedLoginURL(from: "https://chatgpt.com/auth/login")?.host,
            "chatgpt.com"
        )
    }

    func testRejectsUntrustedSchemesHostsCredentialsAndPorts() {
        XCTAssertNil(ExternalURLPolicy.trustedLoginURL(from: "http://auth.openai.com/authorize"))
        XCTAssertNil(ExternalURLPolicy.trustedLoginURL(from: "file:///tmp/payload"))
        XCTAssertNil(ExternalURLPolicy.trustedLoginURL(from: "https://openai.com.evil.example/login"))
        XCTAssertNil(ExternalURLPolicy.trustedLoginURL(from: "https://user:pass@openai.com/login"))
        XCTAssertNil(ExternalURLPolicy.trustedLoginURL(from: "https://openai.com:8443/login"))
    }
}

final class ProviderTransportSecurityTests: XCTestCase {
    func testWarnsForNonLoopbackHTTPProvider() {
        var draft = ProviderDraft()
        draft.name = "private-api"
        draft.baseUrl = "http://203.0.113.10:3000/v1"

        XCTAssertNotNil(draft.transportSecurityWarning)
    }

    func testDoesNotWarnForHTTPSOrLoopback() {
        var draft = ProviderDraft()
        draft.name = "secure-api"
        draft.baseUrl = "https://api.example.com/v1"
        XCTAssertNil(draft.transportSecurityWarning)

        draft.baseUrl = "http://127.0.0.1:3000/v1"
        XCTAssertNil(draft.transportSecurityWarning)
    }
}

final class ConfigurationPermissionTests: XCTestCase {
    func testVisionRoutingStateIsPrivate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.json")
        let stateDirectory = directory.appendingPathComponent("state", isDirectory: true)
        let stateURL = stateDirectory.appendingPathComponent("vision-routing.json")
        try #"{"providers":{"local":{"adapter":"openai-chat","models":["vision-model"]}}}"#
            .data(using: .utf8)!
            .write(to: configURL)

        let store = VisionRoutingSettingsStore(configURL: configURL, stateURL: stateURL)
        try store.save(forceGPTVision: true)

        XCTAssertEqual(permissions(at: stateDirectory), 0o700)
        XCTAssertEqual(permissions(at: stateURL), 0o600)
        XCTAssertEqual(permissions(at: configURL), 0o600)
    }

    private func permissions(at url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? Int).map { $0 & 0o777 }
    }
}

final class APIClientRequestTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testAuthenticatedRequestUsesManagementHeaderOnLoopback() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.host, "localhost")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-OpenCodex-API-Key"), "test-token")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("[]".utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = OpenCodexAPIClient(
            host: "localhost",
            port: AppConstants.Connection.defaultPort,
            session: URLSession(configuration: configuration),
            tokenProvider: AdminTokenProvider(environment: ["OPENCODEX_ADMIN_AUTH_TOKEN": "test-token"])
        )

        let providers = try await client.providers()

        XCTAssertTrue(providers.isEmpty)
    }

    func testUnauthorizedResponseMapsToDomainError() async {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = OpenCodexAPIClient(
            host: "localhost",
            port: AppConstants.Connection.defaultPort,
            session: URLSession(configuration: configuration),
            tokenProvider: AdminTokenProvider(environment: ["OPENCODEX_ADMIN_AUTH_TOKEN": "test-token"])
        )

        do {
            _ = try await client.providers()
            XCTFail("Expected unauthorized error")
        } catch let error as OpenCodexAPIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
