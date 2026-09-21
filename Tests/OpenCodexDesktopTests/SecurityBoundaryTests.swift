import Foundation
import XCTest

@testable import OpenCodexDesktop

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
            let body = #"{"codexRuntime":{"path":"codex","version":"0.148.0","source":"path","warning":null}}"#
            return (response, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = OpenCodexAPIClient(
            host: "localhost",
            port: AppConstants.Connection.defaultPort,
            session: URLSession(configuration: configuration),
            tokenProvider: AdminTokenProvider(environment: ["OPENCODEX_ADMIN_AUTH_TOKEN": "test-token"])
        )

        let settings = try await client.settings()

        XCTAssertEqual(settings.codexRuntime?.version, "0.148.0")
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
            _ = try await client.settings()
            XCTFail("Expected unauthorized error")
        } catch let error as OpenCodexAPIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUsageReadsSevenDayAggregateFromLoopback() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/usage")
            XCTAssertEqual(request.url?.query, "range=7d")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-OpenCodex-API-Key"), "test-token")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
                {"range":"7d","summary":{"requests":1,"measuredRequests":1,
                "totalTokens":12,"coverageRatio":1},"days":[],"models":[]}
                """
            return (response, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = OpenCodexAPIClient(
            host: "localhost",
            port: AppConstants.Connection.defaultPort,
            session: URLSession(configuration: configuration),
            tokenProvider: AdminTokenProvider(environment: ["OPENCODEX_ADMIN_AUTH_TOKEN": "test-token"])
        )

        let report = try await client.usage()

        XCTAssertEqual(report.summary.requests, 1)
    }

    private func stopClient() -> OpenCodexAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return OpenCodexAPIClient(
            host: "localhost", port: 10100,
            session: URLSession(configuration: configuration),
            tokenProvider: AdminTokenProvider(environment: ["OPENCODEX_ADMIN_AUTH_TOKEN": "test-token"]))
    }

    func testStopRequiresExplicitSuccessNotJustHTTP200() async throws {
        for body in [#"{"success":true}"#, #"{"success":false,"message":"restore failed"}"#, #"{"ok":true}"#, "{}"] {
            URLProtocolStub.handler = { request in
                XCTAssertEqual(request.url?.path, "/api/stop")
                XCTAssertEqual(request.httpMethod, "POST")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8)
                )
            }
            do {
                try await stopClient().stopProxy()
                XCTAssertEqual(body, #"{"success":true}"#)
            } catch {
                XCTAssertNotEqual(body, #"{"success":true}"#)
                guard case OpenCodexAPIError.operationFailed = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testOnlyConnectionRefusalConfirmsStoppedListener() async throws {
        URLProtocolStub.handler = { _ in throw URLError(.cannotConnectToHost) }
        let stopped = try await stopClient().isProxyListenerStopped()
        XCTAssertTrue(stopped)
        URLProtocolStub.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await stopClient().isProxyListenerStopped()
            XCTFail("Timeout is not evidence of a stopped process")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        URLProtocolStub.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "X-OpenCodex-API-Key"))
            return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data())
        }
        let stillListening = try await stopClient().isProxyListenerStopped()
        XCTAssertFalse(stillListening)
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
