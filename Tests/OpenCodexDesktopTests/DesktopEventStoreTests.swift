import Foundation
import XCTest

@testable import OpenCodexDesktop

extension DesktopEventStore {
    /// A store in a throwaway file.
    ///
    /// AppModel writes lifecycle events, and a test that reuses `.shared` pollutes the developer's
    /// real timeline with fixtures — which is exactly what happened before this existed.
    static func scratch(function: String = #function) -> DesktopEventStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocx-event-tests", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(function)-\(UUID().uuidString).json")
        return DesktopEventStore(fileURL: file)
    }
}

@MainActor
final class DesktopEventStoreTests: XCTestCase {
    func testRedactsAndPersistsAllowlistedEvents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = root.appendingPathComponent("events.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000)
        let store = DesktopEventStore(fileURL: file, now: { now })

        store.append(.coreCrashed, detail: "Bearer super-secret user@example.com")

        XCTAssertEqual(store.events.count, 1)
        XCTAssertFalse(store.events[0].detail?.contains("super-secret") == true)
        XCTAssertFalse(store.events[0].detail?.contains("user@example.com") == true)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testPrunesEventsOlderThanSevenDaysOnLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = root.appendingPathComponent("events.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 8 * 24 * 60 * 60)
        let events = [DesktopEvent(id: UUID(), timestamp: .distantPast, kind: .appStarted, detail: nil)]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(events).write(to: file)

        let store = DesktopEventStore(fileURL: file, now: { now })

        XCTAssertTrue(store.events.isEmpty)
    }
}
