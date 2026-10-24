import AppKit

@MainActor final class AppUpdater {
    let store: SettingsStore
    private(set) var busy = false
    var changed: (() -> Void)?
    private var timer: Timer?
    var automatic: Bool { (try? store.string(forKey: "updates.automatic")) != "off" }
    init(store: SettingsStore) { self.store = store }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduledCheck() }
        }
        // Keep startup quiet while headphone discovery is in progress.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.scheduledCheck() }
    }
    private func scheduledCheck() {
        guard automatic, !busy else { return }
        let last = (try? store.string(forKey: "updates.lastCheck")).flatMap(Double.init) ?? 0
        if Date().timeIntervalSince1970 - last >= 86400 { check(manual: false) }
    }
    func toggleAutomatic() {
        do { try store.set(automatic ? "off" : "on", forKey: "updates.automatic"); changed?() }
        catch { showError(error) }
    }
    func check(manual: Bool) {
        guard !busy else { return }
        busy = true; changed?()
        Task {
            var reportErrors = manual
            defer { busy = false; changed?() }
            do {
                let data = try await download(UpdateManifest.feed, limit: 65_536)
                guard let publicKey = Bundle.main.object(forInfoDictionaryKey: "UpdatePublicKey") as? String,
                      let current = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init)
                else { throw UpdateFailure.invalidRelease }
                let manifest = try UpdateManifest.verified(data, publicKey: publicKey)
                try store.set(String(Date().timeIntervalSince1970), forKey: "updates.lastCheck")
                guard manifest.build > current else {
                    if manual { inform("You’re up to date", "Sound Control \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") is the latest version.") }
                    return
                }
                let os = ProcessInfo.processInfo.operatingSystemVersion
                guard manifest.supports(system: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") else {
                    if manual { inform("A newer macOS version is needed", "Sound Control \(manifest.version) needs macOS \(manifest.minimumSystemVersion) or later.") }
                    return
                }
                let alert = NSAlert()
                alert.messageText = "Sound Control \(manifest.version) is available"
                alert.informativeText = "Install the update and restart Sound Control. Your saved settings will be kept."
                alert.addButton(withTitle: "Update and restart")
                alert.addButton(withTitle: "Later")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else {
                    return
                }
                reportErrors = true
                try await install(manifest)
            } catch { if reportErrors { showError(error) } }
        }
    }
    private func download(_ url: URL, limit: Int) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("SoundControl", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", response.expectedContentLength <= limit else { throw UpdateFailure.download }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw UpdateFailure.download }
            data.append(byte)
        }
        return data
    }
    private func install(_ manifest: UpdateManifest) async throws {
        let fm = FileManager.default
        let target = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else { throw UpdateFailure.permissions }
        let folder = fm.temporaryDirectory.appendingPathComponent("sound-control-update-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var handedOff = false
        defer { if !handedOff { try? fm.removeItem(at: folder) } }
        let data = try await download(URL(string: manifest.url)!, limit: manifest.size)
        try manifest.verifyArchive(data)
        let archive = folder.appendingPathComponent("update.zip")
        try data.write(to: archive, options: .atomic)
        // Only an authenticated, size-checked archive reaches the extractor.
        try UpdateInstallation.run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        try fm.removeItem(at: archive)
        try UpdateInstallation.validate(folder.appendingPathComponent("Sound Control.app"), build: manifest.build)
        let helper = folder.appendingPathComponent("UpdateInstaller")
        try fm.copyItem(at: target.appendingPathComponent("Contents/Helpers/UpdateInstaller"), to: helper)
        let process = Process()
        process.executableURL = helper
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), target.path, folder.path, String(manifest.build)]
        try process.run()
        handedOff = true
        NSApp.terminate(nil)
    }
    private func inform(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.runModal()
    }
    private func showError(_ error: Error) { inform("Could not update Sound Control", error.localizedDescription) }
}
