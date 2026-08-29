import AppKit
import SwiftUI
import WebKit

enum DashboardNavigationPolicy {
    static func allows(_ candidate: URL, dashboardURL: URL) -> Bool {
        guard candidate.scheme?.lowercased() == "http",
            let candidateHost = normalizedHost(candidate.host),
            let dashboardHost = normalizedHost(dashboardURL.host),
            AppConstants.Connection.loopbackHosts.contains(candidateHost),
            candidateHost == dashboardHost
        else { return false }

        return candidate.port == dashboardURL.port
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard var host = host?.lowercased() else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        return host
    }
}

struct WebDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var reloadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                PageHeader(
                    title: "OpenCodex 控制台",
                    subtitle: "由 Core 提供；Provider、账号、模型与日志统一在这里管理"
                )
                Spacer()
                if model.isOnline {
                    Button("在浏览器中打开", systemImage: "arrow.up.right.square") {
                        model.openDashboard()
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            if model.isOnline, let dashboardURL = model.dashboardURL {
                LocalDashboardWebView(url: dashboardURL, reloadID: reloadID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(
                    symbol: "bolt.slash",
                    title: "OpenCodex Core 尚未运行",
                    detail: "启动 Core 后，即可从这里打开 OpenCodex 控制台。",
                    actionTitle: "启动 Core"
                ) {
                    Task { await model.startService() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .toolbar {
            ToolbarItem {
                Button("重新加载", systemImage: "arrow.clockwise") {
                    reloadID = UUID()
                }
                .disabled(!model.isOnline)
            }
        }
    }
}

private struct LocalDashboardWebView: NSViewRepresentable {
    let url: URL
    let reloadID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(dashboardURL: url, reloadID: reloadID)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.dashboardURL = url
        if context.coordinator.reloadID != reloadID {
            context.coordinator.reloadID = reloadID
            webView.reload()
        } else if webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var dashboardURL: URL
        var reloadID: UUID

        init(dashboardURL: URL, reloadID: UUID) {
            self.dashboardURL = dashboardURL
            self.reloadID = reloadID
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if targetURL.absoluteString == "about:blank"
                || DashboardNavigationPolicy.allows(targetURL, dashboardURL: dashboardURL)
            {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated,
                ["http", "https"].contains(targetURL.scheme?.lowercased() ?? "")
            {
                NSWorkspace.shared.open(targetURL)
            }
            decisionHandler(.cancel)
        }
    }
}
