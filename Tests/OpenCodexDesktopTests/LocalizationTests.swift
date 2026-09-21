import Foundation
import XCTest

@testable import OpenCodexDesktop

final class LocalizationTests: XCTestCase {
    func testPreferredLanguageResolution() {
        for tag in ["zh", "zh-CN", "zh-Hans", "zh-Hant-TW", "zh_TW"] {
            XCTAssertEqual(L10n.Language.resolve([tag]), .chinese)
        }
        for tag in ["en", "en-US", "en_GB"] {
            XCTAssertEqual(L10n.Language.resolve([tag]), .english)
        }
        XCTAssertEqual(L10n.Language.resolve([]), .english)
        XCTAssertEqual(L10n.Language.resolve(["ja", "de"]), .english)
        XCTAssertEqual(L10n.Language.resolve(["ja", "zh-Hans", "en"]), .chinese)
        XCTAssertEqual(L10n.Language.resolve(["en", "zh-Hans"]), .english)
    }

    func testExplicitLanguageAndInterpolation() {
        XCTAssertEqual(L10n.tr("设置", language: .english), "Settings")
        XCTAssertEqual(L10n.tr("设置", language: .chinese), "设置")
        XCTAssertEqual(L10n.tr("Core 当前使用 Codex \("0.148.0")", language: .english), "Core is using Codex 0.148.0")
        XCTAssertEqual(L10n.tr("Core 当前使用 Codex \("0.148.0")", language: .chinese), "Core 当前使用 Codex 0.148.0")
        XCTAssertEqual(L10n.tr("周额度 %.0f%%", language: .english), "Weekly quota %.0f%%")
    }

    func testArgumentsAreNeverTranslatedOrReinterpreted() {
        let account = "用户 %2$@ 100% /private/path"
        XCTAssertEqual(L10n.tr("已添加账号 \(account)", language: .english), "Added account \(account)")
        XCTAssertEqual(
            L10n.tr("当前 \(account) · 上次检查 \("today")", language: .english), "Current \(account) · Last checked today")
        XCTAssertEqual(L10n.tr("missing key", language: .english), "missing key")
    }

    func testCatalogsAreCompleteAndPreservePlaceholders() throws {
        let english = try catalog(.english)
        let chinese = try catalog(.chinese)
        XCTAssertGreaterThan(english.count, 500)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let placeholders = try NSRegularExpression(pattern: #"%\d+\$@|%\.0f|%%"#)
        func tokens(_ value: String) -> [String] {
            let string = value as NSString
            return placeholders.matches(in: value, range: NSRange(location: 0, length: string.length))
                .map { string.substring(with: $0.range) }.sorted()
        }
        for (key, value) in english {
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertNil(value.range(of: #"\p{Han}"#, options: .regularExpression), key)
            XCTAssertEqual(tokens(key), tokens(value), key)
            XCTAssertEqual(tokens(key), tokens(chinese[key] ?? ""), key)
        }
    }

    func testShortcutResourcesInBothLanguages() throws {
        for language in L10n.Language.allCases {
            let bundle = L10n.bundle(for: language)
            let url = try XCTUnwrap(bundle.url(forResource: "AppShortcuts", withExtension: "strings"))
            let data = try Data(contentsOf: url)
            let phrases = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertEqual(phrases.count, 4)
            XCTAssertTrue(phrases.values.allSatisfy { $0.contains("${applicationName}") })
        }
    }

    private func catalog(_ language: L10n.Language) throws -> [String: String] {
        let url = try XCTUnwrap(L10n.bundle(for: language).url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }
}
