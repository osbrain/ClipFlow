import Foundation
import Testing
@testable import ClipFlowCore

@Suite("Retention policy")
struct RetentionPolicyTests {
    @Test("preserves favorites and removes oldest items until every budget is met")
    func preservesFavoritesAndMeetsBudgets() {
        let oldest = UUID()
        let newer = UUID()
        let favorite = UUID()
        let decision = RetentionPolicy(
            maxAge: nil,
            maxItemCount: 2,
            maxBytes: 100
        ).cleanupCandidates([
            RetentionCandidate(
                id: oldest,
                timestamp: Date(timeIntervalSince1970: 1),
                byteSize: 70,
                isFavorite: false
            ),
            RetentionCandidate(
                id: newer,
                timestamp: Date(timeIntervalSince1970: 2),
                byteSize: 70,
                isFavorite: false
            ),
            RetentionCandidate(
                id: favorite,
                timestamp: Date(timeIntervalSince1970: 3),
                byteSize: 70,
                isFavorite: true
            )
        ], now: Date(timeIntervalSince1970: 10))

        #expect(decision == [oldest, newer])
        #expect(!decision.contains(favorite))
    }

    @Test("removes expired non-favorites before applying count limits")
    func expirationRunsBeforeCountLimit() {
        let expired = UUID()
        let current = UUID()
        let decision = RetentionPolicy(
            maxAge: 10,
            maxItemCount: 10,
            maxBytes: 1_000
        ).cleanupCandidates([
            RetentionCandidate(
                id: expired,
                timestamp: Date(timeIntervalSince1970: 1),
                byteSize: 10,
                isFavorite: false
            ),
            RetentionCandidate(
                id: current,
                timestamp: Date(timeIntervalSince1970: 95),
                byteSize: 10,
                isFavorite: false
            )
        ], now: Date(timeIntervalSince1970: 100))

        #expect(decision == [expired])
    }
}
