import CSQLCipher
import Foundation

public enum SQLCipherDatabaseError: Error, Sendable {
    case openFailed(code: Int32, message: String)
    case keyFailed(code: Int32, message: String)
    case statementFailed(code: Int32, sql: String, message: String)
    case cipherUnavailable
    case integrityFailed(String)
}

public enum SQLValue: Equatable, Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null
}

public struct SQLRow: Equatable, Sendable {
    public let columns: [String: SQLValue]

    public subscript(_ name: String) -> SQLValue? {
        columns[name]
    }
}

public final class SQLCipherDatabase: @unchecked Sendable {
    private let connection: OpaquePointer
    private let lock = NSRecursiveLock()
    private var queryObserver: (@Sendable (String) -> Void)?

    public let cipherVersion: String

    public init(url: URL, key: Data) throws {
        guard key.count == 32 else {
            throw SQLCipherDatabaseError.keyFailed(
                code: SQLITE_MISUSE,
                message: "SQLCipher keys must contain exactly 32 bytes"
            )
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openCode = sqlite3_open_v2(url.path, &database, flags, nil)
        guard openCode == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Unable to allocate SQLite connection"
            if let database { sqlite3_close(database) }
            throw SQLCipherDatabaseError.openFailed(code: openCode, message: message)
        }
        connection = database

        let keyCode = key.withUnsafeBytes { bytes in
            sqlite3_key(database, bytes.baseAddress, Int32(bytes.count))
        }
        guard keyCode == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(database))
            sqlite3_close(database)
            throw SQLCipherDatabaseError.keyFailed(code: keyCode, message: message)
        }

        do {
            guard let version = try Self.scalarText(
                connection: database,
                sql: "PRAGMA cipher_version;"
            ), !version.isEmpty else {
                throw SQLCipherDatabaseError.cipherUnavailable
            }
            cipherVersion = version

            let integrity = try Self.scalarText(
                connection: database,
                sql: "PRAGMA cipher_integrity_check;"
            )
            if let integrity, integrity != "ok" {
                throw SQLCipherDatabaseError.integrityFailed(integrity)
            }

            try Self.execute(connection: database, sql: "PRAGMA foreign_keys=ON;")
            try Self.execute(connection: database, sql: "PRAGMA journal_mode=WAL;")
            try Self.execute(connection: database, sql: "PRAGMA synchronous=NORMAL;")
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    deinit {
        sqlite3_close(connection)
    }

    public func execute(_ sql: String, bindings: [SQLValue] = []) throws {
        try lock.withLock {
            if bindings.isEmpty {
                try Self.execute(connection: connection, sql: sql)
            } else {
                let statement = try Self.prepare(connection: connection, sql: sql)
                defer { sqlite3_finalize(statement) }
                try Self.bind(bindings, to: statement, connection: connection, sql: sql)
                let code = sqlite3_step(statement)
                guard code == SQLITE_DONE else {
                    throw Self.statementError(connection: connection, code: code, sql: sql)
                }
            }
        }
    }

    public func query(_ sql: String, bindings: [SQLValue] = []) throws -> [SQLRow] {
        try lock.withLock {
            queryObserver?(sql)
            let statement = try Self.prepare(connection: connection, sql: sql)
            defer { sqlite3_finalize(statement) }
            try Self.bind(bindings, to: statement, connection: connection, sql: sql)

            var rows: [SQLRow] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return rows }
                guard code == SQLITE_ROW else {
                    throw Self.statementError(connection: connection, code: code, sql: sql)
                }

                var columns: [String: SQLValue] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    columns[name] = Self.columnValue(statement: statement, index: index)
                }
                rows.append(SQLRow(columns: columns))
            }
        }
    }

    func setQueryObserver(_ observer: (@Sendable (String) -> Void)?) {
        lock.withLock {
            queryObserver = observer
        }
    }

    public func transaction<T>(_ body: (SQLCipherDatabase) throws -> T) throws -> T {
        try lock.withLock {
            try Self.execute(connection: connection, sql: "BEGIN IMMEDIATE;")
            do {
                let result = try body(self)
                try Self.execute(connection: connection, sql: "COMMIT;")
                return result
            } catch {
                try? Self.execute(connection: connection, sql: "ROLLBACK;")
                throw error
            }
        }
    }

    public func scalarText(_ sql: String) throws -> String? {
        try lock.withLock {
            try Self.scalarText(connection: connection, sql: sql)
        }
    }

    private static func execute(connection: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(connection, sql, nil, nil, &errorMessage)
        guard code == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(connection))
            sqlite3_free(errorMessage)
            throw SQLCipherDatabaseError.statementFailed(
                code: code,
                sql: sql,
                message: message
            )
        }
    }

    private static func scalarText(
        connection: OpaquePointer,
        sql: String
    ) throws -> String? {
        var statement: OpaquePointer?
        let prepareCode = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareCode == SQLITE_OK, let statement else {
            throw SQLCipherDatabaseError.statementFailed(
                code: prepareCode,
                sql: sql,
                message: String(cString: sqlite3_errmsg(connection))
            )
        }
        defer { sqlite3_finalize(statement) }

        let stepCode = sqlite3_step(statement)
        if stepCode == SQLITE_DONE {
            return nil
        }
        guard stepCode == SQLITE_ROW else {
            throw SQLCipherDatabaseError.statementFailed(
                code: stepCode,
                sql: sql,
                message: String(cString: sqlite3_errmsg(connection))
            )
        }
        guard let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
    }

    private static func prepare(
        connection: OpaquePointer,
        sql: String
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            throw statementError(connection: connection, code: code, sql: sql)
        }
        return statement
    }

    private static func bind(
        _ bindings: [SQLValue],
        to statement: OpaquePointer,
        connection: OpaquePointer,
        sql: String
    ) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .integer(let value):
                code = sqlite3_bind_int64(statement, index, value)
            case .real(let value):
                code = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                code = value.withCString {
                    sqlite3_bind_text(statement, index, $0, -1, transient)
                }
            case .blob(let value):
                code = value.withUnsafeBytes {
                    sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient)
                }
            case .null:
                code = sqlite3_bind_null(statement, index)
            }
            guard code == SQLITE_OK else {
                throw statementError(connection: connection, code: code, sql: sql)
            }
        }
    }

    private static func columnValue(statement: OpaquePointer, index: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: text))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count > 0, let bytes = sqlite3_column_blob(statement, index) else {
                return .blob(Data())
            }
            return .blob(Data(bytes: bytes, count: count))
        default:
            return .null
        }
    }

    private static func statementError(
        connection: OpaquePointer,
        code: Int32,
        sql: String
    ) -> SQLCipherDatabaseError {
        SQLCipherDatabaseError.statementFailed(
            code: code,
            sql: sql,
            message: String(cString: sqlite3_errmsg(connection))
        )
    }
}
