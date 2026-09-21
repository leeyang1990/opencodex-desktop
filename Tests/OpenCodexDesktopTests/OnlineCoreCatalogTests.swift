import CryptoKit
import Foundation
import XCTest

@testable import OpenCodexDesktop

final class OnlineCoreCatalogTests: XCTestCase {
    private let sample = Data("release archive".utf8)

    private func entry(
        _ version: String = "2.59.0", bun: String = "1.4.0", url: URL? = nil,
        commit: String? = String(repeating: "a", count: 40), deprecated: String? = nil
    ) -> OnlineCoreVersion {
        OnlineCoreVersion(
            name: OnlineCoreCatalog.packageName, version: version, gitHead: commit,
            dist: .init(
                tarball: url ?? OnlineCoreCatalog.packageURL(version),
                integrity: "sha512-" + Data(SHA512.hash(data: sample)).base64EncodedString()),
            dependencies: ["bun": bun], deprecated: deprecated)
    }

    private func registry(
        _ entries: [OnlineCoreVersion], name: String = OnlineCoreCatalog.packageName, latest: String = "2.59.0"
    ) throws -> Data {
        let values = try entries.reduce(into: [String: Any]()) { result, entry in
            result[entry.version] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry))
        }
        return try JSONSerialization.data(withJSONObject: [
            "name": name, "dist-tags": ["latest": latest], "versions": values,
        ])
    }

    func testStableVersionsSortedNumericallyAndPrereleasesExcluded() throws {
        let catalog = try OnlineCoreCatalog.decode(
            registry([entry("2.9.0"), entry(), entry("2.100.0"), entry("2.60.0-beta.1")]))
        XCTAssertEqual(catalog.versions.map(\.version), ["2.100.0", "2.59.0", "2.9.0"])
        XCTAssertEqual(catalog.latest, "2.59.0")
    }

    func testRejectsDifferentPackageOrEmptyCatalog() throws {
        XCTAssertThrowsError(try OnlineCoreCatalog.decode(registry([entry()], name: "other")))
        XCTAssertThrowsError(try OnlineCoreCatalog.decode(registry([])))
    }

    func testPickerShowsOnlyFiveNewestVersionsWithoutTruncatingCatalog() throws {
        let catalog = try OnlineCoreCatalog.decode(registry((50...60).map { entry("2.\($0).0") }))
        let options = CoreVersionOption.choices(
            catalog: catalog, pinned: CoreReleaseCatalog.userSelectable, selected: nil)
        XCTAssertEqual(options.map(\.version), ["2.60.0", "2.59.0", "2.58.0", "2.57.0", "2.56.0"])
        XCTAssertEqual(catalog.versions.count, 11)
        XCTAssertTrue(options[1].label.contains("最新"))
    }

    func testPickerPreservesOlderSelectionOnlyOnce() throws {
        let catalog = try OnlineCoreCatalog.decode(registry((50...60).map { entry("2.\($0).0") }))
        let options = CoreVersionOption.choices(catalog: catalog, pinned: [], selected: "2.50.0")
        XCTAssertEqual(options.count, 6)
        XCTAssertEqual(options.last?.version, "2.50.0")
        XCTAssertTrue(options.last?.label.contains("当前选择") == true)
        let current = CoreVersionOption.choices(catalog: catalog, pinned: [], selected: "2.60.0")
        XCTAssertEqual(current.count, 5)
        XCTAssertEqual(current.filter { $0.version == "2.60.0" }.count, 1)
    }

    func testPickerRetainsPinnedSelectionAbsentFromRegistry() throws {
        let pinned = CoreReleaseCatalog.userSelectable
        let catalog = try OnlineCoreCatalog.decode(registry((50...60).map { entry("2.\($0).0") }))
        let options = CoreVersionOption.choices(catalog: catalog, pinned: pinned, selected: pinned[0].version)
        XCTAssertEqual(options.count, 6)
        XCTAssertEqual(options.last?.version, pinned[0].version)
        XCTAssertFalse(options.last!.unavailable)
        XCTAssertTrue(options.last!.label.contains("已锁定"))
    }

    func testPickerOfflineFallbackAndCompatibilityWarnings() throws {
        let pinned = CoreReleaseCatalog.userSelectable
        let offline = CoreVersionOption.choices(catalog: nil, pinned: pinned, selected: pinned[0].version)
        XCTAssertEqual(Set(offline.map(\.version)), Set(pinned.map(\.version)))
        XCTAssertTrue(CoreVersionOption.choices(catalog: nil, pinned: [], selected: nil).isEmpty)
        let catalog = try OnlineCoreCatalog.decode(registry([entry("2.60.0", bun: "9.0.0"), entry()]))
        let options = CoreVersionOption.choices(catalog: catalog, pinned: [], selected: nil)
        XCTAssertTrue(options[0].unavailable)
        XCTAssertTrue(options[0].label.contains("尚未适配"))
        XCTAssertFalse(options[1].unavailable)
    }

    func testUnknownLatestTagNeverCreatesAnInstallCandidate() throws {
        let catalog = try OnlineCoreCatalog.decode(registry([entry()], latest: "9.0.0"))
        XCTAssertNil(catalog.latest)
        XCTAssertEqual(catalog.versions.count, 1)
    }

    func testCompatibilityBoundRequiresCoreTwoAndPinnedBun() {
        XCTAssertNil(entry().unavailableReason)
        XCTAssertNotNil(entry("3.0.0").unavailableReason)
        XCTAssertNotNil(entry("2.11.0").unavailableReason)
        XCTAssertNotNil(entry(bun: "1.5.0").unavailableReason)
        XCTAssertNotNil(entry(bun: "^1.4.0").unavailableReason)
    }

    func testRejectsMissingCommitUntrustedURLsAndDeprecatedReleases() {
        XCTAssertNotNil(entry(commit: nil).unavailableReason)
        XCTAssertNotNil(entry(commit: "main").unavailableReason)
        XCTAssertNotNil(entry(url: URL(string: "http://registry.npmjs.org/pkg.tgz")!).unavailableReason)
        XCTAssertNotNil(entry(url: URL(string: "https://example.com/pkg.tgz")!).unavailableReason)
        XCTAssertNotNil(entry(deprecated: "retired").unavailableReason)
    }

    func testArchiveMustMatchPublishedSHA512() {
        XCTAssertTrue(entry().verifiesPackage(sample))
        XCTAssertFalse(entry().verifiesPackage(Data("tampered".utf8)))
        XCTAssertNil(OnlineCoreVersion.integrityDigest("sha1-deadbeef"))
        XCTAssertNil(OnlineCoreVersion.integrityDigest("sha512-YQ=="))
    }

    func testCachePreservesMetadataAndFetchTime() throws {
        let date = Date(timeIntervalSince1970: 100)
        let catalog = try OnlineCoreCatalog.decode(registry([entry()]), now: date)
        let cached = try JSONDecoder().decode(OnlineCoreCatalog.self, from: JSONEncoder().encode(catalog))
        XCTAssertEqual(cached.versions, catalog.versions)
        XCTAssertEqual(cached.fetchedAt, date)
    }

    func testPreparedDescriptorsRoundTripAndRejectChangedRuntimeHash() throws {
        let release = CoreReleaseCatalog.userSelectable[0]
        XCTAssertTrue(OnlineCoreCatalog.validatePrepared(release))
        let cached = try JSONDecoder().decode(CoreRelease.self, from: JSONEncoder().encode(release))
        XCTAssertEqual(cached, release)
        let invalid = CoreRelease(
            version: release.version, commit: release.commit, package: release.package,
            lockfile: release.lockfile, bunVersion: release.bunVersion, bunArm64SHA256: "bad",
            bunX64SHA256: release.bunX64SHA256)
        XCTAssertFalse(OnlineCoreCatalog.validatePrepared(invalid))
    }

    func testCachedCustomSelectionSurvivesOfflineRestart() {
        let old = CoreReleaseCatalog.userSelectable[0]
        let release = CoreRelease(
            version: "2.59.0", commit: old.commit, package: old.package, lockfile: old.lockfile,
            bunVersion: old.bunVersion, bunArm64SHA256: old.bunArm64SHA256, bunX64SHA256: old.bunX64SHA256)
        let normalized = CoreReleaseCatalog.normalizedSelection(
            modeRawValue: "custom", customVersion: "2.59.0", releases: [release])
        XCTAssertEqual(normalized.mode, .custom)
        XCTAssertEqual(
            CoreReleaseCatalog.resolve(
                mode: normalized.mode, customVersion: normalized.customVersion, releases: [release]), release)
        XCTAssertEqual(
            CoreReleaseCatalog.resolve(mode: .build, customVersion: "2.59.0", releases: [release]),
            CoreReleaseCatalog.build)
    }

    func testLiveDiscoveryAndPreparationWithoutInstallingOrSelecting() async throws {
        guard ProcessInfo.processInfo.environment["OPENCODEX_LIVE_CATALOG_TEST"] == "1" else {
            throw XCTSkip("Opt-in public registry check; no Core is installed, selected or started.")
        }
        let client = OnlineCoreCatalogClient()
        let catalog = try await client.fetch()
        let candidate = try XCTUnwrap(catalog.versions.first { $0.version == catalog.latest })
        XCTAssertNil(candidate.unavailableReason)
        let release = try await client.prepare(candidate)
        XCTAssertTrue(OnlineCoreCatalog.validatePrepared(release))
        XCTAssertEqual(release.version, catalog.latest)
        print(
            "Verified public Core release \(release.version); \(catalog.versions.count) stable versions; no install performed"
        )
    }
}
