import Foundation

/// Desktop-owned preferences that describe launcher behavior only.
///
/// Provider, account, model, and routing configuration stay in the Core; these keys never
/// mirror Core state.
enum DesktopPreferences {
    /// Whether an installed, offline Core should be started when Desktop launches.
    static let startsCoreWithAppKey = "startsCoreWithApp"
    /// Restore native Codex routing when the launcher quits.
    static let restoresRoutingOnQuitKey = "restoreCodexRoutingOnQuit"
    /// Timestamp of the last successful quit-time restore, used to keep one restore per quit.
    static let lastExitCleanupKey = "lastCodexRoutingRestoreAt"

    /// Defaults to `true`: quitting should not leave ChatGPT pointed at a proxy it cannot reach.
    static func restoresRoutingOnQuit(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: restoresRoutingOnQuitKey) as? Bool ?? true
    }

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
