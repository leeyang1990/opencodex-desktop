import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var connectionState: ConnectionState = .checking
    @Published var health: HealthResponse?
    @Published var config: ConfigSummary?
    @Published var settings: RuntimeSettings?
    @Published var imageGenerationSettings: ImageGenerationSettings = .defaults
    @Published var forceGPTVision = false
    @Published var providers: [Provider] = []
    @Published var presets: [ProviderPreset] = []
    @Published var codexAccounts: [CodexAccount] = []
    @Published var accountPoolStatus: CodexAccountPoolStatus?
    @Published var managedModels: [ManagedModel] = []
    @Published var selectedModels: [String: [String]] = [:]
    @Published var availableModels: [String: [String]] = [:]
    @Published var liveModelCounts: [String: Int] = [:]
    @Published var modelContextCaps: [String: Int] = [:]
    @Published var globalModelContextCap = AppConstants.Models.defaultContextCap
    @Published var accountLoginState: AccountLoginState = .idle
    @Published var isRefreshing = false
    @Published var isRefreshingAccounts = false
    @Published var isRefreshingModels = false
    @Published var busyProvider: String?
    @Published var busyAccount: String?
    @Published var busyModel: String?
    @Published var busyModelProvider: String?
    @Published var operationMessage: String?
    @Published var errorMessage: String?

    @Published var connectionHost: String
    @Published var connectionPort: Int

    let client: OpenCodexAPIClient
    let coreManager = CoreManager.shared
    let defaults: UserDefaults
    var accountLoginTask: Task<Void, Never>?
    let imageGenerationSettingsStore: ImageGenerationSettingsStore
    let visionRoutingSettingsStore: VisionRoutingSettingsStore

    init(
        defaults: UserDefaults = .standard,
        client: OpenCodexAPIClient? = nil,
        imageGenerationSettingsStore: ImageGenerationSettingsStore = ImageGenerationSettingsStore(),
        visionRoutingSettingsStore: VisionRoutingSettingsStore = VisionRoutingSettingsStore()
    ) {
        self.defaults = defaults
        self.imageGenerationSettingsStore = imageGenerationSettingsStore
        self.visionRoutingSettingsStore = visionRoutingSettingsStore
        let initialHost = defaults.string(forKey: "connectionHost") ?? AppConstants.Connection.defaultHost
        let savedPort = defaults.integer(forKey: "connectionPort")
        let initialPort = savedPort == 0 ? AppConstants.Connection.defaultPort : savedPort
        connectionHost = initialHost
        connectionPort = initialPort
        self.client = client ?? OpenCodexAPIClient(host: initialHost, port: initialPort)
    }

    var isOnline: Bool { connectionState == .online }
    var enabledProviders: [Provider] { providers.filter { !$0.disabled } }
    var defaultProvider: Provider? { providers.first { $0.name == config?.defaultProvider } }
    var baseAddress: String { "http://\(connectionHost):\(connectionPort)" }
    var tokenAvailable: Bool { AdminTokenProvider().load() != nil }
    var tokenPath: String { AdminTokenProvider().tokenFileURL.path }

    func bootstrap() async {
        coreManager.refreshInstallation()
        forceGPTVision = visionRoutingSettingsStore.load()
        await refresh()
        guard connectionState == .offline, coreManager.installationState.isInstalled else { return }
        await startService()
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
            async let configValue = client.config()
            async let settingsValue = client.settings()
            async let providerValue = client.providers()
            async let presetValue = client.presets()
            let loaded = try await (configValue, settingsValue, providerValue, presetValue)
            config = loaded.0
            settings = loaded.1
            imageGenerationSettings = (try? imageGenerationSettingsStore.load()) ?? .defaults
            providers = loaded.2.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            presets = loaded.3
            connectionState = .online
            errorMessage = nil
            await refreshAccounts(showErrors: false)
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
        providers = []
        managedModels = []
        selectedModels = [:]
        availableModels = [:]
        liveModelCounts = [:]
        modelContextCaps = [:]
        codexAccounts = []
        accountPoolStatus = nil
        config = nil
        settings = nil
        imageGenerationSettings = (try? imageGenerationSettingsStore.load()) ?? .defaults
    }
}
