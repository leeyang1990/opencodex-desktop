import Foundation

struct ImageGenerationSettings: Equatable {
    var usesCustomProvider: Bool
    var provider: String
    var timeoutMs: Int

    static let defaults = ImageGenerationSettings(
        usesCustomProvider: false,
        provider: "",
        timeoutMs: 300_000
    )
}

struct ImageGenerationSettingsStore {
    private static let managedNotePrefix = "OpenCodex Desktop image provider for "
    let configURL: URL

    init(configURL: URL = CoreInstallationPaths.dataDirectory.appendingPathComponent("config.json")) {
        self.configURL = configURL
    }

    func load() throws -> ImageGenerationSettings {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return .defaults }
        let data = try Data(contentsOf: configURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let images = root["images"] as? [String: Any]
        let routedProvider = (images?["provider"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let providers = root["providers"] as? [String: Any]
        let routedConfig = providers?[routedProvider] as? [String: Any]
        let note = routedConfig?["note"] as? String
        let provider = note?.hasPrefix(Self.managedNotePrefix) == true
            ? String(note!.dropFirst(Self.managedNotePrefix.count))
            : routedProvider
        let timeout = images?["timeoutMs"] as? Int ?? ImageGenerationSettings.defaults.timeoutMs
        return ImageGenerationSettings(
            usesCustomProvider: !routedProvider.isEmpty,
            provider: provider,
            timeoutMs: timeout
        )
    }

    func save(_ settings: ImageGenerationSettings) throws {
        let data = try Data(contentsOf: configURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var images = root["images"] as? [String: Any] ?? [:]
        var providers = root["providers"] as? [String: Any] ?? [:]
        removeUnusedManagedProvider(images["provider"] as? String, from: &providers)
        if settings.usesCustomProvider {
            let providerName = settings.provider.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !providerName.isEmpty else { throw ImageGenerationSettingsError.missingProvider }
            guard var provider = providers[providerName] as? [String: Any] else {
                throw ImageGenerationSettingsError.providerNotFound(providerName)
            }
            let adapter = provider["adapter"] as? String
            let authMode = provider["authMode"] as? String
            if adapter == "openai-responses" && (authMode == nil || authMode == "key") {
                images["provider"] = providerName
            } else {
                let managedName = uniqueManagedName(for: providerName, providers: providers)
                provider["adapter"] = "openai-responses"
                provider["authMode"] = "key"
                provider["liveModels"] = false
                provider["note"] = Self.managedNotePrefix + providerName
                providers[managedName] = provider
                images["provider"] = managedName
            }
        } else {
            images.removeValue(forKey: "provider")
        }
        images["timeoutMs"] = min(max(settings.timeoutMs, 1_000), 300_000)
        root["images"] = images
        root["providers"] = providers
        let encoded = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try encoded.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private func uniqueManagedName(for source: String, providers: [String: Any]) -> String {
        let preferred = "\(source).images"
        if let existing = providers[preferred] as? [String: Any],
           existing["note"] as? String == Self.managedNotePrefix + source {
            return preferred
        }
        if providers[preferred] == nil { return preferred }
        return "\(source).opencodex-images"
    }

    private func removeUnusedManagedProvider(_ name: String?, from providers: inout [String: Any]) {
        guard let name, let provider = providers[name] as? [String: Any],
              (provider["note"] as? String)?.hasPrefix(Self.managedNotePrefix) == true else { return }
        providers.removeValue(forKey: name)
    }
}

enum ImageGenerationSettingsError: LocalizedError {
    case missingProvider
    case providerNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingProvider: "请选择生图 Provider"
        case let .providerNotFound(name): "找不到 Provider：\(name)"
        }
    }
}

struct VisionRoutingSettingsStore {
    let configURL: URL
    let stateURL: URL

    init(
        configURL: URL = CoreInstallationPaths.dataDirectory.appendingPathComponent("config.json"),
        stateURL: URL = CoreInstallationPaths.applicationSupportDirectory.appendingPathComponent("vision-routing.json")
    ) {
        self.configURL = configURL
        self.stateURL = stateURL
    }

    func load() -> Bool {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(State.self, from: data),
              state.forceGPTVision,
              let configData = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              let providers = root["providers"] as? [String: Any] else { return false }
        return providers.values.contains { value in
            guard let provider = value as? [String: Any] else { return false }
            return (provider["noVisionModels"] as? [String])?.isEmpty == false
        }
    }

    func save(forceGPTVision: Bool) throws {
        let data = try Data(contentsOf: configURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var providers = root["providers"] as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for (name, value) in providers {
            guard var provider = value as? [String: Any] else { continue }
            if forceGPTVision {
                let models = provider["models"] as? [String] ?? []
                if !models.isEmpty { provider["noVisionModels"] = Array(Set(models)).sorted() }
            } else {
                provider.removeValue(forKey: "noVisionModels")
            }
            providers[name] = provider
        }
        root["providers"] = providers
        let encoded = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try encoded.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(State(forceGPTVision: forceGPTVision)).write(to: stateURL, options: .atomic)
    }

    private struct State: Codable {
        let forceGPTVision: Bool
    }
}
