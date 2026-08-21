import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var showingCreate = false
    @State private var editingProvider: Provider?
    @State private var deletingProvider: Provider?

    private let columns = [
        GridItem(.adaptive(minimum: 285, maximum: 380), spacing: 14)
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
                                        onToggle: { enabled in
                                            Task { await model.setEnabled(provider, enabled: enabled) }
                                        },
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
