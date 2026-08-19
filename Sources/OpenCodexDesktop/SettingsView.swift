import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var loginItem = LoginItemManager()
    @ObservedObject private var coreManager = CoreManager.shared

    @State private var host = "127.0.0.1"
    @State private var port = 10100
    @State private var codexAutoStart = true
    @State private var streamMode = "auto"
    @State private var memoryBudget = 256
    @State private var accountPicker = false
    @State private var loaded = false
    @State private var isSaving = false
    @State private var confirmUninstall = false

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

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("连接", symbol: "network")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("主机").foregroundStyle(.secondary)
                    TextField("127.0.0.1", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("端口").foregroundStyle(.secondary)
                    TextField("10100", value: $port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150, alignment: .leading)
                }
            }
            Text("为保护管理令牌，客户端只接受 127.0.0.1、localhost 或 ::1。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                StatusDot(state: model.connectionState)
                Text(model.connectionState.label)
                    .font(.callout.weight(.medium))
                Text("http://\(host):\(port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("应用并重连") {
                    model.connectionHost = host
                    model.connectionPort = port
                    Task { await model.saveConnection() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .cardStyle()
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader("运行设置", symbol: "slider.horizontal.3")
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
            }

            settingRow(
                title: "账号选择器",
                detail: "在 Codex 模型列表中显示账号池选择项"
            ) {
                Toggle("", isOn: $accountPicker)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            settingRow(
                title: "流式模式",
                detail: "控制响应流的兼容与性能策略"
            ) {
                Picker("", selection: $streamMode) {
                    Text("自动").tag("auto")
                    Text("兼容").tag("legacy-tee")
                    Text("高性能").tag("eager-relay")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("内存预算").font(.callout.weight(.medium))
                        Text("OpenCodex 自有缓存与流状态的内存上限")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(memoryBudget) MB")
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(AppPalette.accent)
                }
                Slider(value: Binding(
                    get: { Double(memoryBudget) },
                    set: { memoryBudget = Int($0.rounded()) }
                ), in: 64...4096, step: 64)
            }

            HStack {
                Spacer()
                Button("还原") { loadValues() }
                    .disabled(isSaving)
                Button("保存运行设置") { saveRuntimeSettings() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
        }
        .cardStyle()
    }

    private var coreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader("OpenCodex 内核", symbol: "shippingbox")
                Spacer()
                Text("兼容版本 \(coreManager.compatibleRelease.version)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            coreInstallationStatus

            Divider()
            settingRow(
                title: "登录时启动",
                detail: "登录 Mac 后启动客户端与已安装的本地内核"
            ) {
                Toggle("", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { value in
                        do { try loginItem.setEnabled(value) }
                        catch { model.errorMessage = error.localizedDescription }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if loginItem.requiresApproval {
                HStack {
                    Label("需要在系统设置中批准登录项", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppPalette.warning)
                    Spacer()
                    Button("打开系统设置") { loginItem.openSystemSettings() }
                }
            }
            HStack {
                Button("查看内核日志") { model.openCoreLog() }
                    .disabled(!coreManager.installationState.isInstalled)
                Button("打开安装目录") { model.openCoreInstallationFolder() }
                    .disabled(!coreManager.installationState.isInstalled)
                Spacer()
                if coreManager.installationState.isInstalled {
                    Button("卸载", role: .destructive) { confirmUninstall = true }
                    Button("重新安装") { Task { await model.installCore() } }
                    if model.isOnline {
                        Button("Web 控制台") { model.openDashboard() }
                        Button("停止服务", role: .destructive) {
                            Task { await model.stopService() }
                        }
                    } else {
                        Button("启动服务") { Task { await model.startService() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var coreInstallationStatus: some View {
        switch coreManager.installationState {
        case .checking:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在检查本地内核…").foregroundStyle(.secondary)
            }
        case .notInstalled:
            coreStatusRow(
                symbol: "arrow.down.circle.fill",
                color: AppPalette.accent,
                title: "内核尚未安装",
                detail: "客户端保持轻量；首次使用时单独下载经过校验的 OpenCodex Core、锁定依赖和 Bun 运行时。"
            ) {
                Button("下载并安装") { Task { await model.installCore() } }
                    .buttonStyle(.borderedProminent)
            }
        case let .installing(phase):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在安装 Core \(coreManager.compatibleRelease.version)")
                        .font(.callout.weight(.medium))
                    Text(phase).font(.caption).foregroundStyle(.secondary)
                }
            }
        case let .installed(manifest):
            coreStatusRow(
                symbol: "checkmark.seal.fill",
                color: AppPalette.success,
                title: "OpenCodex Core \(manifest.coreVersion)",
                detail: "提交 \(String(manifest.coreCommit.prefix(7))) · Bun \(manifest.bunVersion) · 与应用分离安装"
            ) { EmptyView() }
        case let .updateAvailable(installed, target):
            coreStatusRow(
                symbol: "arrow.triangle.2.circlepath.circle.fill",
                color: AppPalette.warning,
                title: "可安装兼容内核 \(target.version)",
                detail: "当前已安装 \(installed.coreVersion)，客户端不会自动运行未经绑定的版本。"
            ) {
                Button("安装兼容版本") { Task { await model.installCore() } }
                    .buttonStyle(.borderedProminent)
            }
        case let .failed(message):
            coreStatusRow(
                symbol: "exclamationmark.triangle.fill",
                color: AppPalette.danger,
                title: "内核安装失败",
                detail: message
            ) {
                Button("重试") { Task { await model.installCore() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func coreStatusRow<Accessory: View>(
        symbol: String,
        color: Color,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("安全", symbol: "lock.shield")
            HStack(spacing: 12) {
                Image(systemName: model.tokenAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(model.tokenAvailable ? AppPalette.success : AppPalette.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.tokenAvailable ? "管理令牌可用" : "未找到管理令牌")
                        .font(.callout.weight(.medium))
                    Text(model.tokenPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("在 Finder 中显示") { model.openConfigFolder() }
            }
            Text("客户端只在发送本机管理请求时读取令牌，不会显示、记录或另存其内容。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func settingRow<Accessory: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }

    private func loadValues() {
        host = model.connectionHost
        port = model.connectionPort
        if let settings = model.settings {
            codexAutoStart = settings.codexAutoStart
            streamMode = settings.streamMode
            memoryBudget = settings.appOwnedMemoryBudgetMb
            accountPicker = settings.codexAccountPickerEnabled
        }
        loaded = true
    }

    private func saveRuntimeSettings() {
        guard loaded else { return }
        isSaving = true
        Task {
            _ = await model.saveSettings(
                codexAutoStart: codexAutoStart,
                streamMode: streamMode,
                memoryBudget: memoryBudget,
                accountPicker: accountPicker
            )
            isSaving = false
        }
    }
}
