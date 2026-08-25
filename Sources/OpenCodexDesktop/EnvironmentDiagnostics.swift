import Foundation

enum EnvironmentCheckID: String, CaseIterable {
    case systemPrivacy
    case localStorage
    case coreInstallation
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
}

enum EnvironmentDiagnostics {
    static func evaluate(
        dataDirectoryWritable: Bool,
        coreDirectoryWritable: Bool,
        coreInstalled: Bool,
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

        items.append(
            EnvironmentCheckItem(
                id: .coreInstallation,
                title: "OpenCodex Core",
                detail: coreInstalled ? "兼容的 Core 已安装并通过完整性检查。" : "尚未安装兼容 Core；安装后会继续检查运行状态。",
                state: coreInstalled ? .passed : .pending
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
        } else if serviceOnline {
            runtimeItem = EnvironmentCheckItem(
                id: .codexRuntime,
                title: "Codex CLI",
                detail: runtime?.warning ?? "服务未能验证可用的 Codex CLI。",
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
        let baseEnvironment = ProcessInfo.processInfo.environment
        let preparedEnvironment = CodexRuntimeEnvironment.prepared(
            from: baseEnvironment,
            dataDirectory: CoreInstallationPaths.dataDirectory
        )
        let loginItem = LoginItemManager()
        environmentReport = EnvironmentDiagnostics.evaluate(
            dataDirectoryWritable: EnvironmentDiagnostics.canWrite(
                expectedDirectory: CoreInstallationPaths.dataDirectory
            ),
            coreDirectoryWritable: EnvironmentDiagnostics.canWrite(
                expectedDirectory: CoreInstallationPaths.coreDirectory
            ),
            coreInstalled: coreManager.installationState.isInstalled,
            tokenAvailable: tokenAvailable,
            serviceOnline: isOnline,
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
