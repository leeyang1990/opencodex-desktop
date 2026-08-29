import Foundation

enum EnvironmentCheckID: String, CaseIterable {
    case systemPrivacy
    case localStorage
    case diskSpace
    case coreInstallation
    case serviceEndpoint
    case managementToken
    case codexRuntime
    case loginItem
}

enum EnvironmentCheckState: Equatable {
    case passed
    case attention
    case pending
}

struct EnvironmentCheckItem: Identifiable, Equatable {
    let id: EnvironmentCheckID
    let title: String
    let detail: String
    let state: EnvironmentCheckState
}

struct EnvironmentCheckReport: Equatable {
    let checkedAt: Date?
    let items: [EnvironmentCheckItem]

    static let empty = EnvironmentCheckReport(checkedAt: nil, items: [])

    var needsAttention: Bool { items.contains { $0.state == .attention } }
    var requiresLoginItemApproval: Bool {
        items.contains { $0.id == .loginItem && $0.state == .attention }
    }

    func item(_ id: EnvironmentCheckID) -> EnvironmentCheckItem? {
        items.first { $0.id == id }
    }
}

enum CoreIntegrityInspection: Equatable {
    case missing
    case valid(InstalledCoreManifest)
    case invalid(String)

    var isValid: Bool {
        if case .valid = self { true } else { false }
    }

    var needsRepair: Bool {
        if case .invalid = self { true } else { false }
    }
}

enum CoreIntegrityInspector {
    static func inspect(
        release: CoreRelease,
        root: URL,
        fileManager: FileManager = .default
    ) -> CoreIntegrityInspection {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { return .missing }
        guard isDirectory.boolValue else { return .invalid("内核版本路径不是目录。") }

        let manifestURL = root.appendingPathComponent("installation.json", isDirectory: false)
        guard
            let values = try? manifestURL.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            (values.fileSize ?? 16_385) <= 16_384,
            let data = try? Data(contentsOf: manifestURL),
            data.count <= 16_384
        else {
            return .invalid("安装清单缺失或不安全。")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(InstalledCoreManifest.self, from: data) else {
            return .invalid("安装清单无法解析。")
        }
        guard manifest.schemaVersion == 1,
            manifest.coreVersion == release.version,
            manifest.coreCommit == release.commit,
            manifest.bunVersion == release.bunVersion,
            manifest.packageSHA256 == release.package.sha256
        else {
            return .invalid("安装清单与当前可信版本目录不匹配。")
        }

        let runtime = root.appendingPathComponent("bin/bun", isDirectory: false)
        let cli = root.appendingPathComponent("package/src/cli/index.ts", isDirectory: false)
        let dependencies = root.appendingPathComponent("package/node_modules", isDirectory: true)
        guard fileManager.isExecutableFile(atPath: runtime.path),
            fileManager.fileExists(atPath: cli.path),
            fileManager.fileExists(atPath: dependencies.path)
        else {
            return .invalid("Core、Bun 或运行依赖不完整。")
        }
        return .valid(manifest)
    }
}

enum LocalPortInspection: Equatable {
    case available
    case core(pid: Int?)
    case occupied(pid: Int?)
    case unknown
}

enum LocalPortInspector {
    static func inspect(port: Int, serviceOnline: Bool, corePID: Int?) -> LocalPortInspection {
        guard (1...65_535).contains(port) else { return .unknown }
        if serviceOnline { return .core(pid: corePID) }

        let executable = URL(fileURLWithPath: "/usr/sbin/lsof")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return .unknown }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let firstPID = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isNewline)
                .first
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if let firstPID { return .occupied(pid: firstPID) }
            return process.terminationStatus == 1 ? .available : .unknown
        } catch {
            return .unknown
        }
    }
}

enum EnvironmentDiagnostics {
    static func availableDiskBytes(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Int64? {
        var probe = directory.standardizedFileURL
        while !fileManager.fileExists(atPath: probe.path) {
            let parent = probe.deletingLastPathComponent()
            guard parent.path != probe.path else { return nil }
            probe = parent
        }
        guard let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let bytes = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return bytes
    }

    static func evaluate(
        dataDirectoryWritable: Bool,
        coreDirectoryWritable: Bool,
        availableDiskBytes: Int64?,
        coreInspection: CoreIntegrityInspection,
        portInspection: LocalPortInspection,
        tokenAvailable: Bool,
        serviceOnline: Bool,
        runtime: CodexRuntime?,
        detectedCodexCommand: String?,
        loginItemEnabled: Bool,
        loginItemRequiresApproval: Bool,
        now: Date = Date()
    ) -> EnvironmentCheckReport {
        var items = [
            EnvironmentCheckItem(
                id: .systemPrivacy,
                title: "系统隐私权限",
                detail: "核心功能只使用应用数据目录和本机回环网络，无需完全磁盘访问、辅助功能或屏幕录制。",
                state: .passed
            ),
            EnvironmentCheckItem(
                id: .localStorage,
                title: "本地数据目录",
                detail: dataDirectoryWritable && coreDirectoryWritable
                    ? "应用数据与 Core 安装目录均可写。"
                    : "应用数据或 Core 安装目录不可写，请检查目录所有者与权限。",
                state: dataDirectoryWritable && coreDirectoryWritable ? .passed : .attention
            ),
        ]

        let minimumDiskBytes: Int64 = 1_024 * 1_024 * 1_024
        items.append(
            EnvironmentCheckItem(
                id: .diskSpace,
                title: "可用磁盘空间",
                detail: diskDetail(availableDiskBytes),
                state: availableDiskBytes.map { $0 >= minimumDiskBytes ? .passed : .attention } ?? .pending
            )
        )

        let coreInstalled = coreInspection.isValid
        items.append(
            EnvironmentCheckItem(
                id: .coreInstallation,
                title: "OpenCodex Core",
                detail: coreDetail(coreInspection),
                state: coreState(coreInspection)
            )
        )

        items.append(
            EnvironmentCheckItem(
                id: .serviceEndpoint,
                title: "本机服务与端口",
                detail: serviceDetail(
                    serviceOnline: serviceOnline,
                    portInspection: portInspection
                ),
                state: serviceState(
                    serviceOnline: serviceOnline,
                    coreInstalled: coreInstalled,
                    portInspection: portInspection
                )
            )
        )

        items.append(
            EnvironmentCheckItem(
                id: .managementToken,
                title: "本机管理令牌",
                detail: tokenAvailable
                    ? "令牌文件可安全读取，仅用于本机管理请求。"
                    : coreInstalled
                        ? "Core 已安装但管理令牌不可用，请重新启动或重新安装 Core。"
                        : "安装并首次启动 Core 后自动创建，无需手动授权。",
                state: tokenAvailable ? .passed : coreInstalled ? .attention : .pending
            )
        )

        let runtimeItem: EnvironmentCheckItem
        if let runtime, let version = runtime.version, runtime.warning == nil {
            runtimeItem = EnvironmentCheckItem(
                id: .codexRuntime,
                title: "Codex CLI",
                detail: "已验证 Codex \(version)，来源：\(runtime.source ?? "自动发现")。",
                state: .passed
            )
        } else if serviceOnline, detectedCodexCommand != nil {
            runtimeItem = EnvironmentCheckItem(
                id: .codexRuntime,
                title: "Codex CLI",
                detail: "Mac 已发现可用的 Codex CLI，但当前 Core 尚未完成版本验证。请在下方 Runtime 中选择后重启 Core。",
                state: .attention
            )
        } else if serviceOnline {
            runtimeItem = EnvironmentCheckItem(
                id: .codexRuntime,
                title: "Codex CLI",
                detail: localizedRuntimeWarning(runtime?.warning),
                state: .attention
            )
        } else if detectedCodexCommand != nil {
            runtimeItem = EnvironmentCheckItem(
                id: .codexRuntime,
                title: "Codex CLI",
                detail: "已发现 Codex 可执行文件，Core 启动后会验证具体版本。",
                state: .passed
            )
        } else {
            runtimeItem = EnvironmentCheckItem(
                id: .codexRuntime,
                title: "Codex CLI",
                detail: "未发现 Codex CLI；请先安装 Codex，或在终端配置 CODEX_CLI_PATH。",
                state: .attention
            )
        }
        items.append(runtimeItem)

        items.append(
            EnvironmentCheckItem(
                id: .loginItem,
                title: "登录项",
                detail: loginItemRequiresApproval
                    ? "登录启动已请求，但仍需要在系统设置中批准。"
                    : loginItemEnabled
                        ? "登录启动已启用。"
                        : "登录启动未启用，不需要系统批准。",
                state: loginItemRequiresApproval ? .attention : .passed
            )
        )

        return EnvironmentCheckReport(checkedAt: now, items: items)
    }

    private static func localizedRuntimeWarning(_ warning: String?) -> String {
        guard let warning, !warning.isEmpty else { return "服务未能验证可用的 Codex CLI。" }
        if warning.contains("No validated Codex runtime found") {
            return "未验证到可用的 Codex CLI；Core 正在尝试使用系统命令 codex。请重启 Core 后重新检查。"
        }
        return warning
    }

    private static func diskDetail(_ bytes: Int64?) -> String {
        guard let bytes else { return "暂时无法读取磁盘容量。" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: bytes)
        return bytes >= 1_024 * 1_024 * 1_024
            ? "应用数据卷剩余约 \(formatted)。"
            : "应用数据卷只剩约 \(formatted)，安装或更新可能失败。"
    }

    private static func coreDetail(_ inspection: CoreIntegrityInspection) -> String {
        switch inspection {
        case .missing:
            "尚未安装当前选择的可信 Core。"
        case let .valid(manifest):
            "Core \(manifest.coreVersion) 的安装清单与运行文件完整。"
        case let .invalid(detail):
            "安装需要修复：\(detail)"
        }
    }

    private static func coreState(_ inspection: CoreIntegrityInspection) -> EnvironmentCheckState {
        switch inspection {
        case .missing: .pending
        case .valid: .passed
        case .invalid: .attention
        }
    }

    private static func serviceDetail(
        serviceOnline: Bool,
        portInspection: LocalPortInspection
    ) -> String {
        if serviceOnline {
            if case let .core(pid) = portInspection, let pid { return "Core 正在本机端口监听，PID \(pid)。" }
            return "Core 管理接口仅在本机回环地址可用。"
        }
        switch portInspection {
        case .available:
            return "目标端口当前空闲，可以启动 Core。"
        case let .occupied(pid):
            return pid.map { "目标端口被其他进程占用（PID \($0)）。" } ?? "目标端口被其他进程占用。"
        case .core:
            return "目标端口已监听，但 Core 管理接口尚未就绪。"
        case .unknown:
            return "服务未响应，暂时无法确认端口占用者。"
        }
    }

    private static func serviceState(
        serviceOnline: Bool,
        coreInstalled: Bool,
        portInspection: LocalPortInspection
    ) -> EnvironmentCheckState {
        if serviceOnline { return .passed }
        if case .occupied = portInspection { return .attention }
        return coreInstalled ? .attention : .pending
    }

    static func canWrite(
        expectedDirectory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        var probeDirectory = expectedDirectory.standardizedFileURL
        var isDirectory: ObjCBool = false
        while !fileManager.fileExists(atPath: probeDirectory.path, isDirectory: &isDirectory) {
            let parent = probeDirectory.deletingLastPathComponent()
            guard parent.path != probeDirectory.path else { return false }
            probeDirectory = parent
        }
        guard isDirectory.boolValue else { return false }

        let probe = probeDirectory.appendingPathComponent(
            ".opencodex-write-check-\(UUID().uuidString)",
            isDirectory: false
        )
        do {
            try Data().write(to: probe, options: .withoutOverwriting)
            try fileManager.removeItem(at: probe)
            return true
        } catch {
            try? fileManager.removeItem(at: probe)
            return false
        }
    }
}

extension AppModel {
    private static var environmentCheckDefaultsKey: String { "environmentCheckCompletedV1" }

    func runEnvironmentCheck(presentOnFirstLaunch: Bool = false) {
        let serviceResponding = connectionState == .online || (connectionState == .checking && health != nil)
        let baseEnvironment = ProcessInfo.processInfo.environment
        let preparedEnvironment = CodexRuntimeEnvironment.prepared(
            from: baseEnvironment,
            dataDirectory: CoreInstallationPaths.dataDirectory
        )
        let loginItem = LoginItemManager()
        let targetRelease = coreManager.targetRelease
        let inspection = CoreIntegrityInspector.inspect(
            release: targetRelease,
            root: CoreInstallationPaths.versionDirectory(targetRelease.version)
        )
        let portInspection = LocalPortInspector.inspect(
            port: connectionPort,
            serviceOnline: serviceResponding,
            corePID: health?.pid
        )
        coreIntegrityInspection = inspection
        localPortInspection = portInspection
        securityAuditReport = LocalSecurityAuditor.audit(
            servicePort: connectionPort,
            servicePID: health?.pid,
            tokenURL: AdminTokenProvider().tokenFileURL,
            dataDirectory: CoreInstallationPaths.dataDirectory,
            appBundleURL: Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil
        )
        environmentReport = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: EnvironmentDiagnostics.canWrite(
                expectedDirectory: CoreInstallationPaths.dataDirectory
            ),
            coreDirectoryWritable: EnvironmentDiagnostics.canWrite(
                expectedDirectory: CoreInstallationPaths.coreDirectory
            ),
            availableDiskBytes: EnvironmentDiagnostics.availableDiskBytes(
                at: CoreInstallationPaths.applicationSupportDirectory
            ),
            coreInspection: inspection,
            portInspection: portInspection,
            tokenAvailable: tokenAvailable,
            serviceOnline: serviceResponding,
            runtime: settings?.codexRuntime,
            detectedCodexCommand: CodexRuntimeEnvironment.detectedCodexCommand(in: preparedEnvironment),
            loginItemEnabled: loginItem.isEnabled,
            loginItemRequiresApproval: loginItem.requiresApproval
        )

        if presentOnFirstLaunch, !defaults.bool(forKey: Self.environmentCheckDefaultsKey) {
            showsFirstLaunchEnvironmentCheck = true
        }
    }

    func completeFirstLaunchEnvironmentCheck() {
        defaults.set(true, forKey: Self.environmentCheckDefaultsKey)
        showsFirstLaunchEnvironmentCheck = false
    }
}
