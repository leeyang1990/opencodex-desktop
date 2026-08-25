import Foundation
import XCTest

@testable import OpenCodexDesktop

final class CoreReleaseTests: XCTestCase {
    func testBuildReleaseIsPinnedToImmutableArtifacts() {
        let release = CoreReleaseCatalog.build

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

    func testUserSelectableReleasesArePinnedAndSeparateFromBuildVersion() {
        XCTAssertGreaterThanOrEqual(CoreReleaseCatalog.userSelectable.count, 2)
        XCTAssertFalse(
            CoreReleaseCatalog.userSelectable.contains(where: {
                $0.version == CoreReleaseCatalog.build.version
            })
        )

        for release in CoreReleaseCatalog.userSelectable {
            XCTAssertEqual(release.package.url.scheme, "https")
            XCTAssertEqual(release.lockfile.url.scheme, "https")
            XCTAssertEqual(release.bunArtifact.archive.url.scheme, "https")
            XCTAssertEqual(release.package.sha256.count, 64)
            XCTAssertEqual(release.lockfile.sha256.count, 64)
            XCTAssertEqual(release.bunArtifact.archive.sha256.count, 64)
            XCTAssertTrue(release.bunArtifact.archive.url.absoluteString.contains("bun-v\(release.bunVersion)"))
        }
    }

    func testVersionSelectionUsesTrustedCustomReleaseAndFallsBackToBuild() {
        let custom = try! XCTUnwrap(CoreReleaseCatalog.userSelectable.first)
        XCTAssertEqual(
            CoreReleaseCatalog.resolve(mode: .custom, customVersion: custom.version),
            custom
        )
        XCTAssertEqual(
            CoreReleaseCatalog.resolve(mode: .custom, customVersion: "99.99.99"),
            CoreReleaseCatalog.build
        )
        XCTAssertEqual(
            CoreReleaseCatalog.resolve(mode: .build, customVersion: custom.version),
            CoreReleaseCatalog.build
        )
    }

    func testPersistedUntrustedVersionIsNormalizedToBuildMode() {
        let selection = CoreReleaseCatalog.normalizedSelection(
            modeRawValue: CoreVersionMode.custom.rawValue,
            customVersion: "99.99.99"
        )

        XCTAssertEqual(selection.mode, .build)
        XCTAssertNil(selection.customVersion)
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
                target: CoreReleaseCatalog.build
            ).isInstalled
        )
        XCTAssertFalse(CoreInstallationState.notInstalled.isInstalled)
    }
}

final class CodexRuntimeEnvironmentTests: XCTestCase {
    func testAddsPersistedNodeRuntimeDirectoryToFinderPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dataDirectory = root.appendingPathComponent("data", isDirectory: true)
        let runtimeDirectory = root.appendingPathComponent("nvm/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codex = runtimeDirectory.appendingPathComponent("codex", isDirectory: false)
        XCTAssertTrue(FileManager.default.createFile(atPath: codex.path, contents: Data("#!/usr/bin/env node\n".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        let state = """
            {"version":1,"command":"\(codex.path)","source":"configured"}
            """
        try Data(state.utf8).write(to: dataDirectory.appendingPathComponent("codex-runtime.json"))

        let environment = CodexRuntimeEnvironment.prepared(
            from: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            dataDirectory: dataDirectory,
            homeDirectory: root
        )

        XCTAssertEqual(environment["PATH"]?.split(separator: ":").first.map(String.init), runtimeDirectory.path)
    }

    func testIgnoresMissingPersistedRuntime() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dataDirectory = root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"version":1,"command":"/missing/codex","source":"configured"}"#.utf8)
            .write(to: dataDirectory.appendingPathComponent("codex-runtime.json"))

        let environment = CodexRuntimeEnvironment.prepared(
            from: ["PATH": "/usr/bin:/bin"],
            dataDirectory: dataDirectory,
            homeDirectory: root
        )

        let components = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        XCTAssertFalse(components.contains("/missing"))
        XCTAssertEqual(Array(components.suffix(2)), ["/usr/bin", "/bin"])
    }
}
