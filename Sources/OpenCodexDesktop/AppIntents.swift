import AppIntents

struct OpenRuntimeStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 OpenCodex 首页"
    static let description = IntentDescription("打开 Desktop 的本机 Core 运行状态。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.show(.home)
        return .result()
    }
}

struct OpenAccountsIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 OpenCodex 账号"
    static let description = IntentDescription("在 Desktop 中管理 Codex 多账号与调度设置。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.show(.accounts)
        return .result()
    }
}

struct OpenChannelsIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 OpenCodex 渠道"
    static let description = IntentDescription("在 Desktop 中管理 API 渠道。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.show(.channels)
        return .result()
    }
}

struct OpenSubagentsIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 OpenCodex 子代理"
    static let description = IntentDescription("在 Desktop 中选择子代理模型并调整偏好顺序。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.show(.subagents)
        return .result()
    }
}

struct OpenCodexDesktopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRuntimeStatusIntent(),
            phrases: ["在 \(.applicationName) 中打开运行状态"],
            shortTitle: "运行状态",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: OpenAccountsIntent(),
            phrases: ["在 \(.applicationName) 中打开账号"],
            shortTitle: "账号",
            systemImageName: "person.2"
        )
        AppShortcut(
            intent: OpenChannelsIntent(),
            phrases: ["在 \(.applicationName) 中打开渠道"],
            shortTitle: "渠道",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: OpenSubagentsIntent(),
            phrases: ["在 \(.applicationName) 中打开子代理"],
            shortTitle: "子代理",
            systemImageName: "person.3.sequence"
        )
    }
}
