import CryptoKit
import Foundation
import Testing
import ClipFlowCore
@testable import ClipFlowStorage

@Suite("Clipboard performance smoke", .serialized)
struct ClipboardPerformanceSmokeTests {
    @Test("one thousand and ten thousand item histories stay bounded")
    func largeHistoriesStayBounded() throws {
        for itemCount in [1_000, 10_000] {
            let harness = try PerformanceRepositoryHarness()
            defer { harness.cleanup() }
            try harness.seed(itemCount: itemCount)
            let categoryQueries = SmokeCounter()
            harness.database.setQueryObserver { sql in
                if sql == "SELECT item_id, category_id FROM item_categories;" {
                    categoryQueries.increment()
                }
            }
            let query = SearchQuery(
                text: "",
                categoryID: nil,
                kind: nil,
                favoritesOnly: false
            )
            let clock = ContinuousClock()
            let start = clock.now

            let results = try harness.repository.search(query, limit: 500)

            let elapsed = start.duration(to: clock.now)
            #expect(results.count == 500)
            #expect(results.first?.previewText == "Item \(itemCount - 1)")
            #expect(results.last?.previewText == "Item \(itemCount - 500)")
            #expect(categoryQueries.value == 1)
            #expect(elapsed < .seconds(10))
        }
    }

    @Test("recency ordering uses its database index")
    func recencyOrderingUsesIndex() throws {
        let harness = try PerformanceRepositoryHarness()
        defer { harness.cleanup() }

        let rows = try harness.database.query(
            """
            EXPLAIN QUERY PLAN
            SELECT id FROM clipboard_items
            ORDER BY COALESCE(last_used_at, updated_at) DESC, updated_at DESC
            LIMIT 500;
            """
        )
        let details = rows.compactMap { row -> String? in
            guard case .text(let value) = row["detail"] else { return nil }
            return value
        }

        #expect(details.contains { $0.contains("idx_items_recency") })
    }

    @Test("rapid equivalent rich copies store one row")
    func rapidEquivalentCopiesStoreOneRow() throws {
        let harness = try PerformanceRepositoryHarness()
        defer { harness.cleanup() }
        let normalizer = ClipboardNormalizer(
            maxRepresentationBytes: 10_000,
            maxCaptureBytes: 20_000
        )
        var insertedCount = 0
        var refreshedCount = 0

        for index in 0..<200 {
            let capture = RawClipboardCapture(
                sourceAppName: index.isMultiple(of: 2) ? "Notes" : "Safari",
                sourceBundleID: nil,
                items: [
                    RawClipboardItem(representations: index.isMultiple(of: 2)
                        ? [
                            RawClipboardRepresentation(
                                type: "public.utf8-plain-text",
                                data: Data("Same value".utf8)
                            )
                        ]
                        : [
                            RawClipboardRepresentation(
                                type: "public.html",
                                data: Data("<b>Same value</b>".utf8)
                            ),
                            RawClipboardRepresentation(
                                type: "public.utf8-plain-text",
                                data: Data("Same value".utf8)
                            )
                        ])
                ]
            )
            let result = try harness.repository.upsert(
                normalizer.normalize(capture),
                timestamp: Date(timeIntervalSince1970: TimeInterval(index))
            )
            if result.disposition == .inserted {
                insertedCount += 1
            } else {
                refreshedCount += 1
            }
        }

        let results = try harness.repository.search(
            SearchQuery(text: "", categoryID: nil, kind: nil, favoritesOnly: false),
            limit: 500
        )
        #expect(insertedCount == 1)
        #expect(refreshedCount == 199)
        #expect(results.count == 1)
        #expect(results.first?.updatedAt == Date(timeIntervalSince1970: 199))
    }

    @Test("history row source contains no live relative timer or row material")
    func historyRowsStayStatic() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/ClipFlowUI/MainPanelView.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("Text(item.updatedAt, style: .relative)"))
        #expect(!source.contains("isSelected ? AnyShapeStyle(.thinMaterial)"))
        #expect(source.contains("HistoryTimePresentation.text(for: item.updatedAt)"))
    }
}

private final class PerformanceRepositoryHarness {
    let root: URL
    let database: SQLCipherDatabase
    let repository: ClipboardRepository

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        database = try SQLCipherDatabase(
            url: root.appendingPathComponent("ClipFlow.sqlite"),
            key: Data(repeating: 0x71, count: 32)
        )
        repository = try ClipboardRepository(
            database: database,
            externalPayloadStore: ExternalPayloadStore(
                root: root.appendingPathComponent("Payloads", isDirectory: true),
                key: SymmetricKey(size: .bits256)
            ),
            externalThresholdBytes: 1_000_000
        )
    }

    func seed(itemCount: Int) throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<itemCount {
            let preview = "Item \(index)"
            _ = try repository.upsert(
                NormalizedCapture(
                    sourceAppName: "Smoke",
                    sourceBundleID: "local.clipflow.smoke",
                    kind: .text,
                    previewText: preview,
                    searchText: preview.lowercased(),
                    byteSize: preview.utf8.count,
                    contentHash: "smoke-\(index)",
                    payloads: [
                        NormalizedPayload(
                            itemIndex: 0,
                            type: "public.utf8-plain-text",
                            data: Data(preview.utf8)
                        )
                    ]
                ),
                timestamp: base.addingTimeInterval(TimeInterval(index))
            )
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class SmokeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}
