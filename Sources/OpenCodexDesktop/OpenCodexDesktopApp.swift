import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        ApplicationAppearance.shared.applyStoredPreference()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DesktopEventStore.shared.append(.appStarted)
        Task { await AppUpdateManager.shared.checkForUpdatesIfNeeded() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DesktopEventStore.shared.append(.appStopped)
        CoreManager.shared.detachOwnedProcess()
    }
}

@main
struct OpenCodexDesktopApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(model)
        }
        .defaultSize(width: 1040, height: 700)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    Task { await AppUpdateManager.shared.checkForUpdatesPresentingResult() }
                }
            }
            CommandGroup(after: .toolbar) {
                Button("刷新") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r")
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            Label(
                "OpenCodex Desktop",
                systemImage: model.isOnline
                    ? "point.3.filled.connected.trianglepath.dotted" : "point.3.connected.trianglepath.dotted")
        }
        .menuBarExtraStyle(.menu)
    }
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
                Text("OpenCodex Core \(version)\(model.health?.pid.map { " · PID \($0)" } ?? "")")
                    .font(.caption)
            } else {
                Text("已选择 Core \(coreManager.targetRelease.version)")
                    .font(.caption)
            }
        }
        Divider()
        Button("打开 OpenCodex Desktop") {
            show(.overview)
        }
        Button("打开 OpenCodex 控制台") {
            show(.dashboard)
        }
        Button("诊断与修复") {
            show(.diagnostics)
        }
        Button("刷新状态") {
            Task {
                await model.refresh(showSpinner: false)
                model.runEnvironmentCheck()
            }
        }
        if let release = appUpdateManager.availableRelease {
            Button("下载并打开客户端更新 \(release.version)") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                Task {
                    await appUpdateManager.downloadAvailableUpdate()
                    if appUpdateManager.downloadedUpdateURL != nil {
                        appUpdateManager.openDownloadedUpdate()
                    }
                }
            }
            .disabled(appUpdateManager.isBusy)
        } else {
            Button("检查客户端更新") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                Task { await appUpdateManager.checkForUpdatesPresentingResult() }
            }
            .disabled(appUpdateManager.isBusy)
        }
        Divider()
        if model.isOnline {
            Button("重启本地服务") {
                Task { await model.restartService() }
            }
            Button("停止本地服务") {
                Task { await model.stopService() }
            }
        } else if coreManager.installationState.isInstalled {
            Button("启动本地服务") {
                Task { await model.startService() }
            }
        } else {
            Button("下载并安装内核") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                Task { await model.installCore() }
            }
        }
        Button("查看 Core 日志") { model.openCoreLog() }
            .disabled(!FileManager.default.fileExists(atPath: CoreInstallationPaths.logFile.path))
        Divider()
        Button("退出客户端（Core 继续运行）") { NSApp.terminate(nil) }
    }

    private func show(_ destination: SidebarDestination) {
        navigation.show(destination)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
