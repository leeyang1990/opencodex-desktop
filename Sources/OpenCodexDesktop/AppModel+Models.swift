import Foundation

extension AppModel {
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
            globalModelContextCap = loaded.2.value ?? loaded.2.cap ?? AppConstants.Models.defaultContextCap
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
        busyModel = item?.namespaced ?? "new-custom-model"
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
}
