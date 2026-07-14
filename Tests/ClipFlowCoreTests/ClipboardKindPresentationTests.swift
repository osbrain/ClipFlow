import ClipFlowCore
import ClipFlowSystem
import Foundation
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

    @Test("debug locale override selects matching translations")
    func debugLocaleOverrideSelectsTranslations() {
        let chineseEnvironment = ["CLIPFLOW_LOCALE_IDENTIFIER": "zh-Hans"]
        let englishEnvironment = ["CLIPFLOW_LOCALE_IDENTIFIER": "en"]

        #expect(L10n.locale(environment: chineseEnvironment).identifier == "zh-Hans")
        #expect(L10n.locale(environment: englishEnvironment).identifier == "en")
        #expect(L10n.string("filter.all", environment: chineseEnvironment) == "全部")
        #expect(L10n.string("filter.all", environment: englishEnvironment) == "All")
    }

    @Test("date formatting follows the supplied locale")
    func dateFormattingFollowsLocale() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let english = L10n.formattedDateTime(
            date,
            locale: Locale(identifier: "en_US")
        )
        let chinese = L10n.formattedDateTime(
            date,
            locale: Locale(identifier: "zh_Hans_CN")
        )

        #expect(english.contains("Nov"))
        #expect(chinese.contains("11月"))
        #expect(english != chinese)
    }

    @Test("UI action labels and user messages have English and Chinese translations")
    func uiMessagesHaveTranslations() {
        let keys = [
            "onboarding.subtitle",
            "onboarding.localEncryption",
            "onboarding.enabled",
            "onboarding.automaticPaste",
            "onboarding.granted",
            "onboarding.optional",
            "onboarding.accessibilitySettings",
            "onboarding.continue",
            "error.preview",
            "error.action",
            "error.history.load",
            "error.paste",
            "error.favorite",
            "error.rename",
            "error.delete",
            "error.category.create",
            "error.category.assign",
            "error.category.delete",
            "error.browser.activate",
            "error.contextAction",
            "action.feishu",
            "action.doubao",
            "contextAction.pasteOriginal.text",
            "contextAction.pasteOriginal.richText",
            "contextAction.pasteOriginal.image",
            "contextAction.pasteOriginal.file",
            "contextAction.pasteOriginal.link",
            "contextAction.pasteOriginal.mixed",
            "contextAction.pasteOriginal.unknown",
            "contextAction.pastePlainText",
            "contextAction.pasteFilePath",
            "contextAction.openLink",
            "contextAction.openFile",
            "contextAction.revealInFinder",
            "contextAction.quickLook",
            "settings.language",
            "settings.language.system",
            "settings.language.simplifiedChinese",
            "settings.language.english",
            "settings.error.shortcut",
            "settings.error.loginItem",
            "settings.error.runtime",
            "settings.dismissError",
            "settings.logPath",
            "settings.logNotCreated",
            "settings.revealLog",
            "header.pasteTarget",
            "header.clipboardTarget"
        ]

        for key in keys {
            #expect(L10n.string(key, locale: "en") != key)
            #expect(L10n.string(key, locale: "zh-Hans") != key)
        }
        #expect(ApplicationAction.openFeishu.localizedDisplayName == L10n.string("action.feishu"))
        #expect(ApplicationAction.askDoubao.localizedDisplayName == L10n.string("action.doubao"))
        #expect(L10n.format("error.action", "Feishu").contains("Feishu"))
    }
}
