# Encrypted Backup Import Export Design

## Scope

Add a local encrypted backup format for ClipFlow history. Users can export all stored clipboard records and import a backup later without uploading data or calling external services.

## Behavior

- Export writes a `.clipflowbackup` JSON envelope.
- The envelope exposes only format metadata, KDF metadata, nonce, and ciphertext. Clipboard contents, previews, payload data, titles, categories, and quick paste slots are inside the encrypted payload.
- Import requires the same password. A wrong password or malformed file fails before the repository is changed.
- Import uses safe merge semantics. Existing items are matched by `contentHash`; the importer does not delete current history and does not replace existing payload bytes.
- Imported metadata may restore favorites, custom titles, categories, and quick paste slots when the referenced imported item exists after merge.

## Architecture

- `ClipFlowStorage` owns the archive format and repository import/export because it already owns complete history, payload, category, and quick-slot access.
- `EncryptedBackupCodec` handles KDF and AES-GCM envelope encoding/decoding.
- `ClipboardRepository` builds backup snapshots and imports snapshots transactionally where possible.
- `ClipFlowApp` owns macOS save/open panels and password prompts, then calls repository APIs and refreshes the main model.
- `ClipFlowUI` shows a backup section in Settings and user-facing status/error text.

## Security

- Key derivation is local and salted.
- Backup payloads are encrypted with AES-GCM.
- Empty passwords are rejected.
- Failed decrypt/import does not mutate local storage.

## First Release Non-goals

- No destructive “replace all local history” import mode.
- No cloud sync.
- No background automatic backup scheduler.
- No recovery for forgotten backup passwords.
