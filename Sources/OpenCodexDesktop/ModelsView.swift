import Foundation
import SwiftUI

private enum ModelCatalogFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case disabled
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .enabled: "已启用"
        case .disabled: "已隐藏"
        case .custom: "自定义"
        }
    }
}

struct ModelProviderGroup: Identifiable {
    let provider: String
    let models: [ManagedModel]
    let allModels: [ManagedModel]
    var id: String { provider }
    var isNative: Bool { !allModels.isEmpty && allModels.allSatisfy(\.native) }
}

struct CustomModelEditorContext: Identifiable {
    let id = UUID()
    let item: ManagedModel?
    let preferredProvider: String?
}

struct ProviderCapEditorContext: Identifiable {
    let provider: String
    var id: String { provider }
}

struct ModelsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var catalogFilter: ModelCatalogFilter = .all
    @State private var providerFilter = "all"
    @State private var collapsedProviders: Set<String> = []
    @State private var editorContext: CustomModelEditorContext?
    @State private var capEditorContext: ProviderCapEditorContext?
    @State private var showingGlobalCap = false
    @State private var deletingModel: ManagedModel?

    private var allGroups: [ModelProviderGroup] {
        var grouped = Dictionary(grouping: model.managedModels, by: \.provider)
        for provider in model.providers where !provider.disabled && provider.authMode != "forward" {
            if grouped[provider.name] == nil { grouped[provider.name] = [] }
        }
        return grouped.map { ModelProviderGroup(provider: $0.key, models: $0.value, allModels: $0.value) }
            .sorted {
                if $0.isNative != $1.isNative { return $0.isNative }
                return $0.provider.localizedCaseInsensitiveCompare($1.provider) == .orderedAscending
            }
    }

    private var filteredGroups: [ModelProviderGroup] {
        allGroups.compactMap { group in
            guard providerFilter == "all" || group.provider == providerFilter else { return nil }
            let providerMatches = group.provider.localizedCaseInsensitiveContains(searchText)
            let rows = group.models.filter { item in
                let matchesSearch =
                    searchText.isEmpty
                    || providerMatches
                    || item.modelID.localizedCaseInsensitiveContains(searchText)
                    || item.namespaced.localizedCaseInsensitiveContains(searchText)
                    || (item.displayName?.localizedCaseInsensitiveContains(searchText) ?? false)
                guard matchesSearch else { return false }
                switch catalogFilter {
                case .all: return true
                case .enabled: return model.isModelVisible(item)
                case .disabled: return !model.isModelVisible(item)
                case .custom: return item.custom
                }
            }
            if rows.isEmpty && (!searchText.isEmpty || catalogFilter != .all) { return nil }
            return ModelProviderGroup(provider: group.provider, models: rows, allModels: group.allModels)
        }
    }

    private var visibleCount: Int { model.managedModels.filter(model.isModelVisible).count }
    private var customCount: Int { model.managedModels.filter(\.custom).count }
    private var routedProviderCount: Int { Set(model.managedModels.filter { !$0.native }.map(\.provider)).count }
    private var modelSourceCount: Int { Set(model.managedModels.map(\.provider)).count }

    var body: some View {
        Group {
            if !model.isOnline {
                EmptyState(
                    symbol: "square.stack.3d.up.slash",
                    title: "无法加载模型",
                    detail: "请先在概览页启动 OpenCodex 服务。",
                    actionTitle: "重新连接"
                ) {
                    Task { await model.refresh() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        PageHeader(
                            title: "模型",
                            subtitle: "决定 Codex 可以看到、选择和路由到哪些模型"
                        )

                        summaryCards
                        catalogControls

                        if model.isRefreshingModels && model.managedModels.isEmpty {
                            loadingState
                        } else if filteredGroups.isEmpty {
                            EmptyState(
                                symbol: "magnifyingglass",
                                title: "没有匹配的模型",
                                detail: "尝试清除搜索或更换筛选条件。"
                            )
                            .frame(minHeight: 300)
                            .cardStyle()
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(filteredGroups) { group in
                                    ModelProviderCard(
                                        group: group,
                                        configuredProvider: model.providers.first { $0.name == group.provider },
                                        visible: model.isModelVisible,
                                        isCollapsed: collapsedProviders.contains(group.provider),
                                        busyModel: model.busyModel,
                                        providerBusy: model.busyModelProvider == group.provider,
                                        contextCap: model.modelContextCaps[group.provider],
                                        liveCount: model.liveModelCounts[group.provider],
                                        onToggleCollapse: { toggleCollapsed(group.provider) },
                                        onToggleModel: { item, enabled in
                                            Task { await model.setModelVisible(item, visible: enabled) }
                                        },
                                        onToggleAll: { enabled in
                                            Task {
                                                await model.setProviderModelsVisible(
                                                    provider: group.provider, items: group.allModels, visible: enabled)
                                            }
                                        },
                                        onAddCustom: {
                                            editorContext = CustomModelEditorContext(
                                                item: nil, preferredProvider: group.provider)
                                        },
                                        onEditCustom: { item in
                                            editorContext = CustomModelEditorContext(
                                                item: item, preferredProvider: item.provider)
                                        },
                                        onDeleteCustom: { deletingModel = $0 },
                                        onSetDefault: { item in
                                            Task {
                                                await model.setProviderDefaultModel(
                                                    provider: group.provider, item: item)
                                            }
                                        },
                                        onEditCap: {
                                            capEditorContext = ProviderCapEditorContext(provider: group.provider)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 1180, alignment: .leading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .searchable(text: $searchText, placement: .toolbar, prompt: "搜索模型")
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refreshModels() }
                } label: {
                    Label("刷新模型目录", systemImage: "arrow.clockwise")
                }
                .disabled(!model.isOnline || model.isRefreshingModels)

                Menu {
                    Button("默认上下文限制…", systemImage: "gauge.with.dots.needle.67percent") {
                        showingGlobalCap = true
                    }
                } label: {
                    Label("模型设置", systemImage: "slider.horizontal.3")
                }
                .disabled(!model.isOnline)

                Button {
                    editorContext = CustomModelEditorContext(item: nil, preferredProvider: preferredCustomProvider)
                } label: {
                    Label("添加模型", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(customModelProviders.isEmpty)
            }
        }
        .task {
            if model.managedModels.isEmpty { await model.refreshModels() }
        }
        .sheet(item: $editorContext) { context in
            CustomModelEditor(context: context)
                .environmentObject(model)
        }
        .sheet(item: $capEditorContext) { context in
            ProviderContextCapEditor(provider: context.provider)
                .environmentObject(model)
        }
        .sheet(isPresented: $showingGlobalCap) {
            GlobalContextCapEditor()
                .environmentObject(model)
        }
        .confirmationDialog(
            "删除 \(deletingModel?.title ?? "")？",
            isPresented: Binding(
                get: { deletingModel != nil },
                set: { if !$0 { deletingModel = nil } }
            )
        ) {
            Button("删除自定义模型", role: .destructive) {
                guard let item = deletingModel else { return }
                deletingModel = nil
                Task { await model.deleteCustomModel(item) }
            }
            Button("取消", role: .cancel) { deletingModel = nil }
        } message: {
            Text("只会删除 OpenCodex 中的自定义定义，不会修改上游服务。")
        }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
            MetricCard(
                title: "模型目录", value: "\(model.managedModels.count)", detail: "已发现模型", symbol: "square.stack.3d.up")
            MetricCard(
                title: "对 Codex 可见", value: "\(visibleCount)",
                detail: "隐藏 \(max(0, model.managedModels.count - visibleCount))", symbol: "eye",
                tint: AppPalette.success)
            MetricCard(
                title: "模型来源", value: "\(modelSourceCount)", detail: "\(routedProviderCount) 个外部路由",
                symbol: "point.3.connected.trianglepath.dotted", tint: Color(red: 0.56, green: 0.35, blue: 0.91))
            MetricCard(
                title: "自定义", value: "\(customCount)", detail: "手动维护",
                symbol: "slider.horizontal.below.square.filled.and.square")
        }
    }

    private var catalogControls: some View {
        HStack(spacing: 12) {
            Picker("状态", selection: $catalogFilter) {
                ForEach(ModelCatalogFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            Picker("Provider", selection: $providerFilter) {
                Text("全部 Provider").tag("all")
                ForEach(allGroups) { group in
                    Text(group.provider).tag(group.provider)
                }
            }
            .frame(width: 190)

            Spacer()

            Text("\(filteredGroups.reduce(0) { $0 + $1.models.count }) 个结果")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.primary.opacity(0.06))
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在读取模型目录…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .cardStyle()
    }

    private var customModelProviders: [Provider] {
        model.providers.filter { !$0.disabled && $0.authMode != "forward" }
    }

    private var preferredCustomProvider: String? {
        if providerFilter != "all", customModelProviders.contains(where: { $0.name == providerFilter }) {
            return providerFilter
        }
        return customModelProviders.first?.name
    }

    private func toggleCollapsed(_ provider: String) {
        if collapsedProviders.contains(provider) {
            collapsedProviders.remove(provider)
        } else {
            collapsedProviders.insert(provider)
        }
    }
}
