import Foundation

/// App-owned text follows macOS language preferences (including per-app language settings).
/// Provider names, model IDs, paths and upstream messages are never translated.
enum L10n {
    enum Language: String, CaseIterable, Sendable {
        case english = "en"
        case chinese = "zh-Hans"

        static func resolve(_ preferredLanguages: [String]) -> Language {
            for language in preferredLanguages {
                let prefix = language.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first
                if prefix == "zh" { return .chinese }
                if prefix == "en" { return .english }
            }
            return .english
        }
    }

    static var language: Language { Language.resolve(Locale.preferredLanguages) }
    static var locale: Locale { Locale(identifier: language.rawValue) }

    // Installed apps use standard bundle resources; command-line builds and tests use SwiftPM.
    // Do not rely on SwiftPM's generated absolute development-directory fallback in a release.
    static let resourceBundle: Bundle = {
        if let url = Bundle.main.url(forResource: "OpenCodexDesktop_OpenCodexDesktop", withExtension: "bundle"),
            let bundle = Bundle(url: url)
        {
            return bundle
        }
        return Bundle.module
    }()

    static func bundle(for language: Language) -> Bundle {
        guard let path = resourceBundle.path(forResource: language.rawValue.lowercased(), ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return resourceBundle }
        return bundle
    }

    /// An interpolation-safe localization key: arguments never become lookup keys or format strings.
    struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
        let key: String
        let arguments: [String]

        init(stringLiteral value: String) {
            key = value
            arguments = []
        }

        init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []

            init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity)
                arguments.reserveCapacity(interpolationCount)
            }

            mutating func appendLiteral(_ literal: String) { key += literal }

            mutating func appendInterpolation<T>(_ value: T) {
                arguments.append(String(describing: value))
                key += "%\(arguments.count)$@"
            }
        }
    }

    static func tr(_ message: Message, language: Language = language) -> String {
        let translated = bundle(for: language).localizedString(forKey: message.key, value: message.key, table: nil)
        // Work on template ranges once: text inside an argument cannot inject another placeholder.
        let expression = try? NSRegularExpression(pattern: #"%(\d+)\$@"#)
        let source = translated as NSString
        let matches = expression?.matches(in: translated, range: NSRange(location: 0, length: source.length)) ?? []
        var result = ""
        var offset = 0
        for match in matches {
            result += source.substring(with: NSRange(location: offset, length: match.range.location - offset))
            let index = Int(source.substring(with: match.range(at: 1))).map { $0 - 1 } ?? -1
            result +=
                message.arguments.indices.contains(index)
                ? message.arguments[index] : source.substring(with: match.range)
            offset = NSMaxRange(match.range)
        }
        result += source.substring(from: offset)
        return result
    }

    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, locale: locale, bundle: .atURL(bundle(for: language).bundleURL))
    }
}
