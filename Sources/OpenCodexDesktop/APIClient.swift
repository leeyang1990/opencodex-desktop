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

    func settings() async throws -> RuntimeSettings {
        try await request(path: "/api/settings")
    }

    func stopProxy() async throws {
        let _: APIAcknowledgement = try await request(path: "/api/stop", method: "POST", body: Optional<String>.none)
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
