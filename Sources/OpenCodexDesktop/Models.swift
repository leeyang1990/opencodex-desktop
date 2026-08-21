import Foundation

enum SidebarDestination: String, CaseIterable, Identifiable {
    case overview
    case providers
    case accounts
    case models
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .providers: "Providers"
        case .accounts: "账号"
        case .models: "模型"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .providers: "point.3.connected.trianglepath.dotted"
        case .accounts: "person.2"
        case .models: "square.stack.3d.up"
        case .settings: "gearshape"
        }
    }
}

enum ConnectionState: Equatable {
    case checking
    case online
    case offline
    case unauthorized

    var label: String {
        switch self {
        case .checking: "正在连接"
        case .online: "服务正常"
        case .offline: "服务未运行"
        case .unauthorized: "需要授权"
        }
    }

    var colorName: String {
        switch self {
        case .checking: "orange"
        case .online: "green"
        case .offline: "secondary"
        case .unauthorized: "orange"
        }
    }
}

struct HealthResponse: Decodable {
    let service: String?
    let version: String?
    let status: String?
    let uptime: Double?
    let pid: Int?
    let port: Int?
}

struct ConfigSummary: Decodable {
    let port: Int?
    let hostname: String?
    let defaultProvider: String
    let codexAutoStart: Bool?
}

struct StartupHealth: Decodable {
    let autostartEnabled: Bool?
    let serviceInstalled: Bool?
    let serviceRunning: Bool?
    let shimInstalled: Bool?
}

struct CodexRuntime: Decodable {
    let path: String?
    let version: String?
    let source: String?
    let warning: String?
}

struct RuntimeSettings: Decodable {
    let timeZone: String?
    let codexAutoStart: Bool
    let port: Int?
    let hostname: String
    let streamMode: String
    let appOwnedMemoryBudgetMb: Int
    let codexAccountPickerEnabled: Bool
    let startupHealth: StartupHealth?
    let codexRuntime: CodexRuntime?
}

struct Provider: Decodable, Identifiable, Hashable {
    let name: String
    let adapter: String
    let baseUrl: String
    let defaultModel: String?
    let hasApiKey: Bool
    let hasHeaders: Bool?
    let allowPrivateNetwork: Bool
    let liveModels: Bool
    let models: [String]
    let contextWindow: Int?
    let modelContextWindows: [String: Int]
    let authMode: String?
    let apiKeyTransport: String?
    let disabled: Bool
    let codexAccountMode: String?

    var id: String { name }
    var displayModel: String { defaultModel?.isEmpty == false ? defaultModel! : "自动选择" }
    var displayAuth: String {
        switch authMode {
        case "key": "API Key"
        case "oauth": "OAuth"
        case "forward": "Codex 登录"
        case "local": "本地"
        default: "未设置"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, adapter, baseUrl, defaultModel, hasApiKey, hasHeaders
        case allowPrivateNetwork, liveModels, models, contextWindow, modelContextWindows, authMode
        case apiKeyTransport, disabled, codexAccountMode
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        adapter = try values.decode(String.self, forKey: .adapter)
        baseUrl = try values.decode(String.self, forKey: .baseUrl)
        defaultModel = try values.decodeIfPresent(String.self, forKey: .defaultModel)
        hasApiKey = try values.decodeIfPresent(Bool.self, forKey: .hasApiKey) ?? false
        hasHeaders = try values.decodeIfPresent(Bool.self, forKey: .hasHeaders)
        allowPrivateNetwork = try values.decodeIfPresent(Bool.self, forKey: .allowPrivateNetwork) ?? false
        liveModels = try values.decodeIfPresent(Bool.self, forKey: .liveModels) ?? true
        models = try values.decodeIfPresent([String].self, forKey: .models) ?? []
        contextWindow = try values.decodeIfPresent(Int.self, forKey: .contextWindow)
        modelContextWindows = try values.decodeIfPresent([String: Int].self, forKey: .modelContextWindows) ?? [:]
        authMode = try values.decodeIfPresent(String.self, forKey: .authMode)
        apiKeyTransport = try values.decodeIfPresent(String.self, forKey: .apiKeyTransport)
        disabled = try values.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        codexAccountMode = try values.decodeIfPresent(String.self, forKey: .codexAccountMode)
    }
}

struct ManagedModel: Decodable, Identifiable, Hashable {
    let provider: String
    let modelID: String
    let namespaced: String
    let disabled: Bool
    let native: Bool
    let custom: Bool
    let customID: String?
    let displayName: String?
    let inputModalities: [String]
    let contextWindow: Int?
    let maxInputTokens: Int?
    let contextCap: Int?
    let contextCapped: Bool
    let reasoningEfforts: [String]
    let defaultReasoningEffort: String?
    let parallelToolCalls: Bool?
    let supportsVerbosity: Bool?
    let supportsReasoningSummaries: Bool?
    let capabilities: [String]

    var id: String { namespaced }
    var title: String { displayName?.isEmpty == false ? displayName! : modelID }
    var supportsVision: Bool { inputModalities.contains("image") }
    var supportsAudio: Bool { inputModalities.contains("audio") }

    enum CodingKeys: String, CodingKey {
        case provider, namespaced, disabled, native, custom, customID = "customId"
        case displayName, inputModalities, contextWindow, maxInputTokens, contextCap
        case contextCapped, reasoningEfforts, defaultReasoningEffort, parallelToolCalls
        case supportsVerbosity, supportsReasoningSummaries, capabilities
        case modelID = "id"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decode(String.self, forKey: .provider)
        modelID = try values.decode(String.self, forKey: .modelID)
        namespaced = try values.decode(String.self, forKey: .namespaced)
        disabled = try values.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        native = try values.decodeIfPresent(Bool.self, forKey: .native) ?? false
        custom = try values.decodeIfPresent(Bool.self, forKey: .custom) ?? false
        customID = try values.decodeIfPresent(String.self, forKey: .customID)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName)
        inputModalities = try values.decodeIfPresent([String].self, forKey: .inputModalities) ?? []
        contextWindow = try values.decodeIfPresent(Int.self, forKey: .contextWindow)
        maxInputTokens = try values.decodeIfPresent(Int.self, forKey: .maxInputTokens)
        contextCap = try values.decodeIfPresent(Int.self, forKey: .contextCap)
        contextCapped = try values.decodeIfPresent(Bool.self, forKey: .contextCapped) ?? false
        reasoningEfforts = try values.decodeIfPresent([String].self, forKey: .reasoningEfforts) ?? []
        defaultReasoningEffort = try values.decodeIfPresent(String.self, forKey: .defaultReasoningEffort)
        parallelToolCalls = try values.decodeIfPresent(Bool.self, forKey: .parallelToolCalls)
        supportsVerbosity = try values.decodeIfPresent(Bool.self, forKey: .supportsVerbosity)
        supportsReasoningSummaries = try values.decodeIfPresent(Bool.self, forKey: .supportsReasoningSummaries)
        capabilities = try values.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }
}

struct SelectedModelsResponse: Decodable {
    let selected: [String: [String]]
    let available: [String: [String]]
    let liveModelCounts: [String: Int]

    enum CodingKeys: String, CodingKey { case selected, available, liveModelCounts }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selected = try values.decodeIfPresent([String: [String]].self, forKey: .selected) ?? [:]
        available = try values.decodeIfPresent([String: [String]].self, forKey: .available) ?? [:]
        liveModelCounts = try values.decodeIfPresent([String: Int].self, forKey: .liveModelCounts) ?? [:]
    }
}

struct ProviderContextCapsResponse: Decodable {
    let cap: Int?
    let value: Int?
    let caps: [String: Int]

    enum CodingKeys: String, CodingKey { case cap, value, caps }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cap = try values.decodeIfPresent(Int.self, forKey: .cap)
        value = try values.decodeIfPresent(Int.self, forKey: .value)
        caps = try values.decodeIfPresent([String: Int].self, forKey: .caps) ?? [:]
    }
}

struct ModelVisibilityTarget: Encodable {
    let id: String
    let native: Bool
}

struct CustomModelDraft: Equatable {
    var provider = ""
    var modelID = ""
    var displayName = ""
    var contextWindow = ""
    var supportsText = true
    var supportsImage = false
    var supportsAudio = false

    init() {}

    init(model: ManagedModel) {
        provider = model.provider
        modelID = model.modelID
        displayName = model.displayName ?? ""
        contextWindow = model.contextWindow.map(String.init) ?? ""
        supportsText = model.inputModalities.isEmpty || model.inputModalities.contains("text")
        supportsImage = model.inputModalities.contains("image")
        supportsAudio = model.inputModalities.contains("audio")
    }

    var parsedContextWindow: Int? {
        let normalized = contextWindow.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : Int(normalized)
    }

    var modalities: [String] {
        var result: [String] = []
        if supportsText { result.append("text") }
        if supportsImage { result.append("image") }
        if supportsAudio { result.append("audio") }
        return result
    }

    var validationMessage: String? {
        if provider.isEmpty { return "请选择 Provider" }
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID.isEmpty { return "请输入模型 ID" }
        if trimmedID.contains("/") { return "模型 ID 不能包含斜杠" }
        if displayName.contains("/") { return "显示名称不能包含斜杠" }
        if !contextWindow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            parsedContextWindow.map({ $0 > 0 }) != true
        {
            return "上下文窗口必须是正整数"
        }
        if modalities.isEmpty { return "至少选择一种输入类型" }
        return nil
    }
}

struct ProviderPresetResponse: Decodable {
    let providers: [ProviderPreset]
}

struct ProviderPreset: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let adapter: String
    let baseUrl: String
    let defaultModel: String?
    let auth: String
    let note: String?
    let keyOptional: Bool?
    let freeTier: Bool?
    let codexAccountMode: String?
}

struct ProviderTestResult: Decodable {
    let ok: Bool?
    let applicable: Bool?
    let latencyMs: Int?
    let models: Int?
    let message: String?
    let error: String?
    let reason: String?
}

struct APIAcknowledgement: Decodable {
    let success: Bool?
    let ok: Bool?
    let message: String?
    let catalogRefresh: CatalogRefreshDisposition?
}

struct CatalogRefreshDisposition: Decodable, Equatable {
    let status: String
    let changed: Bool?
    let degraded: Bool?
    let reason: String?
    let retryable: Bool?
    let partialWrite: Bool?

    var isCommitted: Bool { status == "committed" }
}

struct EmptyResponse: Decodable {}

enum AccountPoolStrategy: String, Codable, CaseIterable, Identifiable {
    case quota
    case roundRobin = "round-robin"
    case fillFirst = "fill-first"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quota: "额度优先"
        case .roundRobin: "轮询"
        case .fillFirst: "用完再切"
        }
    }

    var detail: String {
        switch self {
        case .quota: "新会话优先选择使用量较低的健康账号"
        case .roundRobin: "新会话依次分配到可用账号"
        case .fillFirst: "优先使用排序靠前的账号，达到阈值后再切换"
        }
    }
}

struct CodexAccountQuota: Decodable, Equatable {
    let fiveHourPercent: Double?
    let weeklyPercent: Double?
    let monthlyPercent: Double?
    let fiveHourResetAt: Double?
    let weeklyResetAt: Double?
    let monthlyResetAt: Double?
    let resetCredits: Int?
    let updatedAt: Double?
}

struct CodexAccountHealth: Decodable, Equatable {
    let status: String
    let until: String?
    let reason: String?
}

struct CodexAccount: Decodable, Identifiable, Equatable {
    let id: String
    let email: String
    let alias: String?
    let plan: String?
    let isMain: Bool
    let paused: Bool
    let priority: Int
    let hasCredential: Bool
    let needsReauth: Bool
    let quota: CodexAccountQuota?
    let health: CodexAccountHealth?
    let healthLabel: String?
    let healthSummary: String?

    var displayName: String {
        if let alias, !alias.isEmpty { return alias }
        return isMain ? "Codex 主账号" : email
    }

    var effectiveID: String { isMain ? "__main__" : id }
    var isHealthy: Bool { !paused && !needsReauth && (health?.status == nil || health?.status == "healthy") }
}

struct CodexAccountListResponse: Decodable {
    let accounts: [CodexAccount]
}

struct CodexAccountPoolStatus: Decodable, Equatable {
    let activeCodexAccountId: String?
    let pinned: Bool
    let pinnedAccountId: String?
    let autoSwitchThreshold: Int
    let upstreamFailoverThreshold: Int
    let accountPoolStrategy: AccountPoolStrategy
    let accountPoolStickyLimit: Int
}

struct CodexAccountMutationResponse: Decodable {
    let ok: Bool?
    let activeCodexAccountId: String?
    let accountPoolStrategy: AccountPoolStrategy?
    let accountPoolStickyLimit: Int?
}

struct CodexLoginStartResponse: Decodable {
    let ok: Bool?
    let flowId: String
    let url: String?
    let instructions: String?
}

struct CodexLoginStatusResponse: Decodable {
    let status: String
    let accountId: String?
    let email: String?
    let error: String?
    let catalogRefreshPending: Bool?
}

enum AccountLoginState: Equatable {
    case idle
    case starting
    case waiting(flowId: String, url: String?)
    case completed(String?)
    case failed(String)

    var isInProgress: Bool {
        switch self {
        case .starting, .waiting: true
        default: false
        }
    }
}

struct ProviderDraft: Equatable {
    var name = ""
    var adapter = "openai-chat"
    var baseUrl = ""
    var authMode = "key"
    var apiKey = ""
    var apiKeyTransport = "bearer"
    var defaultModel = ""
    var allowPrivateNetwork = false
    var liveModels = true
    var setDefault = false

    init() {}

    init(provider: Provider) {
        name = provider.name
        adapter = provider.adapter
        baseUrl = provider.baseUrl
        authMode = provider.authMode ?? "key"
        apiKeyTransport = provider.apiKeyTransport ?? "bearer"
        defaultModel = provider.defaultModel ?? ""
        allowPrivateNetwork = provider.allowPrivateNetwork
        liveModels = provider.liveModels
    }

    mutating func apply(_ preset: ProviderPreset) {
        name = preset.id == "custom" ? "" : preset.id
        adapter = preset.adapter
        baseUrl = preset.baseUrl
        authMode = preset.auth
        defaultModel = preset.defaultModel ?? ""
        allowPrivateNetwork = preset.auth == "local"
        liveModels = true
        apiKey = ""
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入 Provider 名称" }
        let valid = name.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
        if !valid { return "名称只能包含字母、数字、点、下划线和连字符" }
        if adapter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请选择适配器" }
        guard let url = URL(string: baseUrl), let scheme = url.scheme, ["http", "https"].contains(scheme),
            url.host != nil
        else {
            return "请输入有效的 HTTP(S) 地址"
        }
        return nil
    }

    var transportSecurityWarning: String? {
        guard let url = URL(string: baseUrl),
            url.scheme?.lowercased() == "http",
            let host = url.host?.lowercased(),
            !AppConstants.Connection.loopbackHosts.contains(host)
        else { return nil }
        return "该 Provider 使用未加密 HTTP；API Key 和请求内容可能被网络中的其他设备读取。"
    }
}
