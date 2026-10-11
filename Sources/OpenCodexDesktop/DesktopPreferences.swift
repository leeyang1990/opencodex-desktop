import Foundation

/// Desktop-owned preferences that describe launcher behavior only.
///
/// Provider, account, model, and routing configuration stay in the Core; these keys never
/// mirror Core state.
enum DesktopPreferences {
    /// Whether an installed, offline Core should be started when Desktop launches.
    static let startsCoreWithAppKey = "startsCoreWithApp"
    /// Defaults to `false`: opening the desktop shell must not implicitly start a local service.
    static func startsCoreWithApp(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: startsCoreWithAppKey) as? Bool ?? false
    }

    static func shouldStartCoreWithApp(
        preferenceEnabled: Bool,
        connectionState: ConnectionState,
        isCoreInstalled: Bool
    ) -> Bool {
        guard preferenceEnabled, isCoreInstalled else { return false }
        guard case .offline = connectionState else { return false }
        return true
    }
}
