import Foundation

/// Identifier for the auxiliary windows that are not part of the tab strip.
enum ShellWindow {
    static let main = "main"
    static let diagnostics = "diagnostics"
}

/// Main-window pages, including Desktop settings. Diagnostics remains an auxiliary tool.
enum SidebarDestination: String, CaseIterable, Identifiable {
    case home
    case accounts
    case channels
    case subagents
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "概览"
        case .accounts: "账号"
        case .channels: "渠道"
        case .subagents: "子代理"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .accounts: "person.2"
        case .channels: "server.rack"
        case .subagents: "person.3.sequence"
        case .settings: "slider.horizontal.3"
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

struct CodexRuntime: Decodable {
    let path: String?
    let version: String?
    let source: String?
    let warning: String?
}

struct StartupHealth: Decodable {
    let routingKind: String?
    let routingInjected: Bool?
}

struct RuntimeSettings: Decodable {
    let codexRuntime: CodexRuntime?
    let startupHealth: StartupHealth?

    /// Whether the Core reports that plain Codex currently routes through it.
    ///
    /// Core omits the field on older builds; `nil` means "unknown", not "off".
    var isCodexRoutingInjected: Bool? { startupHealth?.routingInjected }
}

struct APIAcknowledgement: Decodable {
    let success: Bool?
    let ok: Bool?
    let message: String?
}

/// One row of `GET /api/models`, the same list the console's model manager renders.
struct ManagedModel: Decodable, Identifiable, Equatable {
    let provider: String
    let id: String
    let namespaced: String
    let disabled: Bool
    /// Requests to `openai` travel natively; every other provider is routed through the proxy.
    let native: Bool?
    let inputModalities: [String]?

    var isNative: Bool { native == true }
    var supportsImages: Bool { inputModalities?.contains("image") ?? false }
    /// The visibility write requires the same native flag the row was listed with.
    var nativeFlag: Bool { isNative }
}

struct ProviderSummary: Identifiable, Equatable {
    let id: String
    let adapter: String?
    let baseURL: String?
    let hasAPIKey: Bool
    let authMode: String?
    let note: String?
    let liveModels: Bool
    let codexAccountMode: String?
    let isDefault: Bool
}

extension ManagedModel {
    /// The id the visibility endpoint stores and compares.
    ///
    /// `namespaced` is a display form that already carries the provider prefix, while the write
    /// path stores `provider/<id>` internally. Sending `namespaced` for a routed row therefore
    /// persists `new-api/new-api/<id>`, which no later read compares equal to — the switch would
    /// look like it worked and silently do nothing. `id` is the value both paths agree on.
    var selector: ModelVisibilityTarget { ModelVisibilityTarget(id: id, native: nativeFlag) }
}

struct ModelVisibilityTarget: Codable, Equatable {
    let id: String
    let native: Bool
}

struct ModelVisibilityRequest: Encodable {
    let scope: String
    let provider: String
    let enabled: Bool
    let targets: [ModelVisibilityTarget]
}

/// The subset of `GET /api/config` the shell summarizes. Credentials are never read or shown:
/// the endpoint reports only whether a key exists.
struct CoreConfig: Decodable {
    let port: Int?
    let defaultProvider: String?
    let codexAutoStart: Bool?
    let providers: [String: CoreConfigProvider]?
}

struct CoreConfigProvider: Decodable {
    let adapter: String?
    let baseUrl: String?
    let hasApiKey: Bool?
    let authMode: String?
    let note: String?
    let liveModels: Bool?
    let codexAccountMode: String?
}

struct EmptyResponse: Decodable {}

// MARK: - Aggregated usage

/// Seven-day aggregate returned by the Core. This deliberately models statistics only: request
/// contents and account identity never enter the Desktop process.
struct UsageReport: Decodable, Equatable {
    let range: String
    let generatedAt: Int64?
    let summary: UsageSummary
    let days: [UsageDay]
    let models: [UsageModel]
}

struct UsageSummary: Decodable, Equatable {
    let requests: Int
    let measuredRequests: Int
    let totalTokens: Int64
    let coverageRatio: Double
    let estimatedCostUsd: Double?
}

struct UsageDay: Decodable, Identifiable, Equatable {
    let date: String
    let requests: Int
    let measuredRequests: Int
    let totalTokens: Int64

    var id: String { date }
    var shortDate: String {
        guard let value = Self.parser.date(from: date) else { return date }
        return Self.label.string(from: value)
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let label: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter
    }()
}

struct UsageModel: Decodable, Identifiable, Equatable {
    let provider: String
    let model: String
    let requests: Int
    let totalTokens: Int64

    var id: String { "\(provider)/\(model)" }
}

// MARK: - Codex accounts and scheduling

/// One row of `GET /api/codex-auth/accounts`.
struct CodexAccount: Decodable, Identifiable, Equatable {
    let id: String
    let email: String?
    let plan: String?
    let logLabel: String?
    let isMain: Bool?
    let paused: Bool?
    let priority: Int?
    let hasCredential: Bool?
    let needsReauth: Bool?
    let quota: AccountQuota?
    let health: AccountHealth?
    let healthLabel: String?
    let healthSummary: String?

    var isPaused: Bool { paused == true }
    var isHealthy: Bool { (health?.status ?? "healthy") == "healthy" }
    var displayName: String { logLabel ?? email ?? id }

    /// The account the Codex CLI uses when no pool account is pinned.
    static let mainID = "__main__"
}

struct AccountQuota: Decodable, Equatable {
    let weeklyPercent: Double?
    let weeklyResetAt: Int?
    let resetCredits: Int?
}

struct AccountHealth: Decodable, Equatable {
    let status: String?
}

/// Scheduling state from `GET /api/codex-auth/active`.
struct CodexAccountScheduling: Decodable, Equatable {
    let activeCodexAccountId: String?
    let pinned: Bool?
    let pinnedAccountId: String?
    let autoSwitchThreshold: Int?
    let upstreamFailoverThreshold: Int?
    let accountPoolStrategy: String?
    let accountPoolStickyLimit: Int?

    /// Automatic switching is off when the threshold is 0, matching the Core's own contract.
    var isAutoSwitchEnabled: Bool { (autoSwitchThreshold ?? 0) > 0 }

    static let strategies = ["quota", "round-robin", "fill-first"]

    static func strategyTitle(_ raw: String?) -> String {
        switch raw {
        case "quota": "按额度"
        case "round-robin": "轮询"
        case "fill-first": "用尽再换"
        default: raw ?? "默认"
        }
    }
}

struct CodexLoginStatus: Decodable, Equatable {
    let status: String?
    let flowId: String?
    let accountId: String?
    let email: String?
    let error: String?
}

// MARK: - API channels

/// One row of `GET /api/providers`.
struct APIChannel: Decodable, Identifiable, Equatable {
    let name: String
    let adapter: String?
    let baseUrl: String?
    let hasApiKey: Bool?
    let hasHeaders: Bool?
    let allowPrivateNetwork: Bool?
    let liveModels: Bool?
    let authMode: String?
    let disabled: Bool?
    let note: String?
    let models: [String]?
    let codexAccountMode: String?
    let discovery: ChannelDiscovery?

    var id: String { name }
    var isDisabled: Bool { disabled == true }
    var modelCount: Int { models?.count ?? 0 }
    /// `forward` channels reuse the Codex login instead of a stored key.
    var usesCredentialForwarding: Bool { authMode == "forward" }
}

struct ChannelDiscovery: Decodable, Equatable {
    let status: String?
    let reason: String?
    let httpStatus: Int?
}

struct ChannelProbeResult: Decodable, Equatable {
    let ok: Bool?
    let status: Int?
    let message: String?
    let modelCount: Int?
}

/// Body for `POST /api/providers`: the new channel is nested under `provider`.
struct ChannelPayload: Encodable {
    var adapter: String
    var baseUrl: String
    var disabled: Bool?
    var liveModels: Bool?
    var note: String?
    var allowPrivateNetwork: Bool?
    var authMode: String?
    var models: [String]?
    var defaultModel: String?
}

/// Body for `PATCH /api/providers?name=…`: a flat field mask.
///
/// The Core applies recognized top-level fields onto the existing provider and rejects an
/// unknown-body shape with "no recognized fields to update". API keys are deliberately absent:
/// they are written through the provider key endpoints and cannot be patched here.
struct ChannelPatch: Encodable {
    var adapter: String?
    var baseUrl: String?
    var disabled: Bool?
    var liveModels: Bool?
    var note: String?

    var isEmpty: Bool {
        adapter == nil && baseUrl == nil && disabled == nil && liveModels == nil && note == nil
    }
}

/// One credential in a provider's key pool, from `GET /api/providers/keys?name=…`.
///
/// The Core returns the masked form only, e.g. `{"id":"a0e62070","masked":"sk-Q****Jpbm","active":true}`.
struct ProviderKey: Decodable, Identifiable, Equatable {
    let id: String
    let masked: String?
    let active: Bool?
}

struct ProviderKeyPool: Decodable, Equatable {
    let activeId: String?
    let keys: [ProviderKey]
}

// MARK: - Subagents

/// `GET /api/subagent-models`: at most five chosen models for spawned subagents.
struct SubagentSelection: Decodable, Equatable {
    let chosen: [String]
    let available: [String]

    /// The Core silently truncates beyond five, so the client must cap before writing.
    static let maximumChosen = 5
}
