import Foundation
import XCTest

@testable import OpenCodexDesktop

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
