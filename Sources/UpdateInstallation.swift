import Foundation

// Also compiled into the detached installer, which runs after the app closes.
enum UpdateInstallation {
    static let bundleID = "app.timothyosmond.LinkBudsBar"
    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure.installation }
    }
    static func validate(_ app: URL, build: Int) throws {
        let fm = FileManager.default
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard (try app.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleID,
              info["CFBundleExecutable"] as? String == "SoundControl",
              (info["CFBundleVersion"] as? String).flatMap(Int.init) == build,
              fm.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/SoundControl").path)
        else { throw UpdateFailure.invalidRelease }
        // Finder can add this unsigned presentation metadata when copying a
        // bundle. Remove only that attribute; retain Gatekeeper quarantine.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.FinderInfo", app.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }
    static func replace(target: URL, staged: URL, build: Int, launch: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        guard target.pathExtension == "app", fm.isWritableFile(atPath: parent.path),
              target.standardizedFileURL != staged.standardizedFileURL,
              (try target.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true
        else { throw UpdateFailure.permissions }
        try validate(staged, build: build)
        let backup = parent.appendingPathComponent(".SoundControl-backup-\(UUID().uuidString).app")
        let incoming = parent.appendingPathComponent(".SoundControl-incoming-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: incoming) }
        try run("/usr/bin/ditto", ["--noextattr", staged.path, incoming.path])
        try validate(incoming, build: build)
        try fm.moveItem(at: target, to: backup)
        do {
            try fm.moveItem(at: incoming, to: target)
            try launch(target)
        } catch {
            try? fm.removeItem(at: target)
            // Keep the backup if rollback fails, so it can be recovered manually.
            try fm.moveItem(at: backup, to: target)
            try? launch(target)
            throw error
        }
        try? fm.removeItem(at: backup)
    }
}
