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

    @Published var connectionHost: String
    @Published var connectionPort: Int

    let client: OpenCodexAPIClient
    let coreManager = CoreManager.shared
    let defaults: UserDefaults
    let eventStore = DesktopEventStore.shared
    var notificationManager: NativeNotificationManager { .shared }

    private var systemMonitoringStarted = false
    private var serviceMonitorTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        client: OpenCodexAPIClient? = nil
    ) {
        self.defaults = defaults
        let initialHost = defaults.string(forKey: "connectionHost") ?? AppConstants.Connection.defaultHost
        let savedPort = defaults.integer(forKey: "connectionPort")
        let initialPort = savedPort == 0 ? AppConstants.Connection.defaultPort : savedPort
        connectionHost = initialHost
        connectionPort = initialPort
        self.client = client ?? OpenCodexAPIClient(host: initialHost, port: initialPort)
        super.init()
    }

    var isOnline: Bool { connectionState == .online }
    var baseAddress: String { "http://\(connectionHost):\(connectionPort)" }
    var dashboardURL: URL? {
        let normalizedHost = connectionHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard AppConstants.Connection.loopbackHosts.contains(normalizedHost), (1...65_535).contains(connectionPort)
        else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = normalizedHost == "::1" ? "[::1]" : normalizedHost
        components.port = connectionPort
        components.path = "/v1"
        return components.url
    }
    var tokenAvailable: Bool { AdminTokenProvider().load() != nil }
    var tokenPath: String { AdminTokenProvider().tokenFileURL.path }

    func bootstrap() async {
        coreManager.refreshInstallation()
        await refresh()
        await scanCodexRuntimes()
        runEnvironmentCheck(presentOnFirstLaunch: true)
        if connectionState == .offline, coreManager.installationState.isInstalled {
            await startService()
        }
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
                    self.eventStore.append(.coreCrashed, detail: "健康检查未响应")
                    self.notificationManager.send(
                        title: "OpenCodex Core 已离线",
                        body: "打开诊断与修复查看本机状态。"
                    )
                } else if !wasOnline, self.isOnline {
                    self.eventStore.append(.serviceRecovered)
                }
            }
        }
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
            eventStore.append(.wakeCheckFailed, detail: "Core 管理接口未响应")
            notificationManager.send(
                title: "唤醒后 Core 未恢复",
                body: "打开诊断与修复检查进程、端口和运行时。"
            )
        }
    }
}
