import SwiftUI

struct ModelProviderCard: View {
    let group: ModelProviderGroup
    let configuredProvider: Provider?
    let visible: (ManagedModel) -> Bool
    let isCollapsed: Bool
    let busyModel: String?
    let providerBusy: Bool
    let contextCap: Int?
    let liveCount: Int?
    let onToggleCollapse: () -> Void
    let onToggleModel: (ManagedModel, Bool) -> Void
    let onToggleAll: (Bool) -> Void
    let onAddCustom: () -> Void
    let onEditCustom: (ManagedModel) -> Void
    let onDeleteCustom: (ManagedModel) -> Void
    let onSetDefault: (ManagedModel) -> Void
    let onEditCap: () -> Void

    private var visibleCount: Int { group.allModels.filter(visible).count }
    private var canAddCustom: Bool { configuredProvider != nil && configuredProvider?.authMode != "forward" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onToggleCollapse) {
                    HStack(spacing: 12) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        providerIcon
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(group.provider)
                                    .font(.headline)
                                if group.isNative { Pill(text: "原生", color: AppPalette.accent) }
                                if let liveCount { Pill(text: "实时 \(liveCount)", color: AppPalette.success) }
                            }
                            Text("启用 \(visibleCount) / \(group.allModels.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if providerBusy { ProgressView().controlSize(.small) }

                if let contextCap {
                    Button(action: onEditCap) {
                        Label(formatTokenCount(contextCap), systemImage: "gauge.with.dots.needle.67percent")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Provider 上下文限制")
                } else if !group.isNative && configuredProvider != nil {
                    Button("上下文限制", action: onEditCap)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }

                Menu {
                    if canAddCustom {
                        Button("添加自定义模型", systemImage: "plus", action: onAddCustom)
                        Divider()
                    }
                    Button("全部启用", systemImage: "eye", action: { onToggleAll(true) })
                        .disabled(group.allModels.isEmpty || visibleCount == group.allModels.count)
                    Button("全部隐藏", systemImage: "eye.slash", action: { onToggleAll(false) })
                        .disabled(group.allModels.isEmpty || visibleCount == 0)
                    if !group.isNative && configuredProvider != nil {
                        Divider()
                        Button("上下文限制…", systemImage: "gauge.with.dots.needle.67percent", action: onEditCap)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 25, height: 25)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(providerBusy)
            }
            .padding(16)

            if !isCollapsed {
                Divider().padding(.horizontal, 16)

                if group.models.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                        Text(configuredProvider?.liveModels == false ? "这个 Provider 尚未配置静态模型。" : "暂未发现模型，可检查连接或手动添加。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if canAddCustom { Button("添加模型", action: onAddCustom) }
                    }
                    .padding(18)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(group.models.sorted(by: modelSort)) { item in
                            ModelCatalogRow(
                                item: item,
                                enabled: visible(item),
                                isDefault: configuredProvider?.defaultModel == item.modelID,
                                isBusy: busyModel == item.namespaced,
                                canSetDefault: configuredProvider != nil && configuredProvider?.authMode != "forward",
                                onToggle: { onToggleModel(item, $0) },
                                onSetDefault: { onSetDefault(item) },
                                onEdit: { onEditCustom(item) },
                                onDelete: { onDeleteCustom(item) }
                            )
                            if item.id != group.models.sorted(by: modelSort).last?.id {
                                Divider().padding(.leading, 66)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.07))
        }
    }

    private var providerIcon: some View {
        Text(String(group.provider.prefix(1)).uppercased())
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                LinearGradient(
                    colors: group.isNative
                        ? [AppPalette.accent, Color(red: 0.43, green: 0.67, blue: 0.98)]
                        : [Color(red: 0.55, green: 0.34, blue: 0.91), AppPalette.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }

    private func modelSort(_ lhs: ManagedModel, _ rhs: ManagedModel) -> Bool {
        if visible(lhs) != visible(rhs) { return visible(lhs) }
        if lhs.custom != rhs.custom { return lhs.custom }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

struct ModelCatalogRow: View {
    let item: ManagedModel
    let enabled: Bool
    let isDefault: Bool
    let isBusy: Bool
    let canSetDefault: Bool
    let onToggle: (Bool) -> Void
    let onSetDefault: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(
                systemName: item.native
                    ? "sparkles" : item.custom ? "slider.horizontal.below.square.filled.and.square" : "cube"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(enabled ? AppPalette.accent : Color.secondary)
            .frame(width: 34, height: 34)
            .background(
                (enabled ? AppPalette.accent : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(enabled ? Color.primary : Color.secondary)
                    if isDefault { Pill(text: "默认", color: AppPalette.success) }
                    if item.custom { Pill(text: "自定义") }
                    if item.contextCapped, let cap = item.contextCap {
                        Pill(text: "限制 \(formatTokenCount(cap))", color: AppPalette.warning)
                    }
                }
                HStack(spacing: 9) {
                    Text(item.namespaced)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let context = item.contextWindow {
                        Label(formatTokenCount(context), systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    if item.supportsVision { Label("图像", systemImage: "photo") }
                    if item.supportsAudio { Label("音频", systemImage: "waveform") }
                    if !item.reasoningEfforts.isEmpty { Label("推理", systemImage: "brain") }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 8)

            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    if canSetDefault && !isDefault {
                        Button("设为 Provider 默认模型", systemImage: "checkmark.circle", action: onSetDefault)
                    }
                    if item.custom {
                        Button("编辑自定义模型", systemImage: "pencil", action: onEdit)
                        Divider()
                        Button("删除自定义模型", systemImage: "trash", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 23, height: 23)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity((canSetDefault && !isDefault) || item.custom ? 1 : 0)
                .disabled((!canSetDefault || isDefault) && !item.custom)
            }

            Toggle("启用", isOn: Binding(get: { enabled }, set: onToggle))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(isBusy)
                .help(enabled ? "对 Codex 隐藏" : "对 Codex 可见")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .opacity(enabled ? 1 : 0.72)
    }
}

struct CustomModelEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let context: CustomModelEditorContext
    @State private var draft: CustomModelDraft
    @State private var isSaving = false

    init(context: CustomModelEditorContext) {
        self.context = context
        var initial = context.item.map { CustomModelDraft(model: $0) } ?? CustomModelDraft()
        if initial.provider.isEmpty { initial.provider = context.preferredProvider ?? "" }
        _draft = State(initialValue: initial)
    }

    private var isEditing: Bool { context.item != nil }
    private var providers: [Provider] {
        model.providers.filter { !$0.disabled && $0.authMode != "forward" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isEditing ? "编辑自定义模型" : "添加自定义模型")
                        .font(.title2.weight(.semibold))
                    Text("补充上游未发现的模型及能力信息")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                Section("模型") {
                    Picker("Provider", selection: $draft.provider) {
                        ForEach(providers) { provider in
                            Text(provider.name).tag(provider.name)
                        }
                    }
                    .disabled(isEditing)
                    TextField("模型 ID", text: $draft.modelID, prompt: Text("例如 claude-sonnet-4-5"))
                    TextField("显示名称", text: $draft.displayName, prompt: Text("可选"))
                    TextField("上下文窗口", text: $draft.contextWindow, prompt: Text("例如 200000"))
                }

                Section("输入能力") {
                    Toggle("文本", isOn: $draft.supportsText)
                    Toggle("图像", isOn: $draft.supportsImage)
                    Toggle("音频", isOn: $draft.supportsAudio)
                }

                Section {
                    Label("模型 ID 使用上游原始 ID，不需要添加 Provider 前缀。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let validation = draft.validationMessage {
                        Label(validation, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(AppPalette.warning)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 560, height: 540)
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
    }

    private func save() {
        guard draft.validationMessage == nil else { return }
        isSaving = true
        Task {
            let success = await model.saveCustomModel(draft, editing: context.item)
            isSaving = false
            if success { dismiss() }
        }
    }
}

struct ProviderContextCapEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let provider: String
    @State private var enabled: Bool
    @State private var value: String
    @State private var isSaving = false

    init(provider: String) {
        self.provider = provider
        _enabled = State(initialValue: false)
        _value = State(initialValue: "")
    }

    private var parsedValue: Int? {
        Int(value.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("上下文限制").font(.title2.weight(.semibold))
                    Text(provider).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("应用") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || (enabled && parsedValue.map { $0 > 0 } != true))
            }
            .padding(22)
            Divider()
            Form {
                Section {
                    Toggle("限制发送给此 Provider 的上下文", isOn: $enabled)
                    TextField("Token 上限", text: $value, prompt: Text("\(model.globalModelContextCap)"))
                        .disabled(!enabled)
                }
                Section {
                    Text("限制会在请求路由前裁剪上下文，用于避免超过上游模型窗口。它不会改变模型本身声明的上下文大小。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 330)
        .onAppear {
            let existing = model.modelContextCaps[provider]
            enabled = existing != nil
            value = String(existing ?? model.globalModelContextCap)
        }
    }

    private func save() {
        isSaving = true
        Task {
            let success = await model.setProviderContextCap(
                provider: provider,
                enabled: enabled,
                value: enabled ? parsedValue : nil
            )
            isSaving = false
            if success { dismiss() }
        }
    }
}

struct GlobalContextCapEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var applyToAll = false
    @State private var isSaving = false

    private var parsedValue: Int? {
        Int(value.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("默认上下文限制").font(.title2.weight(.semibold))
                    Text("为新的 Provider 限制提供默认值")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || parsedValue.map { $0 > 0 } != true)
            }
            .padding(22)
            Divider()
            Form {
                Section {
                    TextField("默认 Token 上限", text: $value)
                    Toggle("同时应用到当前已限制的 Provider", isOn: $applyToAll)
                }
                Section {
                    Text("建议按上游模型的实际能力设置。过小会损失上下文，过大会导致上游拒绝请求。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 540, height: 330)
        .onAppear { value = String(model.globalModelContextCap) }
    }

    private func save() {
        guard let parsedValue else { return }
        isSaving = true
        Task {
            let success = await model.setGlobalModelContextCap(parsedValue, applyToAll: applyToAll)
            isSaving = false
            if success { dismiss() }
        }
    }
}

func formatTokenCount(_ value: Int) -> String {
    if value >= 1_000_000 {
        let number = Double(value) / 1_000_000
        return number.rounded() == number ? "\(Int(number))M" : String(format: "%.1fM", number)
    }
    if value >= 1_000 { return "\(value / 1_000)k" }
    return "\(value)"
}
