import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app scene so the termination path can run cleanup against the live model.
    weak var model: AppModel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        ApplicationAppearance.shared.applyStoredPreference()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reconcileDockVisibility()
        DesktopEventStore.shared.append(.appStarted)
        Task { await AppUpdateManager.shared.checkForUpdatesIfNeeded() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        reconcileDockVisibility()
    }

    private func reconcileDockVisibility() {
        // SwiftUI/LaunchServices can restore regular activation while creating or reopening the
        // main scene. Apply after that work, not only in willFinishLaunching.
        DispatchQueue.main.async {
            ApplicationAppearance.shared.applyStoredPreference()
        }
    }

    /// Finish stop → restore → restart before allowing termination. Failures keep the app open
    /// and the next quit retries cleanup; only a fully successful cleanup is deduplicated.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.hasMarkedTerminating { return .terminateLater }
        model.hasMarkedTerminating = true

        Task { @MainActor in
            let message = await model.runExitCleanup()
            if let message {
                model.errorMessage = message
                model.hasMarkedTerminating = false
                NSApp.reply(toApplicationShouldTerminate: false)
                return
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        DesktopEventStore.shared.append(.appStopped)
    }
}

@main
struct OpenCodexDesktopApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // A single-window scene keeps the launcher to exactly one main window. `WindowGroup`
        // publishes a "New Window" (⌘N) command and can therefore multiply identical main
        // windows, which then cascade over each other; `openWindow(id: "main")` still reveals
        // this window, including after the user closes it.
        Window("OpenCodex Desktop", id: "main") {
            RootView()
                .environmentObject(model)
                .environment(\.locale, L10n.locale)
                .disabled(model.hasMarkedTerminating)
                .onAppear { applicationDelegate.model = model }
        }
        .defaultSize(width: 1040, height: 700)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.tr("检查更新…")) {
                    Task { await AppUpdateManager.shared.checkForUpdatesPresentingResult() }
                }
            }
            CommandGroup(after: .toolbar) {
                Button(L10n.tr("刷新")) {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r")
            }
        }

        Window(L10n.tr("诊断"), id: ShellWindow.diagnostics) {
            DiagnosticsView()
                .environmentObject(model)
                .environment(\.locale, L10n.locale)
                .liquidWindowSurface()
        }
        .defaultSize(width: 940, height: 760)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
                .environment(\.locale, L10n.locale)
                .disabled(model.hasMarkedTerminating)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
                .accessibilityLabel("OpenCodex Desktop")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// A real AppKit template image is used here instead of a SwiftUI `Shape`.
/// `MenuBarExtra` can allocate a status-item slot without rasterising a custom
/// shape on some macOS releases; an `NSImage` template renders reliably and is
/// automatically tinted for light, dark, highlighted, and inactive menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            let codexRing = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 2.5, width: 13, height: 13))
            codexRing.lineWidth = 2.25
            codexRing.lineCapStyle = .round
            codexRing.lineJoinStyle = .round
            codexRing.stroke()

            let routeArrow = NSBezierPath()
            routeArrow.move(to: NSPoint(x: 4.75, y: 9))
            routeArrow.line(to: NSPoint(x: 18, y: 9))
            routeArrow.move(to: NSPoint(x: 13, y: 4.25))
            routeArrow.line(to: NSPoint(x: 18, y: 9))
            routeArrow.line(to: NSPoint(x: 13, y: 13.75))
            routeArrow.lineWidth = 2.5
            routeArrow.lineCapStyle = .round
            routeArrow.lineJoinStyle = .round
            routeArrow.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

private struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var coreManager = CoreManager.shared
    @ObservedObject private var appUpdateManager = AppUpdateManager.shared
    @ObservedObject private var navigation = AppNavigation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.connectionState.label)
                .font(.headline)
            if let version = model.health?.version {
                Text("OpenCodex \(version)\(model.health?.pid.map { " · PID \($0)" } ?? "")")
                    .font(.caption)
            } else {
                Text(L10n.tr("已选择 \(coreManager.targetRelease.version)"))
                    .font(.caption)
            }
        }
        Divider()
        Button(L10n.tr("打开 OpenCodex Desktop")) {
            show(.home)
        }
        Button(L10n.tr("账号")) { show(.accounts) }
        Button(L10n.tr("渠道")) { show(.channels) }
        Button(L10n.tr("子代理")) { show(.subagents) }
        Button(L10n.tr("设置")) { show(.settings) }
        Divider()
        Button(L10n.tr("诊断…")) { openWindow(id: ShellWindow.diagnostics) }
        Divider()
        if model.isOnline {
            Button(L10n.tr("重启本机代理")) { Task { await model.restartService() } }
            Button(L10n.tr("停止本机代理")) { Task { await model.stopService() } }
                .help(L10n.tr("还原路由，并重启正在运行的 ChatGPT"))
        } else if coreManager.installationState.isInstalled {
            Button(L10n.tr("启动本机代理")) { Task { await model.startService() } }
        } else {
            Button(L10n.tr("下载并安装内核")) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                Task { await model.installCore() }
            }
        }
        Button(L10n.tr("重启 ChatGPT（应用 Codex 配置）")) {
            Task { await model.restartChatGPT(reason: L10n.tr("菜单栏")) }
        }
        .disabled(model.isRestartingChatGPT)
        Divider()
        Button(L10n.tr("退出并停止代理")) {
            NSApp.terminate(nil)
        }
    }

    private func show(_ destination: SidebarDestination) {
        navigation.show(destination)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
