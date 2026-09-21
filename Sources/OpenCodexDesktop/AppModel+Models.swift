import Foundation

/// Native access to the Core's model surface.
///
/// This is the same data and the same write the console's model manager uses — the shell does not
/// keep a parallel copy of provider, routing, or catalog state. Keys, account pools, and routing
/// profiles stay in the console; only visibility is writable here.
extension AppModel {
    /// Models grouped by provider, in the order the Core lists them.
    var modelsByProvider: [(provider: String, models: [ManagedModel])] {
        var order: [String] = []
        var grouped: [String: [ManagedModel]] = [:]
        for model in models {
            if grouped[model.provider] == nil { order.append(model.provider) }
            grouped[model.provider, default: []].append(model)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    var enabledModelCount: Int { models.filter { !$0.disabled }.count }

    var defaultProviderSummary: ProviderSummary? {
        providerSummaries.first { $0.isDefault } ?? providerSummaries.first
    }

    func loadModelCatalog() async {
        guard isOnline else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            async let modelsResponse = client.models()
            async let configResponse = client.config()
            models = try await modelsResponse
            providerSummaries = Self.summaries(from: try await configResponse)
            modelErrorMessage = nil
        } catch {
            modelErrorMessage = error.localizedDescription
        }
    }

    /// Applies one visibility switch and reloads, so the UI never shows an optimistic state that
    /// the Core rejected.
    func setModelEnabled(_ model: ManagedModel, enabled: Bool) async {
        await applyVisibility(provider: model.provider, targets: [model.selector], enabled: enabled, scope: "models")
    }

    func setProviderModelsEnabled(_ provider: String, enabled: Bool) async {
        let targets = models.filter { $0.provider == provider }.map(\.selector)
        guard !targets.isEmpty else { return }
        await applyVisibility(provider: provider, targets: targets, enabled: enabled, scope: "provider")
    }

    private func applyVisibility(
        provider: String,
        targets: [ModelVisibilityTarget],
        enabled: Bool,
        scope: String
    ) async {
        guard isOnline, !isUpdatingModels else { return }
        isUpdatingModels = true
        defer { isUpdatingModels = false }
        do {
            try await client.setModelVisibility(provider: provider, targets: targets, enabled: enabled, scope: scope)
            await loadModelCatalog()
            // The Core rewrites the Codex catalog on every visibility change, and a running
            // ChatGPT keeps the catalog it read at launch.
            if chatGPT.isRunning { isChatGPTRestartPending = true }
            operationMessage = enabled ? L10n.tr("已启用所选模型") : L10n.tr("已隐藏所选模型")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func summaries(from config: CoreConfig) -> [ProviderSummary] {
        (config.providers ?? [:])
            .map { name, provider in
                ProviderSummary(
                    id: name,
                    adapter: provider.adapter,
                    baseURL: provider.baseUrl,
                    hasAPIKey: provider.hasApiKey ?? false,
                    authMode: provider.authMode,
                    note: provider.note,
                    liveModels: provider.liveModels ?? false,
                    codexAccountMode: provider.codexAccountMode,
                    isDefault: name == config.defaultProvider
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }
}
