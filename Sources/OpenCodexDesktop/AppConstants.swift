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
        /// Bound for one-shot Core CLI commands such as `ocx restore`.
        static let coreCommandTimeout: Duration = .seconds(20)
    }

    enum Accounts {
        /// How long a browser sign-in may stay pending before the client gives up.
        static let loginTimeout: Duration = .seconds(300)
        static let loginPollInterval: Duration = .seconds(2)
    }

    enum ChatGPT {
        static let bundleIdentifier = "com.openai.codex"
        static let applicationName = "ChatGPT"
        /// Time allowed for a cooperative quit. ChatGPT runs the Codex app-server, so it gets a
        /// generous window to flush its own state; nothing is force-killed.
        static let quitTimeout: Duration = .seconds(15)
        static let quitPollInterval: Duration = .milliseconds(200)
        static let terminationReplyTimeout: Duration = .seconds(25)
    }
}
