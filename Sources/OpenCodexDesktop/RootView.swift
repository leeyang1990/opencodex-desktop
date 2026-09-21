import SwiftUI

/// The shell window: shared navigation for configuration and Desktop settings.
///
/// A single desktop-backed frosted surface supports quiet navigation and content layers.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var navigation = AppNavigation.shared
    @ObservedObject private var appUpdateManager = AppUpdateManager.shared

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .tint(AppPalette.accent)
        .translucentWindowBacking()
        .task { await model.bootstrap() }
        .alert(L10n.tr("出现问题"), isPresented: errorPresented) {
            Button(L10n.tr("好")) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? L10n.tr("未知错误"))
        }
        .sheet(isPresented: $model.showsFirstLaunchEnvironmentCheck) {
            FirstLaunchEnvironmentCheckView()
                .environmentObject(model)
                .interactiveDismissDisabled()
        }
        .overlay(alignment: .bottom) {
            if let message = model.operationMessage {
                toast(message)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.operationMessage)
        .onOpenURL { url in
            guard let destination = DeepLinkPolicy.destination(for: url) else { return }
            navigation.show(destination)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Glass chrome

    private var titleBar: some View {
        HStack(spacing: 14) {
            appIdentity
            tabs
            Spacer(minLength: 8)
            statusCluster
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassChromeBar()
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .zIndex(10)
    }

    private var appIdentity: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .padding(3)
                .glassControl(tint: AppPalette.accent.opacity(0.16))
                .accessibilityHidden(true)

            Text("OpenCodex")
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .fixedSize()
        }
    }

    /// Keep the navigation lightweight; the window already provides the blur.
    private var tabs: some View {
        GlassTabs(selection: navigation.selection) { destination in
            navigation.show(destination)
        }
    }

    private var statusCluster: some View {
        HStack(spacing: 8) {
            if model.isRefreshing || model.isUpdatingModels {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            }

            if appUpdateManager.availableRelease != nil {
                Button {
                    navigation.show(.settings)
                } label: {
                    Label(L10n.tr("可更新"), systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.medium))
                        .labelStyle(.titleAndIcon)
                }
                .shellButtonStyle()
                .tint(AppPalette.accent)
                .help(L10n.tr("有可用的客户端更新"))
            }

            connectionPill
            Button {
                model.openConsole()
            } label: {
                Label(L10n.tr("控制台"), systemImage: "arrow.up.right.square")
                    .font(.caption.weight(.medium))
            }
            .shellButtonStyle()
            .disabled(!model.isOnline)
            .help(L10n.tr("在浏览器中打开 OpenCodex 完整设置"))
        }
    }

    private var connectionPill: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            HStack(spacing: 7) {
                StatusDot(state: model.connectionState, size: 7)
                Text(model.isOnline ? L10n.tr("已连接") : model.connectionState.label)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(model.isOnline ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glassControl(interactive: true)
        .help(L10n.tr("点击刷新状态 · \(model.baseAddress)"))
        .disabled(model.isRefreshing)
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.selection {
        case .home:
            HomeView()
        case .accounts:
            AccountsView()
        case .channels:
            ChannelsView()
        case .subagents:
            SubagentsView()
        case .settings:
            SettingsView()
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private func toast(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppPalette.success)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Button {
                model.operationMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassControl()
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .frame(maxWidth: 380)
    }
}

// MARK: - Tabs

/// Low-contrast tabs on the shared frosted surface.
private struct GlassTabs: View {
    let selection: SidebarDestination
    let onSelect: (SidebarDestination) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SidebarDestination.allCases) { destination in
                tab(destination, isSelected: selection == destination)
            }
        }
        .padding(3)
    }

    @ViewBuilder
    private func tab(_ destination: SidebarDestination, isSelected: Bool) -> some View {
        let label = HStack(spacing: 6) {
            Image(systemName: destination.symbol)
                .font(.system(size: 11.5, weight: .semibold))
            Text(destination.title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
        }
        .foregroundStyle(isSelected ? AppPalette.accent : Color.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 6.5)
        .contentShape(ShellGlass.controlShape)

        Button {
            onSelect(destination)
        } label: {
            label.background {
                ShellGlass.controlShape.fill(isSelected ? AppPalette.accent.opacity(0.13) : .clear)
            }
        }
        .buttonStyle(.plain)
        .help(destination.title)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
