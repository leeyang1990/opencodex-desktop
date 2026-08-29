import Foundation

enum SecurityAuditID: String, CaseIterable {
    case networkBinding
    case managementToken
    case dataDirectory
    case appSignature
}

struct SecurityAuditItem: Identifiable, Equatable {
    let id: SecurityAuditID
    let title: String
    let detail: String
    let state: EnvironmentCheckState
}

struct SecurityAuditReport: Equatable {
    let checkedAt: Date?
    let items: [SecurityAuditItem]

    static let empty = SecurityAuditReport(checkedAt: nil, items: [])
    var needsAttention: Bool { items.contains { $0.state == .attention } }
}

enum LocalSecurityAuditor {
    static func audit(
        servicePort: Int,
        servicePID: Int?,
        tokenURL: URL,
        dataDirectory: URL,
        appBundleURL: URL?,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> SecurityAuditReport {
        SecurityAuditReport(
            checkedAt: now,
            items: [
                networkItem(port: servicePort, pid: servicePID),
                permissionItem(
                    id: .managementToken,
                    title: "管理令牌文件",
                    url: tokenURL,
                    expectedDescription: "令牌文件仅当前用户可读写（0600）。",
                    missingState: .pending,
                    fileManager: fileManager
                ),
                permissionItem(
                    id: .dataDirectory,
                    title: "Core 数据目录",
                    url: dataDirectory,
                    expectedDescription: "数据目录仅当前用户可访问（0700）。",
                    missingState: .pending,
                    fileManager: fileManager
                ),
                signatureItem(appBundleURL: appBundleURL, fileManager: fileManager),
            ]
        )
    }

    private static func networkItem(port: Int, pid: Int?) -> SecurityAuditItem {
        guard let pid else {
            return SecurityAuditItem(
                id: .networkBinding,
                title: "本机监听范围",
                detail: "Core 未运行，启动后检查实际监听地址。",
                state: .pending
            )
        }
        let names = listeningNames(pid: pid, port: port)
        guard !names.isEmpty else {
            return SecurityAuditItem(
                id: .networkBinding,
                title: "本机监听范围",
                detail: "未读取到 Core 的监听套接字。",
                state: .attention
            )
        }
        let unsafe = names.contains { name in
            name.contains("*:") || name.contains("0.0.0.0:") || name.contains("[::]:")
        }
        return SecurityAuditItem(
            id: .networkBinding,
            title: "本机监听范围",
            detail: unsafe
                ? "Core 存在非回环监听地址，请检查 Core hostname 设置。"
                : "Core 只在本机回环地址监听端口 \(port)。",
            state: unsafe ? .attention : .passed
        )
    }

    private static func listeningNames(pid: Int, port: Int) -> [String] {
        let executable = URL(fileURLWithPath: "/usr/sbin/lsof")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return [] }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["-nP", "-a", "-p", String(pid), "-iTCP:\(port)", "-sTCP:LISTEN", "-Fn"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = output.fileHandleForReading.readDataToEndOfFile().prefix(16_384)
            return (String(data: data, encoding: .utf8) ?? "")
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { $0.hasPrefix("n") }
                .map { String($0.dropFirst()) }
        } catch {
            return []
        }
    }

    private static func permissionItem(
        id: SecurityAuditID,
        title: String,
        url: URL,
        expectedDescription: String,
        missingState: EnvironmentCheckState,
        fileManager: FileManager
    ) -> SecurityAuditItem {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
            values.isSymbolicLink != true,
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let permissions = attributes[.posixPermissions] as? NSNumber
        else {
            return SecurityAuditItem(
                id: id,
                title: title,
                detail: "目标尚不存在或无法安全读取。",
                state: missingState
            )
        }
        let mode = permissions.intValue & 0o777
        let privateToUser = mode & 0o077 == 0
        return SecurityAuditItem(
            id: id,
            title: title,
            detail: privateToUser
                ? expectedDescription
                : "当前权限为 \(String(mode, radix: 8))，其他本机用户可能访问。",
            state: privateToUser ? .passed : .attention
        )
    }

    private static func signatureItem(appBundleURL: URL?, fileManager: FileManager) -> SecurityAuditItem {
        guard let appBundleURL,
            appBundleURL.pathExtension == "app",
            fileManager.fileExists(atPath: appBundleURL.path)
        else {
            return SecurityAuditItem(
                id: .appSignature,
                title: "客户端代码签名",
                detail: "开发测试环境不执行 App Bundle 签名检查。",
                state: .pending
            )
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", appBundleURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let valid = process.terminationStatus == 0
            return SecurityAuditItem(
                id: .appSignature,
                title: "客户端代码签名",
                detail: valid ? "App Bundle 代码签名结构有效。" : "App Bundle 签名校验失败，请重新安装可信发布包。",
                state: valid ? .passed : .attention
            )
        } catch {
            return SecurityAuditItem(
                id: .appSignature,
                title: "客户端代码签名",
                detail: "无法执行系统代码签名检查。",
                state: .attention
            )
        }
    }
}
