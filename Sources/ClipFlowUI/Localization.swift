import Foundation

public enum L10n {
    public static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }

    public static func string(_ key: String, locale identifier: String) -> String {
        let path = Bundle.module.path(forResource: identifier, ofType: "lproj")
            ?? Bundle.module.path(forResource: identifier.lowercased(), ofType: "lproj")

        guard let path,
              let bundle = Bundle(path: path) else {
            return key
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
