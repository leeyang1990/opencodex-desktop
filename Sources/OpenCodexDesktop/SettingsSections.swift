import AppKit
import SwiftUI

extension SettingsView {
    var clientSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("客户端", symbol: "macwindow")

            settingRow(
                title: "退出时还原 Codex 路由",
                detail: "还原原生路由并重启 ChatGPT；内核继续运行。"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.restoresRoutingOnQuit },
                        set: { model.restoresRoutingOnQuit = $0 }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Divider()

            settingRow(
                title: "重启 ChatGPT",
                detail: "使路由与模型配置生效"
            ) {
                Button("立即重启") { Task { await model.restartChatGPT(reason: "设置") } }
                    .disabled(model.isRestartingChatGPT)
            }

            Divider()

            settingRow(
                title: "在 Dock 中显示",
                detail: "关闭后可从菜单栏打开"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { applicationAppearance.showsDockIcon },
                        set: { isVisible in
                            do {
                                try applicationAppearance.setDockIconVisible(isVisible)
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    )
                )
                .labelsHidden()
                .accessibilityLabel("在 Dock 中显示")
                .toggleStyle(.switch)
            }
            .help("关闭后也会从 ⌘-Tab 移除。Dock 中固定或最近使用的快捷方式需手动移除。")

            Divider()

            settingRow(
                title: "系统通知",
                detail: "仅提醒异常与更新"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { notificationManager.isEnabled },
                        set: { enabled in Task { await notificationManager.setEnabled(enabled) } }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if notificationManager.authorizationDenied {
                Label("请在系统设置 › 通知中允许 OpenCodex。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppPalette.warning)
            }

            Divider()

            settingRow(
                title: "登录 Mac 时启动 App"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { value in
                            do { try loginItem.setEnabled(value) } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    )
                )
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
        }
        .cardStyle()
    }

    var coreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("内核", symbol: "shippingbox")

            coreVersionSelection

            Divider()
            coreInstallationStatus

            Divider()

            settingRow(
                title: "随 App 启动内核"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.startsCoreWithApp },
                        set: { model.startsCoreWithApp = $0 }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Label("退出 App 不停止内核，可在首页停止。", systemImage: "bolt.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    var connectionSection: some View {
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
                .shellButtonStyle(prominent: true)
            }
        }
        .cardStyle()
    }

    var coreVersionSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingRow(
                title: "版本来源",
                detail: coreManager.versionMode == .build
                    ? "已随客户端验证"
                    : nil
            ) {
                Picker("", selection: coreVersionModeBinding) {
                    ForEach(CoreVersionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(coreVersionSelectionDisabled)
            }

            if coreManager.versionMode == .custom {
                settingRow(
                    title: "选择版本",
                    detail: "实验性支持，未完整验证；可切回构建版本。"
                ) {
                    Picker("", selection: customCoreVersionBinding) {
                        ForEach(coreVersionOptions, id: \.version) { option in
                            Text(option.label).tag(option.version).disabled(option.unavailable)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    .disabled(coreVersionSelectionDisabled)
                }
                HStack(spacing: 10) {
                    if coreManager.isRefreshingVersions || coreManager.isPreparingVersion {
                        ProgressView().controlSize(.small)
                    }
                    if coreManager.isPreparingVersion {
                        Text("正在校验版本…")
                    } else if let catalog = coreManager.onlineCatalog {
                        Text(
                            "最新 \(catalog.latest ?? "未知") · \(catalog.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
                        )
                    } else {
                        Text("在线列表未获取，显示内置版本")
                    }
                    Spacer()
                    Button("刷新版本") { Task { await coreManager.refreshAvailableVersions() } }
                        .disabled(coreManager.isRefreshingVersions || coreManager.isPreparingVersion)
                        .help("联网刷新列表，不会切换内核。仅支持 Core 2.x 与已适配的 Bun；选择后校验并锁定版本。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let error = coreManager.versionCatalogError {
                    Text(error).font(.caption).foregroundStyle(AppPalette.warning)
                }
            }

            if model.isOnline || coreManager.ownsRunningProcess || coreManager.installationState.isBusy {
                Label("请先停止代理再切换版本。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var coreVersionModeBinding: Binding<CoreVersionMode> {
        Binding(
            get: { coreManager.versionMode },
            set: { coreManager.setVersionMode($0) }
        )
    }

    var customCoreVersionBinding: Binding<String> {
        Binding(
            get: { coreManager.customVersion ?? coreManager.userSelectableReleases.first?.version ?? "" },
            set: { version in
                Task {
                    do {
                        let release = try await coreManager.prepareVersion(version)
                        guard !model.isOnline, !coreManager.ownsRunningProcess, !coreManager.installationState.isBusy
                        else {
                            throw CoreManagerError.launchFailed("请先停止当前代理再切换版本。")
                        }
                        try coreManager.selectTrustedRelease(release)
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    var coreVersionSelectionDisabled: Bool {
        model.isOnline || coreManager.ownsRunningProcess || coreManager.installationState.isBusy
            || coreManager.isPreparingVersion
    }

    var coreVersionOptions: [CoreVersionOption] {
        CoreVersionOption.choices(
            catalog: coreManager.onlineCatalog,
            pinned: coreManager.userSelectableReleases, selected: customCoreVersionBinding.wrappedValue)
    }

    @ViewBuilder
    var coreInstallationStatus: some View {
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
                detail: "下载后即可启动代理"
            ) {
                Button("下载并安装") { Task { await model.installCore() } }
                    .shellButtonStyle(prominent: true)
            }
        case let .installing(phase):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在安装内核 \(coreManager.targetRelease.version)")
                        .font(.callout.weight(.medium))
                    Text(phase).font(.caption).foregroundStyle(.secondary)
                }
            }
        case let .installed(manifest):
            DisclosureGroup {
                Text("提交 \(String(manifest.coreCommit.prefix(7))) · Bun \(manifest.bunVersion)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            } label: {
                Label("已安装 \(manifest.coreVersion)", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppPalette.success)
            }
        case let .updateAvailable(installed, target):
            coreStatusRow(
                symbol: "arrow.triangle.2.circlepath.circle.fill",
                color: AppPalette.warning,
                title: "已选择 \(target.version)",
                detail: "已安装 \(installed.coreVersion)，需安装所选版本。"
            ) {
                Button("安装所选版本") { Task { await model.installCore() } }
                    .shellButtonStyle(prominent: true)
            }
        case let .failed(message):
            coreStatusRow(
                symbol: "exclamationmark.triangle.fill",
                color: AppPalette.danger,
                title: "内核安装失败",
                detail: message
            ) {
                Button("重试") { Task { await model.installCore() } }
                    .shellButtonStyle(prominent: true)
            }
        }
    }

    func coreStatusRow<Accessory: View>(
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

    var clientUpdateStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("客户端版本")
                        .font(.callout.weight(.medium))
                    Text(clientVersionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if appUpdateManager.isBusy {
                    ProgressView().controlSize(.small)
                }
                if let release = appUpdateManager.availableRelease {
                    Button("下载 \(release.version)") {
                        Task {
                            await appUpdateManager.downloadAvailableUpdate()
                            if appUpdateManager.downloadedUpdateURL != nil {
                                appUpdateManager.openDownloadedUpdate()
                            }
                        }
                    }
                    .shellButtonStyle(prominent: true)
                    .disabled(appUpdateManager.isBusy)
                } else {
                    Button("检查更新") {
                        Task { await appUpdateManager.checkForUpdatesPresentingResult() }
                    }
                    .disabled(appUpdateManager.isBusy)
                }
            }

            if let downloaded = appUpdateManager.downloadedUpdateURL {
                HStack {
                    Label("已下载 \(downloaded.lastPathComponent)", systemImage: "shippingbox.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("打开") { appUpdateManager.openDownloadedUpdate() }
                }
            }
        }
    }

    private var clientVersionDetail: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        if let release = appUpdateManager.availableRelease {
            return "当前 \(version) · 可更新到 \(release.version)"
        }
        if let checked = appUpdateManager.lastCheckedAt {
            return "当前 \(version) · 上次检查 \(checked.formatted(date: .abbreviated, time: .shortened))"
        }
        return "当前 \(version) · 尚未检查更新"
    }

    func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }

    func settingRow<Accessory: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            accessory()
        }
    }

    func loadValues() {
        host = model.connectionHost
        port = model.connectionPort
    }
}
