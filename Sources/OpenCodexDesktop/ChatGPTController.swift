import AppKit
import Foundation

/// The subset of ChatGPT.app lifecycle the launcher needs.
///
/// ChatGPT reads `~/.codex/config.toml` (including the injected `openai_base_url`) once at
/// launch, so a configuration change only takes effect after the app is restarted. This
/// boundary keeps that OS-level work testable without launching the real app.
@MainActor
protocol ChatGPTAppControlling {
    var isRunning: Bool { get }
    /// Asks the app to quit and waits for it to disappear within `timeout`.
    func requestQuit(timeout: Duration) async -> Bool
    /// Relaunches the app and waits for Launch Services to report the result.
    func launch() async -> Bool
}

@MainActor
struct ChatGPTAppController: ChatGPTAppControlling {
    private let bundleIdentifier: String
    private let workspace: NSWorkspace

    init(
        bundleIdentifier: String = AppConstants.ChatGPT.bundleIdentifier,
        workspace: NSWorkspace = .shared
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.workspace = workspace
    }

    private var runningApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    var isRunning: Bool { runningApplication != nil }

    func requestQuit(timeout: Duration) async -> Bool {
        guard let application = runningApplication else { return true }
        // A cooperative quit first: the app can flush its own state, and an app that refuses
        // (unsaved work) keeps running rather than losing data to a forced kill.
        application.terminate()
        let deadline = ContinuousClock.now + timeout
        while !application.isTerminated, ContinuousClock.now < deadline {
            try? await Task.sleep(for: AppConstants.ChatGPT.quitPollInterval)
        }
        return application.isTerminated
    }

    func launch() async -> Bool {
        guard let url = applicationURL else { return false }
        return await withCheckedContinuation { continuation in
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { application, error in
                if let error {
                    NSLog("OpenCodex Desktop: failed to launch ChatGPT: \(error.localizedDescription)")
                }
                continuation.resume(returning: application != nil && error == nil)
            }
        }
    }

    /// ChatGPT is normally in `/Applications`, but a per-user install must keep working.
    private var applicationURL: URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/ChatGPT.app", isDirectory: true),
        ]
        if let installed = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return installed
        }
        return workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}
