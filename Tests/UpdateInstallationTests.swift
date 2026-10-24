import Foundation

@main struct UpdateInstallationTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sound-control-install-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("Sound Control.app")
        let staged = root.appendingPathComponent("New.app")
        let source = URL(fileURLWithPath: "build/Sound Control.app")
        try UpdateInstallation.run("/usr/bin/ditto", ["--noextattr", source.path, target.path])
        try UpdateInstallation.run("/usr/bin/ditto", ["--noextattr", source.path, staged.path])
        let info = try Data(contentsOf: source.appendingPathComponent("Contents/Info.plist"))
        let dictionary = try PropertyListSerialization.propertyList(from: info, format: nil) as! [String: Any]
        let build = Int(dictionary["CFBundleVersion"] as! String)!
        // The old copy carries an extra marker, covered by its fresh signature.
        try fm.createDirectory(at: target.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        let marker = target.appendingPathComponent("Contents/Resources/old-marker")
        try Data("original".utf8).write(to: marker)
        try UpdateInstallation.run("/usr/bin/xattr", ["-cr", target.path])
        try UpdateInstallation.run("/usr/bin/codesign", ["--force","--sign","-",target.path])
        var launches = 0
        do {
            try UpdateInstallation.replace(target: target, staged: staged, build: build) { _ in
                launches += 1
                if launches == 1 { throw UpdateFailure.installation }
            }
            preconditionFailure("Expected launch failure")
        } catch { precondition(fm.fileExists(atPath: marker.path), "Rollback preserves original") }
        precondition(launches == 2, "Rollback reopens original")
        // A wrong build must leave the target untouched.
        do {
            try UpdateInstallation.replace(target: target, staged: staged, build: build+1) { _ in preconditionFailure() }
            preconditionFailure("Wrong build accepted")
        } catch { precondition(fm.fileExists(atPath: marker.path)) }
        let stagedInfo = staged.appendingPathComponent("Contents/Info.plist")
        try (info + Data("\n".utf8)).write(to: stagedInfo)
        do {
            try UpdateInstallation.replace(target: target, staged: staged, build: build) { _ in preconditionFailure() }
            preconditionFailure("Damaged signature accepted")
        } catch { precondition(fm.fileExists(atPath: marker.path)) }
        try info.write(to: stagedInfo)
        try UpdateInstallation.replace(target: target, staged: staged, build: build) { app in
            try UpdateInstallation.validate(app, build: build)
            precondition(!fm.fileExists(atPath: marker.path), "Replacement installed")
        }
        let remaining = try fm.contentsOfDirectory(atPath: root.path).sorted()
        precondition(remaining == ["New.app","Sound Control.app"], "No leftover backups")
        print("PASS: replacement, build mismatch, signature damage, rollback, relaunch and cleanup")
    }
}
