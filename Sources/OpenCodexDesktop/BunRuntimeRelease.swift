import Foundation

/// Resolve the runtime named by a user-selected Core from Bun's official, versioned release.
/// New runtime versions need release metadata, not a Desktop update or an allowlist entry.
struct BunRuntimeRelease: Equatable, Sendable {
    let version: String
    let arm64SHA256: String
    let x64SHA256: String

    static func metadataURL(_ version: String) -> URL {
        URL(string: "https://api.github.com/repos/oven-sh/bun/releases/tags/bun-v\(version)")!
    }

    static func assetURL(version: String, name: String) -> URL {
        URL(string: "https://github.com/oven-sh/bun/releases/download/bun-v\(version)/\(name)")!
    }

    static func isSHA256(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }

    static func decode(_ data: Data, version: String) throws -> Self {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
                let digest: String?
                let size: Int64
                let state: String
            }
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard OnlineCoreVersion.components(version) != nil,
            release.tag_name == "bun-v\(version)", !release.draft, !release.prerelease
        else { throw OnlineCoreCatalogError.invalidRuntimeMetadata(version) }

        func checksum(for name: String) throws -> String {
            let matches = release.assets.filter { $0.name == name }
            guard matches.count == 1, let asset = matches.first,
                asset.browser_download_url == assetURL(version: version, name: name),
                asset.state == "uploaded", asset.size > 0, asset.size <= 256 * 1_024 * 1_024,
                let digest = asset.digest, digest.hasPrefix("sha256:"),
                isSHA256(String(digest.dropFirst(7)))
            else { throw OnlineCoreCatalogError.invalidRuntimeMetadata(version) }
            return String(digest.dropFirst(7))
        }

        return try Self(
            version: version,
            arm64SHA256: checksum(for: "bun-darwin-aarch64.zip"),
            x64SHA256: checksum(for: "bun-darwin-x64.zip")
        )
    }
}
