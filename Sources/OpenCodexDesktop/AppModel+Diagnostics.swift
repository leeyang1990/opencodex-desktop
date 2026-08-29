import AppKit
import Foundation

extension AppModel {
    func scanCodexRuntimes() async {
        isScanningCodexRuntimes = true
        defer { isScanningCodexRuntimes = false }
        let environment = CodexRuntimeEnvironment.prepared(
            from: ProcessInfo.processInfo.environment,
            dataDirectory: CoreInstallationPaths.dataDirectory
        )
        codexRuntimeCandidates = await CodexRuntimeDiscovery.scan(
            environment: environment,
            dataDirectory: CoreInstallationPaths.dataDirectory,
            preferredPath: coreManager.preferredCodexRuntimePath
        )
    }

    func useCodexRuntime(_ candidate: CodexRuntimeCandidate) async {
        guard candidate.isValid else { return }
        do {
            try coreManager.setPreferredCodexRuntimePath(candidate.path)
            if isOnline || coreManager.ownsRunningProcess {
                await restartService()
            } else {
                operationMessage = "已选择 Codex \(candidate.version ?? "")，启动 Core 后生效"
            }
            await scanCodexRuntimes()
            runEnvironmentCheck()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearCodexRuntimePreference() async {
        do {
            try coreManager.setPreferredCodexRuntimePath(nil)
            if isOnline || coreManager.ownsRunningProcess {
                await restartService()
            }
            await scanCodexRuntimes()
            runEnvironmentCheck()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restartService() async {
        errorMessage = nil
        await stopService()
        guard errorMessage == nil else { return }
        await startService()
    }

    func exportDiagnostics() {
        runEnvironmentCheck()
        do {
            let archive = try DiagnosticArchiveExporter.createArchive(context: diagnosticExportContext())
            defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }

            let panel = NSSavePanel()
            panel.title = "导出脱敏诊断包"
            panel.nameFieldStringValue = "OpenCodex-Diagnostics-\(diagnosticTimestamp()).zip"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: archive, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            operationMessage = "脱敏诊断包已导出"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func diagnosticExportContext() -> DiagnosticExportContext {
        let logURL = CoreInstallationPaths.logFile
        let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path)
        return DiagnosticExportContext(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.currentArchitecture,
            connectionHost: connectionHost,
            connectionPort: connectionPort,
            connectionState: connectionState.label,
            coreVersion: health?.version,
            corePID: health?.pid,
            coreUptime: health?.uptime,
            selectedCoreVersion: coreManager.targetRelease.version,
            selectedCoreMode: coreManager.versionMode.title,
            coreIntegrity: Self.coreIntegrityDescription(coreIntegrityInspection),
            managementTokenAvailable: tokenAvailable,
            lastCoreExitDetected: coreManager.lastExitMessage != nil,
            coreLogExists: FileManager.default.fileExists(atPath: logURL.path),
            coreLogSize: (attributes?[.size] as? NSNumber)?.int64Value,
            coreLogModifiedAt: attributes?[.modificationDate] as? Date,
            report: environmentReport,
            securityReport: securityAuditReport,
            recentEvents: eventStore.events,
            runtimeCandidates: codexRuntimeCandidates,
            preferredRuntimePath: coreManager.preferredCodexRuntimePath
        )
    }

    private func diagnosticTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func coreIntegrityDescription(_ inspection: CoreIntegrityInspection) -> String {
        switch inspection {
        case .missing: "missing"
        case .valid: "valid"
        case .invalid: "invalid"
        }
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }
}
