import Foundation

/// API channels: add, enable, test, and choose a default for common daily use.
/// Detailed provider behavior, deletion, and key-pool maintenance remain in the Core console.
///
/// Keys entered here live only in `pendingChannelKeys` for the current session — enough to add a
/// credential, never written to preferences, the event timeline, or any log. Reads come back from
/// the Core as a masked key, never as key material.
extension AppModel {
    func loadChannels() async {
        guard isOnline else { return }
        isLoadingChannels = true
        defer { isLoadingChannels = false }
        do {
            async let channelsResponse = client.channels()
            async let configResponse = client.config()
            channels = try await channelsResponse
            defaultChannelName = try await configResponse.defaultProvider
            // Masked key rows are the only credential view the shell shows.
            var pools: [String: ProviderKeyPool] = [:]
            for channel in channels where channel.usesCredentialForwarding == false {
                if let pool = try? await client.channelKeys(name: channel.name) { pools[channel.name] = pool }
            }
            channelKeyPools = pools
            channelErrorMessage = nil
        } catch {
            channelErrorMessage = error.localizedDescription
        }
    }

    func channelKey(for channel: String) -> String {
        pendingChannelKeys[channel] ?? ""
    }

    func setChannelKey(_ value: String, for channel: String) {
        // Never store a key outside this session-scoped dictionary.
        if value.isEmpty {
            pendingChannelKeys.removeValue(forKey: channel)
        } else {
            pendingChannelKeys[channel] = value
        }
    }

    /// Adds a credential to the channel's key pool, then drops it from memory.
    func saveChannelKey(_ channel: APIChannel, label: String? = nil) async {
        let key = channelKey(for: channel.name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        await performChannelChange {
            try await self.client.addChannelKey(name: channel.name, key: key, label: label)
        } completion: {
            self.pendingChannelKeys.removeValue(forKey: channel.name)
            self.operationMessage = L10n.tr("已为 \(channel.name) 添加 API Key")
            self.eventStore.append(.channelChanged, detail: channel.name)
        }
    }

    func addChannel(draft: ChannelDraft, apiKey: String) async -> ChannelCreationResult {
        guard isOnline else { return .failed(L10n.tr("Core 未连接，请启动代理后重试。")) }
        guard !isUpdatingChannels else { return .failed(L10n.tr("其他渠道操作正在保存，请稍后重试。")) }
        isUpdatingChannels = true
        defer { isUpdatingChannels = false }
        let client = self.client
        let creator = ChannelCreator(
            existingNames: { try await client.channels().map(\.name) },
            create: { try await client.createChannel(name: $0, payload: $1, setDefault: false) },
            addKey: { try await client.addChannelKey(name: $0, key: $1) },
            makeDefault: { try await client.setDefaultChannel(name: $0) }
        )
        let result = await creator.save(draft, key: apiKey)
        if result.didCreate {
            await loadChannels()
            await refresh(showSpinner: false)
            eventStore.append(.channelChanged)
        }
        switch result {
        case .saved: operationMessage = L10n.tr("渠道已添加")
        case .partial(let message): channelErrorMessage = message
        case .failed: break  // The sheet owns validation and save errors.
        }
        return result
    }

    func setChannelEnabled(_ channel: APIChannel, enabled: Bool) async {
        await performChannelChange {
            try await self.client.updateChannel(name: channel.name, patch: ChannelPatch(disabled: !enabled))
        } completion: {
            self.operationMessage = enabled ? L10n.tr("已启用 \(channel.name)") : L10n.tr("已停用 \(channel.name)")
        }
    }

    /// Sets the default channel. The Core accepts this only as a standalone field and refuses a
    /// disabled channel, so its error is surfaced verbatim.
    func setDefaultChannel(_ channel: APIChannel) async {
        await performChannelChange {
            try await self.client.setDefaultChannel(name: channel.name)
        } completion: {
            self.defaultChannelName = channel.name
            self.operationMessage = L10n.tr("已将 \(channel.name) 设为默认渠道")
        }
    }

    /// Probes the channel with the Core's own connectivity test. The Core resolves the credential
    /// from its own pool, so no key passes through the client here.
    func testChannel(_ channel: APIChannel) async {
        guard isOnline, !isTestingChannel else { return }
        isTestingChannel = true
        defer { isTestingChannel = false }
        do {
            channelProbeResults[channel.name] = try await client.testChannel(name: channel.name)
        } catch {
            channelProbeResults[channel.name] = ChannelProbeResult(
                ok: false,
                status: nil,
                message: error.localizedDescription,
                modelCount: nil
            )
        }
    }

    func isDefaultChannel(_ channel: APIChannel) -> Bool {
        channel.name == defaultChannelName
    }

    private func performChannelChange(
        _ change: () async throws -> Void,
        completion: @escaping () -> Void
    ) async {
        guard isOnline, !isUpdatingChannels else { return }
        isUpdatingChannels = true
        defer { isUpdatingChannels = false }
        do {
            try await change()
            await loadChannels()
            await refresh(showSpinner: false)
            completion()
            channelErrorMessage = nil
            errorMessage = nil
        } catch {
            channelErrorMessage = error.localizedDescription
        }
    }
}
