import Foundation
import SQLite3

/// Accessed on the app's main thread. SQLite owns all persistent app preferences.
final class SettingsStore {
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sound Control", isDirectory: true)
            .appendingPathComponent("settings.sqlite3")
    }
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL = SettingsStore.defaultURL, legacyDefaults: UserDefaults = .standard) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = failure()
            sqlite3_close(database); database = nil
            throw error
        }
        do {
            sqlite3_busy_timeout(database, 1000)
            try execute("BEGIN IMMEDIATE")
            try execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS migrations (name TEXT PRIMARY KEY NOT NULL)")
            let migrated = try query("SELECT name FROM migrations WHERE name = ?", key: "user-defaults-v1")
            if migrated == nil {
                if try string(forKey: "selectedDevice") == nil,
                   let address = legacyDefaults.string(forKey: "selectedDevice") {
                    try set(address, forKey: "selectedDevice")
                }
                try execute("INSERT INTO migrations (name) VALUES ('user-defaults-v1')")
            }
            try execute("COMMIT")
            // Remove the old value only after the database transaction succeeds.
            legacyDefaults.removeObject(forKey: "selectedDevice")
        } catch {
            try? execute("ROLLBACK")
            sqlite3_close(database); database = nil
            throw error
        }
    }
    deinit { sqlite3_close(database) }

    func string(forKey key: String) throws -> String? {
        try query("SELECT value FROM settings WHERE key = ?", key: key)
    }

    func set(_ value: String?, forKey key: String) throws {
        let sql = value == nil ? "DELETE FROM settings WHERE key = ?" :
            "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(key, to: statement, at: 1)
        if let value { try bind(value, to: statement, at: 2) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    private func query(_ sql: String, key: String) throws -> String? {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(key, to: statement, at: 1)
        switch sqlite3_step(statement) {
        case SQLITE_DONE: return nil
        case SQLITE_ROW:
            guard let bytes = sqlite3_column_text(statement, 0) else { return nil }
            return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, 0))), as: UTF8.self)
        default: throw failure()
        }
    }
    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        let bytes = value.utf8CString
        let result = bytes.withUnsafeBytes { buffer in
            sqlite3_bind_text(statement, index, buffer.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(bytes.count - 1), transient)
        }
        guard result == SQLITE_OK else { throw failure() }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw failure()
        }
        return statement
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> NSError {
        NSError(domain: "SoundControl.Settings", code: Int(sqlite3_errcode(database)),
                userInfo: [NSLocalizedDescriptionKey: "Sound Control could not access its settings database. Check that your Application Support folder is available and has free space, then try again."])
    }
}
