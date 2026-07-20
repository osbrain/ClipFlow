import Foundation

enum Migrations {
    static func apply(to database: SQLCipherDatabase) throws {
        try database.transaction { database in
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version INTEGER PRIMARY KEY,
                    applied_at REAL NOT NULL
                );
                """
            )

            let current = try database.query(
                "SELECT COALESCE(MAX(version), 0) AS version FROM schema_migrations;"
            ).first?.integer("version") ?? 0

            if current < 1 {
                try database.execute(schemaV1)
                try database.execute(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);",
                    bindings: [.integer(1), .real(Date().timeIntervalSince1970)]
                )
            }
            if current < 2 {
                try database.execute(schemaV2)
                try database.execute(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);",
                    bindings: [.integer(2), .real(Date().timeIntervalSince1970)]
                )
            }
            if current < 3 {
                try database.execute(schemaV3)
                try database.execute(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);",
                    bindings: [.integer(3), .real(Date().timeIntervalSince1970)]
                )
            }
            if current < 4 {
                try database.execute(schemaV4)
                try database.execute(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);",
                    bindings: [.integer(4), .real(Date().timeIntervalSince1970)]
                )
            }
            if current < 5 {
                try database.execute(schemaV5)
                try database.execute(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);",
                    bindings: [.integer(5), .real(Date().timeIntervalSince1970)]
                )
            }
            if current < 6 {
                try database.execute(schemaV6)
                try database.execute(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);",
                    bindings: [.integer(6), .real(Date().timeIntervalSince1970)]
                )
            }
            if current < 7 {
                try database.execute(schemaV7)
                try database.execute(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);",
                    bindings: [.integer(7), .real(Date().timeIntervalSince1970)]
                )
            }
        }
    }

    private static let schemaV1 = """
        CREATE TABLE clipboard_items (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            app_name TEXT NOT NULL,
            bundle_id TEXT,
            kind TEXT NOT NULL,
            preview_text TEXT NOT NULL,
            search_text TEXT NOT NULL,
            byte_size INTEGER NOT NULL,
            content_hash TEXT NOT NULL UNIQUE,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            last_used_at REAL,
            custom_title TEXT
        );
        CREATE TABLE pasteboard_payloads (
            item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
            item_index INTEGER NOT NULL,
            type TEXT NOT NULL,
            inline_data BLOB,
            external_file_name TEXT,
            byte_size INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            PRIMARY KEY(item_id, item_index, type)
        );
        CREATE TABLE clip_categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL,
            sort_order INTEGER NOT NULL
        );
        CREATE TABLE item_categories (
            item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
            category_id TEXT NOT NULL REFERENCES clip_categories(id) ON DELETE CASCADE,
            created_at REAL NOT NULL,
            PRIMARY KEY(item_id, category_id)
        );
        CREATE INDEX idx_items_created_at ON clipboard_items(created_at DESC);
        CREATE INDEX idx_items_kind ON clipboard_items(kind);
        CREATE INDEX idx_items_favorite ON clipboard_items(is_favorite);
        CREATE INDEX idx_item_categories_category ON item_categories(category_id);
        CREATE VIRTUAL TABLE clipboard_items_fts USING fts5(
            item_id UNINDEXED, custom_title, preview_text, search_text, app_name
        );
        CREATE TRIGGER clipboard_items_fts_insert AFTER INSERT ON clipboard_items BEGIN
            INSERT INTO clipboard_items_fts(item_id, custom_title, preview_text, search_text, app_name)
            VALUES (new.id, new.custom_title, new.preview_text, new.search_text, new.app_name);
        END;
        CREATE TRIGGER clipboard_items_fts_update AFTER UPDATE ON clipboard_items BEGIN
            DELETE FROM clipboard_items_fts WHERE item_id = old.id;
            INSERT INTO clipboard_items_fts(item_id, custom_title, preview_text, search_text, app_name)
            VALUES (new.id, new.custom_title, new.preview_text, new.search_text, new.app_name);
        END;
        CREATE TRIGGER clipboard_items_fts_delete AFTER DELETE ON clipboard_items BEGIN
            DELETE FROM clipboard_items_fts WHERE item_id = old.id;
        END;
        """

    private static let schemaV2 = """
        CREATE INDEX IF NOT EXISTS idx_items_recency
        ON clipboard_items(
            COALESCE(last_used_at, updated_at) DESC,
            updated_at DESC
        );
        """

    private static let schemaV3 = """
        CREATE TABLE quick_paste_slots (
            slot_index INTEGER PRIMARY KEY CHECK(slot_index BETWEEN 1 AND 9),
            item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX idx_quick_paste_slots_item ON quick_paste_slots(item_id);
        """

    private static let schemaV4 = """
        CREATE TABLE paste_stack_items (
            position INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
            created_at REAL NOT NULL
        );
        CREATE INDEX idx_paste_stack_items_item ON paste_stack_items(item_id);
        """

    private static let schemaV5 = """
        ALTER TABLE clipboard_items ADD COLUMN ocr_text TEXT;
        """

    private static let schemaV6 = """
        ALTER TABLE clipboard_items ADD COLUMN expires_at REAL;
        ALTER TABLE clipboard_items ADD COLUMN is_one_time INTEGER NOT NULL DEFAULT 0;
        CREATE INDEX idx_items_expires_at ON clipboard_items(expires_at);
        """

    private static let schemaV7 = """
        CREATE TABLE snippet_templates (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX idx_snippet_templates_updated_at ON snippet_templates(updated_at DESC);
        """
}

private extension SQLRow {
    func integer(_ name: String) -> Int64? {
        guard case .integer(let value) = self[name] else { return nil }
        return value
    }
}
