import Foundation
import XCTest

@testable import OpenCodexDesktop

final class DiagnosticBundleTests: XCTestCase {
    func testPrivacyRedactorRemovesCredentialsEmailAndHomePath() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let input = "Bearer abc.def api_key=secret sk-testsecret123 user@example.com /Users/example/.codex"

        let output = DiagnosticPrivacy.redact(input, homeDirectory: home)

        XCTAssertFalse(output.contains("abc.def"))
        XCTAssertFalse(output.contains("secret123"))
        XCTAssertFalse(output.contains("user@example.com"))
        XCTAssertFalse(output.contains("/Users/example"))
        XCTAssertTrue(output.contains("~/.codex"))
    }

    func testExportExplicitlyExcludesSensitivePayloadClasses() throws {
        let report = EnvironmentCheckReport(
            checkedAt: Date(timeIntervalSince1970: 0),
            items: [
                EnvironmentCheckItem(
                    id: .localStorage,
                    title: "本地数据目录",
                    detail: "Bearer hidden-token user@example.com",
                    state: .passed
                )
            ]
        )
        let context = DiagnosticExportContext(
            appVersion: "0.10.0",
            operatingSystem: "macOS",
            architecture: "arm64",
            connectionHost: "127.0.0.1",
            connectionPort: 10_100,
            connectionState: "服务正常",
            coreVersion: "2.31.0",
            corePID: 42,
            coreUptime: 12,
            selectedCoreVersion: "2.31.0",
            selectedCoreMode: "自选版本",
            coreIntegrity: "valid",
            managementTokenAvailable: true,
            lastCoreExitDetected: false,
            coreLogExists: true,
            coreLogSize: 128,
            coreLogModifiedAt: Date(timeIntervalSince1970: 0),
            report: report,
            securityReport: SecurityAuditReport(
                checkedAt: Date(timeIntervalSince1970: 0),
                items: [
                    SecurityAuditItem(
                        id: .managementToken,
                        title: "管理令牌文件",
                        detail: "token=hidden-token",
                        state: .attention
                    )
                ]
            ),
            recentEvents: [
                DesktopEvent(
                    id: UUID(),
                    timestamp: Date(timeIntervalSince1970: 0),
                    kind: .coreCrashed,
                    detail: "user@example.com"
                )
            ],
            runtimeCandidates: [
                CodexRuntimeCandidate(
                    path: "/Users/example/.nvm/bin/codex",
                    source: .nvm,
                    version: "0.148.0",
                    validationError: nil
                )
            ],
            preferredRuntimePath: "/Users/example/.nvm/bin/codex"
        )

        let data = try DiagnosticBundleBuilder.makeJSON(
            context: context,
            now: Date(timeIntervalSince1970: 0)
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("hidden-token"))
        XCTAssertFalse(json.contains("user@example.com"))
        XCTAssertTrue(json.contains(#""rawLogsIncluded" : false"#))
        XCTAssertTrue(json.contains(#""credentialsIncluded" : false"#))
        XCTAssertTrue(json.contains(#""requestBodiesIncluded" : false"#))
        XCTAssertTrue(json.contains(#""schemaVersion" : 2"#))
        XCTAssertTrue(json.contains(#""source" : "nvm""#))
        XCTAssertFalse(json.contains("/Users/example"))
    }
}
