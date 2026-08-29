import AppIntents

struct OpenRuntimeStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 OpenCodex 运行状态"
    static let description = IntentDescription("打开 Desktop 的本机 Core 运行状态。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.show(.overview)
        return .result()
    }
}

struct OpenDiagnosticsIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 OpenCodex 诊断"
    static let description = IntentDescription("打开 Desktop 的诊断、Runtime 与安全检查。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.show(.diagnostics)
        return .result()
    }
}

struct OpenOpenCodexConsoleIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 OpenCodex 控制台"
    static let description = IntentDescription("打开由本机 Core 提供的 OpenCodex 控制台。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigation.shared.show(.dashboard)
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
            intent: OpenDiagnosticsIntent(),
            phrases: ["在 \(.applicationName) 中打开诊断"],
            shortTitle: "诊断与修复",
            systemImageName: "stethoscope"
        )
        AppShortcut(
            intent: OpenOpenCodexConsoleIntent(),
            phrases: ["在 \(.applicationName) 中打开控制台"],
            shortTitle: "OpenCodex 控制台",
            systemImageName: "safari"
        )
    }
}
