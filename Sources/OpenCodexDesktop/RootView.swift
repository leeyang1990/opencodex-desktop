import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: SidebarDestination? = .overview

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
        } detail: {
            detail
        }
        .tint(AppPalette.accent)
        .task { await model.bootstrap() }
        .alert("出现问题", isPresented: errorPresented) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .sheet(isPresented: $model.showsFirstLaunchEnvironmentCheck) {
            FirstLaunchEnvironmentCheckView()
                .environmentObject(model)
                .interactiveDismissDisabled()
        }
        .overlay(alignment: .bottomTrailing) {
            if let message = model.operationMessage {
                toast(message)
                    .padding(18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.operationMessage)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OpenCodex Desktop")
                        .font(.headline)
                    Text("Core Launcher")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 10)

            VStack(spacing: 4) {
                ForEach(SidebarDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: destination.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 18, alignment: .center)
                            Text(destination.title)
                                .font(.callout.weight(selection == destination ? .semibold : .regular))
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selection == destination ? AppPalette.accent : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selection == destination ? AppPalette.accent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(destination.title)
                    .accessibilityLabel(destination.title)
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusDot(state: model.connectionState)
                    Text(model.connectionState.label)
                        .font(.caption.weight(.medium))
                    Spacer()
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(model.baseAddress)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .background(.thinMaterial)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView()
        case .providers:
            ProvidersView()
        case .accounts:
            AccountsView()
        case .models:
            ModelsView()
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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .frame(maxWidth: 360)
    }
}
