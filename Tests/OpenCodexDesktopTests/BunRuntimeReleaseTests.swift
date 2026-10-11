import CryptoKit
import Foundation
import XCTest

@testable import OpenCodexDesktop

final class BunRuntimeReleaseTests: XCTestCase {
    private let version = "1.4.2"
    private let armHash = String(repeating: "a", count: 64)
    private let x64Hash = String(repeating: "b", count: 64)

    private func metadata(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var value: [String: Any] = [
            "tag_name": "bun-v\(version)", "draft": false, "prerelease": false,
            "assets": [
                asset("bun-darwin-aarch64.zip", hash: armHash),
                asset("bun-darwin-x64.zip", hash: x64Hash),
            ],
        ]
        mutate(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }

    private func asset(_ name: String, hash: String) -> [String: Any] {
        [
            "name": name, "size": 25_000_000, "state": "uploaded", "digest": "sha256:\(hash)",
            "browser_download_url": BunRuntimeRelease.assetURL(version: version, name: name).absoluteString,
        ]
    }

    func testResolvesBothArchitecturesWithoutABuiltInRuntime() throws {
        XCTAssertFalse(CoreReleaseCatalog.all.contains { $0.bunVersion == version })
        let runtime = try BunRuntimeRelease.decode(metadata(), version: version)
        XCTAssertEqual(runtime.version, version)
        XCTAssertEqual(runtime.arm64SHA256, armHash)
        XCTAssertEqual(runtime.x64SHA256, x64Hash)
    }

    func testRejectsWrongTagDraftAndPrerelease() throws {
        for (key, value) in [("tag_name", "bun-v9.0.0" as Any), ("draft", true), ("prerelease", true)] {
            let data = try metadata { $0[key] = value }
            XCTAssertThrowsError(try BunRuntimeRelease.decode(data, version: version))
        }
    }

    func testRejectsMissingDuplicateForeignOrUnverifiableAssets() throws {
        let changes: [(inout [[String: Any]]) -> Void] = [
            { $0.removeLast() },
            { $0.append($0[0]) },
            { $0[0]["browser_download_url"] = "https://example.com/bun.zip" },
            {
                $0[0]["browser_download_url"] =
                    "https://github.com/oven-sh/bun/releases/download/bun-v1.4.0/bun-darwin-aarch64.zip"
            },
            { $0[0].removeValue(forKey: "digest") },
            { $0[0]["digest"] = "sha256:bad" },
            { $0[0]["state"] = "new" },
            { $0[0]["size"] = 0 },
            { $0[0]["size"] = 300 * 1_024 * 1_024 },
        ]
        for change in changes {
            let data = try metadata { value in
                var assets = value["assets"] as! [[String: Any]]
                change(&assets)
                value["assets"] = assets
            }
            XCTAssertThrowsError(try BunRuntimeRelease.decode(data, version: version))
        }
    }

    func testPreparationResolvesRuntimeAndPinsItsHashesThroughPublicMetadataOnly() async throws {
        let package = Data("core archive".utf8)
        let lock = Data("lock contents".utf8)
        let commit = String(repeating: "c", count: 40)
        let candidate = OnlineCoreVersion(
            name: OnlineCoreCatalog.packageName, version: "2.83.0", gitHead: commit,
            dist: .init(
                tarball: OnlineCoreCatalog.packageURL("2.83.0"),
                integrity: "sha512-" + Data(SHA512.hash(data: package)).base64EncodedString()),
            dependencies: ["bun": version], deprecated: nil)
        let lockMetadata = try JSONSerialization.data(withJSONObject: [
            "sha": Insecure.SHA1.hash(data: Data("blob \(lock.count)\0".utf8) + lock)
                .map { String(format: "%02x", $0) }.joined(),
            "encoding": "base64", "content": lock.base64EncodedString(), "size": lock.count,
        ])
        let fixtures: [String: Data] = [
            OnlineCoreCatalog.endpoint.appendingPathComponent(candidate.version).absoluteString:
                try JSONEncoder().encode(candidate),
            candidate.dist.tarball.absoluteString: package,
            "https://api.github.com/repos/lidge-jun/opencodex/contents/bun.lock?ref=\(commit)": lockMetadata,
            BunRuntimeRelease.metadataURL(version).absoluteString: try metadata(),
        ]
        RuntimeMetadataProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-OpenCodex-API-Key"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let url = try XCTUnwrap(request.url)
            let data = try XCTUnwrap(fixtures[url.absoluteString], "Unexpected URL: \(url)")
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        defer { RuntimeMetadataProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RuntimeMetadataProtocol.self]
        let release = try await OnlineCoreCatalogClient(configuration: config).prepare(candidate)
        XCTAssertEqual(release.bunVersion, version)
        XCTAssertEqual(release.bunArm64SHA256, armHash)
        XCTAssertEqual(release.bunX64SHA256, x64Hash)
        XCTAssertTrue(OnlineCoreCatalog.validatePrepared(release))
    }
}

private final class RuntimeMetadataProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
