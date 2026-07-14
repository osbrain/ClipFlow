import Foundation
import ClipFlowSystem

public enum L10n {
    public static var locale: Locale {
        #if DEBUG
        locale(environment: ProcessInfo.processInfo.environment)
        #else
        .current
        #endif
    }

    public static func string(_ key: String) -> String {
        #if DEBUG
        return string(key, environment: ProcessInfo.processInfo.environment)
        #else
        Bundle.module.localizedString(forKey: key, value: key, table: nil)
        #endif
    }

    public static func string(_ key: String, locale identifier: String) -> String {
        let normalizedIdentifier = identifier.replacingOccurrences(of: "_", with: "-")
        let languageIdentifier = normalizedIdentifier.split(separator: "-").first.map(String.init)
        let candidates = [identifier, normalizedIdentifier, languageIdentifier]
            .compactMap { $0 }
        let path = candidates.lazy.compactMap {
            Bundle.module.path(forResource: $0, ofType: "lproj")
                ?? Bundle.module.path(forResource: $0.lowercased(), ofType: "lproj")
        }.first

        guard let path,
              let bundle = Bundle(path: path) else {
            return key
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func formattedDateTime(_ date: Date) -> String {
        formattedDateTime(date, locale: locale)
    }

    public static func formattedByteCount(_ byteCount: Int) -> String {
        Int64(byteCount).formatted(.byteCount(style: .file).locale(locale))
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    static func locale(environment: [String: String]) -> Locale {
        guard let identifier = environment["CLIPFLOW_LOCALE_IDENTIFIER"],
              !identifier.isEmpty else {
            return .current
        }
        return Locale(identifier: identifier)
    }

    static func string(_ key: String, environment: [String: String]) -> String {
        guard let identifier = environment["CLIPFLOW_LOCALE_IDENTIFIER"],
              !identifier.isEmpty else {
            return Bundle.module.localizedString(forKey: key, value: key, table: nil)
        }
        return string(key, locale: identifier)
    }

    static func formattedDateTime(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

public extension ApplicationAction {
    var localizedDisplayName: String {
        switch self {
        case .openFeishu: L10n.string("action.feishu")
        case .askDoubao: L10n.string("action.doubao")
        }
    }
}
