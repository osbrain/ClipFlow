import ClipFlowCore
import SwiftUI

public struct ClipboardKindPresentation: Equatable, Sendable {
    public let symbolName: String
    public let accent: ClipFlowAccent

    public init(symbolName: String, accent: ClipFlowAccent) {
        self.symbolName = symbolName
        self.accent = accent
    }
}

public enum ClipFlowAccent: String, Equatable, Sendable {
    case blue
    case indigo
    case teal
    case green
    case orange
    case pink
    case gray

    public var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .gray: .gray
        }
    }
}

public extension ClipboardKind {
    var presentation: ClipboardKindPresentation {
        switch self {
        case .text:
            ClipboardKindPresentation(symbolName: "text.alignleft", accent: .blue)
        case .richText:
            ClipboardKindPresentation(symbolName: "doc.richtext", accent: .indigo)
        case .image:
            ClipboardKindPresentation(symbolName: "photo", accent: .green)
        case .file:
            ClipboardKindPresentation(symbolName: "doc", accent: .orange)
        case .link:
            ClipboardKindPresentation(symbolName: "link", accent: .teal)
        case .mixed:
            ClipboardKindPresentation(symbolName: "square.stack.3d.up", accent: .pink)
        case .unknown:
            ClipboardKindPresentation(symbolName: "questionmark.square.dashed", accent: .gray)
        }
    }

    var localizedDisplayName: String {
        let key = switch self {
        case .text: "kind.text"
        case .richText: "kind.richText"
        case .image: "kind.image"
        case .file: "kind.file"
        case .link: "kind.link"
        case .mixed: "kind.mixed"
        case .unknown: "kind.unknown"
        }

        return L10n.string(key)
    }
}
