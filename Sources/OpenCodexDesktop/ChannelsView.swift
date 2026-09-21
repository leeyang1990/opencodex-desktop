import SwiftUI

/// The common channel path: add an endpoint, provide a key, enable it, test it, and make it the
/// default. Detailed provider and model behavior remains in the Core console.
///
/// API keys typed here are held in memory only for the current session, sent once to the Core,
/// and then dropped. Reads always come back as "has a key", never as the key.
struct ChannelsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsAddSheet = false
    @State private var keyEditingChannel: String?
    @State private var keyDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "渠道")
                    .padding(.bottom, 2)

                if !model.isOnline {
                    offlineCard
                } else {
                    toolbar
                    if let message = model.channelErrorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppPalette.warning)
                    }
                    ForEach(model.channels) { channel in
                        channelCard(channel)
                    }
                    if model.channels.isEmpty && !model.isLoadingChannels {
                        Text("暂无渠道")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task { await model.loadChannels() }
        .sheet(isPresented: $showsAddSheet) {
            ChannelEditorSheet { draft, key in
                await model.addChannel(draft: draft, apiKey: key)
            }
            .environmentObject(model)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if model.isLoadingChannels || model.isUpdatingChannels || model.isTestingChannel {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("刷新") { Task { await model.loadChannels() } }
                .disabled(model.isLoadingChannels)
            Button("添加渠道") { showsAddSheet = true }
                .shellButtonStyle(prominent: true)
                .disabled(model.isUpdatingChannels)
        }
    }

    private func channelCard(_ channel: APIChannel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(.system(size: 14, weight: .semibold))
                        if model.isDefaultChannel(channel) {
                            Pill(text: "默认", color: AppPalette.accent, symbol: "star.fill")
                        }
                        if channel.isDisabled {
                            Pill(text: "已停用", color: AppPalette.warning)
                        }
                        credentialBadge(channel)
                    }
                    Text(channel.baseUrl ?? "—")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Toggle(
                    "启用",
                    isOn: Binding(
                        get: { !channel.isDisabled },
                        set: { enabled in Task { await model.setChannelEnabled(channel, enabled: enabled) } }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(model.isUpdatingChannels)
            }

            HStack(spacing: 8) {
                Text("\(channel.adapter ?? "—") · \(channel.modelCount) 个模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let discovery = channel.discovery, discovery.status == "failed" {
                    Pill(
                        text: "探测失败 \(discovery.httpStatus.map(String.init) ?? discovery.reason ?? "")",
                        color: AppPalette.danger,
                        symbol: "exclamationmark.triangle.fill"
                    )
                }
                if let pool = model.channelKeyPools[channel.name], pool.keys.count > 1 {
                    Pill(text: "\(pool.keys.count) 个 Key", color: AppPalette.accent, symbol: "key.fill")
                }
                if let probe = model.channelProbeResults[channel.name] {
                    Pill(
                        text: probe.ok == true ? "连通正常" : (probe.message ?? "测试失败"),
                        color: probe.ok == true ? AppPalette.success : AppPalette.danger,
                        symbol: probe.ok == true ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                }
                Spacer(minLength: 8)
                Button("测试") { Task { await model.testChannel(channel) } }
                    .controlSize(.small)
                    .disabled(model.isTestingChannel)
                if !channel.usesCredentialForwarding {
                    Button("添加 Key") { beginKeyEdit(channel) }
                        .controlSize(.small)
                }
                Menu {
                    Button("设为默认渠道") { Task { await model.setDefaultChannel(channel) } }
                        .disabled(model.isDefaultChannel(channel) || channel.isDisabled)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24)
                .disabled(model.isUpdatingChannels)
            }

            if keyEditingChannel == channel.name {
                keyEntryRow(channel)
            }
        }
        .cardStyle()
    }

    private func credentialBadge(_ channel: APIChannel) -> some View {
        if channel.usesCredentialForwarding {
            return Pill(
                text: channel.codexAccountMode == "pool" ? "Codex 账号池" : "Codex 登录",
                color: AppPalette.success,
                symbol: "person.crop.circle"
            )
        }
        if channel.hasApiKey == true {
            return Pill(text: "已配置 Key", color: AppPalette.success, symbol: "key.fill")
        }
        if channel.authMode == "local" {
            return Pill(text: "无需密钥", color: AppPalette.accent)
        }
        return Pill(text: "未配置 Key", color: AppPalette.warning, symbol: "key.slash")
    }

    private func beginKeyEdit(_ channel: APIChannel) {
        keyEditingChannel = channel.name
        keyDraft = ""
    }

    private func keyEntryRow(_ channel: APIChannel) -> some View {
        HStack(spacing: 8) {
            SecureField("粘贴新的 API Key（加入该渠道的密钥池）", text: $keyDraft)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassControl()
            Button("保存") {
                model.setChannelKey(keyDraft, for: channel.name)
                keyDraft = ""
                keyEditingChannel = nil
                Task { await model.saveChannelKey(channel) }
            }
            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("取消") {
                keyDraft = ""
                keyEditingChannel = nil
            }
        }
    }

    private var offlineCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text("启动代理后管理渠道")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("启动代理") { Task { await model.startService() } }
                .shellButtonStyle(prominent: true)
                .disabled(model.isRefreshing)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .cardStyle()
    }
}

/// Adds one channel. The key field is deliberately not bound to any stored state beyond the
/// sheet's lifetime.
private struct ChannelEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ChannelDraft()
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var hasCreatedChannel = false
    @State private var showsOptions = false

    private let onSave: (ChannelDraft, String) async -> ChannelCreationResult

    init(onSave: @escaping (ChannelDraft, String) async -> ChannelCreationResult) {
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加渠道")
                .font(.title3.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                        GridRow {
                            Text("名称")
                            TextField("例如 new-api", text: $draft.name)
                                .accessibilityLabel("渠道名称")
                        }
                        GridRow {
                            Text("协议")
                            VStack(alignment: .leading, spacing: 5) {
                                Picker("协议", selection: $draft.transport) {
                                    ForEach(ChannelProtocol.allCases) { Text($0.title).tag($0) }
                                }.labelsHidden()
                                Text(draft.transport.hint).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        GridRow {
                            Text("Base URL")
                            TextField(draft.transport.placeholder, text: $draft.baseURL)
                                .accessibilityLabel("Base URL")
                        }
                        GridRow {
                            Text("鉴权")
                            Picker("鉴权", selection: $draft.requiresKey) {
                                Text("API Key").tag(true)
                                if draft.transport == .chat { Text("无需密钥").tag(false) }
                            }.labelsHidden().pickerStyle(.segmented)
                        }
                        if draft.requiresKey {
                            GridRow {
                                Text("API Key")
                                SecureField("由本机 Core 保存", text: $apiKey)
                                    .accessibilityLabel("API Key")
                            }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    if draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http://") {
                        Label("HTTP 不加密，仅建议用于可信的本机或内网服务。", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(AppPalette.warning)
                    }
                    Divider()
                    Picker("模型", selection: $draft.automaticModels) {
                        Text("自动获取").tag(true)
                        Text("手动填写").tag(false)
                    }.pickerStyle(.segmented)
                    if draft.automaticModels {
                        Text("保存后由 Core 获取；不支持模型列表接口时可手动填写。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("模型 ID · 每行一个，或用逗号分隔").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $draft.modelText)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 72)
                                .padding(4)
                                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.2)))
                                .accessibilityLabel("模型 ID")
                        }
                    }
                    HStack {
                        Text("默认模型")
                        TextField("可选，填写准确的模型 ID", text: $draft.defaultModel)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("默认模型")
                    }
                    Toggle("设为默认渠道", isOn: $draft.setDefault).toggleStyle(.checkbox)
                    DisclosureGroup("更多选项", isExpanded: $showsOptions) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("允许内网地址", isOn: $draft.allowPrivateNetwork).toggleStyle(.checkbox)
                            Text("连接 localhost、局域网 IP 或内网域名时开启；Core 仍会检查目标地址。")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("备注（可选）", text: $draft.note).textFieldStyle(.roundedBorder)
                        }.padding(.top, 8)
                    }
                }
                .padding(2)
                .disabled(isSaving || hasCreatedChannel)
            }
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(AppPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("密钥仅发送给本机 Core，Desktop 不存储。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    model.openConsole(page: .providers)
                } label: {
                    Label("高级配置", systemImage: "arrow.up.right.square")
                }
                .accessibilityLabel("高级配置")
                .help("在浏览器中打开 OpenCodex 供应方配置；当前未保存的表单不会自动带入。")
                .disabled(isSaving || !model.isOnline)
                if isSaving { ProgressView().controlSize(.small); Text("正在保存…").font(.caption) }
                Spacer()
                Button(hasCreatedChannel ? "关闭" : "取消") {
                    apiKey = ""; dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
                if !hasCreatedChannel {
                    Button("添加", action: save)
                        .shellButtonStyle(prominent: true)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving)
                }
            }
        }
        .padding(22)
        .frame(width: 560, height: 620)
        .background(.regularMaterial)
        .interactiveDismissDisabled(isSaving)
        .onChange(of: draft.transport) { _, value in
            if value != .chat { draft.requiresKey = true }
            saveError = nil
        }
        .onChange(of: draft.requiresKey) { _, value in
            if !value { apiKey = "" }
        }
        .onDisappear { apiKey = "" }
    }

    private func save() {
        guard !isSaving, !hasCreatedChannel else { return }
        if let error = draft.validationError(key: apiKey, existingNames: model.channels.map(\.name)) {
            saveError = error
            return
        }
        saveError = nil
        isSaving = true
        Task {
            let result = await onSave(draft, apiKey)
            isSaving = false
            switch result {
            case .saved: apiKey = ""; dismiss()
            case .failed(let message): saveError = message
            case .partial(let message):
                apiKey = ""
                hasCreatedChannel = true
                saveError = message
            }
        }
    }
}
