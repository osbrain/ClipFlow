import Foundation
import Testing
@testable import ClipFlowCore

@Suite("History search")
struct SearchQueryTests {
    @Test("ranks title matches before body matches and filters favorites")
    func titleMatchRanksBeforeBodyAndFavoriteFilterApplies() {
        let query = SearchQuery(
            text: "road map",
            categoryID: nil,
            kind: nil,
            favoritesOnly: true
        )
        let titleMatch = ItemSearchDocument(
            id: UUID(),
            title: "Road Map",
            body: "x",
            appName: "Notes",
            isFavorite: true
        )
        let bodyMatch = ItemSearchDocument(
            id: UUID(),
            title: "x",
            body: "the road map for launch",
            appName: "Notes",
            isFavorite: true
        )
        let notFavorite = ItemSearchDocument(
            id: UUID(),
            title: "Road Map",
            body: "",
            appName: "Notes",
            isFavorite: false
        )

        #expect(query.score(titleMatch)! < query.score(bodyMatch)!)
        #expect(query.score(notFavorite) == nil)
    }

    @Test("requires every search token to match")
    func everyTokenMustMatch() {
        let query = SearchQuery(
            text: "release checklist",
            categoryID: nil,
            kind: nil,
            favoritesOnly: false
        )
        let partial = ItemSearchDocument(
            id: UUID(),
            title: "Release notes",
            body: "",
            appName: "Notes",
            isFavorite: false
        )

        #expect(query.score(partial) == nil)
    }
}

