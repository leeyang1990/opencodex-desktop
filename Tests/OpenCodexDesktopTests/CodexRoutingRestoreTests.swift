import Foundation
import XCTest

@testable import OpenCodexDesktop

final class CodexRoutingRestoreTests: XCTestCase {
    private static let successEnvelope = """
        {"success":true,"message":"Removed opencodex routing from Codex config + profile.","artifacts":{}}
        """

    func testAcceptsConfirmedRestoreEnvelope() throws {
        let result = ManagedCLIResult(terminated: true, timedOut: false, status: 0, output: Self.successEnvelope)

        XCTAssertNoThrow(try CoreManager.validateRestoreOutput(result))
    }

    func testToleratesUnrelatedOutputBeforeTheEnvelope() throws {
        let result = ManagedCLIResult(
            terminated: true,
            timedOut: false,
            status: 0,
            output: "warning: adapter probe failed\n\(Self.successEnvelope)\n"
        )

        XCTAssertNoThrow(try CoreManager.validateRestoreOutput(result))
    }

    /// Exit code zero without the machine-readable confirmation is not proof of a restore.
    func testRejectsSuccessExitCodeWithoutEnvelope() {
        let result = ManagedCLIResult(
            terminated: true,
            timedOut: false,
            status: 0,
            output: "Codex integration is already OFF and native; no Codex files changed."
        )

        assertRestoreFailure(result, contains: "already OFF")
    }

    func testRejectsExplicitUnconfirmedEnvelope() {
        let result = ManagedCLIResult(
            terminated: true,
            timedOut: false,
            status: 1,
            output: #"{"success":false,"message":"Codex config is busy; retry shortly"}"#
        )

        assertRestoreFailure(result, contains: "busy")
    }

    func testRejectsTimedOutCommand() {
        let result = ManagedCLIResult(terminated: true, timedOut: true, status: -1, output: "")

        XCTAssertThrowsError(try CoreManager.validateRestoreOutput(result)) { error in
            guard case .restoreTimedOut? = error as? CoreManagerError else {
                XCTFail("Expected restoreTimedOut, got \(error)")
                return
            }
        }
    }

    func testCodexHomePrefersEnvironmentOverride() {
        let home = URL(fileURLWithPath: "/Users/tester")

        XCTAssertEqual(
            CoreManager.resolvedCodexHome(from: ["CODEX_HOME": "/tmp/custom-codex"], homeDirectory: home).path,
            "/tmp/custom-codex"
        )
        XCTAssertEqual(
            CoreManager.resolvedCodexHome(from: ["CODEX_HOME": "   "], homeDirectory: home).path,
            "/Users/tester/.codex"
        )
        XCTAssertEqual(CoreManager.resolvedCodexHome(from: [:], homeDirectory: home).path, "/Users/tester/.codex")
    }

    func testManagedEnvironmentCarriesNoCredentialsAndPinsTheRuntime() {
        let environment = ManagedCLI.environment(
            dataDirectory: URL(fileURLWithPath: "/tmp/ocx-data"),
            runtimeExecutable: URL(fileURLWithPath: "/tmp/core/bin/bun"),
            base: ["PATH": "/usr/bin", "OPENCODEX_ADMIN_AUTH_TOKEN": "should-not-be-forwarded"],
            codexHome: URL(fileURLWithPath: "/tmp/codex-home")
        )

        XCTAssertEqual(environment["OPENCODEX_HOME"], "/tmp/ocx-data")
        XCTAssertEqual(environment["OPENCODEX_BUN_PATH"], "/tmp/core/bin/bun")
        XCTAssertEqual(environment["CODEX_HOME"], "/tmp/codex-home")
        XCTAssertEqual(environment["NO_COLOR"], "1")
        // The token stays in its file: the launcher never copies a credential into a child env.
        XCTAssertNil(environment["OPENCODEX_ADMIN_AUTH_TOKEN"])
        XCTAssertNil(environment["OCX_ADMIN_TOKEN"])
    }

    private func assertRestoreFailure(
        _ result: ManagedCLIResult,
        contains fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try CoreManager.validateRestoreOutput(result), file: file, line: line) { error in
            guard case let CoreManagerError.restoreFailed(message)? = error as? CoreManagerError else {
                XCTFail("Expected restoreFailed, got \(error)", file: file, line: line)
                return
            }
            XCTAssertTrue(
                message.localizedCaseInsensitiveContains(fragment),
                "\(message) does not contain \(fragment)",
                file: file,
                line: line
            )
        }
    }
}

final class ManagedCLIRunnerTests: XCTestCase {
    private var scripts: [URL] = []

    override func tearDown() {
        for script in scripts { try? FileManager.default.removeItem(at: script) }
        scripts = []
        super.tearDown()
    }

    /// Wraps `script` in a temporary executable entry so the production path — an `entry` file
    /// executed by `executable` — is exercised without the real Core CLI.
    private func makeCLI(script: String, timeout: Duration) -> ManagedCLI {
        let entry = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocx-cli-\(UUID().uuidString).sh", isDirectory: false)
        try? Data(script.utf8).write(to: entry)
        scripts.append(entry)
        return ManagedCLI(
            executable: URL(fileURLWithPath: "/bin/sh"),
            entry: entry,
            arguments: [],
            currentDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            environment: ["PATH": "/bin:/usr/bin"],
            timeout: timeout
        )
    }

    func testRunnerReturnsOutputAndExitStatus() async {
        let cli = makeCLI(
            script: "printf '%s\\n' '{\"success\":true,\"message\":\"ok\"}'; exit 0",
            timeout: .seconds(5)
        )

        let result = await ManagedCLIRunner.run(cli)

        XCTAssertTrue(result.terminated)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.contains("\"success\":true"))
    }

    func testRunnerReportsNonZeroStatus() async {
        let cli = makeCLI(script: "echo refused >&2; exit 2", timeout: .seconds(5))

        let result = await ManagedCLIRunner.run(cli)

        XCTAssertTrue(result.terminated)
        XCTAssertEqual(result.status, 2)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.output.contains("refused"))
    }

    /// A hung command must be signalled instead of blocking the quit path forever.
    func testRunnerStopsACommandThatExceedsItsBudget() async {
        let cli = makeCLI(script: "sleep 30", timeout: .milliseconds(600))

        let started = ContinuousClock.now
        let result = await ManagedCLIRunner.run(cli)
        let elapsed = ContinuousClock.now - started

        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(elapsed, .seconds(5), "the deadline must interrupt the command, not wait it out")
    }
}
