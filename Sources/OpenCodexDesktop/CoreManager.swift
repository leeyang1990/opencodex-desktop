import AppKit
import CryptoKit
import Darwin
import Foundation
import ServiceManagement

struct DownloadArtifact: Sendable, Equatable {
    let url: URL
    let sha256: String
    let maximumBytes: Int64

    init(url: URL, sha256: String, maximumBytes: Int64 = 256 * 1_024 * 1_024) {
        self.url = url
        self.sha256 = sha256
        self.maximumBytes = maximumBytes
    }
}

struct BunArtifact: Sendable, Equatable {
    let archive: DownloadArtifact
    let archiveDirectory: String
}

struct CoreRelease: Sendable, Equatable {
    let version: String
    let commit: String
    let package: DownloadArtifact
    let lockfile: DownloadArtifact
    let bunVersion: String
    let bunArm64SHA256: String
    let bunX64SHA256: String

}

enum CoreVersionMode: String, CaseIterable, Identifiable, Sendable {
    case build
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .build: "构建版本"
        case .custom: "自选版本"
        }
    }
}

enum CoreReleaseCatalog {
    static let build = CoreRelease(
        version: "2.12.0",
        commit: "6d881db206c6a74da6b64fa22b6980faf05d0122",
        package: DownloadArtifact(
            url: URL(string: "https://registry.npmjs.org/@bitkyc08/opencodex/-/opencodex-2.12.0.tgz")!,
            sha256: "0c66a292f102f7eb7befca97cdfd5e03941a172e8031ce540ca5927743744d34"
        ),
        lockfile: DownloadArtifact(
            url: URL(
                string:
                    "https://raw.githubusercontent.com/lidge-jun/opencodex/6d881db206c6a74da6b64fa22b6980faf05d0122/bun.lock"
            )!,
            sha256: "a22537a6b5f7c67c3043c1c112d90122e0a1874d0704b5ce997f8e855975d103"
        ),
        bunVersion: "1.3.14",
        bunArm64SHA256: "d8b96221828ad6f97ac7ac0ab7e95872341af763001e8803e8267652c2652620",
        bunX64SHA256: "4183df3374623e5bab315c547cfa0974533cd457d86b73b639f7a87974cd6633"
    )

    static let userSelectable = [
        CoreRelease(
            version: "2.31.0",
            commit: "6ae83b1f189c353935d4977bb01227484fbdb52b",
            package: DownloadArtifact(
                url: URL(string: "https://registry.npmjs.org/@bitkyc08/opencodex/-/opencodex-2.31.0.tgz")!,
                sha256: "a7454788c532de12fd323c7cac54c7394bd92137d2a3ad6aad5443f684f85603"
            ),
            lockfile: DownloadArtifact(
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/lidge-jun/opencodex/6ae83b1f189c353935d4977bb01227484fbdb52b/bun.lock"
                )!,
                sha256: "29a6cf6ad4c475b5ec0fbcc104b032fbdb293fed12eb17d803ce626481e7e2f5"
            ),
            bunVersion: "1.4.0",
            bunArm64SHA256: "c669e97f6164e1c96e0701748db98dfa77492908cbd8394c7557134a735de381",
            bunX64SHA256: "1d0211b8f1dc991182344687ad15e72ee86f154845a5f7fa477994cd341dd9b0"
        ),
        CoreRelease(
            version: "2.29.0",
            commit: "231e622be00706677a9e721496e4858a7ccee13e",
            package: DownloadArtifact(
                url: URL(string: "https://registry.npmjs.org/@bitkyc08/opencodex/-/opencodex-2.29.0.tgz")!,
                sha256: "4832802bd6bc2bde3c74724d29d7e52a372a99eb24c40f5fb65fd5c0ed46326a"
            ),
            lockfile: DownloadArtifact(
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/lidge-jun/opencodex/231e622be00706677a9e721496e4858a7ccee13e/bun.lock"
                )!,
                sha256: "dbbd8ffc7f0fc893dbf15cb96552b9ba044a4ffaf0447ac5f6c1817b9ec48ca2"
            ),
            bunVersion: "1.3.14",
            bunArm64SHA256: "d8b96221828ad6f97ac7ac0ab7e95872341af763001e8803e8267652c2652620",
            bunX64SHA256: "4183df3374623e5bab315c547cfa0974533cd457d86b73b639f7a87974cd6633"
        ),
    ]

    static var all: [CoreRelease] { [build] + userSelectable }

    static func resolve(mode: CoreVersionMode, customVersion: String?) -> CoreRelease {
        guard mode == .custom,
            let customVersion,
            let release = userSelectable.first(where: { $0.version == customVersion })
        else { return build }
        return release
    }

    static func normalizedSelection(modeRawValue: String?, customVersion: String?) -> (
        mode: CoreVersionMode,
        customVersion: String?
    ) {
        guard modeRawValue == CoreVersionMode.custom.rawValue,
            let customVersion,
            userSelectable.contains(where: { $0.version == customVersion })
        else { return (.build, nil) }
        return (.custom, customVersion)
    }
}

extension CoreRelease {

    var bunArtifact: BunArtifact {
        #if arch(arm64)
            BunArtifact(
                archive: DownloadArtifact(
                    url: URL(
                        string:
                            "https://github.com/oven-sh/bun/releases/download/bun-v\(bunVersion)/bun-darwin-aarch64.zip"
                    )!,
                    sha256: bunArm64SHA256
                ),
                archiveDirectory: "bun-darwin-aarch64"
            )
        #elseif arch(x86_64)
            BunArtifact(
                archive: DownloadArtifact(
                    url: URL(
                        string:
                            "https://github.com/oven-sh/bun/releases/download/bun-v\(bunVersion)/bun-darwin-x64.zip"
                    )!,
                    sha256: bunX64SHA256
                ),
                archiveDirectory: "bun-darwin-x64"
            )
        #else
            fatalError("Unsupported Mac architecture")
        #endif
    }
}

struct InstalledCoreManifest: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let coreVersion: String
    let coreCommit: String
    let bunVersion: String
    let packageSHA256: String
    let installedAt: Date
}

struct InstalledCorePaths: Sendable {
    let versionRoot: URL
    let sourceRoot: URL
    let runtimeExecutable: URL
    let cliEntry: URL
    let dataDirectory: URL
    let logFile: URL
}

enum CoreInstallationPaths {
    static var applicationSupportDirectory: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("OpenCodex Desktop", isDirectory: true)
    }

    static var coreDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Core", isDirectory: true)
    }

    static var versionsDirectory: URL {
        coreDirectory.appendingPathComponent("versions", isDirectory: true)
    }

    static var stagingDirectory: URL {
        coreDirectory.appendingPathComponent("staging", isDirectory: true)
    }

    static var cacheDirectory: URL {
        coreDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    static var dataDirectory: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return
            base
            .appendingPathComponent("OpenCodex", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
    }

    static var logFile: URL {
        applicationSupportDirectory.appendingPathComponent("Logs/core.log")
    }

    static func versionDirectory(_ version: String) -> URL {
        versionsDirectory.appendingPathComponent(version, isDirectory: true)
    }

    static func paths(for version: String) -> InstalledCorePaths {
        let root = versionDirectory(version)
        return InstalledCorePaths(
            versionRoot: root,
            sourceRoot: root.appendingPathComponent("package", isDirectory: true),
            runtimeExecutable: root.appendingPathComponent("bin/bun"),
            cliEntry: root.appendingPathComponent("package/src/cli/index.ts"),
            dataDirectory: dataDirectory,
            logFile: logFile
        )
    }
}

enum CodexRuntimeEnvironment {
    private struct PersistedRuntime: Decodable {
        let command: String
    }

    static func prepared(
        from base: [String: String],
        dataDirectory: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [String: String] {
        var environment = base
        var directories: [URL] = []

        if let configuredPath = base["CODEX_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            let directory = executableDirectory(for: configuredPath, fileManager: fileManager)
        {
            directories.append(directory)
        }
        if let directory = persistedRuntimeDirectory(in: dataDirectory, fileManager: fileManager) {
            directories.append(directory)
        }

        directories.append(contentsOf: versionManagerDirectories(in: homeDirectory, fileManager: fileManager))
        directories.append(contentsOf: [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".npm-global/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".bun/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".volta/bin", isDirectory: true),
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications/Codex.app/Contents/Resources", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        ])

        let discovered = directories.compactMap { directory -> String? in
            let codex = directory.appendingPathComponent("codex", isDirectory: false)
            return fileManager.isExecutableFile(atPath: codex.path) ? directory.path : nil
        }
        let existing = (base["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        environment["PATH"] = unique(discovered + existing).joined(separator: ":")
        return environment
    }

    static func detectedCodexCommand(
        in environment: [String: String],
        fileManager: FileManager = .default
    ) -> String? {
        if let configured = environment["CODEX_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            executableDirectory(for: configured, fileManager: fileManager) != nil
        {
            return configured
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("codex", isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate.path }
        }
        return nil
    }

    private static func persistedRuntimeDirectory(in dataDirectory: URL, fileManager: FileManager) -> URL? {
        let stateURL = dataDirectory.appendingPathComponent("codex-runtime.json", isDirectory: false)
        guard
            let values = try? stateURL.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            (values.fileSize ?? 16_385) <= 16_384,
            let data = try? Data(contentsOf: stateURL),
            data.count <= 16_384,
            let state = try? JSONDecoder().decode(PersistedRuntime.self, from: data)
        else { return nil }
        return executableDirectory(for: state.command, fileManager: fileManager)
    }

    private static func executableDirectory(for path: String, fileManager: FileManager) -> URL? {
        guard path.hasPrefix("/"), fileManager.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: false).deletingLastPathComponent()
    }

    private static func versionManagerDirectories(in homeDirectory: URL, fileManager: FileManager) -> [URL] {
        let nodeVersions = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let versions =
            (try? fileManager.contentsOfDirectory(
                at: nodeVersions,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        return
            versions
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appendingPathComponent("bin", isDirectory: true) }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

enum CoreInstallationState: Equatable {
    case checking
    case notInstalled
    case installing(String)
    case installed(InstalledCoreManifest)
    case updateAvailable(installed: InstalledCoreManifest, target: CoreRelease)
    case failed(String)

    var isInstalled: Bool {
        switch self {
        case .installed: true
        default: false
        }
    }

    var isBusy: Bool {
        if case .installing = self { true } else { false }
    }
}

enum CoreManagerError: LocalizedError {
    case notInstalled
    case unsupportedArchitecture
    case downloadFailed(String)
    case insecureDownload(String)
    case artifactTooLarge(String)
    case checksumMismatch(String)
    case commandFailed(String)
    case invalidInstallation
    case untrustedVersion(String)
    case launchFailed(String)
    case stoppedUnexpectedly(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "尚未安装兼容的 OpenCodex 内核"
        case .unsupportedArchitecture:
            "当前 Mac 架构不受支持"
        case let .downloadFailed(message):
            "内核下载失败：\(message)"
        case let .insecureDownload(name):
            "\(name) 下载未保持 HTTPS，安装已终止"
        case let .artifactTooLarge(name):
            "\(name) 超过允许的下载大小，安装已终止"
        case let .checksumMismatch(name):
            "\(name) 校验失败，安装已终止"
        case let .commandFailed(message):
            message
        case .invalidInstallation:
            "内核安装不完整，请重新安装"
        case let .untrustedVersion(version):
            "Core \(version) 不在客户端的可信版本目录中"
        case let .launchFailed(message):
            message.isEmpty ? "OpenCodex 内核启动失败" : message
        case let .stoppedUnexpectedly(message):
            message.isEmpty ? "OpenCodex 内核意外停止" : message
        }
    }
}

actor CoreInstaller {
    typealias PhaseHandler = @Sendable (String) async -> Void

    private let fileManager = FileManager.default
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func install(release: CoreRelease, phase: PhaseHandler) async throws -> InstalledCoreManifest {
        try ensurePrivateDirectory(CoreInstallationPaths.stagingDirectory)
        try ensurePrivateDirectory(CoreInstallationPaths.versionsDirectory)
        try ensurePrivateDirectory(CoreInstallationPaths.cacheDirectory)

        let stagingRoot = CoreInstallationPaths.stagingDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloadRoot = stagingRoot.appendingPathComponent("payload", isDirectory: true)
        let packageRoot = payloadRoot.appendingPathComponent("package", isDirectory: true)
        let binRoot = payloadRoot.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: binRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        await phase("正在下载 OpenCodex Core \(release.version)…")
        let packageArchive = stagingRoot.appendingPathComponent("opencodex.tgz")
        try await download(release.package, named: "OpenCodex Core", to: packageArchive)

        await phase("正在下载锁定依赖清单…")
        let lockfile = stagingRoot.appendingPathComponent("bun.lock")
        try await download(release.lockfile, named: "bun.lock", to: lockfile)

        await phase("正在下载 Bun \(release.bunVersion)…")
        let bunArtifact = release.bunArtifact
        let bunArchive = stagingRoot.appendingPathComponent("bun.zip")
        try await download(bunArtifact.archive, named: "Bun", to: bunArchive)

        await phase("正在解压内核…")
        try run(
            executable: "/usr/bin/tar",
            arguments: ["-xzf", packageArchive.path, "-C", packageRoot.path, "--strip-components", "1"],
            logURL: stagingRoot.appendingPathComponent("extract-core.log")
        )
        try fileManager.copyItem(at: lockfile, to: packageRoot.appendingPathComponent("bun.lock"))

        let bunExtractRoot = stagingRoot.appendingPathComponent("bun-extract", isDirectory: true)
        try fileManager.createDirectory(at: bunExtractRoot, withIntermediateDirectories: true)
        try run(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", bunArchive.path, bunExtractRoot.path],
            logURL: stagingRoot.appendingPathComponent("extract-bun.log")
        )
        let extractedBun =
            bunExtractRoot
            .appendingPathComponent(bunArtifact.archiveDirectory, isDirectory: true)
            .appendingPathComponent("bun")
        let installedBun = binRoot.appendingPathComponent("bun")
        guard fileManager.fileExists(atPath: extractedBun.path) else {
            throw CoreManagerError.invalidInstallation
        }
        try fileManager.copyItem(at: extractedBun, to: installedBun)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedBun.path)
        try run(
            executable: "/usr/bin/codesign",
            arguments: ["--force", "--sign", "-", installedBun.path],
            logURL: stagingRoot.appendingPathComponent("codesign-bun.log")
        )

        await phase("正在安装内核依赖…")
        try run(
            executable: installedBun.path,
            arguments: ["install", "--production", "--frozen-lockfile"],
            currentDirectory: packageRoot,
            environment: [
                "BUN_INSTALL_CACHE_DIR": CoreInstallationPaths.cacheDirectory.path,
                "CI": "1",
            ],
            logURL: stagingRoot.appendingPathComponent("install-dependencies.log")
        )

        await phase("正在验证本机组件…")
        try signNativeModules(in: packageRoot, logRoot: stagingRoot)
        pruneDevelopmentPackages(in: packageRoot)

        let manifest = InstalledCoreManifest(
            schemaVersion: 1,
            coreVersion: release.version,
            coreCommit: release.commit,
            bunVersion: release.bunVersion,
            packageSHA256: release.package.sha256,
            installedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: payloadRoot.appendingPathComponent("installation.json"),
            options: .atomic
        )

        guard fileManager.isExecutableFile(atPath: installedBun.path),
            fileManager.fileExists(atPath: packageRoot.appendingPathComponent("src/cli/index.ts").path),
            fileManager.fileExists(atPath: packageRoot.appendingPathComponent("node_modules").path)
        else {
            throw CoreManagerError.invalidInstallation
        }

        await phase("正在完成安装…")
        try publish(payloadRoot: payloadRoot, version: release.version)
        return manifest
    }

    func uninstall(version: String) throws {
        let target = CoreInstallationPaths.versionDirectory(version)
        guard
            target.deletingLastPathComponent().standardizedFileURL
                == CoreInstallationPaths.versionsDirectory.standardizedFileURL
        else {
            throw CoreManagerError.invalidInstallation
        }
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
    }

    private func download(_ artifact: DownloadArtifact, named name: String, to destination: URL) async throws {
        guard artifact.url.scheme?.lowercased() == "https" else {
            throw CoreManagerError.insecureDownload(name)
        }
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await session.download(from: artifact.url)
        } catch {
            throw CoreManagerError.downloadFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CoreManagerError.downloadFailed("HTTP \(status)")
        }
        guard response.url?.scheme?.lowercased() == "https" else {
            throw CoreManagerError.insecureDownload(name)
        }
        let attributes = try fileManager.attributesOfItem(atPath: temporary.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? Int64.max
        guard size <= artifact.maximumBytes else {
            throw CoreManagerError.artifactTooLarge(name)
        }
        let actual = try Self.sha256(of: temporary)
        guard actual == artifact.sha256.lowercased() else {
            throw CoreManagerError.checksumMismatch(name)
        }
        try fileManager.copyItem(at: temporary, to: destination)
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:],
        logURL: URL
    ) throws {
        fileManager.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CoreManagerError.commandFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let detail = Self.logTail(from: logURL)
            throw CoreManagerError.commandFailed(detail.isEmpty ? "内核安装命令执行失败" : detail)
        }
    }

    private func signNativeModules(in packageRoot: URL, logRoot: URL) throws {
        guard
            let enumerator = fileManager.enumerator(
                at: packageRoot.appendingPathComponent("node_modules", isDirectory: true),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return }
        var index = 0
        for case let url as URL in enumerator where url.pathExtension == "node" {
            index += 1
            try run(
                executable: "/usr/bin/codesign",
                arguments: ["--force", "--sign", "-", url.path],
                logURL: logRoot.appendingPathComponent("codesign-native-\(index).log")
            )
        }
    }

    private func pruneDevelopmentPackages(in packageRoot: URL) {
        let nodeModules = packageRoot.appendingPathComponent("node_modules", isDirectory: true)
        for relative in ["@types", "@typescript", "bun", "bun-types", "typescript"] {
            try? fileManager.removeItem(at: nodeModules.appendingPathComponent(relative, isDirectory: true))
        }
    }

    private func publish(payloadRoot: URL, version: String) throws {
        let destination = CoreInstallationPaths.versionDirectory(version)
        let backup = CoreInstallationPaths.versionsDirectory
            .appendingPathComponent(".\(version)-backup-\(UUID().uuidString)", isDirectory: true)
        let hadExisting = fileManager.fileExists(atPath: destination.path)
        if hadExisting { try fileManager.moveItem(at: destination, to: backup) }
        do {
            try fileManager.moveItem(at: payloadRoot, to: destination)
            if hadExisting { try? fileManager.removeItem(at: backup) }
        } catch {
            if hadExisting, !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    private static func logTail(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return "" }
        return String(data: data.suffix(8_192), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

@MainActor
final class CoreManager: ObservableObject {
    static let shared = CoreManager()

    private static let versionModeDefaultsKey = "coreVersionMode"
    private static let customVersionDefaultsKey = "customCoreVersion"

    @Published private(set) var installationState: CoreInstallationState = .checking
    @Published private(set) var ownsRunningProcess = false
    @Published private(set) var lastExitMessage: String?
    @Published private(set) var versionMode: CoreVersionMode
    @Published private(set) var customVersion: String?

    let buildRelease = CoreReleaseCatalog.build
    let userSelectableReleases = CoreReleaseCatalog.userSelectable
    private let installer = CoreInstaller()
    private let defaults: UserDefaults
    private var process: Process?
    private var logHandle: FileHandle?
    private var stopRequested = false

    var targetRelease: CoreRelease {
        CoreReleaseCatalog.resolve(mode: versionMode, customVersion: customVersion)
    }

    var targetIsBuildRelease: Bool { targetRelease.version == buildRelease.version }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let selection = CoreReleaseCatalog.normalizedSelection(
            modeRawValue: defaults.string(forKey: Self.versionModeDefaultsKey),
            customVersion: defaults.string(forKey: Self.customVersionDefaultsKey)
        )
        versionMode = selection.mode
        customVersion = selection.customVersion
        refreshInstallation()
    }

    func setVersionMode(_ mode: CoreVersionMode) {
        if mode == .custom, customVersion == nil {
            customVersion = userSelectableReleases.first?.version
        }
        versionMode = mode
        persistVersionSelection()
        refreshInstallation()
    }

    func selectCustomVersion(_ version: String) throws {
        guard userSelectableReleases.contains(where: { $0.version == version }) else {
            throw CoreManagerError.untrustedVersion(version)
        }
        customVersion = version
        versionMode = .custom
        persistVersionSelection()
        refreshInstallation()
    }

    private func persistVersionSelection() {
        defaults.set(versionMode.rawValue, forKey: Self.versionModeDefaultsKey)
        if let customVersion {
            defaults.set(customVersion, forKey: Self.customVersionDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.customVersionDefaultsKey)
        }
    }

    func refreshInstallation() {
        let targetRelease = targetRelease
        let manifests = Self.discoverInstalledCores()
        if let compatible = manifests.first(where: { Self.isCompatibleManifest($0, with: targetRelease) }),
            Self.isValidInstallation(compatible)
        {
            installationState = .installed(compatible)
        } else if let existing = manifests.first(where: Self.isValidInstallation) {
            installationState = .updateAvailable(installed: existing, target: targetRelease)
        } else {
            installationState = .notInstalled
        }
    }

    func installTargetCore() async throws {
        let targetRelease = targetRelease
        installationState = .installing("正在准备安装…")
        do {
            let manager = self
            let manifest = try await installer.install(release: targetRelease) { phase in
                await manager.reportInstallationPhase(phase)
            }
            installationState = .installed(manifest)
        } catch {
            installationState = .failed(error.localizedDescription)
            throw error
        }
    }

    func uninstallTargetCore() async throws {
        await stop()
        try await installer.uninstall(version: targetRelease.version)
        refreshInstallation()
    }

    func start(port: Int) async throws {
        if let process, process.isRunning {
            ownsRunningProcess = true
            return
        }
        refreshInstallation()
        guard installationState.isInstalled else { throw CoreManagerError.notInstalled }
        let paths = CoreInstallationPaths.paths(for: targetRelease.version)
        guard FileManager.default.isExecutableFile(atPath: paths.runtimeExecutable.path),
            FileManager.default.fileExists(atPath: paths.cliEntry.path)
        else {
            throw CoreManagerError.invalidInstallation
        }
        try prepareDirectories(paths)
        let handle = try openLog(paths.logFile)
        let process = Process()
        process.executableURL = paths.runtimeExecutable
        process.arguments = [paths.cliEntry.path, "start", "--port", String(port)]
        process.currentDirectoryURL = paths.sourceRoot
        process.standardOutput = handle
        process.standardError = handle
        var environment = CodexRuntimeEnvironment.prepared(
            from: ProcessInfo.processInfo.environment,
            dataDirectory: paths.dataDirectory
        )
        environment["OPENCODEX_HOME"] = paths.dataDirectory.path
        environment["OPENCODEX_AGENT_DRIVEN"] = "1"
        environment["OPENCODEX_BUN_PATH"] = paths.runtimeExecutable.path
        environment["OCX_BUN_RUNTIME_SOURCE"] = "bundled"
        environment["OCX_BUN_RUNTIME_PATH"] = paths.runtimeExecutable.path
        environment["NO_COLOR"] = "1"
        process.environment = environment
        stopRequested = false
        process.terminationHandler = { [weak self] terminatedProcess in
            guard let manager = self else { return }
            Task { @MainActor [manager] in
                manager.handleTermination(of: terminatedProcess)
            }
        }
        do {
            try process.run()
        } catch {
            try? handle.close()
            throw CoreManagerError.launchFailed(error.localizedDescription)
        }
        self.process = process
        logHandle = handle
        ownsRunningProcess = true
        lastExitMessage = nil
    }

    func stop() async {
        guard let process, process.isRunning else {
            ownsRunningProcess = false
            return
        }
        stopRequested = true
        process.terminate()
        let deadline = ContinuousClock.now + AppConstants.Service.terminateTimeout
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: AppConstants.Service.processPollInterval)
        }
        if process.isRunning {
            process.interrupt()
            let interruptDeadline = ContinuousClock.now + AppConstants.Service.interruptTimeout
            while process.isRunning, ContinuousClock.now < interruptDeadline {
                try? await Task.sleep(for: AppConstants.Service.processPollInterval)
            }
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            let killDeadline = ContinuousClock.now + AppConstants.Service.forceKillTimeout
            while process.isRunning, ContinuousClock.now < killDeadline {
                try? await Task.sleep(for: AppConstants.Service.processPollInterval)
            }
        }
        guard !process.isRunning else {
            lastExitMessage = "无法停止 OpenCodex 内核进程（PID \(process.processIdentifier)）"
            ownsRunningProcess = true
            stopRequested = false
            return
        }
        lastExitMessage = nil
        self.process = nil
        try? logHandle?.close()
        logHandle = nil
        ownsRunningProcess = false
        stopRequested = false
    }

    func openLog() {
        NSWorkspace.shared.activateFileViewerSelecting([CoreInstallationPaths.logFile])
    }

    func openInstallationFolder() {
        NSWorkspace.shared.open(CoreInstallationPaths.coreDirectory)
    }

    func terminateOwnedProcess() {
        guard let process, process.isRunning else { return }
        stopRequested = true
        process.terminate()
    }

    private func reportInstallationPhase(_ phase: String) {
        installationState = .installing(phase)
    }

    private static func discoverInstalledCores() -> [InstalledCoreManifest] {
        let manager = FileManager.default
        guard
            let directories = try? manager.contentsOfDirectory(
                at: CoreInstallationPaths.versionsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return directories.compactMap { directory in
            let manifestURL = directory.appendingPathComponent("installation.json")
            guard let data = try? Data(contentsOf: manifestURL), data.count <= 16_384 else { return nil }
            guard let manifest = try? decoder.decode(InstalledCoreManifest.self, from: data),
                manifest.coreVersion == directory.lastPathComponent
            else { return nil }
            return manifest
        }.sorted { $0.installedAt > $1.installedAt }
    }

    private static func isValidInstallation(_ manifest: InstalledCoreManifest) -> Bool {
        guard isSafeVersion(manifest.coreVersion) else { return false }
        let paths = CoreInstallationPaths.paths(for: manifest.coreVersion)
        return manifest.schemaVersion == 1
            && FileManager.default.isExecutableFile(atPath: paths.runtimeExecutable.path)
            && FileManager.default.fileExists(atPath: paths.cliEntry.path)
            && FileManager.default.fileExists(atPath: paths.sourceRoot.appendingPathComponent("node_modules").path)
    }

    private static func isCompatibleManifest(_ manifest: InstalledCoreManifest, with release: CoreRelease) -> Bool {
        manifest.schemaVersion == 1
            && manifest.coreVersion == release.version
            && manifest.coreCommit == release.commit
            && manifest.bunVersion == release.bunVersion
            && manifest.packageSHA256 == release.package.sha256
    }

    private static func isSafeVersion(_ version: String) -> Bool {
        version.range(
            of: #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-.][0-9A-Za-z.-]+)?$"#,
            options: .regularExpression
        ) != nil && !version.contains("..")
    }

    private func handleTermination(of terminatedProcess: Process) {
        guard process === terminatedProcess else { return }
        if !stopRequested {
            lastExitMessage = Self.logTail(from: CoreInstallationPaths.logFile)
            if lastExitMessage?.isEmpty != false {
                lastExitMessage = "OpenCodex 内核已退出（状态码 \(terminatedProcess.terminationStatus)）"
            }
        }
        process = nil
        try? logHandle?.close()
        logHandle = nil
        ownsRunningProcess = false
    }

    private func prepareDirectories(_ paths: InstalledCorePaths) throws {
        try FileManager.default.createDirectory(at: paths.dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: paths.logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.dataDirectory.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: paths.logFile.deletingLastPathComponent().path
        )
    }

    private func openLog(_ url: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }

    private static func logTail(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return "" }
        return String(data: data.suffix(8_192), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
