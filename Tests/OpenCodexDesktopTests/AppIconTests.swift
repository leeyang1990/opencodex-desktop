import AppKit
import XCTest

final class AppIconTests: XCTestCase {
    func testSourceIconIsFullBleedOpaqueSquareForSystemMasking() throws {
        let iconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets/AppIcon-Source.png")
        let iconData = try Data(contentsOf: iconURL)
        let icon = try XCTUnwrap(NSBitmapImageRep(data: iconData))

        XCTAssertEqual(icon.pixelsWide, 1024)
        XCTAssertEqual(icon.pixelsHigh, 1024)
        XCTAssertFalse(icon.hasAlpha)

        let edgePoints = [
            NSPoint(x: 0, y: 0),
            NSPoint(x: 1023, y: 0),
            NSPoint(x: 0, y: 1023),
            NSPoint(x: 1023, y: 1023),
            NSPoint(x: 512, y: 0),
            NSPoint(x: 512, y: 1023),
            NSPoint(x: 0, y: 512),
            NSPoint(x: 1023, y: 512),
        ]
        for point in edgePoints {
            let color = try XCTUnwrap(icon.colorAt(x: Int(point.x), y: Int(point.y)))
            XCTAssertGreaterThanOrEqual(color.alphaComponent, 0.99, "Expected opaque pixel at \(point)")
        }
    }
}
