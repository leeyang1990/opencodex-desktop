import Foundation

enum SidebarDestination: String, CaseIterable, Identifiable {
    case overview
    case diagnostics
    case dashboard
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "运行状态"
        case .diagnostics: "诊断与修复"
        case .dashboard: "OpenCodex 控制台"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .diagnostics: "stethoscope"
        case .dashboard: "safari"
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

struct CodexRuntime: Decodable {
    let path: String?
    let version: String?
    let source: String?
    let warning: String?
}

struct RuntimeSettings: Decodable {
    let codexRuntime: CodexRuntime?
}

struct APIAcknowledgement: Decodable {
    let success: Bool?
    let ok: Bool?
    let message: String?
}

struct EmptyResponse: Decodable {}
