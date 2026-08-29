import Darwin
import Foundation

enum CodexRuntimeSource: String, Codable, CaseIterable, Sendable {
    case desktopPreference
    case coreConfigured
    case environment
    case nvm
    case homebrew
    case codexApp
    case chatGPTApp
    case path

    var title: String {
        switch self {
        case .desktopPreference: "Desktop 偏好"
        case .coreConfigured: "已保存路径"
        case .environment: "环境变量"
        case .nvm: "NVM"
        case .homebrew: "Homebrew"
        case .codexApp: "Codex.app"
        case .chatGPTApp: "ChatGPT.app"
        case .path: "系统 PATH"
        }
    }
}

struct CodexRuntimeCandidate: Identifiable, Equatable, Sendable {
    let path: String
    let source: CodexRuntimeSource
    let version: String?
    let validationError: String?

    var id: String { path }
    var isValid: Bool { version != nil && validationError == nil }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

private struct PersistedCodexRuntimeSelection: Decodable {
    let command: String
    let selectedVersion: String?
}

enum CodexRuntimeDiscovery {
    static func scan(
        environment: [String: String],
        dataDirectory: URL,
        preferredPath: String?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> [CodexRuntimeCandidate] {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager()
            let candidates = candidatePaths(
                environment: environment,
                dataDirectory: dataDirectory,
                preferredPath: preferredPath,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
            return candidates.map { path, source in
                probe(path: path, source: source, environment: environment, fileManager: fileManager)
            }
        }.value
    }

    static func candidatePaths(
        environment: [String: String],
        dataDirectory: URL,
        preferredPath: String?,
        homeDirectory: URL,
        fileManager: FileManager
    ) -> [(String, CodexRuntimeSource)] {
        var values: [(String, CodexRuntimeSource)] = []
        if let preferredPath {
            values.append((preferredPath, .desktopPreference))
        }
        if let environmentPath = environment["CODEX_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !environmentPath.isEmpty
        {
            values.append((environmentPath, .environment))
        }
        if let persisted = persistedSelection(in: dataDirectory), !persisted.command.isEmpty {
            values.append((persisted.command, .coreConfigured))
        }

        let fixed: [(URL, CodexRuntimeSource)] = [
            (URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"), .codexApp),
            (URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"), .chatGPTApp),
            (homeDirectory.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex"), .codexApp),
            (homeDirectory.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"), .chatGPTApp),
            (URL(fileURLWithPath: "/opt/homebrew/bin/codex"), .homebrew),
            (URL(fileURLWithPath: "/usr/local/bin/codex"), .homebrew),
            (homeDirectory.appendingPathComponent(".local/bin/codex"), .path),
            (homeDirectory.appendingPathComponent(".npm-global/bin/codex"), .path),
            (homeDirectory.appendingPathComponent(".bun/bin/codex"), .path),
            (homeDirectory.appendingPathComponent(".volta/bin/codex"), .path),
        ]
        values.append(contentsOf: fixed.map { ($0.0.path, $0.1) })

        let nvmRoot = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let nvmVersions =
            (try? fileManager.contentsOfDirectory(
                at: nvmRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        for version in nvmVersions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            values.append((version.appendingPathComponent("bin/codex").path, .nvm))
        }

        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            values.append((URL(fileURLWithPath: String(directory)).appendingPathComponent("codex").path, .path))
        }

        var seen = Set<String>()
        return values.compactMap { path, source in
            let normalized = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL.path
            guard fileManager.isExecutableFile(atPath: normalized), seen.insert(normalized).inserted else {
                return nil
            }
            return (normalized, source)
        }
    }

    private static func persistedSelection(in dataDirectory: URL) -> PersistedCodexRuntimeSelection? {
        let file = dataDirectory.appendingPathComponent("codex-runtime.json", isDirectory: false)
        guard
            let values = try? file.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            (values.fileSize ?? 16_385) <= 16_384,
            let data = try? Data(contentsOf: file),
            data.count <= 16_384
        else { return nil }
        return try? JSONDecoder().decode(PersistedCodexRuntimeSelection.self, from: data)
    }

    private static func probe(
        path: String,
        source: CodexRuntimeSource,
        environment: [String: String],
        fileManager: FileManager
    ) -> CodexRuntimeCandidate {
        guard fileManager.isExecutableFile(atPath: path) else {
            return CodexRuntimeCandidate(path: path, source: source, version: nil, validationError: "文件不可执行")
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return CodexRuntimeCandidate(
                path: path,
                source: source,
                version: nil,
                validationError: "无法启动：\(error.localizedDescription)"
            )
        }

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.025)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            return CodexRuntimeCandidate(path: path, source: source, version: nil, validationError: "版本检查超时")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile().prefix(4_096)
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0,
            let version = parseVersion(text)
        else {
            return CodexRuntimeCandidate(
                path: path,
                source: source,
                version: nil,
                validationError: text.isEmpty ? "无法读取版本" : String(text.prefix(160))
            )
        }
        return CodexRuntimeCandidate(path: path, source: source, version: version, validationError: nil)
    }

    static func parseVersion(_ output: String) -> String? {
        guard
            let match = output.range(
                of: #"(?i)\bcodex(?:-cli)?\s+v?([0-9]+\.[0-9]+\.[0-9]+(?:[-.][0-9A-Za-z.-]+)?)"#,
                options: .regularExpression
            )
        else { return nil }
        let matched = String(output[match])
        guard let rawVersion = matched.split(whereSeparator: \.isWhitespace).last.map(String.init) else {
            return nil
        }
        return rawVersion.hasPrefix("v") ? String(rawVersion.dropFirst()) : rawVersion
    }
}
