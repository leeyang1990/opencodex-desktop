import AppKit
import XCTest

final class AppIconTests: XCTestCase {
    func testSourceIconHasTransparentMacOSCorners() throws {
        let iconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets/AppIcon-Source.png")
        let iconData = try Data(contentsOf: iconURL)
        let icon = try XCTUnwrap(NSBitmapImageRep(data: iconData))

        XCTAssertEqual(icon.pixelsWide, 1024)
        XCTAssertEqual(icon.pixelsHigh, 1024)
        XCTAssertTrue(icon.hasAlpha)

        let transparentPoints = [
            NSPoint(x: 0, y: 0),
            NSPoint(x: 1023, y: 0),
            NSPoint(x: 0, y: 1023),
            NSPoint(x: 1023, y: 1023),
        ]
        for point in transparentPoints {
            let color = try XCTUnwrap(icon.colorAt(x: Int(point.x), y: Int(point.y)))
            XCTAssertLessThanOrEqual(color.alphaComponent, 0.01, "Expected transparent pixel at \(point)")
        }

        let center = try XCTUnwrap(icon.colorAt(x: 512, y: 512))
        XCTAssertGreaterThanOrEqual(center.alphaComponent, 0.99)
    }
}
