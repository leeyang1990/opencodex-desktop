import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        ApplicationAppearance.shared.applyStoredPreference()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await AppUpdateManager.shared.checkForUpdatesIfNeeded() }
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    var body: some View {
        Text(model.connectionState.label)
        Divider()
        Button("打开 OpenCodex Desktop") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("刷新状态") {
            Task { await model.refresh(showSpinner: false) }
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
        Divider()
        Button("退出客户端（Core 继续运行）") { NSApp.terminate(nil) }
    }
}
