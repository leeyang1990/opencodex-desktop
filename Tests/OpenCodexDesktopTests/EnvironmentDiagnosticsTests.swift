import Foundation
import XCTest

@testable import OpenCodexDesktop

final class EnvironmentDiagnosticsTests: XCTestCase {
    private let validManifest = InstalledCoreManifest(
        schemaVersion: 1,
        coreVersion: CoreReleaseCatalog.build.version,
        coreCommit: CoreReleaseCatalog.build.commit,
        bunVersion: CoreReleaseCatalog.build.bunVersion,
        packageSHA256: CoreReleaseCatalog.build.package.sha256,
        installedAt: Date(timeIntervalSince1970: 0)
    )
    private let validLocalRuntime = CodexRuntimeCandidate(
        path: "/usr/local/bin/codex",
        source: .homebrew,
        version: "0.148.0",
        validationError: nil
    )

    func testHealthyEnvironmentPassesWithoutAttention() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            availableDiskBytes: 5 * 1_024 * 1_024 * 1_024,
            coreInspection: .valid(validManifest),
            portInspection: .core(pid: 42),
            tokenAvailable: true,
            serviceOnline: true,
            localRuntime: validLocalRuntime,
            runtimeScanCompleted: true,
            loginItemEnabled: true,
            loginItemRequiresApproval: false,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertFalse(report.needsAttention)
        XCTAssertTrue(report.items.allSatisfy { $0.state == .passed })
    }

    func testMissingLocalRuntimeNeedsAttentionAfterScan() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            availableDiskBytes: 5 * 1_024 * 1_024 * 1_024,
            coreInspection: .valid(validManifest),
            portInspection: .core(pid: 42),
            tokenAvailable: true,
            serviceOnline: true,
            localRuntime: nil,
            runtimeScanCompleted: true,
            loginItemEnabled: false,
            loginItemRequiresApproval: false
        )

        XCTAssertTrue(report.needsAttention)
        XCTAssertEqual(report.item(.codexRuntime)?.state, .attention)
    }

    func testRuntimeScanIsPendingBeforeCompletion() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            availableDiskBytes: 5 * 1_024 * 1_024 * 1_024,
            coreInspection: .valid(validManifest),
            portInspection: .core(pid: 42),
            tokenAvailable: true,
            serviceOnline: true,
            localRuntime: nil,
            runtimeScanCompleted: false,
            loginItemEnabled: false,
            loginItemRequiresApproval: false
        )

        XCTAssertEqual(report.item(.codexRuntime)?.state, .pending)
        XCTAssertEqual(report.item(.codexRuntime)?.title, "Codex CLI 安装")
    }

    func testUninstalledCoreProducesPendingItemsInsteadOfFalsePermissionFailure() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            availableDiskBytes: 5 * 1_024 * 1_024 * 1_024,
            coreInspection: .missing,
            portInspection: .available,
            tokenAvailable: false,
            serviceOnline: false,
            localRuntime: validLocalRuntime,
            runtimeScanCompleted: true,
            loginItemEnabled: false,
            loginItemRequiresApproval: false
        )

        XCTAssertFalse(report.needsAttention)
        XCTAssertEqual(report.item(.coreInstallation)?.state, .pending)
        XCTAssertEqual(report.item(.managementToken)?.state, .pending)
    }

    func testLoginItemApprovalIsActionable() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            availableDiskBytes: 5 * 1_024 * 1_024 * 1_024,
            coreInspection: .missing,
            portInspection: .available,
            tokenAvailable: false,
            serviceOnline: false,
            localRuntime: validLocalRuntime,
            runtimeScanCompleted: true,
            loginItemEnabled: false,
            loginItemRequiresApproval: true
        )

        XCTAssertTrue(report.requiresLoginItemApproval)
        XCTAssertTrue(report.needsAttention)
    }

    func testOccupiedPortIsActionableWhileCoreIsOffline() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            availableDiskBytes: 5 * 1_024 * 1_024 * 1_024,
            coreInspection: .valid(validManifest),
            portInspection: .occupied(pid: 99),
            tokenAvailable: true,
            serviceOnline: false,
            localRuntime: validLocalRuntime,
            runtimeScanCompleted: true,
            loginItemEnabled: false,
            loginItemRequiresApproval: false
        )

        let service = report.item(.serviceEndpoint)
        XCTAssertEqual(service?.state, .attention)
        XCTAssertTrue(service?.detail.contains("PID 99") == true)
    }

    func testLowDiskSpaceNeedsAttention() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            availableDiskBytes: 500 * 1_024 * 1_024,
            coreInspection: .missing,
            portInspection: .available,
            tokenAvailable: false,
            serviceOnline: false,
            localRuntime: validLocalRuntime,
            runtimeScanCompleted: true,
            loginItemEnabled: false,
            loginItemRequiresApproval: false
        )

        XCTAssertEqual(report.item(.diskSpace)?.state, .attention)
    }

    func testCoreIntegrityInspectorAcceptsTrustedCompleteInstallation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeInstallation(at: root, manifest: validManifest)

        let inspection = CoreIntegrityInspector.inspect(
            release: CoreReleaseCatalog.build,
            root: root
        )

        XCTAssertEqual(inspection, .valid(validManifest))
    }

    func testCoreIntegrityInspectorRejectsMismatchedManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mismatched = InstalledCoreManifest(
            schemaVersion: 1,
            coreVersion: validManifest.coreVersion,
            coreCommit: "untrusted",
            bunVersion: validManifest.bunVersion,
            packageSHA256: validManifest.packageSHA256,
            installedAt: validManifest.installedAt
        )
        try makeInstallation(at: root, manifest: mismatched)

        let inspection = CoreIntegrityInspector.inspect(
            release: CoreReleaseCatalog.build,
            root: root
        )

        XCTAssertTrue(inspection.needsRepair)
    }

    private func makeInstallation(at root: URL, manifest: InstalledCoreManifest) throws {
        let runtime = root.appendingPathComponent("bin/bun", isDirectory: false)
        let cli = root.appendingPathComponent("package/src/cli/index.ts", isDirectory: false)
        let dependencies = root.appendingPathComponent("package/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(
            at: runtime.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: cli.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: dependencies, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: runtime.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: cli.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: root.appendingPathComponent("installation.json"))
    }
}
