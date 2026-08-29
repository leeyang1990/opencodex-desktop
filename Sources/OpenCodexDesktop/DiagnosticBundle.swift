import Foundation

struct DiagnosticExportContext {
    let appVersion: String
    let operatingSystem: String
    let architecture: String
    let connectionHost: String
    let connectionPort: Int
    let connectionState: String
    let coreVersion: String?
    let corePID: Int?
    let coreUptime: Double?
    let selectedCoreVersion: String
    let selectedCoreMode: String
    let coreIntegrity: String
    let managementTokenAvailable: Bool
    let lastCoreExitDetected: Bool
    let coreLogExists: Bool
    let coreLogSize: Int64?
    let coreLogModifiedAt: Date?
    let report: EnvironmentCheckReport
    let securityReport: SecurityAuditReport
    let recentEvents: [DesktopEvent]
    let runtimeCandidates: [CodexRuntimeCandidate]
    let preferredRuntimePath: String?
}

enum DiagnosticPrivacy {
    static func redact(_ input: String, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String
    {
        var value = String(input.prefix(2_000))
        let home = homeDirectory.standardizedFileURL.path
        if !home.isEmpty { value = value.replacingOccurrences(of: home, with: "~") }

        let patterns = [
            (#"(?i)Bearer\s+[A-Za-z0-9._~+\-/=]+"#, "Bearer [REDACTED]"),
            (#"\bsk-[A-Za-z0-9_-]{8,}\b"#, "[REDACTED_API_KEY]"),
            (#"(?i)(api[_-]?key|token|secret|authorization|credential)\s*[:=]\s*[^\s,;]+"#, "$1=[REDACTED]"),
            (#"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "[REDACTED_EMAIL]"),
        ]
        for (pattern, replacement) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            value = expression.stringByReplacingMatches(
                in: value,
                range: range,
                withTemplate: replacement
            )
        }
        return value
    }
}

enum DiagnosticBundleBuilder {
    private struct Document: Encodable {
        let schemaVersion: Int
        let generatedAt: Date
        let app: AppSection
        let system: SystemSection
        let connection: ConnectionSection
        let core: CoreSection
        let privacy: PrivacySection
        let checks: [CheckSection]
        let securityChecks: [CheckSection]
        let recentEvents: [EventSection]
        let runtimeCandidates: [RuntimeSection]
    }

    private struct AppSection: Encodable {
        let version: String
    }

    private struct SystemSection: Encodable {
        let operatingSystem: String
        let architecture: String
    }

    private struct ConnectionSection: Encodable {
        let host: String
        let port: Int
        let state: String
    }

    private struct CoreSection: Encodable {
        let runningVersion: String?
        let pid: Int?
        let uptimeSeconds: Double?
        let selectedVersion: String
        let versionMode: String
        let integrity: String
        let managementTokenAvailable: Bool
        let lastExitDetected: Bool
        let logExists: Bool
        let logSizeBytes: Int64?
        let logModifiedAt: Date?
    }

    private struct PrivacySection: Encodable {
        let rawLogsIncluded: Bool
        let credentialsIncluded: Bool
        let accountIdentifiersIncluded: Bool
        let requestBodiesIncluded: Bool
    }

    private struct CheckSection: Encodable {
        let id: String
        let title: String
        let detail: String
        let state: String
    }

    private struct EventSection: Encodable {
        let timestamp: Date
        let kind: String
        let detail: String?
    }

    private struct RuntimeSection: Encodable {
        let source: String
        let version: String?
        let selected: Bool
        let validationPassed: Bool
    }

    static func makeJSON(context: DiagnosticExportContext, now: Date = Date()) throws -> Data {
        let checks = context.report.items.map { item in
            CheckSection(
                id: item.id.rawValue,
                title: DiagnosticPrivacy.redact(item.title),
                detail: DiagnosticPrivacy.redact(item.detail),
                state: stateName(item.state)
            )
        }
        let securityChecks = context.securityReport.items.map { item in
            CheckSection(
                id: item.id.rawValue,
                title: DiagnosticPrivacy.redact(item.title),
                detail: DiagnosticPrivacy.redact(item.detail),
                state: stateName(item.state)
            )
        }
        let recentEvents = context.recentEvents.prefix(50).map { event in
            EventSection(
                timestamp: event.timestamp,
                kind: event.kind.rawValue,
                detail: event.detail.map { DiagnosticPrivacy.redact($0) }
            )
        }
        let runtimeCandidates = context.runtimeCandidates.map { candidate in
            RuntimeSection(
                source: candidate.source.rawValue,
                version: candidate.version.map { DiagnosticPrivacy.redact($0) },
                selected: candidate.path == context.preferredRuntimePath,
                validationPassed: candidate.isValid
            )
        }
        let document = Document(
            schemaVersion: 2,
            generatedAt: now,
            app: AppSection(version: context.appVersion),
            system: SystemSection(
                operatingSystem: context.operatingSystem,
                architecture: context.architecture
            ),
            connection: ConnectionSection(
                host: context.connectionHost,
                port: context.connectionPort,
                state: context.connectionState
            ),
            core: CoreSection(
                runningVersion: context.coreVersion,
                pid: context.corePID,
                uptimeSeconds: context.coreUptime,
                selectedVersion: context.selectedCoreVersion,
                versionMode: context.selectedCoreMode,
                integrity: context.coreIntegrity,
                managementTokenAvailable: context.managementTokenAvailable,
                lastExitDetected: context.lastCoreExitDetected,
                logExists: context.coreLogExists,
                logSizeBytes: context.coreLogSize,
                logModifiedAt: context.coreLogModifiedAt
            ),
            privacy: PrivacySection(
                rawLogsIncluded: false,
                credentialsIncluded: false,
                accountIdentifiersIncluded: false,
                requestBodiesIncluded: false
            ),
            checks: checks,
            securityChecks: securityChecks,
            recentEvents: recentEvents,
            runtimeCandidates: runtimeCandidates
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static var readme: String {
        """
        OpenCodex Desktop 脱敏诊断包

        diagnostics.json 只包含客户端版本、macOS 环境、本机 Core 状态、端口、脱敏事件和检查结论。
        为保护隐私，诊断包不包含 API Key、管理令牌内容、账号标识、请求正文或 Core 原始日志。
        """
    }

    private static func stateName(_ state: EnvironmentCheckState) -> String {
        switch state {
        case .passed: "passed"
        case .attention: "attention"
        case .pending: "pending"
        }
    }
}

enum DiagnosticArchiveExporter {
    static func createArchive(context: DiagnosticExportContext) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OpenCodex-Diagnostics-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("OpenCodex-Diagnostics", isDirectory: true)
        let archive = root.appendingPathComponent("OpenCodex-Diagnostics.zip", isDirectory: false)
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try DiagnosticBundleBuilder.makeJSON(context: context).write(
            to: bundle.appendingPathComponent("diagnostics.json"),
            options: [.atomic]
        )
        try Data(DiagnosticBundleBuilder.readme.utf8).write(
            to: bundle.appendingPathComponent("README.txt"),
            options: [.atomic]
        )

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", bundle.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, fileManager.fileExists(atPath: archive.path) else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail =
                String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw DiagnosticExportError.archiveFailed(detail)
        }
        return archive
    }
}

enum DiagnosticExportError: LocalizedError {
    case archiveFailed(String)

    var errorDescription: String? {
        switch self {
        case let .archiveFailed(detail):
            detail.isEmpty ? "无法生成脱敏诊断包。" : "无法生成脱敏诊断包：\(detail)"
        }
    }
}
