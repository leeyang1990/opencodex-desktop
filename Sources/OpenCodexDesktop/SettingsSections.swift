import AppKit
import SwiftUI

extension SettingsView {
    var clientSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(L10n.tr("客户端"), symbol: "macwindow")

            settingRow(
                title: L10n.tr("退出清理"),
                detail: L10n.tr("停止本应用启动的 OpenCodex，恢复 Codex 原来的 base URL，并重启正在运行的 Codex。")
            ) {
                Text(L10n.tr("始终执行"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            settingRow(
                title: L10n.tr("重启 ChatGPT"),
                detail: L10n.tr("使路由与模型配置生效")
            ) {
                Button(L10n.tr("立即重启")) { Task { await model.restartChatGPT(reason: L10n.tr("设置")) } }
                    .disabled(model.isRestartingChatGPT)
            }

            Divider()

            settingRow(
                title: L10n.tr("在 Dock 中显示"),
                detail: L10n.tr("关闭后可从菜单栏打开")
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
                .accessibilityLabel(L10n.tr("在 Dock 中显示"))
                .toggleStyle(.switch)
            }
            .help(L10n.tr("关闭后也会从 ⌘-Tab 移除。Dock 中固定或最近使用的快捷方式需手动移除。"))

            Divider()

            settingRow(
                title: L10n.tr("系统通知"),
                detail: L10n.tr("仅提醒异常与更新")
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
                Label(L10n.tr("请在系统设置 › 通知中允许 OpenCodex。"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppPalette.warning)
            }

            Divider()

            settingRow(
                title: L10n.tr("登录 Mac 时启动 App")
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
                    Label(L10n.tr("需要在系统设置中批准登录项"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppPalette.warning)
                    Spacer()
                    Button(L10n.tr("打开系统设置")) { loginItem.openSystemSettings() }
                }
            }
        }
        .cardStyle()
    }

    var coreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(L10n.tr("内核"), symbol: "shippingbox")

            coreVersionSelection

            Divider()
            coreInstallationStatus

            Divider()

            settingRow(
                title: L10n.tr("随 App 启动内核")
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

            Label(L10n.tr("退出 App 时会停止本应用启动的内核。"), systemImage: "bolt.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    var connectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(L10n.tr("连接"), symbol: "network")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(L10n.tr("主机")).foregroundStyle(.secondary)
                    TextField("127.0.0.1", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(L10n.tr("端口")).foregroundStyle(.secondary)
                    TextField("10100", value: $port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150, alignment: .leading)
                }
            }
            Text(L10n.tr("为保护管理令牌，客户端只接受 127.0.0.1、localhost 或 ::1。"))
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
                Button(L10n.tr("应用并重连")) {
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
                title: L10n.tr("版本来源"),
                detail: coreManager.versionMode == .build
                    ? L10n.tr("已随客户端验证")
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
                    title: L10n.tr("选择版本"),
                    detail: L10n.tr("自行选择上游版本，所需运行时会自动下载。")
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
                        Text(L10n.tr("正在校验版本…"))
                    } else if let catalog = coreManager.onlineCatalog {
                        Text(
                            L10n.tr(
                                "最新 \(catalog.latest ?? L10n.tr("未知")) · \(catalog.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                        )
                    } else {
                        Text(L10n.tr("在线列表未获取，显示内置版本"))
                    }
                    Spacer()
                    Button(L10n.tr("刷新版本")) { Task { await coreManager.refreshAvailableVersions() } }
                        .disabled(coreManager.isRefreshingVersions || coreManager.isPreparingVersion)
                        .help(L10n.tr("联网刷新上游版本；选择后自动获取对应运行时并校验下载文件。"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let error = coreManager.versionCatalogError {
                    Text(error).font(.caption).foregroundStyle(AppPalette.warning)
                }
            }

            if model.isOnline || coreManager.ownsRunningProcess || coreManager.installationState.isBusy {
                Label(L10n.tr("请先停止代理再切换版本。"), systemImage: "info.circle")
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
                            throw CoreManagerError.launchFailed(L10n.tr("请先停止当前代理再切换版本。"))
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
                Text(L10n.tr("正在检查本地内核…")).foregroundStyle(.secondary)
            }
        case .notInstalled:
            coreStatusRow(
                symbol: "arrow.down.circle.fill",
                color: AppPalette.accent,
                title: L10n.tr("内核尚未安装"),
                detail: L10n.tr("下载后即可启动代理")
            ) {
                Button(L10n.tr("下载并安装")) { Task { await model.installCore() } }
                    .shellButtonStyle(prominent: true)
            }
        case let .installing(phase):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("正在安装内核 \(coreManager.targetRelease.version)"))
                        .font(.callout.weight(.medium))
                    Text(phase).font(.caption).foregroundStyle(.secondary)
                }
            }
        case let .installed(manifest):
            DisclosureGroup {
                Text(L10n.tr("提交 \(String(manifest.coreCommit.prefix(7))) · Bun \(manifest.bunVersion)"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            } label: {
                Label(L10n.tr("已安装 \(manifest.coreVersion)"), systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppPalette.success)
            }
        case let .updateAvailable(installed, target):
            coreStatusRow(
                symbol: "arrow.triangle.2.circlepath.circle.fill",
                color: AppPalette.warning,
                title: L10n.tr("已选择 \(target.version)"),
                detail: L10n.tr("已安装 \(installed.coreVersion)，需安装所选版本。")
            ) {
                Button(L10n.tr("安装所选版本")) { Task { await model.installCore() } }
                    .shellButtonStyle(prominent: true)
            }
        case let .failed(message):
            coreStatusRow(
                symbol: "exclamationmark.triangle.fill",
                color: AppPalette.danger,
                title: L10n.tr("内核安装失败"),
                detail: message
            ) {
                Button(L10n.tr("重试")) { Task { await model.installCore() } }
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
                    Text(L10n.tr("客户端版本"))
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
                    Button(L10n.tr("下载 \(release.version)")) {
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
                    Button(L10n.tr("检查更新")) {
                        Task { await appUpdateManager.checkForUpdatesPresentingResult() }
                    }
                    .disabled(appUpdateManager.isBusy)
                }
            }

            if let downloaded = appUpdateManager.downloadedUpdateURL {
                HStack {
                    Label(L10n.tr("已下载 \(downloaded.lastPathComponent)"), systemImage: "shippingbox.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L10n.tr("打开")) { appUpdateManager.openDownloadedUpdate() }
                }
            }
        }
    }

    private var clientVersionDetail: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        if let release = appUpdateManager.availableRelease {
            return L10n.tr("当前 \(version) · 可更新到 \(release.version)")
        }
        if let checked = appUpdateManager.lastCheckedAt {
            return L10n.tr("当前 \(version) · 上次检查 \(checked.formatted(date: .abbreviated, time: .shortened))")
        }
        return L10n.tr("当前 \(version) · 尚未检查更新")
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
