import SwiftUI

enum AppPalette {
    static let accent = Color(red: 0.31, green: 0.26, blue: 0.82)
    static let success = Color(red: 0.10, green: 0.43, blue: 0.29)
    static let warning = Color(red: 0.64, green: 0.32, blue: 0.02)
    static let danger = Color(red: 0.76, green: 0.17, blue: 0.20)
}

/// Quiet content panels sit on a single desktop-backed frosted window.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 18
    var tint: Color?

    func body(content: Content) -> some View {
        content.glassPanel(padding: padding, tint: tint)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 18, tint: Color? = nil) -> some View {
        modifier(CardStyle(padding: padding, tint: tint))
    }
}

struct StatusDot: View {
    let state: ConnectionState
    var size: CGFloat = 8

    private var color: Color {
        switch state {
        case .checking: AppPalette.warning
        case .online: AppPalette.success
        case .offline: .secondary
        case .unauthorized: AppPalette.warning
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.5), radius: state == .online ? 5 : 0)
            .accessibilityHidden(true)
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 23, weight: .semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var tint: Color = AppPalette.accent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .glassControl(tint: tint.opacity(0.18))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }
}

/// Compact glass badge used for provider and model state.
struct Pill: View {
    let text: String
    var color: Color = .secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .glassControl(tint: color.opacity(0.30))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .shellButtonStyle(prominent: true)
            }
        }
    }
}
