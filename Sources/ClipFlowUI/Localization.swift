import Foundation
import ClipFlowSystem

public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public var localeIdentifier: String? {
        self == .system ? nil : rawValue
    }

    public var localizationKey: String {
        switch self {
        case .system: "settings.language.system"
        case .simplifiedChinese: "settings.language.simplifiedChinese"
        case .english: "settings.language.english"
        }
    }
}

public enum L10n {
    private static let languageLock = NSLock()
    nonisolated(unsafe) private static var configuredLanguage: AppLanguage = .system

    public static func configure(language: AppLanguage) {
        languageLock.withLock {
            configuredLanguage = language
        }
    }

    public static var locale: Locale {
        #if DEBUG
        if let identifier = environmentLocaleIdentifier(
            ProcessInfo.processInfo.environment
        ) {
            return Locale(identifier: identifier)
        }
        #endif
        return effectiveLocaleIdentifier(
            language: configuredLanguageSnapshot,
            preferredLanguages: Locale.preferredLanguages
        ).map(Locale.init(identifier:)) ?? .current
    }

    public static func string(_ key: String) -> String {
        #if DEBUG
        if let identifier = environmentLocaleIdentifier(
            ProcessInfo.processInfo.environment
        ) {
            return string(key, locale: identifier)
        }
        #endif
        guard let identifier = effectiveLocaleIdentifier(
            language: configuredLanguageSnapshot,
            preferredLanguages: Locale.preferredLanguages
        ) else {
            return resourceBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return string(key, locale: identifier)
    }

    public static func string(_ key: String, locale identifier: String) -> String {
        let normalizedIdentifier = identifier.replacingOccurrences(of: "_", with: "-")
        let languageIdentifier = normalizedIdentifier.split(separator: "-").first.map(String.init)
        let candidates = [identifier, normalizedIdentifier, languageIdentifier]
            .compactMap { $0 }
        let path = candidates.lazy.compactMap {
            resourceBundle.path(forResource: $0, ofType: "lproj")
                ?? resourceBundle.path(forResource: $0.lowercased(), ofType: "lproj")
        }.first

        guard let path,
              let bundle = Bundle(path: path) else {
            return key
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func string(_ key: String, language: AppLanguage) -> String {
        string(
            key,
            language: language,
            preferredLanguages: Locale.preferredLanguages
        )
    }

    static func string(
        _ key: String,
        language: AppLanguage,
        preferredLanguages: [String]
    ) -> String {
        guard let identifier = effectiveLocaleIdentifier(
            language: language,
            preferredLanguages: preferredLanguages
        ) else {
            return resourceBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return string(key, locale: identifier)
    }

    public static func locale(for language: AppLanguage) -> Locale {
        effectiveLocaleIdentifier(
            language: language,
            preferredLanguages: Locale.preferredLanguages
        ).map(Locale.init(identifier:)) ?? .current
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
        guard let identifier = environmentLocaleIdentifier(environment) else {
            return .current
        }
        return Locale(identifier: identifier)
    }

    static func string(_ key: String, environment: [String: String]) -> String {
        guard let identifier = environmentLocaleIdentifier(environment) else {
            return resourceBundle.localizedString(forKey: key, value: key, table: nil)
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

    static func systemLanguageIdentifier(
        preferredLanguages: [String]
    ) -> String? {
        for identifier in preferredLanguages {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized == "zh" || normalized.hasPrefix("zh-hans") ||
                normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") {
                return "zh-Hans"
            }
            if normalized == "en" || normalized.hasPrefix("en-") {
                return "en"
            }
        }
        return nil
    }

    private static var configuredLanguageSnapshot: AppLanguage {
        languageLock.withLock { configuredLanguage }
    }

    private static var resourceBundle: Bundle {
        ClipFlowResourceBundle.bundle
    }

    private static func effectiveLocaleIdentifier(
        language: AppLanguage,
        preferredLanguages: [String]
    ) -> String? {
        language.localeIdentifier ?? systemLanguageIdentifier(
            preferredLanguages: preferredLanguages
        )
    }

    private static func environmentLocaleIdentifier(
        _ environment: [String: String]
    ) -> String? {
        guard let identifier = environment["CLIPFLOW_LOCALE_IDENTIFIER"],
              !identifier.isEmpty else {
            return nil
        }
        return identifier
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
