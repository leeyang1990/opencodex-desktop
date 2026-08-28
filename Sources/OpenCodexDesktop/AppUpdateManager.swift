import AppKit
import CryptoKit
import Foundation

struct AppSemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let value = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let versionCore = value.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? value
        let components = versionCore.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
            let major = Int(components[0]),
            let minor = Int(components[1]),
            let patch = Int(components[2]),
            major >= 0,
            minor >= 0,
            patch >= 0
        else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: AppSemanticVersion, rhs: AppSemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AppUpdateRelease: Equatable {
    let version: String
    let notes: String
    let pageURL: URL
    let diskImageURL: URL
    let checksumURL: URL
    let diskImageFileName: String
    let diskImageSize: Int
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidCurrentVersion
    case invalidResponse
    case httpStatus(Int)
    case responseTooLarge
    case invalidRelease
    case unsupportedRelease
    case missingAssets
    case untrustedURL
    case invalidChecksum
    case downloadTooLarge
    case downloadedFileSizeMismatch
    case checksumMismatch
    case noAvailableUpdate
    case cannotOpenDiskImage

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            "无法识别当前客户端版本。"
        case .invalidResponse:
            "GitHub 返回了无效响应。"
        case let .httpStatus(status):
            "GitHub 请求失败（HTTP \(status)）。"
        case .responseTooLarge:
            "GitHub Release 信息超出预期大小。"
        case .invalidRelease:
            "GitHub Release 的版本信息无效。"
        case .unsupportedRelease:
            "该 Release 不是可安装的正式版本。"
        case .missingAssets:
            "Release 缺少 Apple Silicon DMG 或 SHA-256 校验文件。"
        case .untrustedURL:
            "Release 包含不受信任的下载地址。"
        case .invalidChecksum:
            "Release 的 SHA-256 校验文件格式无效。"
        case .downloadTooLarge:
            "更新文件超出允许的大小。"
        case .downloadedFileSizeMismatch:
            "更新文件大小与 GitHub Release 记录不一致。"
        case .checksumMismatch:
            "更新文件校验失败，已停止安装。"
        case .noAvailableUpdate:
            "当前没有可下载的客户端更新。"
        case .cannotOpenDiskImage:
            "无法打开更新安装镜像。"
        }
    }
}

enum AppUpdatePreference {
    static let automaticChecksKey = "automaticallyChecksForAppUpdates"
    static let lastCheckDateKey = "lastAppUpdateCheckDate"

    static func automaticChecksEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: automaticChecksKey) != nil else { return true }
        return defaults.bool(forKey: automaticChecksKey)
    }

    static func setAutomaticChecksEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: automaticChecksKey)
    }
}

enum AppUpdatePolicy {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/leeyang1990/opencodex-desktop/releases/latest"
    )!
    static let releasesPageURL = URL(string: "https://github.com/leeyang1990/opencodex-desktop/releases")!
    static let maximumMetadataSize = 1_048_576
    static let maximumChecksumSize = 4_096
    static let maximumDiskImageSize = 250 * 1_024 * 1_024

    static func release(from data: Data, currentVersion: String) throws -> AppUpdateRelease? {
        guard data.count <= maximumMetadataSize else { throw AppUpdateError.responseTooLarge }
        guard let installedVersion = AppSemanticVersion(currentVersion) else {
            throw AppUpdateError.invalidCurrentVersion
        }

        let payload: GitHubReleasePayload
        do {
            payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        } catch {
            throw AppUpdateError.invalidResponse
        }

        guard !payload.draft, !payload.prerelease else { throw AppUpdateError.unsupportedRelease }
        guard let releaseVersion = AppSemanticVersion(payload.tagName) else {
            throw AppUpdateError.invalidRelease
        }
        guard installedVersion < releaseVersion else { return nil }

        let normalizedVersion = "\(releaseVersion.major).\(releaseVersion.minor).\(releaseVersion.patch)"
        guard payload.tagName == "v\(normalizedVersion)" else { throw AppUpdateError.invalidRelease }
        let diskImageName = "OpenCodex-Desktop-v\(normalizedVersion)-macOS-arm64.dmg"
        let checksumName = "\(diskImageName).sha256"
        guard let diskImage = payload.assets.first(where: { $0.name == diskImageName }),
            let checksum = payload.assets.first(where: { $0.name == checksumName }),
            diskImage.size > 0,
            diskImage.size <= maximumDiskImageSize,
            checksum.size > 0,
            checksum.size <= maximumChecksumSize
        else {
            throw AppUpdateError.missingAssets
        }
        guard trustedReleasePageURL(payload.htmlURL, version: normalizedVersion),
            trustedAssetURL(diskImage.browserDownloadURL, version: normalizedVersion, fileName: diskImageName),
            trustedAssetURL(checksum.browserDownloadURL, version: normalizedVersion, fileName: checksumName)
        else {
            throw AppUpdateError.untrustedURL
        }

        return AppUpdateRelease(
            version: normalizedVersion,
            notes: payload.body ?? "",
            pageURL: payload.htmlURL,
            diskImageURL: diskImage.browserDownloadURL,
            checksumURL: checksum.browserDownloadURL,
            diskImageFileName: diskImageName,
            diskImageSize: diskImage.size
        )
    }

    static func checksum(from data: Data, expectedFileName: String) throws -> String {
        guard data.count <= maximumChecksumSize,
            let contents = String(data: data, encoding: .utf8)
        else {
            throw AppUpdateError.invalidChecksum
        }
        let lines = contents.split(whereSeparator: \.isNewline)
        guard lines.count == 1 else { throw AppUpdateError.invalidChecksum }
        let fields = lines[0].split(whereSeparator: \.isWhitespace)
        guard fields.count == 2 else { throw AppUpdateError.invalidChecksum }

        let digest = String(fields[0]).lowercased()
        let fileName = String(fields[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard digest.count == 64,
            digest.unicodeScalars.allSatisfy(hexadecimal.contains),
            fileName == expectedFileName
        else {
            throw AppUpdateError.invalidChecksum
        }
        return digest
    }

    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func trustedAPIResponseURL(_ url: URL?) -> Bool {
        guard let components = secureComponents(url),
            components.host?.lowercased() == "api.github.com",
            components.path == "/repos/leeyang1990/opencodex-desktop/releases/latest"
        else {
            return false
        }
        return true
    }

    static func trustedDownloadResponseURL(_ url: URL?) -> Bool {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.user == nil,
            components.password == nil,
            components.port == nil || components.port == 443,
            components.fragment == nil,
            let host = components.host?.lowercased()
        else {
            return false
        }
        if host == "github.com" { return components.query == nil }
        return host == "release-assets.githubusercontent.com"
    }

    private static func trustedReleasePageURL(_ url: URL, version: String) -> Bool {
        guard let components = secureComponents(url),
            components.host?.lowercased() == "github.com",
            components.path == "/leeyang1990/opencodex-desktop/releases/tag/v\(version)"
        else {
            return false
        }
        return true
    }

    private static func trustedAssetURL(_ url: URL, version: String, fileName: String) -> Bool {
        guard let components = secureComponents(url),
            components.host?.lowercased() == "github.com",
            components.path
                == "/leeyang1990/opencodex-desktop/releases/download/v\(version)/\(fileName)"
        else {
            return false
        }
        return true
    }

    private static func secureComponents(_ url: URL?) -> URLComponents? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.user == nil,
            components.password == nil,
            components.port == nil || components.port == 443,
            components.query == nil,
            components.fragment == nil
        else {
            return nil
        }
        return components
    }
}

@MainActor
final class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()

    @Published private(set) var automaticChecksEnabled: Bool
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var availableRelease: AppUpdateRelease?
    @Published private(set) var downloadedUpdateURL: URL?
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastOperationFailed = false

    let currentVersion: String

    private let defaults: UserDefaults
    private let session: URLSession
    private let fileManager: FileManager
    private let automaticCheckInterval: TimeInterval
    private let updatesRootOverride: URL?

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0",
        automaticCheckInterval: TimeInterval = 24 * 60 * 60,
        updatesRootOverride: URL? = nil
    ) {
        self.defaults = defaults
        self.session = session
        self.fileManager = fileManager
        self.currentVersion = currentVersion
        self.automaticCheckInterval = automaticCheckInterval
        self.updatesRootOverride = updatesRootOverride
        automaticChecksEnabled = AppUpdatePreference.automaticChecksEnabled(in: defaults)
        lastCheckedAt = defaults.object(forKey: AppUpdatePreference.lastCheckDateKey) as? Date
    }

    var isBusy: Bool { isChecking || isDownloading }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        automaticChecksEnabled = enabled
        AppUpdatePreference.setAutomaticChecksEnabled(enabled, in: defaults)
        if enabled {
            Task { await checkForUpdates() }
        }
    }

    func checkForUpdatesIfNeeded() async {
        guard automaticChecksEnabled else { return }
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < automaticCheckInterval { return }
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard !isBusy else { return }
        isChecking = true
        lastOperationFailed = false
        statusMessage = "正在检查 GitHub Release…"
        defer { isChecking = false }

        do {
            var request = URLRequest(url: AppUpdatePolicy.latestReleaseURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("OpenCodex-Desktop/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            try validate(response: response, trustedBy: AppUpdatePolicy.trustedAPIResponseURL)
            let release = try AppUpdatePolicy.release(from: data, currentVersion: currentVersion)
            let checkedAt = Date()
            lastCheckedAt = checkedAt
            availableRelease = release
            if let release {
                defaults.removeObject(forKey: AppUpdatePreference.lastCheckDateKey)
                statusMessage = "发现新版本 \(release.version)"
            } else {
                defaults.set(checkedAt, forKey: AppUpdatePreference.lastCheckDateKey)
                downloadedUpdateURL = nil
                statusMessage = "当前已是最新版本 \(currentVersion)"
            }
        } catch {
            lastOperationFailed = true
            statusMessage = "检查更新失败：\(error.localizedDescription)"
        }
    }

    func checkForUpdatesPresentingResult() async {
        guard !isBusy else { return }
        await checkForUpdates()

        let alert = NSAlert()
        if let release = availableRelease, !lastOperationFailed {
            alert.messageText = "发现 OpenCodex Desktop \(release.version)"
            alert.informativeText = "将从本仓库的 GitHub Release 下载 Apple Silicon DMG，并在打开前验证 SHA-256。"
            alert.addButton(withTitle: "下载并打开")
            alert.addButton(withTitle: "查看 Release")
            alert.addButton(withTitle: "稍后")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                await downloadAvailableUpdate()
                if downloadedUpdateURL != nil { openDownloadedUpdate() }
            case .alertSecondButtonReturn:
                openReleasesPage()
            default:
                break
            }
        } else {
            alert.messageText = lastOperationFailed ? "检查更新失败" : "已是最新版本"
            alert.informativeText = statusMessage ?? "当前版本为 \(currentVersion)。"
            alert.addButton(withTitle: "好")
            _ = alert.runModal()
        }
    }

    func downloadAvailableUpdate() async {
        guard !isBusy else { return }
        guard let release = availableRelease else {
            statusMessage = AppUpdateError.noAvailableUpdate.localizedDescription
            return
        }

        isDownloading = true
        lastOperationFailed = false
        downloadedUpdateURL = nil
        statusMessage = "正在下载并校验 OpenCodex Desktop \(release.version)…"
        var temporaryDownloadURL: URL?
        defer {
            if let temporaryDownloadURL { try? fileManager.removeItem(at: temporaryDownloadURL) }
            isDownloading = false
        }

        do {
            var checksumRequest = URLRequest(url: release.checksumURL)
            checksumRequest.timeoutInterval = 20
            checksumRequest.cachePolicy = .reloadIgnoringLocalCacheData
            let (checksumData, checksumResponse) = try await session.data(for: checksumRequest)
            try validate(response: checksumResponse, trustedBy: AppUpdatePolicy.trustedDownloadResponseURL)
            let expectedChecksum = try AppUpdatePolicy.checksum(
                from: checksumData,
                expectedFileName: release.diskImageFileName
            )

            var downloadRequest = URLRequest(url: release.diskImageURL)
            downloadRequest.timeoutInterval = 10 * 60
            downloadRequest.cachePolicy = .reloadIgnoringLocalCacheData
            let (downloadURL, downloadResponse) = try await session.download(for: downloadRequest)
            temporaryDownloadURL = downloadURL
            try validate(response: downloadResponse, trustedBy: AppUpdatePolicy.trustedDownloadResponseURL)

            let attributes = try fileManager.attributesOfItem(atPath: downloadURL.path)
            let downloadedSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard downloadedSize <= AppUpdatePolicy.maximumDiskImageSize else {
                throw AppUpdateError.downloadTooLarge
            }
            guard downloadedSize == release.diskImageSize else {
                throw AppUpdateError.downloadedFileSizeMismatch
            }

            let actualChecksum = try await Task.detached(priority: .utility) {
                try AppUpdatePolicy.sha256(of: downloadURL)
            }.value
            guard actualChecksum == expectedChecksum else { throw AppUpdateError.checksumMismatch }

            let destinationURL = try updateDestination(for: release)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: downloadURL, to: destinationURL)
            temporaryDownloadURL = nil
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
            downloadedUpdateURL = destinationURL
            statusMessage = "版本 \(release.version) 已下载并通过 SHA-256 校验"
        } catch {
            lastOperationFailed = true
            statusMessage = "下载更新失败：\(error.localizedDescription)"
        }
    }

    func openDownloadedUpdate() {
        guard let downloadedUpdateURL else {
            statusMessage = AppUpdateError.noAvailableUpdate.localizedDescription
            return
        }
        guard NSWorkspace.shared.open(downloadedUpdateURL) else {
            lastOperationFailed = true
            statusMessage = AppUpdateError.cannotOpenDiskImage.localizedDescription
            return
        }
        lastOperationFailed = false
        statusMessage = "已打开安装镜像，请将新版 App 拖入“应用程序”文件夹。"
    }

    func revealDownloadedUpdate() {
        guard let downloadedUpdateURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([downloadedUpdateURL])
    }

    func openReleasesPage() {
        let url = availableRelease?.pageURL ?? AppUpdatePolicy.releasesPageURL
        NSWorkspace.shared.open(url)
    }

    private func validate(response: URLResponse, trustedBy policy: (URL?) -> Bool) throws {
        guard let response = response as? HTTPURLResponse else { throw AppUpdateError.invalidResponse }
        guard (200...299).contains(response.statusCode) else {
            throw AppUpdateError.httpStatus(response.statusCode)
        }
        guard policy(response.url) else { throw AppUpdateError.untrustedURL }
    }

    private func updateDestination(for release: AppUpdateRelease) throws -> URL {
        let updatesRoot: URL
        if let updatesRootOverride {
            updatesRoot = updatesRootOverride
        } else {
            guard let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            updatesRoot =
                cacheDirectory
                .appendingPathComponent("com.leeyang.opencodexdesktop", isDirectory: true)
                .appendingPathComponent("Updates", isDirectory: true)
        }
        let updateDirectory =
            updatesRoot
            .appendingPathComponent(release.version, isDirectory: true)
        if let existingVersions = try? fileManager.contentsOfDirectory(
            at: updatesRoot,
            includingPropertiesForKeys: nil
        ) {
            for existingVersion in existingVersions where existingVersion.lastPathComponent != release.version {
                try? fileManager.removeItem(at: existingVersion)
            }
        }
        try fileManager.createDirectory(
            at: updateDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return updateDirectory.appendingPathComponent(release.diskImageFileName, isDirectory: false)
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let body: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case body
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}
