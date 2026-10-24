import AppKit

@main struct UpdateInstaller {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 5, let pid = Int32(args[1]), pid > 1, let build = Int(args[4]) else { exit(2) }
        let target = URL(fileURLWithPath: args[2])
        let folder = URL(fileURLWithPath: args[3])
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let deadline = Date().addingTimeInterval(30)
            while kill(pid, 0) == 0 {
                guard Date() < deadline else { throw UpdateFailure.timeout }
                Thread.sleep(forTimeInterval: 0.1)
            }
            try UpdateInstallation.replace(target: target, staged: folder.appendingPathComponent("Sound Control.app"), build: build) { app in
                try UpdateInstallation.run("/usr/bin/open", [app.path])
            }
        } catch {
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not install the update"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            exit(1)
        }
    }
}
