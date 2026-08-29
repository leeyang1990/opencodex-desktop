import Foundation

enum AppConstants {
    enum Connection {
        static let defaultHost = "127.0.0.1"
        static let defaultPort = 10_100
        static let validPortRange = 1...65_535
        static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
        static let requestTimeout: TimeInterval = 12
    }

    enum Service {
        static let startupTimeout: Duration = .seconds(120)
        static let healthPollInterval: Duration = .milliseconds(250)
        static let gracefulStopDelay: Duration = .milliseconds(500)
        static let terminateTimeout: Duration = .seconds(8)
        static let interruptTimeout: Duration = .seconds(1)
        static let forceKillTimeout: Duration = .seconds(1)
        static let processPollInterval: Duration = .milliseconds(100)
    }
}
