import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject var loginItem = LoginItemManager()
    @ObservedObject var coreManager = CoreManager.shared

    @State var host = AppConstants.Connection.defaultHost
    @State var port = AppConstants.Connection.defaultPort
    @State var codexAutoStart = true
    @State var streamMode = "auto"
    @State var memoryBudget = 256
    @State var accountPicker = false
    @State var customImageProvider = false
    @State var imageProvider = ""
    @State var imageTimeoutSeconds = 300
    @State var forceGPTVision = false
    @State var loaded = false
    @State var isSaving = false
    @State var confirmUninstall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "设置",
                    subtitle: "配置客户端连接与 OpenCodex 运行方式"
                )

                connectionSection
                coreSection

                if model.isOnline {
                    runtimeSection
                    visionRoutingSection
                    imageGenerationSection
                    securitySection
                } else {
                    Label("连接服务后可编辑运行设置", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .cardStyle()
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadValues)
        .onChange(of: model.settings?.port) { _, _ in loadValues() }
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
