import CryptoKit
import Foundation

struct OnlineCoreVersion: Codable, Equatable, Identifiable, Sendable {
    struct Distribution: Codable, Equatable, Sendable {
        let tarball: URL
        let integrity: String?
    }
    let name: String
    let version: String
    let gitHead: String?
    let dist: Distribution
    let dependencies: [String: String]?
    let deprecated: String?
    var id: String { version }

    var unavailableReason: String? {
        guard let parts = Self.components(version), parts[0] == 2, parts[1] >= 12 else {
            return L10n.tr("超出客户端支持的 Core 2.x 范围")
        }
        guard deprecated == nil else { return L10n.tr("上游已弃用") }
        guard dependencies?["bun"].flatMap(OnlineCoreCatalog.runtime) != nil else {
            return L10n.tr("Bun 版本尚未适配")
        }
        guard name == OnlineCoreCatalog.packageName,
            gitHead?.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
            dist.tarball.absoluteString == OnlineCoreCatalog.packageURL(version).absoluteString,
            Self.integrityDigest(dist.integrity) != nil
        else { return L10n.tr("缺少可验证的发布信息") }
        return nil
    }

    static func components(_ version: String) -> [Int]? {
        guard
            version.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#, options: .regularExpression)
                != nil
        else { return nil }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : nil
    }

    static func integrityDigest(_ integrity: String?) -> Data? {
        guard let integrity, integrity.hasPrefix("sha512-"),
            let digest = Data(base64Encoded: String(integrity.dropFirst(7))), digest.count == 64
        else { return nil }
        return digest
    }

    func verifiesPackage(_ data: Data) -> Bool {
        guard let expected = Self.integrityDigest(dist.integrity) else { return false }
        return Data(SHA512.hash(data: data)) == expected
    }
}

struct OnlineCoreCatalog: Codable, Sendable {
    static let packageName = "@bitkyc08/opencodex"
    static let endpoint = URL(string: "https://registry.npmjs.org/@bitkyc08/opencodex")!
    let versions: [OnlineCoreVersion]
    let latest: String?
    let fetchedAt: Date

    static func packageURL(_ version: String) -> URL {
        URL(string: "https://registry.npmjs.org/@bitkyc08/opencodex/-/opencodex-\(version).tgz")!
    }

    static func runtime(_ version: String) -> CoreRelease? {
        CoreReleaseCatalog.all.first { $0.bunVersion == version }
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> Self {
        struct Registry: Decodable {
            let name: String
            let versions: [String: OnlineCoreVersion]
            let tags: [String: String]
            enum CodingKeys: String, CodingKey { case name, versions; case tags = "dist-tags" }
        }
        let registry = try JSONDecoder().decode(Registry.self, from: data)
        guard registry.name == packageName else { throw OnlineCoreCatalogError.invalidMetadata }
        let versions = registry.versions.compactMap { key, value -> OnlineCoreVersion? in
            guard key == value.version, value.name == packageName,
                let parts = OnlineCoreVersion.components(key), parts[0] >= 2
            else { return nil }
            return value
        }.sorted {
            OnlineCoreVersion.components($1.version)!.lexicographicallyPrecedes(
                OnlineCoreVersion.components($0.version)!)
        }
        guard !versions.isEmpty else { throw OnlineCoreCatalogError.invalidMetadata }
        let latest = registry.tags["latest"].flatMap { tag in versions.contains { $0.version == tag } ? tag : nil }
        return Self(versions: versions, latest: latest, fetchedAt: now)
    }

    static func validatePrepared(_ release: CoreRelease) -> Bool {
        guard let runtime = runtime(release.bunVersion),
            let parts = OnlineCoreVersion.components(release.version), parts[0] == 2, parts[1] >= 12,
            release.commit.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil
        else { return false }
        return release.package.url == packageURL(release.version)
            && release.lockfile.url.absoluteString == lockfileURL(release.commit).absoluteString
            && [release.package.sha256, release.lockfile.sha256].allSatisfy {
                $0.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
            }
            && release.bunArm64SHA256 == runtime.bunArm64SHA256
            && release.bunX64SHA256 == runtime.bunX64SHA256
    }

    static func lockfileURL(_ commit: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/lidge-jun/opencodex/\(commit)/bun.lock")!
    }
}

/// Keep the menu compact without truncating cached metadata or losing the saved selection.
struct CoreVersionOption: Equatable {
    let version: String
    let label: String
    let unavailable: Bool

    static func choices(catalog: OnlineCoreCatalog?, pinned: [CoreRelease], selected: String?) -> [Self] {
        let remote = catalog?.versions ?? []  // Catalog entries are sorted newest first.
        var options: [Self]
        if remote.isEmpty {
            options = pinned.sorted {
                $0.version.compare($1.version, options: .numeric) == .orderedDescending
            }.prefix(5).map { locked($0) }
        } else {
            options = remote.prefix(5).map { online($0, latest: catalog?.latest) }
        }
        if let selected, !options.contains(where: { $0.version == selected }) {
            if let entry = remote.first(where: { $0.version == selected }) {
                options.append(online(entry, latest: catalog?.latest))
            } else if let release = pinned.first(where: { $0.version == selected }) {
                options.append(locked(release))
            }
        }
        return options.map { option in
            Self(
                version: option.version,
                label: option.label + (option.version == selected ? L10n.tr(" · 当前选择") : ""),
                unavailable: option.unavailable)
        }
    }

    private static func online(_ entry: OnlineCoreVersion, latest: String?) -> Self {
        let reason = entry.unavailableReason
        return Self(
            version: entry.version,
            label: entry.version + (entry.version == latest ? L10n.tr(" · 最新") : "")
                + (reason.map { " · \($0)" } ?? ""),
            unavailable: reason != nil)
    }

    private static func locked(_ release: CoreRelease) -> Self {
        Self(version: release.version, label: L10n.tr("\(release.version) · 已锁定"), unavailable: false)
    }
}

enum OnlineCoreCatalogError: LocalizedError {
    case invalidMetadata, unsupported(String), checksum, network(Int), oversized
    var errorDescription: String? {
        switch self {
        case .invalidMetadata: L10n.tr("上游版本信息不完整或来源不可信。")
        case .unsupported(let reason): reason
        case .checksum: L10n.tr("版本制品校验失败，未更改当前内核选择。")
        case .network(let status): L10n.tr("版本服务返回 HTTP \(status)，请稍后刷新。")
        case .oversized: L10n.tr("版本服务响应超过大小限制。")
        }
    }
}

/// Public release metadata never uses the loopback management client or its token.
actor OnlineCoreCatalogClient {
    private let session: URLSession
    private let redirectPolicy: CatalogRedirectPolicy

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        let policy = CatalogRedirectPolicy()
        redirectPolicy = policy
        session = URLSession(configuration: config, delegate: policy, delegateQueue: nil)
    }

    func fetch() async throws -> OnlineCoreCatalog {
        try OnlineCoreCatalog.decode(await data(from: OnlineCoreCatalog.endpoint, limit: 12 * 1_024 * 1_024))
    }

    /// Resolve only an explicitly selected stable version, never a floating `latest` install.
    func prepare(_ candidate: OnlineCoreVersion) async throws -> CoreRelease {
        if let reason = candidate.unavailableReason { throw OnlineCoreCatalogError.unsupported(reason) }
        // Refetch the exact version to reject mutated metadata between listing and selection.
        let url = OnlineCoreCatalog.endpoint.appendingPathComponent(candidate.version)
        let current = try JSONDecoder().decode(
            OnlineCoreVersion.self, from: await data(from: url, limit: 1_024 * 1_024))
        guard current == candidate, let commit = current.gitHead,
            let runtime = current.dependencies?["bun"].flatMap(OnlineCoreCatalog.runtime)
        else { throw OnlineCoreCatalogError.invalidMetadata }

        let package = try await data(from: current.dist.tarball, limit: 64 * 1_024 * 1_024)
        guard current.verifiesPackage(package) else { throw OnlineCoreCatalogError.checksum }

        // Read the lockfile as metadata at the registry's immutable source commit, then pin its
        // SHA-256 in the installation descriptor. Check GitHub's blob digest as well.
        let lockURL = URL(string: "https://api.github.com/repos/lidge-jun/opencodex/contents/bun.lock?ref=\(commit)")!
        struct Blob: Decodable { let sha: String; let encoding: String; let content: String; let size: Int }
        let blob = try JSONDecoder().decode(Blob.self, from: await data(from: lockURL, limit: 2 * 1_024 * 1_024))
        guard blob.encoding == "base64",
            let lock = Data(base64Encoded: blob.content, options: .ignoreUnknownCharacters),
            lock.count == blob.size, lock.count <= 1_024 * 1_024
        else { throw OnlineCoreCatalogError.invalidMetadata }
        let gitData = Data("blob \(lock.count)\0".utf8) + lock
        guard Insecure.SHA1.hash(data: gitData).map({ String(format: "%02x", $0) }).joined() == blob.sha else {
            throw OnlineCoreCatalogError.checksum
        }
        let release = CoreRelease(
            version: current.version, commit: commit,
            package: DownloadArtifact(url: current.dist.tarball, sha256: Self.sha256(package)),
            lockfile: DownloadArtifact(
                url: OnlineCoreCatalog.lockfileURL(commit), sha256: Self.sha256(lock), maximumBytes: 1_024 * 1_024),
            bunVersion: runtime.bunVersion, bunArm64SHA256: runtime.bunArm64SHA256, bunX64SHA256: runtime.bunX64SHA256
        )
        guard OnlineCoreCatalog.validatePrepared(release) else { throw OnlineCoreCatalogError.invalidMetadata }
        return release
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func data(from url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OnlineCoreCatalogError.network((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard response.url == url else { throw OnlineCoreCatalogError.invalidMetadata }
        guard response.expectedContentLength <= Int64(limit) else { throw OnlineCoreCatalogError.oversized }
        var result = Data()
        for try await byte in bytes {
            guard result.count < limit else { throw OnlineCoreCatalogError.oversized }
            result.append(byte)
        }
        try Task.checkCancellation()
        return result
    }
}

private final class CatalogRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
