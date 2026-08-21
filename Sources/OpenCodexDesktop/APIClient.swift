import Foundation

enum OpenCodexAPIError: LocalizedError, Equatable {
    case invalidAddress
    case remoteManagementUnsupported
    case offline
    case missingAdminToken
    case unauthorized
    case server(status: Int, message: String)
    case invalidResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "连接地址无效"
        case .remoteManagementUnsupported: "客户端只允许连接本机回环地址，以防管理令牌被发送到其他设备"
        case .offline: "OpenCodex 服务未运行"
        case .missingAdminToken: "找不到本机管理令牌，请先启动一次 OpenCodex"
        case .unauthorized: "管理令牌无效，请检查 OpenCodex 配置"
        case let .server(_, message): message
        case .invalidResponse: "服务返回了无法识别的数据"
        case let .transport(message): message
        }
    }
}

struct AdminTokenProvider {
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    var tokenFileURL: URL {
        if let configuredHome = environment["OPENCODEX_HOME"], !configuredHome.isEmpty {
            return URL(fileURLWithPath: configuredHome, isDirectory: true)
                .appendingPathComponent("admin-api-token", isDirectory: false)
        }
        let managed = CoreInstallationPaths.dataDirectory.appendingPathComponent("admin-api-token", isDirectory: false)
        if FileManager.default.fileExists(atPath: managed.path) {
            return managed
        }
        return
            homeDirectory
            .appendingPathComponent(".opencodex", isDirectory: true)
            .appendingPathComponent("admin-api-token", isDirectory: false)
    }

    func load() -> String? {
        if let environmentToken = environment["OPENCODEX_ADMIN_AUTH_TOKEN"]?.trimmingCharacters(
            in: .whitespacesAndNewlines),
            !environmentToken.isEmpty
        {
            return environmentToken
        }
        guard
            let values = try? tokenFileURL.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            (values.fileSize ?? 513) <= 512,
            let data = try? Data(contentsOf: tokenFileURL),
            data.count <= 512,
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            token.range(of: #"^ocx_admin_[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        return token
    }
}

actor OpenCodexAPIClient {
    private let session: URLSession
    private let tokenProvider: AdminTokenProvider
    private var host: String
    private var port: Int

    init(
        host: String,
        port: Int,
        session: URLSession = .shared,
        tokenProvider: AdminTokenProvider = AdminTokenProvider()
    ) {
        self.host = host
        self.port = port
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func updateConnection(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func baseURL() throws -> URL {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard AppConstants.Connection.loopbackHosts.contains(normalizedHost) else {
            throw OpenCodexAPIError.remoteManagementUnsupported
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = normalizedHost
        components.port = port
        guard let url = components.url else { throw OpenCodexAPIError.invalidAddress }
        return url
    }

    func health() async throws -> HealthResponse {
        try await request(path: "/readyz", authenticated: false)
    }

    func providers() async throws -> [Provider] {
        try await request(path: "/api/providers")
    }

    func config() async throws -> ConfigSummary {
        try await request(path: "/api/config")
    }

    func settings() async throws -> RuntimeSettings {
        try await request(path: "/api/settings")
    }

    func presets() async throws -> [ProviderPreset] {
        let response: ProviderPresetResponse = try await request(path: "/api/provider-presets")
        return response.providers
    }

    func models() async throws -> [ManagedModel] {
        try await request(path: "/api/models")
    }

    func selectedModels() async throws -> SelectedModelsResponse {
        try await request(path: "/api/selected-models")
    }

    func providerContextCaps() async throws -> ProviderContextCapsResponse {
        try await request(path: "/api/provider-context-caps")
    }

    func setModelVisibility(
        provider: String,
        targets: [ModelVisibilityTarget],
        enabled: Bool,
        wholeProvider: Bool = false
    ) async throws {
        struct Body: Encodable {
            let scope: String
            let provider: String
            let targets: [ModelVisibilityTarget]
            let enabled: Bool
        }
        let _: APIAcknowledgement = try await request(
            path: "/api/model-visibility",
            method: "PUT",
            body: Body(
                scope: wholeProvider ? "provider" : "models",
                provider: provider,
                targets: targets,
                enabled: enabled
            )
        )
    }

    func createCustomModel(_ draft: CustomModelDraft) async throws {
        struct Body: Encodable {
            let provider: String
            let modelId: String
            let displayName: String?
            let contextWindow: Int?
            let inputModalities: [String]
        }
        let _: APIAcknowledgement = try await request(
            path: "/api/custom-models",
            method: "POST",
            body: Body(
                provider: draft.provider,
                modelId: draft.modelID.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                contextWindow: draft.parsedContextWindow,
                inputModalities: draft.modalities
            )
        )
    }

    func updateCustomModel(id: String, draft: CustomModelDraft) async throws {
        struct Body: Encodable {
            let modelId: String
            let displayName: String
            let contextWindow: Int
            let inputModalities: [String]
        }
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: APIAcknowledgement = try await request(
            path: "/api/custom-models/\(encodedID)",
            method: "PUT",
            body: Body(
                modelId: draft.modelID.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                contextWindow: draft.parsedContextWindow ?? 0,
                inputModalities: draft.modalities
            )
        )
    }

    func deleteCustomModel(id: String) async throws {
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: APIAcknowledgement = try await request(
            path: "/api/custom-models/\(encodedID)",
            method: "DELETE",
            body: Optional<String>.none
        )
    }

    func setProviderContextCap(provider: String, enabled: Bool, value: Int? = nil) async throws
        -> ProviderContextCapsResponse
    {
        struct Body: Encodable {
            let provider: String
            let enabled: Bool
            let value: Int?
        }
        return try await request(
            path: "/api/provider-context-caps",
            method: "PUT",
            body: Body(provider: provider, enabled: enabled, value: value)
        )
    }

    func setGlobalContextCap(value: Int, applyToAll: Bool) async throws -> ProviderContextCapsResponse {
        struct Body: Encodable { let value: Int; let setAll: Bool }
        return try await request(
            path: "/api/provider-context-caps",
            method: "PUT",
            body: Body(value: value, setAll: applyToAll)
        )
    }

    func setProviderDefaultModel(provider: String, modelID: String) async throws {
        struct Body: Encodable { let defaultModel: String }
        let name = provider.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? provider
        let _: APIAcknowledgement = try await request(
            path: "/api/providers?name=\(name)",
            method: "PATCH",
            body: Body(defaultModel: modelID)
        )
    }

    func createProvider(_ draft: ProviderDraft) async throws {
        struct ProviderBody: Encodable {
            let adapter: String
            let baseUrl: String
            let authMode: String?
            let apiKey: String?
            let apiKeyTransport: String?
            let defaultModel: String?
            let allowPrivateNetwork: Bool?
            let liveModels: Bool
        }
        struct Body: Encodable {
            let name: String
            let provider: ProviderBody
            let setDefault: Bool
        }
        let apiKeyTransport =
            draft.adapter == "anthropic" && draft.authMode == "key"
            ? draft.apiKeyTransport : nil
        let body = Body(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: ProviderBody(
                adapter: draft.adapter,
                baseUrl: draft.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                authMode: draft.authMode.isEmpty ? nil : draft.authMode,
                apiKey: draft.apiKey.isEmpty ? nil : draft.apiKey,
                apiKeyTransport: apiKeyTransport,
                defaultModel: draft.defaultModel.isEmpty ? nil : draft.defaultModel,
                allowPrivateNetwork: draft.allowPrivateNetwork ? true : nil,
                liveModels: draft.liveModels
            ),
            setDefault: draft.setDefault
        )
        let _: APIAcknowledgement = try await request(path: "/api/providers", method: "POST", body: body)
    }

    func updateProvider(original: Provider, draft: ProviderDraft) async throws {
        struct Body: Encodable {
            let adapter: String
            let baseUrl: String
            let authMode: String
            let apiKeyTransport: String?
            let defaultModel: String
            let allowPrivateNetwork: Bool
            let liveModels: Bool
        }
        let queryName = original.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? original.name
        let body = Body(
            adapter: draft.adapter,
            baseUrl: draft.baseUrl,
            authMode: draft.authMode,
            apiKeyTransport: draft.adapter == "anthropic" && draft.authMode == "key" ? draft.apiKeyTransport : nil,
            defaultModel: draft.defaultModel,
            allowPrivateNetwork: draft.allowPrivateNetwork,
            liveModels: draft.liveModels
        )
        let _: APIAcknowledgement = try await request(
            path: "/api/providers?name=\(queryName)", method: "PATCH", body: body)
        if !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await addAPIKey(provider: original.name, key: draft.apiKey)
        }
    }

    func addAPIKey(provider: String, key: String) async throws {
        struct Body: Encodable { let name: String; let key: String }
        let _: APIAcknowledgement = try await request(
            path: "/api/providers/keys",
            method: "POST",
            body: Body(name: provider, key: key)
        )
    }

    func setProviderEnabled(_ provider: Provider, enabled: Bool) async throws {
        struct Body: Encodable { let disabled: Bool }
        let name = provider.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? provider.name
        let response: APIAcknowledgement = try await request(
            path: "/api/providers?name=\(name)",
            method: "PATCH",
            body: Body(disabled: !enabled)
        )
        // Management mutations first attempt the bounded catalog-only convergence path. The
        // embedded runtime can legitimately miss that short deadline (or have no admitted
        // generation yet), while the provider mutation itself has already been persisted. Do not
        // report a fully successful toggle with a stale Codex picker: fall back to the explicit
        // full sync whenever the catalog mutation was not actually committed.
        if response.catalogRefresh?.isCommitted != true {
            try await syncCodexIntegration()
        }
    }

    func syncCodexIntegration() async throws {
        let response: APIAcknowledgement = try await request(
            path: "/api/sync",
            method: "POST",
            body: Optional<String>.none
        )
        if response.ok == false || response.success == false {
            throw OpenCodexAPIError.server(status: 500, message: response.message ?? "Codex 模型目录同步失败")
        }
    }

    func setDefaultProvider(_ provider: Provider) async throws {
        struct Body: Encodable { let setDefault = true }
        let name = provider.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? provider.name
        let _: APIAcknowledgement = try await request(
            path: "/api/providers?name=\(name)",
            method: "PATCH",
            body: Body()
        )
    }

    func deleteProvider(_ provider: Provider) async throws {
        let name = provider.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? provider.name
        let _: APIAcknowledgement = try await request(path: "/api/providers?name=\(name)", method: "DELETE")
    }

    func testProvider(_ provider: Provider) async throws -> ProviderTestResult {
        let name = provider.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? provider.name
        return try await request(path: "/api/providers/test?name=\(name)", method: "POST", body: Optional<String>.none)
    }

    func updateSettings(
        codexAutoStart: Bool,
        streamMode: String,
        memoryBudget: Int,
        accountPicker: Bool
    ) async throws {
        struct Body: Encodable {
            let codexAutoStart: Bool
            let streamMode: String
            let appOwnedMemoryBudgetMb: Int
            let codexAccountPickerEnabled: Bool
        }
        let _: APIAcknowledgement = try await request(
            path: "/api/settings",
            method: "PUT",
            body: Body(
                codexAutoStart: codexAutoStart,
                streamMode: streamMode,
                appOwnedMemoryBudgetMb: memoryBudget,
                codexAccountPickerEnabled: accountPicker
            )
        )
    }

    func stopProxy() async throws {
        let _: APIAcknowledgement = try await request(path: "/api/stop", method: "POST", body: Optional<String>.none)
    }

    func codexAccounts(refreshQuota: Bool = false) async throws -> [CodexAccount] {
        let suffix = refreshQuota ? "?refresh=1" : ""
        let response: CodexAccountListResponse = try await request(path: "/api/codex-auth/accounts\(suffix)")
        return response.accounts
    }

    func codexAccountPoolStatus() async throws -> CodexAccountPoolStatus {
        try await request(path: "/api/codex-auth/active")
    }

    func selectCodexAccount(_ accountId: String?) async throws {
        struct Body: Encodable { let accountId: String? }
        let _: CodexAccountMutationResponse = try await request(
            path: "/api/codex-auth/active",
            method: "PUT",
            body: Body(accountId: accountId)
        )
    }

    func setCodexAccountPaused(_ accountId: String, paused: Bool) async throws {
        struct Body: Encodable { let id: String; let paused: Bool }
        let _: CodexAccountMutationResponse = try await request(
            path: "/api/codex-auth/accounts/pause",
            method: "PUT",
            body: Body(id: accountId, paused: paused)
        )
    }

    func setCodexAccountPriority(_ accountId: String, priority: Int) async throws {
        struct Body: Encodable { let id: String; let priority: Int }
        let _: CodexAccountMutationResponse = try await request(
            path: "/api/codex-auth/accounts/priority",
            method: "PUT",
            body: Body(id: accountId, priority: min(max(priority, -100), 100))
        )
    }

    func removeCodexAccount(_ accountId: String) async throws {
        let id = accountId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? accountId
        let _: CodexAccountMutationResponse = try await request(
            path: "/api/codex-auth/accounts?id=\(id)",
            method: "DELETE",
            body: Optional<String>.none
        )
    }

    func updateCodexPoolStrategy(_ strategy: AccountPoolStrategy) async throws {
        struct Body: Encodable { let strategy: AccountPoolStrategy }
        let _: CodexAccountMutationResponse = try await request(
            path: "/api/codex-auth/pool-strategy",
            method: "PUT",
            body: Body(strategy: strategy)
        )
    }

    func updateCodexAutoSwitchThreshold(_ threshold: Int) async throws {
        struct Body: Encodable { let threshold: Int }
        let _: APIAcknowledgement = try await request(
            path: "/api/codex-auth/auto-switch",
            method: "PUT",
            body: Body(threshold: min(max(threshold, 0), 100))
        )
    }

    func startCodexLogin(accountId: String? = nil, reauth: Bool = false) async throws -> CodexLoginStartResponse {
        struct Body: Encodable { let id: String?; let reauth: Bool }
        return try await request(
            path: "/api/codex-auth/login",
            method: "POST",
            body: Body(id: accountId, reauth: reauth)
        )
    }

    func codexLoginStatus(flowId: String, accountId: String? = nil, reauth: Bool = false) async throws
        -> CodexLoginStatusResponse
    {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "flowId", value: flowId)]
        if let accountId { components.queryItems?.append(URLQueryItem(name: "accountId", value: accountId)) }
        if reauth { components.queryItems?.append(URLQueryItem(name: "reauth", value: "1")) }
        return try await request(path: "/api/codex-auth/login-status?\(components.percentEncodedQuery ?? "")")
    }

    func cancelCodexLogin(flowId: String?) async throws {
        struct Body: Encodable { let flowId: String? }
        let _: APIAcknowledgement = try await request(
            path: "/api/codex-auth/login/cancel",
            method: "POST",
            body: Body(flowId: flowId)
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        authenticated: Bool = true
    ) async throws -> Response {
        try await request(path: path, method: method, authenticated: authenticated, bodyData: nil)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        authenticated: Bool = true,
        body: Body?
    ) async throws -> Response {
        let data = try body.map { try JSONEncoder().encode($0) }
        return try await request(path: path, method: method, authenticated: authenticated, bodyData: data)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        authenticated: Bool,
        bodyData: Data?
    ) async throws -> Response {
        let base = try baseURL()
        guard let url = URL(string: path, relativeTo: base) else { throw OpenCodexAPIError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = AppConstants.Connection.requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let token = tokenProvider.load() else { throw OpenCodexAPIError.missingAdminToken }
            request.setValue(token, forHTTPHeaderField: "X-OpenCodex-API-Key")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OpenCodexAPIError.invalidResponse }
            if http.statusCode == 401 { throw OpenCodexAPIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                let message =
                    (try? JSONDecoder().decode(APIErrorBody.self, from: data).error)
                    ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                throw OpenCodexAPIError.server(status: http.statusCode, message: message)
            }
            if Response.self == EmptyResponse.self, data.isEmpty {
                return EmptyResponse() as! Response
            }
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw OpenCodexAPIError.invalidResponse
            }
        } catch let error as OpenCodexAPIError {
            throw error
        } catch let error as URLError
            where [.cannotConnectToHost, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code)
        {
            throw OpenCodexAPIError.offline
        } catch {
            throw OpenCodexAPIError.transport(error.localizedDescription)
        }
    }
}

private struct APIErrorBody: Decodable {
    let error: String
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
