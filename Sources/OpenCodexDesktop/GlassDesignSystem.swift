import SwiftUI

/// A single frosted window with quiet translucent content layers, not glass on glass.
enum ShellGlass {
    enum Radius {
        static let chrome: CGFloat = 14
        static let card: CGFloat = 16
        static let inset: CGFloat = 10
        static let control: CGFloat = 8
    }

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    }
    static var chromeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.chrome, style: .continuous)
    }
    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    }
    static var insetShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.inset, style: .continuous)
    }
}

private struct GlassSurface: ViewModifier {
    var tint: Color?
    var isInteractive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                ShellGlass.cardShape.fill(
                    reduceTransparency
                        ? Color.white
                        : Color.white.opacity(isInteractive && isHovered ? 0.82 : 0.68))
                if let tint { ShellGlass.cardShape.fill(tint.opacity(0.04)) }
            }
            .overlay {
                ShellGlass.cardShape.strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .onHover { isHovered = $0 }
    }
}

private struct FrostedButtonStyle: ButtonStyle {
    var isProminent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(
                configuration.role == .destructive
                    ? AppPalette.danger : (isProminent ? Color.white : AppPalette.accent)
            )
            .background {
                ShellGlass.controlShape.fill(
                    isProminent
                        ? AppPalette.accent
                        : AppPalette.accent.opacity(isHovered ? 0.12 : 0.065))
            }
            .overlay {
                ShellGlass.controlShape.strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.68 : 1) : 0.38)
            .contentShape(ShellGlass.controlShape)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func shellButtonStyle(prominent: Bool = false) -> some View {
        buttonStyle(FrostedButtonStyle(isProminent: prominent))
    }

    func glassPanel(padding: CGFloat = 18, tint: Color? = nil, interactive: Bool = false) -> some View {
        self.padding(padding).modifier(GlassSurface(tint: tint, isInteractive: interactive))
    }

    func glassSurface(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(tint: tint, isInteractive: interactive))
    }

    func glassInsetSurface() -> some View {
        background { ShellGlass.insetShape.fill(.black.opacity(0.025)) }
    }

    func glassControl(tint: Color? = nil, interactive: Bool = false) -> some View {
        background { ShellGlass.controlShape.fill(tint ?? Color.black.opacity(0.045)) }
    }

    func glassChromeBar() -> some View {
        background { ShellGlass.chromeShape.fill(.white.opacity(0.45)) }
            .overlay(alignment: .bottom) {
                Rectangle().fill(.black.opacity(0.07)).frame(height: 0.5)
                    .padding(.horizontal, 12)
            }
    }

    func liquidWindowSurface() -> some View {
        tint(AppPalette.accent).translucentWindowBacking()
    }
}

struct ShellHairline: View {
    var body: some View {
        Rectangle().fill(.black.opacity(0.08)).frame(height: 0.5)
    }
}
