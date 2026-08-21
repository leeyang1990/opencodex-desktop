import Foundation

extension AppModel {
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
}
