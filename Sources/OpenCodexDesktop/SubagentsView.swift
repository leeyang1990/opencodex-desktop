import SwiftUI

/// The common subagent path: choose up to five models and arrange their preference order.
/// Quota fallback tuning remains in the Core console.
struct SubagentsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "子代理")
                    .padding(.bottom, 2)

                if !model.isOnline {
                    offlineCard
                } else {
                    if let message = model.subagentErrorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppPalette.warning)
                    }
                    selectedCard
                    availableCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task { await model.loadSubagents() }
    }

    // MARK: - Selected

    private var selectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("子代理模型", systemImage: "person.3.sequence")
                    .font(.title3.weight(.semibold))
                Text("\(model.subagentModels.count)/\(SubagentSelection.maximumChosen)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isLoadingSubagents || model.isUpdatingSubagents {
                    ProgressView().controlSize(.small)
                }
                Button("清空") { Task { await model.clearSubagentModels() } }
                    .controlSize(.small)
                    .disabled(model.subagentModels.isEmpty || model.isUpdatingSubagents)
                Button("刷新") { Task { await model.loadSubagents() } }
                    .controlSize(.small)
                    .disabled(model.isLoadingSubagents)
            }

            Text("按顺序优先使用 · 自动保存")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.subagentModels.isEmpty {
                Text("从下方选择模型，最多 \(SubagentSelection.maximumChosen) 个。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.subagentModels.enumerated()), id: \.element) { index, entry in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 16)
                            Text(entry)
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 8)
                            Button {
                                Task { await model.moveSubagentModel(entry, by: -1) }
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0 || model.isUpdatingSubagents)
                            Button {
                                Task { await model.moveSubagentModel(entry, by: 1) }
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.plain)
                            .disabled(index == model.subagentModels.count - 1 || model.isUpdatingSubagents)
                            Button {
                                Task { await model.toggleSubagentModel(entry) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppPalette.danger)
                            .disabled(model.isUpdatingSubagents)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        if index < model.subagentModels.count - 1 {
                            Divider().opacity(0.35).padding(.leading, 14)
                        }
                    }
                }
                .glassInsetSurface()
            }
        }
        .cardStyle()
    }

    // MARK: - Available

    private var availableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("可用模型", systemImage: "square.stack.3d.up")
                    .font(.title3.weight(.semibold))
                Text("\(model.subagentAvailable.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if model.subagentAvailable.isEmpty {
                Text("暂无模型，请先添加渠道。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowGrid(entries: model.subagentAvailable) { entry in
                    let selected = model.isSubagentModelSelected(entry)
                    Button {
                        Task { await model.toggleSubagentModel(entry) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 10, weight: .bold))
                            Text(entry)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                        }
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassControl(tint: selected ? AppPalette.accent.opacity(0.14) : nil, interactive: true)
                    .disabled(model.isUpdatingSubagents)
                }
            }
        }
        .cardStyle()
    }

    private var offlineCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text("启动代理后配置子代理")
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

/// Wraps chips onto as many rows as they need.
private struct FlowGrid<Content: View>: View {
    let entries: [String]
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(entries, id: \.self) { entry in
                HStack {
                    content(entry)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
