import Foundation
import XCTest

@testable import OpenCodexDesktop

final class AppSemanticVersionTests: XCTestCase {
    func testParsesTagsAndComparesNumericComponents() throws {
        let current = try XCTUnwrap(AppSemanticVersion("0.8.9"))
        let newerPatch = try XCTUnwrap(AppSemanticVersion("v0.8.10"))
        let newerMinor = try XCTUnwrap(AppSemanticVersion("0.9.0"))

        XCTAssertLessThan(current, newerPatch)
        XCTAssertLessThan(newerPatch, newerMinor)
        XCTAssertNil(AppSemanticVersion("latest"))
        XCTAssertNil(AppSemanticVersion("1.2"))
    }
}

final class AppUpdatePolicyTests: XCTestCase {
    func testSelectsExactArm64DiskImageAndChecksum() throws {
        let data = releasePayloadData(version: "0.8.1")

        let release = try XCTUnwrap(AppUpdatePolicy.release(from: data, currentVersion: "0.8.0"))

        XCTAssertEqual(release.version, "0.8.1")
        XCTAssertEqual(release.diskImageFileName, "OpenCodex-Desktop-v0.8.1-macOS-arm64.dmg")
        XCTAssertEqual(release.diskImageSize, 3_000_000)
        XCTAssertEqual(release.diskImageURL.scheme, "https")
        XCTAssertEqual(release.diskImageURL.host, "github.com")
    }

    func testReturnsNoUpdateForCurrentOrOlderRelease() throws {
        XCTAssertNil(
            try AppUpdatePolicy.release(from: releasePayloadData(version: "0.8.0"), currentVersion: "0.8.0")
        )
        XCTAssertNil(
            try AppUpdatePolicy.release(from: releasePayloadData(version: "0.7.1"), currentVersion: "0.8.0")
        )
    }

    func testRejectsUntrustedAssetURLAndMissingChecksum() {
        XCTAssertThrowsError(
            try AppUpdatePolicy.release(
                from: releasePayloadData(version: "0.8.1", assetHost: "downloads.example.com"),
                currentVersion: "0.8.0"
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdateError, .untrustedURL)
        }

        XCTAssertThrowsError(
            try AppUpdatePolicy.release(
                from: releasePayloadData(version: "0.8.1", includeChecksum: false),
                currentVersion: "0.8.0"
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdateError, .missingAssets)
        }
    }

    func testRejectsPrereleasesAndUnexpectedTagFormats() {
        XCTAssertThrowsError(
            try AppUpdatePolicy.release(
                from: releasePayloadData(version: "0.8.1", prerelease: true),
                currentVersion: "0.8.0"
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdateError, .unsupportedRelease)
        }

        let data = Data(
            releasePayloadJSON(version: "0.8.1")
                .replacingOccurrences(of: #""tag_name":"v0.8.1""#, with: #""tag_name":"0.8.1""#)
                .utf8
        )
        XCTAssertThrowsError(try AppUpdatePolicy.release(from: data, currentVersion: "0.8.0")) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidRelease)
        }
    }

    func testParsesChecksumOnlyForExpectedFile() throws {
        let fileName = "OpenCodex-Desktop-v0.8.1-macOS-arm64.dmg"
        let digest = String(repeating: "a", count: 64)
        let data = Data("\(digest)  \(fileName)\n".utf8)

        XCTAssertEqual(try AppUpdatePolicy.checksum(from: data, expectedFileName: fileName), digest)
        XCTAssertThrowsError(try AppUpdatePolicy.checksum(from: data, expectedFileName: "different.dmg"))
        XCTAssertThrowsError(
            try AppUpdatePolicy.checksum(
                from: Data("not-a-digest  \(fileName)\n".utf8),
                expectedFileName: fileName
            )
        )
    }

    func testHashesDownloadedFileWithoutLoadingItAllAtOnce() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(
            try AppUpdatePolicy.sha256(of: fileURL),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func testRestrictsAPIAndDownloadResponseHosts() {
        XCTAssertTrue(AppUpdatePolicy.trustedAPIResponseURL(AppUpdatePolicy.latestReleaseURL))
        XCTAssertFalse(AppUpdatePolicy.trustedAPIResponseURL(URL(string: "https://example.com/releases/latest")))
        XCTAssertTrue(
            AppUpdatePolicy.trustedDownloadResponseURL(
                URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/file")
            )
        )
        XCTAssertFalse(
            AppUpdatePolicy.trustedDownloadResponseURL(
                URL(string: "https://release-assets.githubusercontent.com.evil.test/file"))
        )
        XCTAssertFalse(AppUpdatePolicy.trustedDownloadResponseURL(URL(string: "http://github.com/file")))
    }

    private func releasePayloadData(
        version: String,
        assetHost: String = "github.com",
        includeChecksum: Bool = true,
        prerelease: Bool = false
    ) -> Data {
        Data(
            releasePayloadJSON(
                version: version,
                assetHost: assetHost,
                includeChecksum: includeChecksum,
                prerelease: prerelease
            ).utf8
        )
    }

    private func releasePayloadJSON(
        version: String,
        assetHost: String = "github.com",
        includeChecksum: Bool = true,
        prerelease: Bool = false
    ) -> String {
        let diskImageName = "OpenCodex-Desktop-v\(version)-macOS-arm64.dmg"
        let checksumAsset =
            includeChecksum
            ? #",{"name":"\#(diskImageName).sha256","size":107,"browser_download_url":"https://\#(assetHost)/leeyang1990/opencodex-desktop/releases/download/v\#(version)/\#(diskImageName).sha256"}"#
            : ""
        return
            #"{"tag_name":"v\#(version)","html_url":"https://github.com/leeyang1990/opencodex-desktop/releases/tag/v\#(version)","draft":false,"prerelease":\#(prerelease),"body":"Notes","assets":[{"name":"\#(diskImageName)","size":3000000,"browser_download_url":"https://\#(assetHost)/leeyang1990/opencodex-desktop/releases/download/v\#(version)/\#(diskImageName)"}\#(checksumAsset)]}"#
    }
}

final class AppUpdatePreferenceTests: XCTestCase {
    func testAutomaticChecksDefaultToEnabledAndPersistBothStates() throws {
        let suiteName = "AppUpdatePreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(AppUpdatePreference.automaticChecksEnabled(in: defaults))
        AppUpdatePreference.setAutomaticChecksEnabled(false, in: defaults)
        XCTAssertFalse(AppUpdatePreference.automaticChecksEnabled(in: defaults))
        AppUpdatePreference.setAutomaticChecksEnabled(true, in: defaults)
        XCTAssertTrue(AppUpdatePreference.automaticChecksEnabled(in: defaults))
    }
}

@MainActor
final class AppUpdateManagerEndToEndTests: XCTestCase {
    override func tearDown() {
        UpdateURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testChecksDownloadsVerifiesAndStoresReleaseDiskImage() async throws {
        let version = "9.9.9"
        let diskImageName = "OpenCodex-Desktop-v\(version)-macOS-arm64.dmg"
        let diskImageData = Data("mock verified disk image".utf8)
        let scratchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceURL = scratchDirectory.appendingPathComponent("source.dmg")
        let updatesRoot = scratchDirectory.appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        try diskImageData.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }
        let digest = try AppUpdatePolicy.sha256(of: sourceURL)
        let checksumData = Data("\(digest)  \(diskImageName)\n".utf8)
        let metadata = try releaseMetadata(
            version: version,
            diskImageName: diskImageName,
            diskImageSize: diskImageData.count,
            checksumSize: checksumData.count
        )

        UpdateURLProtocolStub.handler = { request in
            let url = try XCTUnwrap(request.url)
            let data: Data
            switch url.path {
            case AppUpdatePolicy.latestReleaseURL.path:
                data = metadata
            case "/leeyang1990/opencodex-desktop/releases/download/v\(version)/\(diskImageName).sha256":
                data = checksumData
            case "/leeyang1990/opencodex-desktop/releases/download/v\(version)/\(diskImageName)":
                data = diskImageData
            default:
                throw URLError(.unsupportedURL)
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(data.count)"]
            )!
            return (response, data)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocolStub.self]
        let suiteName = "AppUpdateManagerEndToEndTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = AppUpdateManager(
            defaults: defaults,
            session: URLSession(configuration: configuration),
            currentVersion: "0.8.0",
            automaticCheckInterval: 0,
            updatesRootOverride: updatesRoot
        )

        await manager.checkForUpdates()
        XCTAssertEqual(manager.availableRelease?.version, version)
        XCTAssertFalse(manager.lastOperationFailed)

        await manager.downloadAvailableUpdate()
        let downloadedURL = try XCTUnwrap(manager.downloadedUpdateURL)
        XCTAssertEqual(try Data(contentsOf: downloadedURL), diskImageData)
        XCTAssertEqual(try AppUpdatePolicy.sha256(of: downloadedURL), digest)
        XCTAssertEqual(permissions(at: downloadedURL), 0o600)
        XCTAssertFalse(manager.lastOperationFailed)
    }

    private func releaseMetadata(
        version: String,
        diskImageName: String,
        diskImageSize: Int,
        checksumSize: Int
    ) throws -> Data {
        let releaseBase = "https://github.com/leeyang1990/opencodex-desktop/releases"
        let payload: [String: Any] = [
            "tag_name": "v\(version)",
            "html_url": "\(releaseBase)/tag/v\(version)",
            "draft": false,
            "prerelease": false,
            "body": "End-to-end test",
            "assets": [
                [
                    "name": diskImageName,
                    "size": diskImageSize,
                    "browser_download_url": "\(releaseBase)/download/v\(version)/\(diskImageName)",
                ],
                [
                    "name": "\(diskImageName).sha256",
                    "size": checksumSize,
                    "browser_download_url": "\(releaseBase)/download/v\(version)/\(diskImageName).sha256",
                ],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func permissions(at url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? Int).map { $0 & 0o777 }
    }
}

private final class UpdateURLProtocolStub: URLProtocol {
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
