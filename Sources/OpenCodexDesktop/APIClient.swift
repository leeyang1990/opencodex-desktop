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
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: L10n.tr("连接地址无效")
        case .remoteManagementUnsupported: L10n.tr("客户端只允许连接本机回环地址，以防管理令牌被发送到其他设备")
        case .offline: L10n.tr("OpenCodex 服务未运行")
        case .missingAdminToken: L10n.tr("找不到本机管理令牌，请先启动一次 OpenCodex")
        case .unauthorized: L10n.tr("管理令牌无效，请检查 OpenCodex 配置")
        case let .server(_, message): message
        case .invalidResponse: L10n.tr("服务返回了无法识别的数据")
        case let .transport(message): message
        case let .operationFailed(message): message
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

    func settings() async throws -> RuntimeSettings {
        try await request(path: "/api/settings")
    }

    func stopProxy() async throws {
        let response: APIAcknowledgement = try await request(
            path: "/api/stop", method: "POST", body: Optional<String>.none)
        guard response.success == true else {
            throw OpenCodexAPIError.operationFailed(response.message ?? L10n.tr("内核未确认停止及路由还原成功。"))
        }
    }

    /// Readiness failures/timeouts do not prove that a process has exited. Only a refused
    /// loopback connection counts as stopped; any HTTP response still means a listener exists.
    func isProxyListenerStopped() async throws -> Bool {
        let base = try baseURL()
        guard let url = URL(string: "/readyz", relativeTo: base) else { throw OpenCodexAPIError.invalidAddress }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            _ = try await session.data(for: request)
            return false
        } catch let error as URLError where error.code == .cannotConnectToHost {
            return true
        } catch {
            throw error
        }
    }

    /// The Core's own model list: provider, native/routed, and current visibility.
    func models() async throws -> [ManagedModel] {
        try await request(path: "/api/models")
    }

    /// The provider summary the shell shows. Only key presence is reported, never key material.
    func config() async throws -> CoreConfig {
        try await request(path: "/api/config")
    }

    /// Aggregated usage only. The Core does not include prompts, response bodies, credentials,
    /// or account identifiers in this payload.
    func usage(range: String = "7d") async throws -> UsageReport {
        try await request(path: "/api/usage?range=\(escaped(range))")
    }

    /// Enables or disables models exactly as the console does, then lets the Core refresh the
    /// Codex catalog. `scope` is `provider` when a whole provider is switched at once.
    func setModelVisibility(
        provider: String,
        targets: [ModelVisibilityTarget],
        enabled: Bool,
        scope: String = "models"
    ) async throws {
        let body = ModelVisibilityRequest(scope: scope, provider: provider, enabled: enabled, targets: targets)
        let response: APIAcknowledgement = try await request(
            path: "/api/model-visibility",
            method: "PUT",
            body: body
        )
        guard response.ok != false else {
            throw OpenCodexAPIError.server(status: 200, message: response.message ?? L10n.tr("模型可见性更新被拒绝"))
        }
    }

    // MARK: - Codex accounts

    func codexAccounts() async throws -> [CodexAccount] {
        let response: CodexAccountList = try await request(path: "/api/codex-auth/accounts")
        return response.accounts
    }

    func codexScheduling() async throws -> CodexAccountScheduling {
        try await request(path: "/api/codex-auth/active")
    }

    /// Starts a browser sign-in. The Core opens the browser itself and returns a flow to poll.
    func startCodexLogin(reauth accountID: String? = nil) async throws -> CodexLoginStatus {
        let body = CodexLoginRequest(id: accountID, reauth: accountID == nil ? nil : true)
        return try await request(path: "/api/codex-auth/login", method: "POST", body: body)
    }

    func codexLoginStatus(flowID: String) async throws -> CodexLoginStatus {
        try await request(path: "/api/codex-auth/login-status?flowId=\(escaped(flowID))")
    }

    func cancelCodexLogin(flowID: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/codex-auth/login/cancel",
            method: "POST",
            body: CodexLoginCancellation(flowId: flowID)
        )
    }

    /// Pins the active pool account, or returns to the plain Codex login with `nil`.
    func selectCodexAccount(_ accountID: String?) async throws {
        let _: APIAcknowledgement = try await request(
            path: "/api/codex-auth/active",
            method: "PUT",
            body: CodexAccountSelection(accountId: accountID)
        )
    }

    func setCodexAccountPaused(_ accountID: String, paused: Bool) async throws {
        let _: APIAcknowledgement = try await request(
            path: "/api/codex-auth/accounts/pause",
            method: "PUT",
            body: CodexAccountPause(id: accountID, paused: paused)
        )
    }

    func setCodexPoolStrategy(_ strategy: String, stickyLimit: Int) async throws {
        let _: APIAcknowledgement = try await request(
            path: "/api/codex-auth/pool-strategy",
            method: "PUT",
            body: CodexPoolStrategy(strategy: strategy, stickyLimit: stickyLimit)
        )
    }

    // MARK: - API channels

    func channels() async throws -> [APIChannel] {
        try await request(path: "/api/providers")
    }

    func createChannel(name: String, payload: ChannelPayload, setDefault: Bool) async throws {
        let body = ChannelCreation(name: name, provider: payload, setDefault: setDefault)
        let response: APIAcknowledgement = try await request(path: "/api/providers", method: "POST", body: body)
        guard response.success == true else {
            throw OpenCodexAPIError.operationFailed(L10n.tr("渠道保存未获确认"))
        }
    }

    /// Applies a flat field mask to an existing channel.
    func updateChannel(name: String, patch: ChannelPatch) async throws {
        guard !patch.isEmpty else { return }
        let _: APIAcknowledgement = try await request(
            path: "/api/providers?name=\(escaped(name))",
            method: "PATCH",
            body: patch
        )
    }

    /// Sets the default channel. The Core accepts this only as a standalone field.
    func setDefaultChannel(name: String) async throws {
        let response: APIAcknowledgement = try await request(
            path: "/api/providers?name=\(escaped(name))",
            method: "PATCH",
            body: ChannelDefaultPatch(setDefault: true)
        )
        guard response.success == true else {
            throw OpenCodexAPIError.operationFailed(L10n.tr("默认渠道修改未获确认"))
        }
    }

    /// Adds one credential to a channel's key pool.
    func addChannelKey(name: String, key: String, label: String? = nil) async throws {
        let response: APIKeyCreation = try await request(
            path: "/api/providers/keys",
            method: "POST",
            body: ChannelKeyCreation(name: name, key: key, label: label)
        )
        guard response.ok == true else {
            throw OpenCodexAPIError.server(status: 200, message: L10n.tr("API Key 写入被拒绝"))
        }
    }

    /// The channel's credentials, masked by the Core.
    func channelKeys(name: String) async throws -> ProviderKeyPool {
        try await request(path: "/api/providers/keys?name=\(escaped(name))")
    }

    /// Probes the channel's own stored configuration; the name travels as a query parameter.
    func testChannel(name: String) async throws -> ChannelProbeResult {
        try await request(
            path: "/api/providers/test?name=\(escaped(name))",
            method: "POST",
            body: Optional<String>.none
        )
    }

    // MARK: - Subagents

    func subagentSelection() async throws -> SubagentSelection {
        try await request(path: "/api/subagent-models")
    }

    func setSubagentSelection(_ models: [String]) async throws {
        // The Core keeps the first five silently; capping here keeps UI and server agreeing.
        let capped = Array(models.prefix(SubagentSelection.maximumChosen))
        let _: APIAcknowledgement = try await request(
            path: "/api/subagent-models",
            method: "PUT",
            body: SubagentSelectionRequest(models: capped)
        )
    }

    // MARK: - Transport

    /// Percent-encodes a path component or query value; identifiers here are user data.
    private func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
            ?? value
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

// MARK: - Response envelopes

private struct CodexAccountList: Decodable {
    let accounts: [CodexAccount]
}

// MARK: - Request bodies

private struct CodexLoginRequest: Encodable {
    let id: String?
    let reauth: Bool?
}

private struct CodexLoginCancellation: Encodable {
    let flowId: String
}

private struct CodexAccountSelection: Encodable {
    let accountId: String?
}

private struct CodexAccountPause: Encodable {
    let id: String
    let paused: Bool
}

private struct CodexPoolStrategy: Encodable {
    let strategy: String
    let stickyLimit: Int
}

private struct ChannelCreation: Encodable {
    let name: String
    let provider: ChannelPayload
    let setDefault: Bool
}

private struct ChannelDefaultPatch: Encodable {
    let setDefault: Bool
}

private struct ChannelKeyCreation: Encodable {
    let name: String
    let key: String
    let label: String?
}

private struct APIKeyCreation: Decodable {
    let ok: Bool?
    let id: String?
}

private struct SubagentSelectionRequest: Encodable {
    let models: [String]
}

private struct APIErrorBody: Decodable {
    let error: String
}
