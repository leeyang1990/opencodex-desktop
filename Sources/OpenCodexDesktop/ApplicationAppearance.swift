import AppKit
import Foundation

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
final class ApplicationAppearance: ObservableObject {
    static let shared = ApplicationAppearance()

    @Published private(set) var showsDockIcon: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsDockIcon = DockVisibilityPreference.load(from: defaults)
    }

    func applyStoredPreference() {
        guard !showsDockIcon else { return }
        let application = NSApplication.shared
        guard application.setActivationPolicy(.accessory) else {
            showsDockIcon = true
            DockVisibilityPreference.save(true, to: defaults)
            return
        }
    }

    func setDockIconVisible(_ isVisible: Bool) throws {
        guard isVisible != showsDockIcon else { return }
        let application = NSApplication.shared
        let policy: NSApplication.ActivationPolicy = isVisible ? .regular : .accessory
        guard application.setActivationPolicy(policy) else {
            throw ApplicationAppearanceError.activationPolicyFailed
        }

        showsDockIcon = isVisible
        DockVisibilityPreference.save(isVisible, to: defaults)
        if isVisible { application.activate(ignoringOtherApps: true) }
    }
}
