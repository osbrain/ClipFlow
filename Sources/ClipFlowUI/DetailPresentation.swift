import ClipFlowCore
import CoreGraphics

public enum DetailField: Equatable, Sendable {
    case source
    case kind
    case created
    case lastUsed
    case size
    case formatting
}

public enum DetailPreviewMode: Equatable, Sendable {
    case text
    case image
    case file
    case link
    case mixed
    case unknown
}

public enum DetailPreviewLayout {
    public static let imageMaximumHeight: CGFloat = 200

    public static func lineLimit(for mode: DetailPreviewMode) -> Int? {
        switch mode {
        case .text: 8
        case .link, .file, .unknown: 5
        case .mixed: 6
        case .image: nil
        }
    }
}

public enum DetailActionPresentation {
    public static func stackActions(
        from actions: [ItemContextAction]
    ) -> [ItemContextAction] {
        actions.filter { $0 != .quickLook }
    }
}

public struct DetailFieldVisibility: Equatable, Sendable {
    public let showsSource: Bool
    public let showsKind: Bool
    public let showsCreated: Bool
    public let showsLastUsed: Bool
    public let showsSize: Bool
    public let showsFormatting: Bool

    public init(
        showsSource: Bool,
        showsKind: Bool,
        showsCreated: Bool,
        showsLastUsed: Bool,
        showsSize: Bool,
        showsFormatting: Bool
    ) {
        self.showsSource = showsSource
        self.showsKind = showsKind
        self.showsCreated = showsCreated
        self.showsLastUsed = showsLastUsed
        self.showsSize = showsSize
        self.showsFormatting = showsFormatting
    }

    public var visibleFields: [DetailField] {
        [
            showsSource ? .source : nil,
            showsKind ? .kind : nil,
            showsCreated ? .created : nil,
            showsLastUsed ? .lastUsed : nil,
            showsSize ? .size : nil,
            showsFormatting ? .formatting : nil
        ].compactMap { $0 }
    }
}

public extension ClipboardKind {
    var detailPreviewMode: DetailPreviewMode {
        switch self {
        case .text, .richText: .text
        case .image: .image
        case .file: .file
        case .link: .link
        case .mixed: .mixed
        case .unknown: .unknown
        }
    }

    var hasFormatting: Bool {
        self == .richText || self == .mixed
    }

    var localizedFormattingAvailability: String {
        L10n.string(hasFormatting ? "detail.available" : "detail.unavailable")
    }
}
