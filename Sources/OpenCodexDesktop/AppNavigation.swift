import SwiftUI

enum CoreConsolePage: String {
    case providers
}

@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()

    @Published var selection: SidebarDestination = .home

    private init() {}

    func show(_ destination: SidebarDestination) {
        selection = destination
    }
}

enum DeepLinkPolicy {
    static let scheme = "opencodex"

    static func destination(for url: URL) -> SidebarDestination? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let route = [url.host, url.path]
            .compactMap { $0 }
            .joined(separator: "/")
            .split(separator: "/")
            .first?
            .lowercased()

        return switch route {
        case "status", "overview", "home": .home
        case "accounts", "codex-auth": .accounts
        case "channels", "providers": .channels
        case "subagents": .subagents
        case "settings": .settings
        default: nil
        }
    }
}
