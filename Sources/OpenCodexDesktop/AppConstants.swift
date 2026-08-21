import Foundation

enum AppConstants {
    enum Connection {
        static let defaultHost = "127.0.0.1"
        static let defaultPort = 10_100
        static let validPortRange = 1...65_535
        static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
        static let requestTimeout: TimeInterval = 12
    }

    enum Models {
        static let defaultContextCap = 350_000
    }

    enum Service {
        static let startupTimeout: Duration = .seconds(120)
        static let restartTimeout: Duration = .seconds(15)
        static let healthPollInterval: Duration = .milliseconds(250)
        static let gracefulStopDelay: Duration = .milliseconds(500)
        static let terminateTimeout: Duration = .seconds(8)
        static let interruptTimeout: Duration = .seconds(1)
        static let forceKillTimeout: Duration = .seconds(1)
        static let processPollInterval: Duration = .milliseconds(100)
        static let loginTimeout: Duration = .seconds(300)
        static let loginPollInterval: Duration = .seconds(2)
    }

    enum ImageGeneration {
        static let defaultTimeoutMs = 300_000
        static let minimumTimeoutMs = 1_000
        static let maximumTimeoutMs = 300_000
        static let selectableTimeoutSeconds = [60, 120, 300]
    }
}

enum ExternalURLPolicy {
    private static let trustedLoginDomains = ["openai.com", "chatgpt.com"]

    static func trustedLoginURL(from rawValue: String?) -> URL? {
        guard let rawValue,
            let components = URLComponents(string: rawValue),
            components.scheme?.lowercased() == "https",
            components.user == nil,
            components.password == nil,
            components.port == nil || components.port == 443,
            let host = components.host?.lowercased(),
            trustedLoginDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
        else {
            return nil
        }
        return components.url
    }
}
