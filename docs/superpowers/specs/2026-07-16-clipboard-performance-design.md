# ClipFlow Clipboard Deduplication and Performance

## Goal

Make repeated clipboard captures behave as a single recent item, keep the main list smooth on large histories, reduce idle CPU and GPU work, and add automated smoke coverage that detects regressions before a release.

The implementation keeps the current product behavior and visual hierarchy. It does not introduce a new database engine, a paginated user interface, or destructive migration of existing history.

## Semantic Identity

`ClipboardNormalizer` will derive a stable semantic fingerprint from the primary content of each clipboard item instead of hashing every advertised pasteboard representation.

- Plain and rich text use normalized visible text. Line endings are canonicalized, while meaningful whitespace and letter case remain significant.
- Web links use a canonical URL representation with a lowercased scheme and host. The URL payload and an equivalent plain-text URL resolve to the same identity.
- Files use standardized file URLs/paths in item order. File names are not used alone.
- Images and otherwise binary-only captures use the preferred original binary representation. Equivalent PNG/JPEG encodings are not treated as identical unless their bytes match.
- Multi-item captures preserve item order and include an explicit kind boundary, preventing accidental collisions between text, links, files, and binary data.
- If no safe semantic representation can be produced, the existing deterministic full-payload digest remains the fallback.

This changes deduplication for new captures only. Existing duplicate rows are not automatically deleted, avoiding surprising loss of favorites, categories, custom titles, or history. A newly copied value may match and update one existing row when its stored hash already equals the new semantic fingerprint.

## Duplicate Fast Path

Repository insertion will return an explicit result describing whether a row was inserted or refreshed. When the semantic fingerprint already exists, the repository will:

- retain the existing ID, creation time, favorite state, categories, custom title, and stored payloads;
- update only the recent-copy timestamp, source application, and source bundle identifier;
- move the existing item to the top through the normal ordering rules;
- avoid rewriting inline payloads, external payload files, and payload digests.

If the metadata-only update fails, the transaction rolls back and the existing payload remains untouched. A new item continues to use the current transactional payload-writing path, including cleanup of newly created external files after an error.

## Model and Query Flow

The model will consume the repository result instead of treating every capture as a completely new data set. A duplicate refresh updates or reorders the matching in-memory item when the active query can still be evaluated safely. Inserts, retention deletions, category-sensitive searches, and error recovery may perform a full reload.

Full reloads will fetch category memberships in one query and build an item-to-category lookup, removing the current per-item category query. The repository will expose a bounded history query for the normal panel while retaining an explicit unbounded path where maintenance code requires it. Search results remain deterministic and use the existing ranking rules.

Clipboard polling retains change-count based detection, but capture processing will not perform repository or UI work while the pasteboard change count is unchanged. Closely grouped model refresh requests will be coalesced on the main actor so a burst cannot schedule overlapping reloads.

## Time and Rendering

Rows will replace SwiftUI's continuously updating relative-date text with a static formatter. The formatter produces stable buckets such as “Just now,” “5 min ago,” “Today,” “Yesterday,” or a short date. Rows recalculate when their item data changes or the list reloads; they do not create one live timer per row.

The panel keeps one window-level material/background treatment. Repeated list rows and ordinary cards use appearance-aware solid translucent colors rather than individual live material blur layers. Selection, hover, borders, rounded corners, and light/dark mode contrast remain intact. Controls that materially benefit from a distinct floating treatment may keep a lightweight material.

No video is rendered by ClipFlow. Avoiding per-row live blur prevents a dynamic or video desktop from being repeatedly sampled through dozens of compositing layers.

## Performance Boundaries

- The normal history view loads a bounded first page large enough for ordinary use; filtering/searching can request additional rows through the repository API without changing visible behavior.
- Thumbnail and visual metadata work remains lazy and must only start for selected or visible content.
- Retention cleanup runs only after a successful insert or meaningful duplicate refresh, never for unchanged pasteboard polls.
- Performance tests use deterministic temporary databases and generous upper bounds intended to detect algorithmic regressions rather than benchmark machine speed.

## Verification

Automated tests will cover:

- repeated plain text returns the same item ID and one stored row;
- plain text with different HTML/RTF companion representations deduplicates;
- equivalent URL and file representations deduplicate without collapsing distinct values;
- repeat capture updates time/source while preserving payload rows, external file references, favorites, categories, and custom titles;
- repository results distinguish insertion from refresh;
- category-aware search uses a bulk membership query rather than one query per item;
- list time strings are static and correct at bucket boundaries;
- unchanged pasteboard polls do not normalize, write, reload, or start thumbnail work;
- reload requests are coalesced and duplicate refreshes do not rebuild unrelated presentation state;
- 1,000- and 10,000-item smoke fixtures complete bounded repository queries and model reloads without failures or superlinear query growth;
- list presentation does not add live relative-date timelines or per-row material backgrounds.

The complete Swift test suite, Debug build, and Release build must pass. A manual smoke run will record idle CPU, rapid-copy CPU, scrolling responsiveness, deduplication behavior, and appearance over both a static and dynamic desktop background. Machine-specific CPU percentages are recorded as observations rather than brittle automated assertions.

## Acceptance Criteria

1. Copying the same semantic value repeatedly leaves one row, refreshes its source/time, and moves it to the top.
2. A repeat capture performs no payload-file rewrite and no full-list reload when the active view can be updated incrementally.
3. Relative times do not update continuously while the user is idle.
4. The list remains responsive with a 10,000-item seeded history and repository query count does not grow once per item.
5. Dynamic desktop imagery does not show through a separate live blur layer for every history row.
6. All new smoke tests and the existing suite pass without changing user data or release/signing behavior.
