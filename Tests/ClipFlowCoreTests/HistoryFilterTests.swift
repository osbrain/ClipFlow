import ClipFlowCore
import Foundation
import Testing
@testable import ClipFlowUI

@Suite("History filters")
struct HistoryFilterTests {
    @Test("compact filter strips keep universal filters visible")
    func compactFilterStripPriorities() {
        #expect(HistoryFilterStripLayout.isPrimary(.all))
        #expect(HistoryFilterStripLayout.isPrimary(.favorites))
        #expect(!HistoryFilterStripLayout.isPrimary(.kind(.text)))
        #expect(!HistoryFilterStripLayout.isPrimary(.browserTabs))
    }

    @Test("compact overflow menu stays highlighted for selected overflow filters")
    func compactOverflowMenuSelectionPersists() {
        let categoryID = UUID()

        #expect(!HistoryFilterStripLayout.isOverflowMenuSelected(.all))
        #expect(!HistoryFilterStripLayout.isOverflowMenuSelected(.favorites))
        #expect(HistoryFilterStripLayout.isOverflowMenuSelected(.kind(.text)))
        #expect(HistoryFilterStripLayout.isOverflowMenuSelected(.kind(.image)))
        #expect(HistoryFilterStripLayout.isOverflowMenuSelected(.category(categoryID)))
        #expect(HistoryFilterStripLayout.isOverflowMenuSelected(.browserTabs))
    }

    @Test("kind filters map to one exclusive repository kind")
    func kindMappingIsExclusive() {
        #expect(
            HistoryFilter.kind(.image).repositoryState ==
                HistoryRepositoryFilterState(
                    kind: .image,
                    categoryID: nil,
                    favoritesOnly: false
                )
        )
    }

    @Test("favorites maps only the favorites repository flag")
    func favoritesMappingIsExclusive() {
        #expect(
            HistoryFilter.favorites.repositoryState ==
                HistoryRepositoryFilterState(
                    kind: nil,
                    categoryID: nil,
                    favoritesOnly: true
                )
        )
    }

    @Test("all browser and category mappings are exact")
    func remainingMappingsAreExact() {
        let categoryID = UUID()

        #expect(
            HistoryFilter.all.repositoryState ==
                HistoryRepositoryFilterState(
                    kind: nil,
                    categoryID: nil,
                    favoritesOnly: false
                )
        )
        #expect(
            HistoryFilter.browserTabs.repositoryState ==
                HistoryRepositoryFilterState(
                    kind: nil,
                    categoryID: nil,
                    favoritesOnly: false
                )
        )
        #expect(
            HistoryFilter.category(categoryID).repositoryState ==
                HistoryRepositoryFilterState(
                    kind: nil,
                    categoryID: categoryID,
                    favoritesOnly: false
                )
        )
    }

    @Test("every kind preserves repository filter exclusivity", arguments: ClipboardKind.allTestCases)
    func everyKindMappingIsExclusive(kind: ClipboardKind) {
        let state = HistoryFilter.kind(kind).repositoryState

        #expect(state.kind == kind)
        #expect(state.categoryID == nil)
        #expect(!state.favoritesOnly)
    }
}

private extension ClipboardKind {
    static let allTestCases: [ClipboardKind] = [
        .text, .richText, .image, .file, .link, .mixed, .unknown
    ]
}
