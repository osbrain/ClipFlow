import ClipFlowCore

public enum ItemContextAction: String, CaseIterable, Equatable, Hashable, Sendable {
    case pasteOriginal
    case pastePlainText
    case pasteFilePath
    case openLink
    case openFile
    case revealInFinder
    case quickLook

    public static func available(for kind: ClipboardKind) -> [Self] {
        switch kind {
        case .text:
            [.pasteOriginal, .pastePlainText, .quickLook]
        case .richText:
            [.pasteOriginal, .pastePlainText, .quickLook]
        case .link:
            [.pasteOriginal, .openLink, .pastePlainText, .quickLook]
        case .file:
            [.pasteOriginal, .pasteFilePath, .openFile, .revealInFinder, .quickLook]
        case .image:
            [.pasteOriginal, .quickLook]
        case .mixed:
            [.pasteOriginal, .pastePlainText, .quickLook]
        case .unknown:
            [.pasteOriginal, .quickLook]
        }
    }

    public var localizationKey: String {
        "contextAction.\(rawValue)"
    }

    public var symbolName: String {
        switch self {
        case .pasteOriginal: "arrow.down.doc"
        case .pastePlainText: "textformat"
        case .pasteFilePath: "point.topleft.down.to.point.bottomright.curvepath"
        case .openLink: "safari"
        case .openFile: "doc.badge.arrow.up"
        case .revealInFinder: "folder"
        case .quickLook: "eye"
        }
    }

    public func titleKey(for kind: ClipboardKind) -> String {
        guard self == .pasteOriginal else { return localizationKey }
        return "contextAction.pasteOriginal.\(kind.rawValue)"
    }
}
