import Foundation
import XCTest

@testable import OpenCodexDesktop

final class EnvironmentDiagnosticsTests: XCTestCase {
    func testHealthyEnvironmentPassesWithoutAttention() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            coreInstalled: true,
            tokenAvailable: true,
            serviceOnline: true,
            runtime: CodexRuntime(path: "codex", version: "0.148.0", source: "configured", warning: nil),
            detectedCodexCommand: "/usr/local/bin/codex",
            loginItemEnabled: true,
            loginItemRequiresApproval: false,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertFalse(report.needsAttention)
        XCTAssertTrue(report.items.allSatisfy { $0.state == .passed })
    }

    func testOnlineServiceWithoutValidatedRuntimeNeedsAttention() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            coreInstalled: true,
            tokenAvailable: true,
            serviceOnline: true,
            runtime: CodexRuntime(path: "codex", version: nil, source: "fallback", warning: "runtime missing"),
            detectedCodexCommand: nil,
            loginItemEnabled: false,
            loginItemRequiresApproval: false
        )

        XCTAssertTrue(report.needsAttention)
        XCTAssertEqual(report.items.first { $0.id == .codexRuntime }?.state, .attention)
    }

    func testUninstalledCoreProducesPendingItemsInsteadOfFalsePermissionFailure() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            coreInstalled: false,
            tokenAvailable: false,
            serviceOnline: false,
            runtime: nil,
            detectedCodexCommand: "/usr/local/bin/codex",
            loginItemEnabled: false,
            loginItemRequiresApproval: false
        )

        XCTAssertFalse(report.needsAttention)
        XCTAssertEqual(report.items.first { $0.id == .coreInstallation }?.state, .pending)
        XCTAssertEqual(report.items.first { $0.id == .managementToken }?.state, .pending)
    }

    func testLoginItemApprovalIsActionable() {
        let report = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: true,
            coreDirectoryWritable: true,
            coreInstalled: false,
            tokenAvailable: false,
            serviceOnline: false,
            runtime: nil,
            detectedCodexCommand: "/usr/local/bin/codex",
            loginItemEnabled: false,
            loginItemRequiresApproval: true
        )

        XCTAssertTrue(report.requiresLoginItemApproval)
        XCTAssertTrue(report.needsAttention)
    }
}
