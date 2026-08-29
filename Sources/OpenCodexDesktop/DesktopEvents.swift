import Foundation
import UserNotifications

enum DesktopEventKind: String, Codable, CaseIterable {
    case appStarted
    case appStopped
    case coreStarted
    case coreStopped
    case coreCrashed
    case serviceRecovered
    case systemSleep
    case systemWake
    case wakeCheckFailed
    case runtimeChanged
    case coreInstalled
    case coreRollback

    var title: String {
        switch self {
        case .appStarted: "Desktop 已启动"
        case .appStopped: "Desktop 已退出"
        case .coreStarted: "Core 已启动"
        case .coreStopped: "Core 已停止"
        case .coreCrashed: "Core 意外退出"
        case .serviceRecovered: "Core 已恢复"
        case .systemSleep: "Mac 进入睡眠"
        case .systemWake: "Mac 已唤醒"
        case .wakeCheckFailed: "唤醒检查失败"
        case .runtimeChanged: "Codex Runtime 已切换"
        case .coreInstalled: "Core 已安装"
        case .coreRollback: "Core 已回滚"
        }
    }

    var symbol: String {
        switch self {
        case .appStarted, .coreStarted, .serviceRecovered: "play.circle.fill"
        case .appStopped, .coreStopped: "stop.circle.fill"
        case .coreCrashed, .wakeCheckFailed: "exclamationmark.triangle.fill"
        case .systemSleep: "moon.zzz.fill"
        case .systemWake: "sunrise.fill"
        case .runtimeChanged: "terminal.fill"
        case .coreInstalled: "shippingbox.fill"
        case .coreRollback: "arrow.uturn.backward.circle.fill"
        }
    }

    var isFailure: Bool {
        self == .coreCrashed || self == .wakeCheckFailed
    }
}

struct DesktopEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: DesktopEventKind
    let detail: String?
}

@MainActor
final class DesktopEventStore: ObservableObject {
    static let shared = DesktopEventStore()

    @Published private(set) var events: [DesktopEvent] = []

    private let fileManager: FileManager
    private let fileURL: URL
    private let now: () -> Date
    private let maximumEvents = 200
    private let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    init(
        fileManager: FileManager = .default,
        fileURL: URL = CoreInstallationPaths.applicationSupportDirectory
            .appendingPathComponent("Events/events.json", isDirectory: false),
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
        self.now = now
        load()
    }

    func append(_ kind: DesktopEventKind, detail: String? = nil) {
        let timestamp = now()
        let safeDetail = detail.map { DiagnosticPrivacy.redact(String($0.prefix(240))) }
        if let latest = events.first,
            latest.kind == kind,
            timestamp.timeIntervalSince(latest.timestamp) < 5
        {
            return
        }
        events.insert(
            DesktopEvent(id: UUID(), timestamp: timestamp, kind: kind, detail: safeDetail),
            at: 0
        )
        prune(referenceDate: timestamp)
        persist()
    }

    func clear() {
        events = []
        persist()
    }

    private func load() {
        guard
            let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            (values.fileSize ?? 524_289) <= 524_288,
            let data = try? Data(contentsOf: fileURL),
            data.count <= 524_288
        else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        events = (try? decoder.decode([DesktopEvent].self, from: data)) ?? []
        prune(referenceDate: now())
    }

    private func prune(referenceDate: Date) {
        let oldest = referenceDate.addingTimeInterval(-retentionInterval)
        events = Array(
            events
                .filter { $0.timestamp >= oldest }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(maximumEvents)
        )
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(events).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Event history is best-effort and must never interrupt Core lifecycle operations.
        }
    }
}

@MainActor
final class NativeNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NativeNotificationManager()
    static let defaultsKey = "nativeNotificationsEnabled"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationDenied = false

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter

    init(
        defaults: UserDefaults = .standard,
        center: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.center = center
        isEnabled = defaults.bool(forKey: Self.defaultsKey)
        super.init()
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    func setEnabled(_ enabled: Bool) async {
        if !enabled {
            isEnabled = false
            defaults.set(false, forKey: Self.defaultsKey)
            return
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            isEnabled = granted
            authorizationDenied = !granted
            defaults.set(granted, forKey: Self.defaultsKey)
        } catch {
            isEnabled = false
            authorizationDenied = true
            defaults.set(false, forKey: Self.defaultsKey)
        }
    }

    func send(title: String, body: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = DiagnosticPrivacy.redact(title)
        content.body = DiagnosticPrivacy.redact(body)
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    private func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorizationDenied = settings.authorizationStatus == .denied
        if settings.authorizationStatus == .denied {
            isEnabled = false
            defaults.set(false, forKey: Self.defaultsKey)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
