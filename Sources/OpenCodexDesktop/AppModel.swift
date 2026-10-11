import AppKit
import Foundation

@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published var connectionState: ConnectionState = .checking
    @Published var health: HealthResponse?
    @Published var settings: RuntimeSettings?
    @Published var isRefreshing = false
    @Published var operationMessage: String?
    @Published var errorMessage: String?
    @Published var environmentReport = EnvironmentCheckReport.empty
    @Published var coreIntegrityInspection: CoreIntegrityInspection = .missing
    @Published var localPortInspection: LocalPortInspection = .unknown
    @Published var codexRuntimeCandidates: [CodexRuntimeCandidate] = []
    @Published var isScanningCodexRuntimes = false
    @Published var hasScannedCodexRuntimes = false
    @Published var securityAuditReport = SecurityAuditReport.empty
    @Published var showsFirstLaunchEnvironmentCheck = false
    @Published var isChatGPTRunning = false
    /// Set when Codex routing was (re)pointed at the proxy while ChatGPT was already running,
    /// because a running ChatGPT keeps the configuration it read at launch.
    @Published var isChatGPTRestartPending = false
    @Published var isRestartingChatGPT = false
    // Accounts, channels, and subagents are the three configuration surfaces the shell owns.
    @Published var codexAccounts: [CodexAccount] = []
    @Published var scheduling: CodexAccountScheduling?
    @Published var isLoadingAccounts = false
    @Published var isUpdatingAccounts = false
    @Published var isStartingLogin = false
    @Published var loginFlowID: String?
    @Published var loginMessage: String?
    @Published var accountErrorMessage: String?
    @Published var consumingResetCreditAccountID: String?
    /// Session-only idempotency identities. Account identifiers and operations are never persisted.
    var resetCreditOperationIDs: [String: String] = [:]

    @Published var channels: [APIChannel] = []
    @Published var defaultChannelName: String?
    @Published var isLoadingChannels = false
    @Published var isUpdatingChannels = false
    @Published var isTestingChannel = false
    @Published var channelProbeResults: [String: ChannelProbeResult] = [:]
    @Published var channelKeyPools: [String: ProviderKeyPool] = [:]
    @Published var channelErrorMessage: String?
    /// Session-only API keys the user typed. Never persisted, never logged.
    @Published var pendingChannelKeys: [String: String] = [:]

    @Published var subagentModels: [String] = []
    @Published var subagentAvailable: [String] = []
    @Published var isLoadingSubagents = false
    @Published var isUpdatingSubagents = false
    @Published var isReorderingSubagents = false
    @Published var subagentErrorMessage: String?

    @Published var models: [ManagedModel] = []
    @Published var providerSummaries: [ProviderSummary] = []
    @Published var isLoadingModels = false
    @Published var isUpdatingModels = false
    @Published var modelErrorMessage: String?

    @Published var usageReport: UsageReport?
    @Published var isLoadingUsage = false
    @Published var usageErrorMessage: String?

    @Published var connectionHost: String
    @Published var connectionPort: Int
    /// Starts an installed, offline Core when Desktop launches. Disabled by default.
    @Published var startsCoreWithApp: Bool {
        didSet { defaults.set(startsCoreWithApp, forKey: DesktopPreferences.startsCoreWithAppKey) }
    }

    let client: OpenCodexAPIClient
    let coreManager: CoreManager
    let defaults: UserDefaults
    /// The event timeline. Injectable so tests never append to the user's real history.
    let eventStore: DesktopEventStore
    var notificationManager: NativeNotificationManager { .shared }

    private var systemMonitoringStarted = false
    private var serviceMonitorTask: Task<Void, Never>?
    var chatGPTStatusTask: Task<Void, Never>?
    var chatGPTObservers: [NSObjectProtocol] = []
    @Published var hasMarkedTerminating = false
    var didRunExitCleanup = false
    var exitCleanupTask: Task<String?, Never>?
    var exitCleanupNeedsClientRestart = false

    /// ChatGPT lifecycle, isolated behind a protocol so the restart and quit paths are testable
    /// without launching the real app.
    lazy var chatGPT: any ChatGPTAppControlling = ChatGPTAppController()

    /// Sign-in flow operations, bound to this model's client at construction. Tests replace them
    /// to drive the polling loop deterministically without a running Core.
    var startLoginOperation: () async throws -> CodexLoginStatus
    var loginStatusOperation: (String) async throws -> CodexLoginStatus
    var cancelLoginOperation: (String) async throws -> Void
    /// Subagent writes, bound to this model's client. Tests replace them to observe the payload
    /// the UI would send without a running Core.
    var setSubagentSelectionOperation: ([String]) async throws -> Void = { _ in }

    /// Deadline and cadence for the sign-in poll; tests shorten the deadline.
    var loginTimeout: Duration = AppConstants.Accounts.loginTimeout
    var loginPollInterval: Duration = AppConstants.Accounts.loginPollInterval

    /// Core-owned routing operations, injectable so the quit path can be exercised without a
    /// running Core. Production always resolves to `CoreManager`.
    var restoreRoutingOperation: () async throws -> Void = { try await CoreManager.shared.restoreNativeCodexRouting() }
    var reapplyRoutingOperation: () async throws -> Void = { try await CoreManager.shared.reapplyNativeCodexRouting() }
    var isStoppingService = false
    /// Tests replace this boundary so stop/restore/restart ordering never touches a real Core.
    lazy var stopCoreOperation: () async throws -> Void = { [unowned self] in
        try await self.stopCoreForShutdown()
    }
    /// Quit only owns the child launched by this Desktop session, even if its API is unhealthy.
    lazy var stopOwnedCoreOnExitOperation: () async throws -> Bool = { [unowned self] in
        let wasRunning = self.coreManager.ownsRunningProcess
        await self.coreManager.stop()
        guard !self.coreManager.ownsRunningProcess else {
            throw CoreManagerError.launchFailed(L10n.tr("内核进程仍在运行，请稍后重试。"))
        }
        return wasRunning
    }
    lazy var needsExitCleanup: () -> Bool = { [unowned self] in
        self.coreManager.installationState.isInstalled || self.coreManager.ownsRunningProcess
            || self.settings?.isCodexRoutingInjected == true || self.exitCleanupNeedsClientRestart
    }

    init(
        defaults: UserDefaults = .standard,
        client: OpenCodexAPIClient? = nil,
        eventStore: DesktopEventStore? = nil,
        coreManager: CoreManager? = nil
    ) {
        self.defaults = defaults
        self.coreManager = coreManager ?? .shared
        self.eventStore = eventStore ?? .shared
        let initialHost = defaults.string(forKey: "connectionHost") ?? AppConstants.Connection.defaultHost
        let savedPort = defaults.integer(forKey: "connectionPort")
        let initialPort = savedPort == 0 ? AppConstants.Connection.defaultPort : savedPort
        connectionHost = initialHost
        connectionPort = initialPort
        startsCoreWithApp = DesktopPreferences.startsCoreWithApp(in: defaults)
        let resolvedClient = client ?? OpenCodexAPIClient(host: initialHost, port: initialPort)
        self.client = resolvedClient
        self.startLoginOperation = { try await resolvedClient.startCodexLogin() }
        self.loginStatusOperation = { try await resolvedClient.codexLoginStatus(flowID: $0) }
        self.cancelLoginOperation = { try await resolvedClient.cancelCodexLogin(flowID: $0) }
        self.setSubagentSelectionOperation = { try await resolvedClient.setSubagentSelection($0) }
        super.init()
    }

    var isOnline: Bool { connectionState == .online }
    var baseAddress: String { "http://\(connectionHost):\(connectionPort)" }
    /// The Core's web console. The shell opens it in the default browser instead of embedding a
    /// WebKit copy of a page the Core already serves.
    func consoleURL(page: CoreConsolePage? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = consoleHost
        components.port = connectionPort
        components.fragment = page?.rawValue
        return components.url
    }
    private var consoleHost: String {
        let normalized = connectionHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard AppConstants.Connection.loopbackHosts.contains(normalized), (1...65_535).contains(connectionPort)
        else { return AppConstants.Connection.defaultHost }
        return normalized == "::1" ? "[::1]" : normalized
    }
    var tokenAvailable: Bool { AdminTokenProvider().load() != nil }
    var tokenPath: String { AdminTokenProvider().tokenFileURL.path }

    func bootstrap() async {
        coreManager.refreshInstallation()
        await refresh()
        await scanCodexRuntimes()
        runEnvironmentCheck(presentOnFirstLaunch: true)
        if DesktopPreferences.shouldStartCoreWithApp(
            preferenceEnabled: startsCoreWithApp,
            connectionState: connectionState,
            isCoreInstalled: coreManager.installationState.isInstalled
        ) {
            await startService()
        } else if isOnline {
            // A previous quit restored native routing; re-point it even when this launch attached
            // to a Core that was already running.
            await reapplyCodexRoutingIfNeeded()
        }
        refreshChatGPTStatus()
        if isOnline { await loadConfigurationSurfaces() }
        startSystemMonitoring()
    }

    func refresh(showSpinner: Bool = true) async {
        if showSpinner { isRefreshing = true }
        defer { isRefreshing = false }
        connectionState = .checking
        do {
            health = try await client.health()
        } catch {
            resetRemoteState()
            if !(error is OpenCodexAPIError) { errorMessage = error.localizedDescription }
            return
        }

        do {
            settings = try await client.settings()
            connectionState = .online
            errorMessage = nil
        } catch OpenCodexAPIError.missingAdminToken {
            connectionState = .unauthorized
            errorMessage = OpenCodexAPIError.missingAdminToken.localizedDescription
        } catch OpenCodexAPIError.unauthorized {
            connectionState = .unauthorized
            errorMessage = OpenCodexAPIError.unauthorized.localizedDescription
        } catch {
            connectionState = .offline
            errorMessage = error.localizedDescription
        }
    }

    private func resetRemoteState() {
        connectionState = .offline
        health = nil
        settings = nil
    }

    private func startSystemMonitoring() {
        guard !systemMonitoringStarted else { return }
        systemMonitoringStarted = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(handleSystemSleepNotification(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleSystemWakeNotification(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        serviceMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                let wasOnline = self.isOnline
                await self.refresh(showSpinner: false)
                if wasOnline, !self.isOnline {
                    self.eventStore.append(.coreCrashed, detail: L10n.tr("健康检查未响应"))
                    self.notificationManager.send(
                        title: L10n.tr("OpenCodex Core 已离线"),
                        body: L10n.tr("打开诊断与修复查看本机状态。")
                    )
                } else if !wasOnline, self.isOnline {
                    self.eventStore.append(.serviceRecovered)
                    await self.loadConfigurationSurfaces()
                }
            }
        }
        startChatGPTStatusObservation()
    }

    @objc private func handleSystemSleepNotification(_ notification: Notification) {
        eventStore.append(.systemSleep)
    }

    @objc private func handleSystemWakeNotification(_ notification: Notification) {
        Task { await handleSystemWake() }
    }

    private func handleSystemWake() async {
        eventStore.append(.systemWake)
        try? await Task.sleep(for: .seconds(2))
        await refresh(showSpinner: false)
        runEnvironmentCheck()
        if !isOnline {
            eventStore.append(.wakeCheckFailed, detail: L10n.tr("Core 管理接口未响应"))
            notificationManager.send(
                title: L10n.tr("唤醒后 Core 未恢复"),
                body: L10n.tr("打开诊断与修复检查进程、端口和运行时。")
            )
        }
    }

    /// Loads every Core-backed configuration surface the shell renders.
    func loadConfigurationSurfaces() async {
        async let models: Void = loadModelCatalog()
        async let accounts: Void = loadCodexAccounts()
        async let channels: Void = loadChannels()
        async let subagents: Void = loadSubagents()
        async let usage: Void = loadUsage()
        _ = await (models, accounts, channels, subagents, usage)
    }
}
