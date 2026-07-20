import ClipFlowCore

public enum ItemContextAction: String, CaseIterable, Equatable, Hashable, Sendable {
    case pasteOriginal
    case pastePlainText
    case pasteFilePath
    case copyOriginal
    case copyPlainText
    case copyMarkdownLink
    case copyFilePath
    case copyCleanText
    case copyFirstLine
    case copyURLs
    case openLink
    case openFile
    case revealInFinder
    case quickLook

    public static func available(for kind: ClipboardKind) -> [Self] {
        switch kind {
        case .text:
            [
                .pasteOriginal, .pastePlainText,
                .copyOriginal, .copyPlainText, .copyCleanText,
                .copyFirstLine, .copyURLs, .quickLook
            ]
        case .richText:
            [
                .pasteOriginal, .pastePlainText,
                .copyOriginal, .copyPlainText, .copyCleanText,
                .copyFirstLine, .copyURLs, .quickLook
            ]
        case .link:
            [
                .pasteOriginal, .openLink, .pastePlainText,
                .copyOriginal, .copyPlainText, .copyMarkdownLink,
                .copyCleanText, .copyFirstLine, .copyURLs, .quickLook
            ]
        case .file:
            [
                .pasteOriginal, .pasteFilePath, .openFile, .revealInFinder,
                .copyOriginal, .copyFilePath, .quickLook
            ]
        case .image:
            [.pasteOriginal, .copyOriginal, .quickLook]
        case .mixed:
            [
                .pasteOriginal, .pastePlainText,
                .copyOriginal, .copyPlainText, .copyCleanText,
                .copyFirstLine, .copyURLs, .quickLook
            ]
        case .unknown:
            [.pasteOriginal, .copyOriginal, .quickLook]
        }
    }

    public var localizationKey: String {
        "contextAction.\(rawValue)"
    }

    public var symbolName: String {
        switch self {
        case .pasteOriginal: "arrow.down.doc"
        case .pastePlainText: "doc.plaintext"
        case .pasteFilePath: "point.topleft.down.to.point.bottomright.curvepath"
        case .copyOriginal: "doc.on.doc"
        case .copyPlainText: "doc.text"
        case .copyMarkdownLink: "link.badge.plus"
        case .copyFilePath: "point.topleft.down.to.point.bottomright.curvepath"
        case .copyCleanText: "wand.and.sparkles"
        case .copyFirstLine: "text.line.first.and.arrowtriangle.forward"
        case .copyURLs: "link"
        case .openLink: "safari"
        case .openFile: "doc.badge.arrow.up"
        case .revealInFinder: "folder"
        case .quickLook: "eye"
        }
    }

    public var isContentOperation: Bool {
        switch self {
        case .copyOriginal, .copyPlainText, .copyMarkdownLink, .copyFilePath,
             .copyCleanText, .copyFirstLine, .copyURLs:
            true
        case .pasteOriginal, .pastePlainText, .pasteFilePath,
             .openLink, .openFile, .revealInFinder, .quickLook:
            false
        }
    }

    public func titleKey(for kind: ClipboardKind) -> String {
        guard self == .pasteOriginal else { return localizationKey }
        return "contextAction.pasteOriginal.\(kind.rawValue)"
    }
}
