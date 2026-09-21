import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @StateObject var loginItem = LoginItemManager()
    @ObservedObject var coreManager = CoreManager.shared
    @ObservedObject var applicationAppearance = ApplicationAppearance.shared
    @ObservedObject var appUpdateManager = AppUpdateManager.shared
    @ObservedObject var notificationManager = NativeNotificationManager.shared

    @State var host = AppConstants.Connection.defaultHost
    @State var port = AppConstants.Connection.defaultPort
    @State var confirmUninstall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: L10n.tr("设置"))
                    .padding(.bottom, 2)

                clientSection
                coreSection
                clientUpdateStatus.cardStyle()
                HStack {
                    Button(L10n.tr("诊断…")) { openWindow(id: ShellWindow.diagnostics) }
                    Button(L10n.tr("查看内核日志")) { model.openCoreLog() }
                    Spacer()
                }
                .shellButtonStyle()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear { loadValues() }
        .task { await coreManager.refreshAvailableVersions() }
        .confirmationDialog(
            L10n.tr("卸载 OpenCodex 内核？"),
            isPresented: $confirmUninstall,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("卸载内核"), role: .destructive) {
                Task { await model.uninstallCore() }
            }
            Button(L10n.tr("取消"), role: .cancel) {}
        } message: {
            Text(L10n.tr("仅删除内核文件，保留账号、渠道与配置。"))
        }
    }
}
