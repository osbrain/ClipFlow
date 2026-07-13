import ClipFlowCore
import Testing
@testable import ClipFlowUI

@Suite("Clipboard kind presentation")
struct ClipboardKindPresentationTests {
    @Test("each kind has a stable symbol and accent")
    func presentations() {
        let expected: [(ClipboardKind, ClipboardKindPresentation)] = [
            (.text, ClipboardKindPresentation(symbolName: "text.alignleft", accent: .blue)),
            (.richText, ClipboardKindPresentation(symbolName: "doc.richtext", accent: .indigo)),
            (.image, ClipboardKindPresentation(symbolName: "photo", accent: .green)),
            (.file, ClipboardKindPresentation(symbolName: "doc", accent: .orange)),
            (.link, ClipboardKindPresentation(symbolName: "link", accent: .teal)),
            (.mixed, ClipboardKindPresentation(symbolName: "square.stack.3d.up", accent: .pink)),
            (.unknown, ClipboardKindPresentation(symbolName: "questionmark.square.dashed", accent: .gray))
        ]

        for (kind, presentation) in expected {
            #expect(kind.presentation == presentation)
        }
    }

    @Test("each kind has localized English and Simplified Chinese names")
    func localizedDisplayNames() {
        let expected: [(ClipboardKind, String, String, String)] = [
            (.text, "kind.text", "Text", "文本"),
            (.richText, "kind.richText", "Rich Text", "富文本"),
            (.image, "kind.image", "Image", "图片"),
            (.file, "kind.file", "File", "文件"),
            (.link, "kind.link", "Link", "链接"),
            (.mixed, "kind.mixed", "Mixed", "混合内容"),
            (.unknown, "kind.unknown", "Unknown", "未知类型")
        ]

        for (kind, key, english, simplifiedChinese) in expected {
            #expect(kind.localizedDisplayName == L10n.string(key))
            #expect(L10n.string(key, locale: "en") == english)
            #expect(L10n.string(key, locale: "zh-Hans") == simplifiedChinese)
        }
    }
}
