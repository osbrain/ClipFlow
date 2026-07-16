# Clipboard Deduplication and Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deduplicate semantically equivalent clipboard captures, avoid expensive duplicate rewrites and full reloads, reduce list rendering work, and add deterministic performance smoke coverage.

**Architecture:** `ClipboardNormalizer` owns stable semantic identity, `ClipboardRepository` reports inserted versus refreshed writes, and a focused capture processor connects monitoring to retention and incremental model updates. Search loads category membership in bulk, row time is a pure static presentation value, and repeated list surfaces use solid appearance-aware fills rather than live material layers.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Observation, CryptoKit, SQLCipher/SQLite, Swift Testing.

---

## File Structure

- Modify `Sources/ClipFlowCore/ClipboardNormalizer.swift`: semantic fingerprint generation.
- Modify `Sources/ClipFlowStorage/ClipboardRepository.swift`: explicit upsert result, metadata-only duplicate path, bulk category loading, bounded search.
- Create `Sources/ClipFlowUI/HistoryTimePresentation.swift`: pure static time-bucket formatter.
- Modify `Sources/ClipFlowUI/AppModel.swift`: bounded repository query and incremental captured-item refresh.
- Create `Sources/ClipFlowUI/ClipboardCaptureProcessor.swift`: testable capture orchestration shared with the app target.
- Modify `Sources/ClipFlowApp/ClipFlowApp.swift`: replace inline capture closure with processor.
- Modify `Sources/ClipFlowUI/MainPanelView.swift`: static time text and low-cost row fills.
- Modify `Sources/ClipFlowUI/VisualComponents.swift`: replace repeated card material where used in scrolling content.
- Modify `Tests/ClipFlowCoreTests/ClipboardNormalizerTests.swift`: semantic identity cases.
- Modify `Tests/ClipFlowCoreTests/ClipboardRepositoryTests.swift`: duplicate fast-path and bulk-query behavior.
- Modify `Tests/ClipFlowCoreTests/AppModelTests.swift`: incremental refresh behavior.
- Modify `Tests/ClipFlowCoreTests/PasteboardMonitorTests.swift`: idle polling smoke coverage.
- Create `Tests/ClipFlowCoreTests/HistoryTimePresentationTests.swift`: deterministic time buckets.
- Create `Tests/ClipFlowCoreTests/ClipboardPerformanceSmokeTests.swift`: large-history smoke tests.

### Task 1: Stable semantic clipboard identity

**Files:**
- Modify: `Tests/ClipFlowCoreTests/ClipboardNormalizerTests.swift`
- Modify: `Sources/ClipFlowCore/ClipboardNormalizer.swift`

- [ ] **Step 1: Write failing semantic-identity tests**

Add tests that normalize the same visible text with plain-only and plain+HTML/RTF payloads, canonical URL representations, standardized file URLs, and distinct text values:

```swift
@Test("Equivalent rich representations share a semantic hash")
func equivalentRichRepresentationsShareHash() throws {
    let plain = try normalizer.normalize(capture(representations: [
        .init(type: "public.utf8-plain-text", data: Data("Hello\nworld".utf8))
    ]))
    let rich = try normalizer.normalize(capture(representations: [
        .init(type: "public.html", data: Data("<p>Hello<br>world</p>".utf8)),
        .init(type: "public.rtf", data: Data("{\\rtf1 Hello\\line world}".utf8)),
        .init(type: "public.utf8-plain-text", data: Data("Hello\r\nworld".utf8))
    ]))

    #expect(plain.contentHash == rich.contentHash)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift run ClipFlowCoreTests --filter ClipboardNormalizerTests`

Expected: the companion-representation and canonical URL/file tests fail because the current hash includes every type and payload byte.

- [ ] **Step 3: Implement semantic fingerprint selection**

Replace `contentHash(for:)` with a kind-aware digest that feeds an explicit version, item boundary, semantic kind, and canonical primary representation. Reuse `decodedPlainText`, `inferredWebURL`, `inferredFileURL`, and the existing length-prefixed SHA-256 helpers. Preserve the full-payload digest as the binary/unknown fallback.

```swift
private static func semanticContentHash(
    for payloads: [NormalizedPayload],
    kind: ClipboardKind
) -> String {
    var hasher = SHA256()
    update(&hasher, data: Data("clipflow-semantic-v1".utf8))
    update(&hasher, data: Data(kind.rawValue.utf8))
    for (itemIndex, itemPayloads) in Dictionary(grouping: payloads, by: \.itemIndex)
        .sorted(by: { $0.key < $1.key }) {
        update(&hasher, integer: itemIndex)
        let identity = semanticIdentity(for: itemPayloads, kind: semanticKind(for: itemPayloads))
        update(&hasher, data: identity)
    }
    return hex(hasher.finalize())
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift run ClipFlowCoreTests --filter ClipboardNormalizerTests`

Expected: all clipboard normalization tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipFlowCore/ClipboardNormalizer.swift Tests/ClipFlowCoreTests/ClipboardNormalizerTests.swift
git commit -m "fix: deduplicate semantic clipboard content"
```

### Task 2: Repository duplicate fast path

**Files:**
- Modify: `Tests/ClipFlowCoreTests/ClipboardRepositoryTests.swift`
- Modify: `Sources/ClipFlowStorage/ClipboardRepository.swift`

- [ ] **Step 1: Write failing fast-path tests**

Replace the existing replacement-payload expectation with explicit inserted/refreshed assertions. Seed an external payload, favorite, title, and category; copy the same hash with new source metadata and different payload bytes; assert that the ID and stored payload/reference are preserved while source/time change.

```swift
let first = try harness.repository.upsert(original, timestamp: firstDate)
let repeated = try harness.repository.upsert(replacement, timestamp: secondDate)
#expect(first.disposition == .inserted)
#expect(repeated.disposition == .refreshed)
#expect(repeated.item.id == first.item.id)
#expect(repeated.item.updatedAt == secondDate)
#expect(try harness.repository.payloads(for: first.item.id).first?.data == originalData)
```

- [ ] **Step 2: Run the repository tests and verify RED**

Run: `swift run ClipFlowCoreTests --filter ClipboardRepositoryTests`

Expected: compile/test failure because `ClipboardUpsertResult` and `disposition` do not exist and current code replaces payloads.

- [ ] **Step 3: Add the explicit result and early duplicate transaction**

Introduce:

```swift
public enum ClipboardUpsertDisposition: Equatable, Sendable { case inserted, refreshed }

public struct ClipboardUpsertResult: Equatable, Sendable {
    public let item: ClipboardItem
    public let disposition: ClipboardUpsertDisposition
}
```

When `content_hash` exists, execute one metadata update and return before reading, writing, or deleting payload references. Preserve `kind`, preview, size, and content hash because the semantic identity says the stored payload is equivalent; update only `updated_at`, `app_name`, and `bundle_id`.

- [ ] **Step 4: Update call sites to use `.item` and run GREEN**

Update demo seeding, repository tests, and any direct `upsert` consumers. Run:

`swift run ClipFlowCoreTests --filter ClipboardRepositoryTests`

Expected: all repository tests pass and duplicate payload preservation is verified.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipFlowStorage/ClipboardRepository.swift Sources/ClipFlowApp/ClipFlowApp.swift Tests/ClipFlowCoreTests/ClipboardRepositoryTests.swift
git commit -m "perf: skip payload rewrites for duplicate captures"
```

### Task 3: Bulk category search and bounded history

**Files:**
- Modify: `Sources/ClipFlowUI/AppModel.swift`
- Modify: `Sources/ClipFlowStorage/ClipboardRepository.swift`
- Modify: `Tests/ClipFlowCoreTests/ClipboardRepositoryTests.swift`
- Modify: `Tests/ClipFlowCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write failing bounded-search tests**

Add a `limit` parameter to the fake repository protocol expectation, seed more rows than the limit, and verify the newest rows are returned. Add category-filter coverage with hundreds of items to prove one bulk membership map produces the same results.

```swift
let results = try harness.repository.search(
    SearchQuery(text: "", categoryID: nil, kind: nil, favoritesOnly: false),
    limit: 200
)
#expect(results.count == 200)
#expect(results.first?.previewText == "Item 999")
```

- [ ] **Step 2: Run focused tests and verify RED**

Run `swift run ClipFlowCoreTests --filter ClipboardRepositoryTests`, then run `swift run ClipFlowCoreTests --filter AppModelTests`.

Expected: compile failure because the repository search API has no limit.

- [ ] **Step 3: Implement bounded selection and bulk membership loading**

Change `HistoryRepository.search` to `search(_:limit:)`, default the panel to 500 items, and add `categoryIDsByItemID()` using one join query:

```sql
SELECT ic.item_id, ic.category_id FROM item_categories ic;
```

Build `[UUID: Set<UUID>]` once before ranking. Apply the SQL `LIMIT` only after choosing a safe candidate bound; preserve search correctness by ranking the candidate set and applying the requested limit to sorted results.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run `swift run ClipFlowCoreTests --filter ClipboardRepositoryTests`, then run `swift run ClipFlowCoreTests --filter AppModelTests`.

Expected: all repository and model tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipFlowStorage/ClipboardRepository.swift Sources/ClipFlowUI/AppModel.swift Tests/ClipFlowCoreTests/ClipboardRepositoryTests.swift Tests/ClipFlowCoreTests/AppModelTests.swift
git commit -m "perf: bound history loads and batch category lookup"
```

### Task 4: Incremental capture processing

**Files:**
- Create: `Sources/ClipFlowUI/ClipboardCaptureProcessor.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Modify: `Sources/ClipFlowUI/AppModel.swift`
- Modify: `Tests/ClipFlowCoreTests/AppModelTests.swift`
- Modify: `Tests/ClipFlowCoreTests/PasteboardMonitorTests.swift`

- [ ] **Step 1: Write failing incremental-update and idle-poll tests**

Add a snapshot counter to `FakePasteboard`, poll repeatedly without changing `changeCount`, and assert zero snapshots/handlers. Add an `AppModel.refreshCapturedItem(_:)` test that starts with two items, refreshes the second with a newer timestamp, and asserts it moves to index zero without another repository search or thumbnail request.

```swift
await model.reload()
let searchesBefore = repository.searchCount
model.refreshCapturedItem(refreshed)
#expect(model.items.map(\.id) == [refreshed.id, other.id])
#expect(repository.searchCount == searchesBefore)
```

- [ ] **Step 2: Run focused tests and verify RED**

Run `swift run ClipFlowCoreTests --filter AppModelTests`, then run `swift run ClipFlowCoreTests --filter PasteboardMonitorTests`.

Expected: `refreshCapturedItem` is missing; the idle-poll test documents existing monitor behavior and should already pass.

- [ ] **Step 3: Implement safe incremental model refresh**

Add `refreshCapturedItem(_:) -> Bool`. It returns `false` when search/category/kind/favorites filters are active or the item is absent; otherwise it replaces the item, sorts by the repository order, preserves its thumbnail because `contentHash` is unchanged, and selects it only if no selection exists.

- [ ] **Step 4: Extract and wire capture processing**

Create `ClipboardCaptureProcessor` in the testable UI library with normalizer, repository, model, a retention closure, and an async logging closure. For `.refreshed`, call incremental refresh and reload only when it returns false. For `.inserted`, apply retention and reload. Keep normalization failures non-fatal and preserve capture logging.

```swift
switch result.disposition {
case .refreshed:
    let refreshedInPlace = await model.refreshCapturedItem(result.item)
    if !refreshedInPlace { await model.reload() }
case .inserted:
    _ = try repository.applyRetention(retentionPolicy())
    await model.reload()
}
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run `swift run ClipFlowCoreTests --filter AppModelTests`, then run `swift run ClipFlowCoreTests --filter PasteboardMonitorTests`.

Expected: all model and monitor tests pass; duplicate refresh causes no additional search.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipFlowUI/ClipboardCaptureProcessor.swift Sources/ClipFlowApp/ClipFlowApp.swift Sources/ClipFlowUI/AppModel.swift Tests/ClipFlowCoreTests/AppModelTests.swift Tests/ClipFlowCoreTests/PasteboardMonitorTests.swift
git commit -m "perf: refresh duplicate captures incrementally"
```

### Task 5: Static time presentation and low-cost scrolling surfaces

**Files:**
- Create: `Sources/ClipFlowUI/HistoryTimePresentation.swift`
- Create: `Tests/ClipFlowCoreTests/HistoryTimePresentationTests.swift`
- Modify: `Sources/ClipFlowUI/MainPanelView.swift`
- Modify: `Sources/ClipFlowUI/VisualComponents.swift`

- [ ] **Step 1: Write failing time-bucket tests**

Test fixed values for just-now, minutes, today, yesterday, and older dates in English and Simplified Chinese using an injected `now`, calendar, and locale.

```swift
#expect(HistoryTimePresentation.text(for: now.addingTimeInterval(-300), now: now, calendar: calendar, locale: Locale(identifier: "en")) == "5 min ago")
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift run ClipFlowCoreTests --filter HistoryTimePresentationTests`

Expected: compile failure because `HistoryTimePresentation` does not exist.

- [ ] **Step 3: Implement the pure formatter**

Create a non-observable enum with a pure static method. Use exact localized bucket strings and `Date.FormatStyle` only for the older-date fallback. The view passes `Date()` once during body evaluation; no `TimelineView`, timer, or relative date style is introduced.

- [ ] **Step 4: Replace row-relative time and per-row material**

In `HistoryCardRow`, replace `Text(item.updatedAt, style: .relative)` with the formatter output. Replace selected `.thinMaterial` with an appearance-aware accent fill and retain existing border/hover contrast. Replace material only on repeated scrolling cards in `VisualComponents`; keep the single panel background material.

- [ ] **Step 5: Run UI-focused tests and verify GREEN**

Run `swift run ClipFlowCoreTests --filter HistoryTimePresentationTests`, then run `swift run ClipFlowCoreTests --filter VisualAcceptanceConfigurationTests`.

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipFlowUI/HistoryTimePresentation.swift Sources/ClipFlowUI/MainPanelView.swift Sources/ClipFlowUI/VisualComponents.swift Tests/ClipFlowCoreTests/HistoryTimePresentationTests.swift
git commit -m "perf: make history rows render statically"
```

### Task 6: Large-history and regression smoke suite

**Files:**
- Create: `Tests/ClipFlowCoreTests/ClipboardPerformanceSmokeTests.swift`
- Modify: `Tests/ClipFlowCoreTests/TestRunner.swift`

- [ ] **Step 1: Add deterministic smoke tests**

Seed 1,000 and 10,000 rows in a temporary repository inside one transaction/helper, then verify bounded result count, ordering, semantic duplicate count, and a generous elapsed-time ceiling. Compare 1,000 versus 10,000 search duration only to reject catastrophic per-item database work; do not assert machine-specific millisecond targets.

```swift
let clock = ContinuousClock()
let elapsed = try clock.measure {
    let query = SearchQuery(text: "", categoryID: nil, kind: nil, favoritesOnly: false)
    #expect(try repository.search(query, limit: 500).count == 500)
}
#expect(elapsed < .seconds(10))
```

Add source-level guards that the history row no longer contains `style: .relative` and that its selected fill no longer uses `.thinMaterial`.

- [ ] **Step 2: Run the smoke suite**

Run: `swift run ClipFlowCoreTests --filter ClipboardPerformanceSmokeTests`

Expected: all smoke tests pass without timeout or memory failure.

- [ ] **Step 3: Run the entire test suite**

Run: `swift run ClipFlowCoreTests`

Expected: all suites and tests pass with no failures.

- [ ] **Step 4: Build Debug and Release**

Run:

```bash
swift build
swift build -c release
```

Expected: both builds complete successfully.

- [ ] **Step 5: Run manual app smoke checks**

Launch the Debug app, copy identical plain/rich/link/file values repeatedly, scroll a seeded history, and observe Activity Monitor at idle and during rapid copying. Verify one row per semantic value, refreshed ordering/source/time, no continuously changing row times, smooth scroll, and no per-row desktop blur over a dynamic background.

- [ ] **Step 6: Commit**

```bash
git add Tests/ClipFlowCoreTests/ClipboardPerformanceSmokeTests.swift Tests/ClipFlowCoreTests/TestRunner.swift
git commit -m "test: add clipboard performance smoke coverage"
```

### Task 7: Final review and release readiness

**Files:**
- Modify only files required by review findings.

- [ ] **Step 1: Inspect the full diff**

Run: `git diff 9f63c6a..HEAD --check && git diff --stat 9f63c6a..HEAD`

Expected: no whitespace errors and changes limited to clipboard identity, storage/query performance, capture flow, row presentation, and tests.

- [ ] **Step 2: Verify authorship and worktree state**

Run: `git log -8 --format='%h %an <%ae> %s' && git status --short`

Expected: every new commit is authored by `aiesst <aiesst.labs@gmail.com>` and the worktree is clean.

- [ ] **Step 3: Record final evidence**

Report exact test count, suite count, Debug/Release build results, manual smoke observations, commits, and any remaining limitation such as unsigned distribution behavior.
