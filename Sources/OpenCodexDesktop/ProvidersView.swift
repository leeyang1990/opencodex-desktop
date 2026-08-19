import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var showingCreate = false
    @State private var editingProvider: Provider?
    @State private var deletingProvider: Provider?

    private let columns = [
        GridItem(.adaptive(minimum: 285, maximum: 380), spacing: 14),
    ]

    private var filteredProviders: [Provider] {
        guard !searchText.isEmpty else { return model.providers }
        return model.providers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.adapter.localizedCaseInsensitiveContains(searchText)
                || $0.baseUrl.localizedCaseInsensitiveContains(searchText)
                || $0.displayModel.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if !model.isOnline {
                EmptyState(
                    symbol: "network.slash",
                    title: "无法加载 Providers",
                    detail: "请先在概览页启动 OpenCodex 服务。",
                    actionTitle: "重新连接"
                ) {
                    Task { await model.refresh() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PageHeader(
                            title: "Providers",
                            subtitle: "添加、配置并测试模型服务"
                        )

                        if filteredProviders.isEmpty {
                            EmptyState(
                                symbol: "point.3.connected.trianglepath.dotted",
                                title: searchText.isEmpty ? "还没有 Provider" : "没有匹配项",
                                detail: searchText.isEmpty ? "添加第一个模型服务以开始路由。" : "尝试更换搜索关键词。",
                                actionTitle: searchText.isEmpty ? "添加 Provider" : nil,
                                action: searchText.isEmpty ? { showingCreate = true } : nil
                            )
                            .frame(minHeight: 360)
                            .cardStyle()
                        } else {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                                ForEach(filteredProviders) { provider in
                                    ProviderCard(
                                        provider: provider,
                                        isDefault: provider.name == model.config?.defaultProvider,
                                        isBusy: model.busyProvider == provider.name,
                                        onEdit: { editingProvider = provider },
                                        onTest: { Task { await model.test(provider) } },
                                        onSetDefault: { Task { await model.setDefault(provider) } },
                                        onToggle: { enabled in Task { await model.setEnabled(provider, enabled: enabled) } },
                                        onDelete: { deletingProvider = provider }
                                    )
                                }
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 1200, alignment: .leading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .searchable(text: $searchText, placement: .toolbar, prompt: "搜索 Provider")
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
                Button {
                    showingCreate = true
                } label: {
                    Label("添加 Provider", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isOnline)
            }
        }
        .sheet(isPresented: $showingCreate) {
            ProviderEditor(mode: .create)
                .environmentObject(model)
        }
        .sheet(item: $editingProvider) { provider in
            ProviderEditor(mode: .edit(provider))
                .environmentObject(model)
        }
        .confirmationDialog(
            "删除 \(deletingProvider?.name ?? "")？",
            isPresented: Binding(
                get: { deletingProvider != nil },
                set: { if !$0 { deletingProvider = nil } }
            )
        ) {
            Button("删除 Provider", role: .destructive) {
                guard let provider = deletingProvider else { return }
                deletingProvider = nil
                Task { await model.delete(provider) }
            }
            Button("取消", role: .cancel) { deletingProvider = nil }
        } message: {
            Text("此操作会从 OpenCodex 配置中移除该 Provider，但不会撤销上游 API Key。")
        }
    }
}

private struct ProviderCard: View {
    let provider: Provider
    let isDefault: Bool
    let isBusy: Bool
    let onEdit: () -> Void
    let onTest: () -> Void
    let onSetDefault: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                providerIcon
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(provider.name)
                            .font(.headline)
                            .lineLimit(1)
                        if isDefault { Pill(text: "默认", color: AppPalette.success) }
                    }
                    Text(provider.adapter)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Menu {
                        Button("编辑", systemImage: "pencil", action: onEdit)
                        Button("测试连接", systemImage: "wave.3.right", action: onTest)
                        if !isDefault && !provider.disabled {
                            Button("设为默认", systemImage: "checkmark.circle", action: onSetDefault)
                        }
                        Divider()
                        Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 24, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                LabeledContent("默认模型") {
                    Text(provider.displayModel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("认证") {
                    HStack(spacing: 5) {
                        if provider.hasApiKey {
                            Image(systemName: "key.fill").foregroundStyle(AppPalette.success)
                        }
                        Text(provider.displayAuth)
                    }
                }
                LabeledContent("端点") {
                    Text(provider.baseUrl)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(provider.baseUrl)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(provider.disabled ? Color.secondary.opacity(0.5) : AppPalette.success)
                        .frame(width: 7, height: 7)
                    Text(provider.disabled ? "已停用" : "已启用")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(provider.disabled ? .secondary : AppPalette.success)
                }
                Spacer()
                Toggle("启用", isOn: Binding(
                    get: { !provider.disabled },
                    set: onToggle
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(isBusy || isDefault)
                .help(isDefault ? "默认 Provider 无法停用" : "启用或停用")
            }
        }
        .cardStyle()
        .opacity(provider.disabled ? 0.68 : 1)
    }

    private var providerIcon: some View {
        let colors: [Color] = provider.authMode == "local"
            ? [Color(red: 0.18, green: 0.67, blue: 0.53), Color(red: 0.13, green: 0.51, blue: 0.66)]
            : [AppPalette.accent, Color(red: 0.58, green: 0.34, blue: 0.91)]
        return Text(String(provider.name.prefix(1)).uppercased())
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct ProviderEditor: View {
    enum Mode {
        case create
        case edit(Provider)

        var title: String {
            switch self {
            case .create: "添加 Provider"
            case .edit: "编辑 Provider"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var draft: ProviderDraft
    @State private var selectedPresetID = "custom"
    @State private var isSaving = false
    @State private var showAdvanced = false
    @State private var saveError: String?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _draft = State(initialValue: ProviderDraft())
        case let .edit(provider):
            _draft = State(initialValue: ProviderDraft(provider: provider))
        }
    }

    private var editingProvider: Provider? {
        if case let .edit(provider) = mode { return provider }
        return nil
    }

    private var isEditing: Bool { editingProvider != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title).font(.title2.weight(.semibold))
                    Text(isEditing ? "修改连接与模型配置" : "连接一个模型服务")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.validationMessage != nil || isSaving)
            }
            .padding(22)

            Divider()

            Form {
                if !isEditing {
                    Section("服务类型") {
                        Picker("预设", selection: $selectedPresetID) {
                            Text("自定义").tag("custom")
                            ForEach(model.presets.filter { $0.id != "custom" }) { preset in
                                Text(preset.label).tag(preset.id)
                            }
                        }
                        .onChange(of: selectedPresetID) { _, id in
                            guard let preset = model.presets.first(where: { $0.id == id }) else { return }
                            draft.apply(preset)
                        }
                    }
                }

                Section("基本信息") {
                    TextField("名称", text: $draft.name, prompt: Text("例如 openrouter"))
                        .disabled(isEditing)
                    TextField("API 地址", text: $draft.baseUrl, prompt: Text("https://api.example.com/v1"))
                        .textContentType(.URL)
                    TextField("默认模型", text: $draft.defaultModel, prompt: Text("留空则自动选择"))
                }

                Section("认证") {
                    Picker("方式", selection: $draft.authMode) {
                        Text("API Key").tag("key")
                        Text("OAuth").tag("oauth")
                        Text("Codex 登录转发").tag("forward")
                        Text("本地服务").tag("local")
                    }
                    if draft.authMode == "key" {
                        SecureField(isEditing ? "新增 API Key（留空不变）" : "API Key", text: $draft.apiKey)
                        Text("密钥会直接写入 OpenCodex 的安全存储，客户端不会保存副本。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup("高级选项", isExpanded: $showAdvanced) {
                    Picker("适配器", selection: $draft.adapter) {
                        Text("OpenAI Chat").tag("openai-chat")
                        Text("OpenAI Responses").tag("openai-responses")
                        Text("Anthropic").tag("anthropic")
                        Text("Google").tag("google")
                        Text("Azure OpenAI").tag("azure-openai")
                    }
                    if draft.adapter == "anthropic" && draft.authMode == "key" {
                        Picker("Key 传输方式", selection: $draft.apiKeyTransport) {
                            Text("Bearer").tag("bearer")
                            Text("x-api-key").tag("x-api-key")
                        }
                    }
                    Toggle("实时发现模型", isOn: $draft.liveModels)
                    Toggle("允许私有网络地址", isOn: $draft.allowPrivateNetwork)
                    if !isEditing {
                        Toggle("设为默认 Provider", isOn: $draft.setDefault)
                    }
                }

                if let validation = draft.validationMessage {
                    Section {
                        Label(validation, systemImage: "exclamationmark.circle")
                            .foregroundStyle(AppPalette.warning)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 570, height: 610)
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView("正在保存…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .ignoresSafeArea()
            }
        }
        .alert("保存 Provider 失败", isPresented: saveErrorPresented) {
            Button("好") { saveError = nil }
        } message: {
            Text(saveError ?? "未知错误")
        }
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private func save() {
        guard draft.validationMessage == nil else { return }
        isSaving = true
        Task {
            let success: Bool
            if let provider = editingProvider {
                success = await model.updateProvider(provider, draft: draft)
            } else {
                success = await model.createProvider(draft)
            }
            isSaving = false
            if success {
                dismiss()
            } else {
                saveError = model.errorMessage ?? "保存 Provider 失败"
                model.errorMessage = nil
            }
        }
    }
}
