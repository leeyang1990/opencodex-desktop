import AppKit
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
    @Published var globalModelContextCap = 350_000
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

    private let client: OpenCodexAPIClient
    let coreManager = CoreManager.shared
    private let defaults: UserDefaults
    private var accountLoginTask: Task<Void, Never>?
    private let imageGenerationSettingsStore = ImageGenerationSettingsStore()
    private let visionRoutingSettingsStore = VisionRoutingSettingsStore()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initialHost = defaults.string(forKey: "connectionHost") ?? "127.0.0.1"
        let savedPort = defaults.integer(forKey: "connectionPort")
        let initialPort = savedPort == 0 ? 10100 : savedPort
        connectionHost = initialHost
        connectionPort = initialPort
        client = OpenCodexAPIClient(host: initialHost, port: initialPort)
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
        guard connectionState == .offline else { return }
        if coreManager.installationState.isInstalled {
            await startService()
        }
    }

    func refresh(showSpinner: Bool = true) async {
        if showSpinner { isRefreshing = true }
        defer { isRefreshing = false }
        connectionState = .checking
        do {
            health = try await client.health()
        } catch {
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

    func refreshAccounts(refreshQuota: Bool = false, showErrors: Bool = true) async {
        guard isOnline else {
            codexAccounts = []
            accountPoolStatus = nil
            return
        }
        isRefreshingAccounts = true
        defer { isRefreshingAccounts = false }
        do {
            async let accountsValue = client.codexAccounts(refreshQuota: refreshQuota)
            async let statusValue = client.codexAccountPoolStatus()
            let loaded = try await (accountsValue, statusValue)
            codexAccounts = loaded.0.sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                if $0.isMain != $1.isMain { return $0.isMain }
                return $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending
            }
            accountPoolStatus = loaded.1
        } catch {
            if showErrors { errorMessage = error.localizedDescription }
        }
    }

    func refreshModels(showErrors: Bool = true) async {
        guard isOnline else {
            managedModels = []
            selectedModels = [:]
            availableModels = [:]
            liveModelCounts = [:]
            modelContextCaps = [:]
            return
        }
        isRefreshingModels = true
        defer { isRefreshingModels = false }
        do {
            async let modelValue = client.models()
            async let selectionValue = client.selectedModels()
            async let capsValue = client.providerContextCaps()
            let loaded = try await (modelValue, selectionValue, capsValue)
            managedModels = loaded.0
            selectedModels = loaded.1.selected
            availableModels = loaded.1.available
            liveModelCounts = loaded.1.liveModelCounts
            modelContextCaps = loaded.2.caps
            globalModelContextCap = loaded.2.value ?? loaded.2.cap ?? 350_000
        } catch {
            if showErrors { errorMessage = error.localizedDescription }
        }
    }

    func isModelVisible(_ item: ManagedModel) -> Bool {
        guard !item.disabled else { return false }
        if item.native { return true }
        guard let allowlist = selectedModels[item.provider], !allowlist.isEmpty else { return true }
        return allowlist.contains(item.modelID)
    }

    func setModelVisible(_ item: ManagedModel, visible: Bool) async {
        busyModel = item.namespaced
        defer { busyModel = nil }
        do {
            try await client.setModelVisibility(
                provider: item.provider,
                targets: [ModelVisibilityTarget(id: item.modelID, native: item.native)],
                enabled: visible
            )
            operationMessage = visible ? "模型已启用" : "模型已隐藏"
            await refreshModels(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setProviderModelsVisible(provider: String, items: [ManagedModel], visible: Bool) async {
        guard !items.isEmpty else { return }
        busyModelProvider = provider
        defer { busyModelProvider = nil }
        do {
            try await client.setModelVisibility(
                provider: provider,
                targets: items.map { ModelVisibilityTarget(id: $0.modelID, native: $0.native) },
                enabled: visible,
                wholeProvider: true
            )
            operationMessage = visible ? "已启用 \(provider) 的全部模型" : "已隐藏 \(provider) 的全部模型"
            await refreshModels(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCustomModel(_ draft: CustomModelDraft, editing item: ManagedModel? = nil) async -> Bool {
        let busyID = item?.namespaced ?? "new-custom-model"
        busyModel = busyID
        defer { busyModel = nil }
        do {
            if let item, let customID = item.customID {
                try await client.updateCustomModel(id: customID, draft: draft)
                operationMessage = "自定义模型已更新"
            } else {
                try await client.createCustomModel(draft)
                operationMessage = "自定义模型已添加"
            }
            await refreshModels(showErrors: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteCustomModel(_ item: ManagedModel) async {
        guard let customID = item.customID else { return }
        busyModel = item.namespaced
        defer { busyModel = nil }
        do {
            try await client.deleteCustomModel(id: customID)
            operationMessage = "自定义模型已删除"
            await refreshModels(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setProviderContextCap(provider: String, enabled: Bool, value: Int?) async -> Bool {
        busyModelProvider = provider
        defer { busyModelProvider = nil }
        do {
            let response = try await client.setProviderContextCap(provider: provider, enabled: enabled, value: value)
            modelContextCaps = response.caps
            globalModelContextCap = response.value ?? response.cap ?? globalModelContextCap
            operationMessage = enabled ? "上下文限制已更新" : "已关闭上下文限制"
            await refreshModels(showErrors: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setGlobalModelContextCap(_ value: Int, applyToAll: Bool) async -> Bool {
        do {
            let response = try await client.setGlobalContextCap(value: value, applyToAll: applyToAll)
            modelContextCaps = response.caps
            globalModelContextCap = response.value ?? response.cap ?? value
            operationMessage = applyToAll ? "默认限制已应用到全部 Provider" : "默认上下文限制已更新"
            await refreshModels(showErrors: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setProviderDefaultModel(provider: String, item: ManagedModel) async {
        busyModel = item.namespaced
        defer { busyModel = nil }
        do {
            try await client.setProviderDefaultModel(provider: provider, modelID: item.modelID)
            operationMessage = "\(item.modelID) 已设为 \(provider) 默认模型"
            await refresh(showSpinner: false)
            await refreshModels(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectCodexAccount(_ account: CodexAccount) async {
        await performAccountOperation(id: account.effectiveID, successMessage: "已切换到 \(account.displayName)") {
            try await self.client.selectCodexAccount(account.effectiveID)
        }
    }

    func setCodexAccountPaused(_ account: CodexAccount, paused: Bool) async {
        await performAccountOperation(
            id: account.effectiveID,
            successMessage: paused ? "账号已暂停" : "账号已恢复"
        ) {
            try await self.client.setCodexAccountPaused(account.effectiveID, paused: paused)
        }
    }

    func setCodexAccountPriority(_ account: CodexAccount, priority: Int) async {
        await performAccountOperation(id: account.effectiveID, successMessage: "账号顺序已更新") {
            try await self.client.setCodexAccountPriority(account.effectiveID, priority: priority)
        }
    }

    func removeCodexAccount(_ account: CodexAccount) async {
        guard !account.isMain else { return }
        await performAccountOperation(id: account.id, successMessage: "账号已移除") {
            try await self.client.removeCodexAccount(account.id)
        }
    }

    func updateAccountPoolStrategy(_ strategy: AccountPoolStrategy) async {
        do {
            try await client.updateCodexPoolStrategy(strategy)
            operationMessage = "账号池策略已更新"
            await refreshAccounts(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateAccountAutoSwitchThreshold(_ threshold: Int) async {
        do {
            try await client.updateCodexAutoSwitchThreshold(threshold)
            operationMessage = "自动切换阈值已更新"
            await refreshAccounts(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginCodexLogin(reauthAccount: CodexAccount? = nil) {
        guard !accountLoginState.isInProgress else { return }
        accountLoginTask?.cancel()
        accountLoginState = .starting
        let accountId = reauthAccount?.id
        let reauth = reauthAccount != nil
        accountLoginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let start = try await self.client.startCodexLogin(accountId: accountId, reauth: reauth)
                guard !Task.isCancelled else { return }
                self.accountLoginState = .waiting(flowId: start.flowId, url: start.url)
                for _ in 0..<150 {
                    try await Task.sleep(for: .seconds(2))
                    let status = try await self.client.codexLoginStatus(
                        flowId: start.flowId,
                        accountId: accountId,
                        reauth: reauth
                    )
                    guard !Task.isCancelled else { return }
                    switch status.status {
                    case "done":
                        self.accountLoginState = .completed(status.email)
                        self.operationMessage = reauth ? "账号已重新认证" : "账号已加入账号池"
                        await self.refreshAccounts(refreshQuota: true, showErrors: false)
                        return
                    case "error", "expired":
                        self.accountLoginState = .failed(status.error ?? "登录已过期，请重试")
                        return
                    default:
                        continue
                    }
                }
                self.accountLoginState = .failed("登录超时，请重试")
                try? await self.client.cancelCodexLogin(flowId: start.flowId)
            } catch is CancellationError {
                return
            } catch {
                self.accountLoginState = .failed(error.localizedDescription)
            }
        }
    }

    func reopenCodexLoginPage() {
        guard case let .waiting(_, urlString) = accountLoginState,
              let urlString,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func cancelCodexLogin() {
        let flowId: String?
        if case let .waiting(id, _) = accountLoginState { flowId = id } else { flowId = nil }
        accountLoginTask?.cancel()
        accountLoginTask = nil
        accountLoginState = .idle
        Task { try? await client.cancelCodexLogin(flowId: flowId) }
    }

    func dismissCodexLoginResult() {
        if !accountLoginState.isInProgress { accountLoginState = .idle }
    }

    func saveConnection() async {
        let trimmedHost = connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)
        connectionHost = trimmedHost.isEmpty ? "127.0.0.1" : trimmedHost
        connectionPort = min(max(connectionPort, 1), 65_535)
        defaults.set(connectionHost, forKey: "connectionHost")
        defaults.set(connectionPort, forKey: "connectionPort")
        await client.updateConnection(host: connectionHost, port: connectionPort)
        await refresh()
    }

    func createProvider(_ draft: ProviderDraft) async -> Bool {
        await performProviderOperation(name: draft.name) {
            try await self.client.createProvider(draft)
        }
    }

    func updateProvider(_ provider: Provider, draft: ProviderDraft) async -> Bool {
        await performProviderOperation(name: provider.name) {
            try await self.client.updateProvider(original: provider, draft: draft)
        }
    }

    func setEnabled(_ provider: Provider, enabled: Bool) async {
        _ = await performProviderOperation(name: provider.name) {
            try await self.client.setProviderEnabled(provider, enabled: enabled)
        }
    }

    func setDefault(_ provider: Provider) async {
        _ = await performProviderOperation(name: provider.name) {
            try await self.client.setDefaultProvider(provider)
        }
    }

    func delete(_ provider: Provider) async {
        _ = await performProviderOperation(name: provider.name) {
            try await self.client.deleteProvider(provider)
        }
    }

    func test(_ provider: Provider) async {
        busyProvider = provider.name
        defer { busyProvider = nil }
        do {
            let result = try await client.testProvider(provider)
            if result.applicable == false {
                operationMessage = "\(provider.name) 使用静态模型目录，无需连接测试。"
            } else if result.ok == true {
                let latency = result.latencyMs.map { " · \($0) ms" } ?? ""
                let models = result.models.map { " · \($0) 个模型" } ?? ""
                operationMessage = "\(provider.name) 连接成功\(latency)\(models)"
            } else {
                errorMessage = result.error ?? "连接测试失败"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSettings(
        codexAutoStart: Bool,
        streamMode: String,
        memoryBudget: Int,
        accountPicker: Bool
    ) async -> Bool {
        do {
            try await client.updateSettings(
                codexAutoStart: codexAutoStart,
                streamMode: streamMode,
                memoryBudget: memoryBudget,
                accountPicker: accountPicker
            )
            operationMessage = "设置已保存"
            await refresh(showSpinner: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveImageGenerationSettings(_ settings: ImageGenerationSettings) async -> Bool {
        do {
            if self.settings != nil {
                try await client.stopProxy()
                try? await Task.sleep(for: .milliseconds(500))
            }
            await coreManager.stop()
            try imageGenerationSettingsStore.save(settings)
            imageGenerationSettings = try imageGenerationSettingsStore.load()
            try await coreManager.start(port: connectionPort)
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(250))
                if (try? await client.health()) != nil {
                    operationMessage = settings.usesCustomProvider
                        ? "生图已切换到自定义 Provider"
                        : "生图已切换到 GPT 账号自动路由"
                    await refresh(showSpinner: false)
                    return true
                }
            }
            throw CoreManagerError.launchFailed("保存成功，但内核未能及时恢复")
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveVisionRouting(forceGPTVision: Bool) async -> Bool {
        do {
            if settings != nil {
                try await client.stopProxy()
                try? await Task.sleep(for: .milliseconds(500))
            }
            await coreManager.stop()
            try visionRoutingSettingsStore.save(forceGPTVision: forceGPTVision)
            self.forceGPTVision = forceGPTVision
            try await coreManager.start(port: connectionPort)
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(250))
                if (try? await client.health()) != nil {
                    operationMessage = forceGPTVision ? "已强制使用 GPT 视觉旁路" : "已恢复模型原生多模态"
                    await refresh(showSpinner: false)
                    return true
                }
            }
            throw CoreManagerError.launchFailed("保存成功，但内核未能及时恢复")
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func startService() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await coreManager.start(port: connectionPort)
            for _ in 0..<240 {
                try? await Task.sleep(for: .milliseconds(500))
                await refresh(showSpinner: false)
                if isOnline {
                    operationMessage = "OpenCodex 内核已启动"
                    return
                }
                if let exitMessage = coreManager.lastExitMessage {
                    throw CoreManagerError.stoppedUnexpectedly(exitMessage)
                }
            }
            throw CoreManagerError.launchFailed("内核在 120 秒内未就绪，请查看内核日志")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopService() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if isOnline {
                try await client.stopProxy()
            }
            try? await Task.sleep(for: .milliseconds(500))
            await coreManager.stop()
            await refresh(showSpinner: false)
            operationMessage = "内核已停止"
        } catch {
            await coreManager.stop()
            await refresh(showSpinner: false)
            errorMessage = error.localizedDescription
        }
    }

    func openConfigFolder() {
        let folder = AdminTokenProvider().tokenFileURL.deletingLastPathComponent()
        NSWorkspace.shared.open(folder)
    }

    func openCoreLog() {
        coreManager.openLog()
    }

    func installCore() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if isOnline || coreManager.ownsRunningProcess {
                await stopService()
            }
            try await coreManager.installCompatibleCore()
            operationMessage = "OpenCodex Core \(coreManager.compatibleRelease.version) 已安装"
            await startService()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uninstallCore() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if isOnline || coreManager.ownsRunningProcess {
                await stopService()
            }
            try await coreManager.uninstallCompatibleCore()
            await refresh(showSpinner: false)
            operationMessage = "内核已卸载，配置与账号数据已保留"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openCoreInstallationFolder() {
        coreManager.openInstallationFolder()
    }

    func openDashboard() {
        if let url = URL(string: baseAddress) { NSWorkspace.shared.open(url) }
    }

    private func performProviderOperation(
        name: String,
        operation: @escaping () async throws -> Void
    ) async -> Bool {
        busyProvider = name
        defer { busyProvider = nil }
        do {
            try await operation()
            operationMessage = "Provider 已更新"
            await refresh(showSpinner: false)
            await refreshModels(showErrors: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func performAccountOperation(
        id: String,
        successMessage: String,
        operation: @escaping () async throws -> Void
    ) async {
        busyAccount = id
        defer { busyAccount = nil }
        do {
            try await operation()
            operationMessage = successMessage
            await refreshAccounts(showErrors: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
