import SwiftUI

@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()

    @Published var selection: SidebarDestination = .overview

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
        case "status", "overview": .overview
        case "diagnostics", "repair": .diagnostics
        case "console", "dashboard": .dashboard
        case "settings": .settings
        default: nil
        }
    }
}
