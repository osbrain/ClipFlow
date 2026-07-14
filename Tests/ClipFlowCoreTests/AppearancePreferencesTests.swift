import SwiftUI
import Testing
@testable import ClipFlowUI

@Suite("Appearance preferences")
struct AppearancePreferencesTests {
    @Test("appearance modes map to color schemes")
    func appearanceModeColorSchemes() {
        #expect(ClipFlowAppearanceMode.system.colorScheme == nil)
        #expect(ClipFlowAppearanceMode.light.colorScheme == .light)
        #expect(ClipFlowAppearanceMode.dark.colorScheme == .dark)
    }

    @Test("list densities provide row heights")
    func listDensityRowHeights() {
        #expect(ClipFlowListDensity.comfortable.rowHeight == 74)
        #expect(ClipFlowListDensity.compact.rowHeight == 62)
    }

    @Test("localized strings load for an explicit locale")
    func localizedStrings() {
        #expect(L10n.string("app.name", locale: "en") == "ClipFlow")
        #expect(L10n.string("settings.title", locale: "zh-Hans") == "设置")
        #expect(L10n.string("history.search.placeholder", locale: "zh-Hans").contains("搜索"))
    }

    @Test("application languages have stable values and select explicit resources")
    func applicationLanguages() {
        #expect(AppLanguage.allCases == [.system, .simplifiedChinese, .english])
        #expect(AppLanguage.system.localeIdentifier == nil)
        #expect(AppLanguage.simplifiedChinese.localeIdentifier == "zh-Hans")
        #expect(AppLanguage.english.localeIdentifier == "en")

        #expect(
            L10n.string("settings.title", language: .simplifiedChinese) == "设置"
        )
        #expect(L10n.locale(for: .simplifiedChinese).identifier.hasPrefix("zh"))
        #expect(L10n.string("settings.title", language: .english) == "Settings")
        #expect(L10n.locale(for: .english).identifier.hasPrefix("en"))
    }
}
