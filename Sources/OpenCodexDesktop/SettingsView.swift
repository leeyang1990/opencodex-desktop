import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
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
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "设置",
                    subtitle: "配置 Desktop 连接与 macOS 原生能力"
                )

                connectionSection
                applicationSection
                coreSection
                securitySection
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadValues()
            model.runEnvironmentCheck()
        }
        .confirmationDialog(
            "卸载 OpenCodex 内核？",
            isPresented: $confirmUninstall,
            titleVisibility: .visible
        ) {
            Button("卸载内核", role: .destructive) {
                Task { await model.uninstallCore() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除已安装的内核运行文件，Provider、账号与配置数据会保留。")
        }
    }
}
