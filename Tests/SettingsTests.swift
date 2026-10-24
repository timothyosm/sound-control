import Foundation
import SQLite3

@main struct SettingsTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SoundControl.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); count += 1
        }
        let url = root.appendingPathComponent("nested/settings.sqlite3")
        defaults.set("AA-BB-CC", forKey: "selectedDevice")
        var store: SettingsStore? = try SettingsStore(url: url, legacyDefaults: defaults)
        check(try store!.string(forKey: "selectedDevice") == "AA-BB-CC", "Migration retains selection")
        check(defaults.string(forKey: "selectedDevice") == nil, "Migration removes old setting after commit")
        try store!.set("耳 ' ; DROP TABLE settings; --", forKey: "quoted'key")
        check(try store!.string(forKey: "quoted'key") == "耳 ' ; DROP TABLE settings; --", "Bound Unicode and SQL text")
        try store!.set("", forKey: "empty")
        check(try store!.string(forKey: "empty") == "", "Empty string differs from absence")
        try store!.set("a\0b", forKey: "nul")
        check(try store!.string(forKey: "nul") == "a\0b", "Embedded null survives")
        try store!.set("DD-EE-FF", forKey: "selectedDevice")
        store = nil
        store = try SettingsStore(url: url, legacyDefaults: defaults)
        check(try store!.string(forKey: "selectedDevice") == "DD-EE-FF", "Selection persists after reopening")
        try store!.set(nil, forKey: "selectedDevice")
        store = nil
        defaults.set("STALE", forKey: "selectedDevice")
        store = try SettingsStore(url: url, legacyDefaults: defaults)
        check(try store!.string(forKey: "selectedDevice") == nil, "Automatic selection survives stale legacy data")
        check(try store!.string(forKey: "missing") == nil, "Missing key returns nil")
        store = nil

        let corrupt = root.appendingPathComponent("corrupt.sqlite3")
        try Data("not a database".utf8).write(to: corrupt)
        defaults.set("KEEP", forKey: "selectedDevice")
        do {
            _ = try SettingsStore(url: corrupt, legacyDefaults: defaults)
            preconditionFailure("Corrupt database must fail")
        } catch { count += 1 }
        check(defaults.string(forKey: "selectedDevice") == "KEEP", "Failed migration preserves legacy data")
        check(try Data(contentsOf: corrupt) == Data("not a database".utf8), "Corrupt database is not replaced")

        let locked = root.appendingPathComponent("locked.sqlite3")
        var connection: OpaquePointer?
        precondition(sqlite3_open(locked.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        precondition(sqlite3_exec(connection, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        do {
            _ = try SettingsStore(url: locked, legacyDefaults: defaults)
            preconditionFailure("Locked database must fail")
        } catch { count += 1 }
        check(defaults.string(forKey: "selectedDevice") == "KEEP", "Lock failure preserves legacy data")
        precondition(sqlite3_exec(connection, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        let recovered = try SettingsStore(url: locked, legacyDefaults: defaults)
        check(try recovered.string(forKey: "selectedDevice") == "KEEP", "Migration retries after lock clears")
        precondition(sqlite3_exec(connection, "CREATE TRIGGER reject_update BEFORE UPDATE ON settings BEGIN SELECT RAISE(ABORT, 'test failure'); END", nil, nil, nil) == SQLITE_OK)
        do {
            try recovered.set("LOST", forKey: "selectedDevice")
            preconditionFailure("Rejected write must fail")
        } catch { count += 1 }
        check(try recovered.string(forKey: "selectedDevice") == "KEEP", "Failed update preserves saved setting")
        print("PASS: \(count) settings assertions")
    }
}
