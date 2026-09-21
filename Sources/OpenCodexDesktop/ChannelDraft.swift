import Foundation

enum ChannelProtocol: String, CaseIterable, Identifiable {
    case chat = "openai-chat", responses = "openai-responses", anthropic, google
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chat: return "OpenAI Chat Completions"
        case .responses: return "OpenAI Responses"
        case .anthropic: return "Anthropic Messages"
        case .google: return "Google Gemini"
        }
    }
    var hint: String {
        switch self {
        case .chat: return "兼容 OpenAI 的渠道（如 New API）通常选此项。"
        case .responses: return "渠道需支持 /responses 接口。"
        case .anthropic: return "渠道需支持 /messages 接口。"
        case .google: return "Gemini 原生协议；填写根地址，不含 /v1beta。"
        }
    }
    var placeholder: String {
        switch self {
        case .chat, .responses: return "https://example.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com"
        }
    }
}

/// Non-secret form values only. Credentials stay in the sheet and travel separately.
struct ChannelDraft {
    var name = ""
    var transport: ChannelProtocol = .chat
    var baseURL = ""
    var requiresKey = true
    var automaticModels = true
    var modelText = ""
    var defaultModel = ""
    var allowPrivateNetwork = false
    var note = ""
    var setDefault = false

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var modelIDs: [String] {
        var seen = Set<String>()
        return modelText.components(separatedBy: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，")))
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    var payload: ChannelPayload {
        ChannelPayload(
            adapter: transport.rawValue,
            baseUrl: baseURL.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
                of: "/+$", with: "", options: .regularExpression),
            liveModels: automaticModels,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            allowPrivateNetwork: allowPrivateNetwork,
            authMode: requiresKey ? "key" : "local",
            models: automaticModels ? nil : modelIDs,
            defaultModel: defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
    }

    func validationError(key: String, existingNames: [String]) -> String? {
        let name = trimmedName
        guard name.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9])?$", options: .regularExpression) != nil
        else {
            return "名称需为 1–64 位字母、数字、点、下划线或短横线，首尾为字母或数字。"
        }
        if ["__proto__", "prototype", "constructor", "policy", "openai", "chatgpt", "openai-multi"].contains(
            name.lowercased())
        {
            return "此名称由 Core 保留，请换一个名称。"
        }
        if existingNames.contains(name) { return "同名渠道已存在，请换一个名称。" }
        let rawURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.contains(where: { $0.isWhitespace }),
            let url = URLComponents(string: rawURL),
            ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host, !host.isEmpty,
            url.url != nil, url.port.map({ (1...65535).contains($0) }) ?? true
        else {
            return "请输入完整的 HTTP 或 HTTPS Base URL。"
        }
        if url.user != nil || url.password != nil || url.query != nil || url.fragment != nil {
            return "Base URL 不能包含账号、密码、查询参数或片段；密钥请填在 API Key 中。"
        }
        let endpoint = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if transport == .google && ["v1", "v1beta"].contains(where: { endpoint == $0 || endpoint.hasSuffix("/" + $0) })
        {
            return "Gemini 请填写根地址，Core 会自动添加 /v1beta。"
        }
        if ["chat/completions", "responses", "messages", "models"].contains(where: {
            endpoint == $0 || endpoint.hasSuffix("/" + $0)
        }) {
            return "请填写接口根地址，不要包含 /chat/completions、/responses、/messages 或 /models。"
        }
        if requiresKey && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请输入 API Key；无鉴权的本地服务请选择「无需密钥」。"
        }
        if !requiresKey && transport != .chat { return "无需密钥仅用于 OpenAI Chat 兼容的本地服务。" }
        if !automaticModels && modelIDs.isEmpty { return "请至少填写一个模型 ID。" }
        let selected = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !automaticModels && !selected.isEmpty && !modelIDs.contains(selected) {
            return "默认模型必须包含在模型列表中。"
        }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}

enum ChannelCreationResult: Equatable {
    case saved
    case failed(String)
    case partial(String)

    var didCreate: Bool {
        switch self {
        case .saved, .partial: return true;
        case .failed: return false
        }
    }
}

/// POST is an upsert, not an atomic create. Re-read names immediately before it; never replay
/// creation after a later step fails. Only switch the default after the credential is stored.
@MainActor
struct ChannelCreator {
    var existingNames: () async throws -> [String]
    var create: (String, ChannelPayload) async throws -> Void
    var addKey: (String, String) async throws -> Void
    var makeDefault: (String) async throws -> Void

    func save(_ draft: ChannelDraft, key: String) async -> ChannelCreationResult {
        if let error = draft.validationError(key: key, existingNames: []) { return .failed(error) }
        do {
            let names = try await existingNames()
            if let error = draft.validationError(key: key, existingNames: names) { return .failed(error) }
        } catch {
            return .failed("无法检查现有渠道，请确认 Core 连接后重试。")
        }
        do { try await create(draft.trimmedName, draft.payload) } catch {
            // A lost acknowledgement may still mean Core saved it. A new attempt always checks
            // names again, so it cannot silently overwrite that channel.
            return .failed("未确认渠道保存成功。请刷新渠道列表后再试，并检查地址、协议及内网访问设置。")
        }
        if draft.requiresKey {
            do { try await addKey(draft.trimmedName, key.trimmingCharacters(in: .whitespacesAndNewlines)) } catch {
                return .partial("渠道已创建，但密钥写入未确认，未切换默认渠道。请关闭后检查该渠道的 Key 状态，必要时点「添加 Key」。")
            }
        }
        if draft.setDefault {
            do { try await makeDefault(draft.trimmedName) } catch {
                return .partial("渠道已保存，但设为默认未确认。请关闭后检查默认状态，必要时重新设置。")
            }
        }
        return .saved
    }
}
