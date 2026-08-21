import Foundation

extension AppModel {
    func saveConnection() async {
        let trimmedHost = connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)
        connectionHost = trimmedHost.isEmpty ? AppConstants.Connection.defaultHost : trimmedHost
        connectionPort = min(
            max(connectionPort, AppConstants.Connection.validPortRange.lowerBound),
            AppConstants.Connection.validPortRange.upperBound
        )
        defaults.set(connectionHost, forKey: "connectionHost")
        defaults.set(connectionPort, forKey: "connectionPort")
        await client.updateConnection(host: connectionHost, port: connectionPort)
        await refresh()
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
            try await applyCoreConfigurationChange(configURL: imageGenerationSettingsStore.configURL) {
                try imageGenerationSettingsStore.save(settings)
            }
            imageGenerationSettings = try imageGenerationSettingsStore.load()
            operationMessage =
                settings.usesCustomProvider
                ? "生图已切换到自定义 Provider"
                : "生图已切换到 GPT 账号自动路由"
            await refresh(showSpinner: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveVisionRouting(forceGPTVision: Bool) async -> Bool {
        do {
            try await applyCoreConfigurationChange(configURL: visionRoutingSettingsStore.configURL) {
                try visionRoutingSettingsStore.save(forceGPTVision: forceGPTVision)
            }
            self.forceGPTVision = forceGPTVision
            operationMessage = forceGPTVision ? "已强制使用 GPT 视觉旁路" : "已恢复模型原生多模态"
            await refresh(showSpinner: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyCoreConfigurationChange(
        configURL: URL,
        mutation: () throws -> Void
    ) async throws {
        let snapshot = try Data(contentsOf: configURL)
        do {
            if isOnline {
                try await client.stopProxy()
                try await Task.sleep(for: AppConstants.Service.gracefulStopDelay)
            }
            await coreManager.stop()
            try mutation()
            try await coreManager.start(port: connectionPort)
            try await waitForServiceReadiness(timeout: AppConstants.Service.restartTimeout)
        } catch {
            try? snapshot.write(to: configURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            await coreManager.stop()
            if coreManager.installationState.isInstalled {
                try? await coreManager.start(port: connectionPort)
                try? await waitForServiceReadiness(timeout: AppConstants.Service.restartTimeout)
            }
            throw error
        }
    }
}
