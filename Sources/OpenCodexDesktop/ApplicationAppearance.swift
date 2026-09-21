import AppKit
import Foundation
import SwiftUI

enum DockVisibilityPreference {
    static let defaultsKey = "showsDockIcon"

    static func load(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    static func save(_ isVisible: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isVisible, forKey: defaultsKey)
    }
}

enum ApplicationAppearanceError: LocalizedError {
    case activationPolicyFailed

    var errorDescription: String? {
        switch self {
        case .activationPolicyFailed:
            "无法更新 Dock 显示状态，请重新启动客户端后再试。"
        }
    }
}

@MainActor
protocol ApplicationActivationControlling {
    var policy: NSApplication.ActivationPolicy { get }
    func setPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool
    func activate()
}

@MainActor
private struct SystemApplicationActivation: ApplicationActivationControlling {
    var policy: NSApplication.ActivationPolicy { NSApplication.shared.activationPolicy() }
    func setPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool {
        NSApplication.shared.setActivationPolicy(policy)
    }
    func activate() { NSApplication.shared.activate(ignoringOtherApps: true) }
}

@MainActor
final class ApplicationAppearance: ObservableObject {
    static let shared = ApplicationAppearance()

    @Published private(set) var showsDockIcon: Bool

    private let defaults: UserDefaults
    private let activation: any ApplicationActivationControlling

    init(defaults: UserDefaults = .standard, activation: (any ApplicationActivationControlling)? = nil) {
        self.defaults = defaults
        self.activation = activation ?? SystemApplicationActivation()
        showsDockIcon = DockVisibilityPreference.load(from: defaults)
    }

    func applyStoredPreference() {
        do {
            try setDockIconVisible(DockVisibilityPreference.load(from: defaults))
        } catch {
            // Keep the user's preference for the next reconciliation, but show the actual state.
            showsDockIcon = activation.policy == .regular
        }
    }

    func setDockIconVisible(_ isVisible: Bool) throws {
        let policy: NSApplication.ActivationPolicy = isVisible ? .regular : .accessory
        let needsChange = activation.policy != policy
        if needsChange {
            guard activation.setPolicy(policy), activation.policy == policy else {
                showsDockIcon = activation.policy == .regular
                throw ApplicationAppearanceError.activationPolicyFailed
            }
        }

        showsDockIcon = isVisible
        DockVisibilityPreference.save(isVisible, to: defaults)
        if isVisible && needsChange { activation.activate() }
    }
}

/// The only full-window background. It must not be covered by an opaque SwiftUI fill.
/// AppKit samples the actual desktop behind the window and respects Reduce Transparency.
final class FrostedWindowMaterialView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // A light window material keeps backdrop color subtle and text legible.
        // The HUD material is too smoky for a text-heavy settings window.
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .aqua)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }
}

private struct TranslucentWindowBacking: NSViewRepresentable {
    func makeNSView(context: Context) -> FrostedWindowMaterialView {
        FrostedWindowMaterialView()
    }

    func updateNSView(_ view: FrostedWindowMaterialView, context: Context) {}
}

extension View {
    /// Backs the shell with system material and keeps the native titlebar visibly frosted.
    @ViewBuilder
    func translucentWindowBacking() -> some View {
        if #available(macOS 15.0, *) {
            background { frostedBackdrop }
                .containerBackground(.clear, for: .window)
                .preferredColorScheme(.light)
                .overlay { frostedWindowRim }
        } else {
            background { frostedBackdrop }
                .preferredColorScheme(.light)
                .overlay { frostedWindowRim }
        }
    }

    private var frostedWindowRim: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.white.opacity(0.65), lineWidth: 0.5)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var frostedBackdrop: some View {
        TranslucentWindowBacking()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
