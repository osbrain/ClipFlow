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
        #expect(L10n.string("app.name", locale: "zh-Hans") == "拾笺")
        #expect(
            L10n.string("menu.show", locale: "zh-Hans") == "显示主控面板"
        )
        #expect(
            String(
                format: L10n.string("menu.status.shortcut", locale: "zh-Hans"),
                "⌘⇧V"
            ) == "唤起面板快捷键：⌘⇧V"
        )
        #expect(L10n.string("settings.title", locale: "zh-Hans") == "设置")
        #expect(L10n.string("history.search.placeholder", locale: "zh-Hans").contains("搜索"))
        #expect(L10n.string("settings.retention.help", locale: "zh-Hans").contains("自动清理"))
        #expect(L10n.string("settings.accessibility.help", locale: "zh-Hans").contains("自动粘贴"))
        #expect(L10n.string("settings.openSource", locale: "en") == "Open Source")
        #expect(L10n.string("settings.openSource", locale: "zh-Hans") == "开源项目")
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

    @Test("system language follows the first supported macOS preferred language")
    func systemLanguageFollowsMacOSPreferences() {
        #expect(
            L10n.systemLanguageIdentifier(
                preferredLanguages: ["zh-Hans-CN", "en-US"]
            ) == "zh-Hans"
        )
        #expect(
            L10n.string(
                "settings.title",
                language: .system,
                preferredLanguages: ["zh-Hans-CN", "en-US"]
            ) == "设置"
        )
        #expect(
            L10n.systemLanguageIdentifier(
                preferredLanguages: ["fr-FR", "en-US"]
            ) == "en"
        )
    }

    @Test("settings sidebar uses concise localized category labels")
    func settingsSidebarUsesConciseLocalizedCategoryLabels() {
        #expect(L10n.string("settings.sidebar.storage", locale: "en") == "Storage")
        #expect(L10n.string("settings.sidebar.permissions", locale: "en") == "Permissions")
        #expect(L10n.string("settings.sidebar.details", locale: "en") == "Details")
        #expect(L10n.string("settings.sidebar.storage", locale: "zh-Hans") == "存储")
        #expect(L10n.string("settings.sidebar.permissions", locale: "zh-Hans") == "权限")
        #expect(L10n.string("settings.sidebar.details", locale: "zh-Hans") == "详情")
    }
}
