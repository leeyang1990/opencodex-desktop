import Foundation
import XCTest

@testable import OpenCodexDesktop

final class CoreReleaseTests: XCTestCase {
    func testCompatibleReleaseIsPinnedToImmutableArtifacts() {
        let release = CoreRelease.compatible

        XCTAssertEqual(release.version, "2.12.0")
        XCTAssertEqual(release.commit, "6d881db206c6a74da6b64fa22b6980faf05d0122")
        XCTAssertEqual(release.package.url.scheme, "https")
        XCTAssertTrue(release.package.url.host == "registry.npmjs.org")
        XCTAssertEqual(release.package.sha256.count, 64)
        XCTAssertEqual(release.lockfile.sha256.count, 64)
        XCTAssertEqual(release.bunArtifact.archive.sha256.count, 64)
        XCTAssertGreaterThan(release.package.maximumBytes, 0)
        XCTAssertGreaterThan(release.lockfile.maximumBytes, 0)
        XCTAssertGreaterThan(release.bunArtifact.archive.maximumBytes, 0)
    }

    func testOnlyCompatibleInstallationIsRunnable() {
        let installed = InstalledCoreManifest(
            schemaVersion: 1,
            coreVersion: "2.12.0",
            coreCommit: "6d881db206c6a74da6b64fa22b6980faf05d0122",
            bunVersion: "1.3.14",
            packageSHA256: String(repeating: "a", count: 64),
            installedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(CoreInstallationState.installed(installed).isInstalled)
        XCTAssertFalse(
            CoreInstallationState.updateAvailable(
                installed: installed,
                target: CoreRelease.compatible
            ).isInstalled
        )
        XCTAssertFalse(CoreInstallationState.notInstalled.isInstalled)
    }
}
