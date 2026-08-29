import Foundation
import XCTest

@testable import OpenCodexDesktop

final class CodexRuntimeDiscoveryTests: XCTestCase {
    func testParsesSupportedVersionOutput() {
        XCTAssertEqual(CodexRuntimeDiscovery.parseVersion("codex-cli 0.148.0"), "0.148.0")
        XCTAssertEqual(CodexRuntimeDiscovery.parseVersion("codex v1.2.3-beta.1"), "1.2.3-beta.1")
        XCTAssertNil(CodexRuntimeDiscovery.parseVersion("unrelated 1.2.3"))
    }

    func testDiscoversAndDeduplicatesNVMRuntime() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let data = root.appendingPathComponent("data", isDirectory: true)
        let runtime = root.appendingPathComponent(".nvm/versions/node/v22/bin/codex")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: runtime.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: runtime.path, contents: Data("#!/bin/sh\n".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let candidates = CodexRuntimeDiscovery.candidatePaths(
            environment: ["PATH": runtime.deletingLastPathComponent().path],
            dataDirectory: data,
            preferredPath: runtime.path,
            homeDirectory: root,
            fileManager: .default
        )

        XCTAssertEqual(candidates.filter { $0.0 == runtime.path }.count, 1)
        XCTAssertEqual(candidates.first?.1, .desktopPreference)
    }
}
