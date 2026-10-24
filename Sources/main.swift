import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var headphones: Headphones!
    var item: NSStatusItem!
    var menu = NSMenu()
    var menuOpen = false
    var hardwareTest: HardwareTest?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { headphones = try Headphones(settings: SettingsStore()) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Could not load settings"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--log"), args.count > index + 1 { headphones.logURL = URL(fileURLWithPath: args[index + 1]) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Headphone controls")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = headphones.deviceName
        menu.delegate = self; item.menu = menu
        headphones.changed = { [weak self] in self?.update() }
        update(); headphones.start()
        if args.contains("--hardware-test") { hardwareTest = HardwareTest(headphones); hardwareTest?.start() }
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; headphones.scan(); rebuild() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }
    func update() {
        item.button?.toolTip = "\(headphones.deviceName) · \(headphones.status)"
        item.button?.appearsDisabled = !headphones.ready
        if !menuOpen { rebuild() }
    }
    @discardableResult func add(_ title: String, _ action: Selector? = nil, enabled: Bool = true) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; entry.isEnabled = enabled && action != nil; menu.addItem(entry); return entry
    }
    func rebuild() {
        menu.removeAllItems(); menu.autoenablesItems = false
        add(headphones.deviceName)
        add(headphones.status)
        if headphones.isNothing { add("Nothing and CMF: not tested on devices") }
        if let battery = headphones.battery { add("Battery: \(battery)%") }
        if headphones.left != nil || headphones.right != nil {
            func value(_ n: Int?) -> String { n.map { "\($0)%" } ?? "Unknown" }
            add("Left: \(value(headphones.left))   Right: \(value(headphones.right))   Case: \(value(headphones.caseBattery))")
        }
        menu.addItem(.separator())
        let enabled = headphones.ready && headphones.state != nil && !headphones.busy
        for mode in SoundMode.allCases {
            let entry = add(headphones.title(for: mode), #selector(modeSelected(_:)), enabled: enabled && headphones.availableModes.contains(mode))
            entry.tag = mode.rawValue; entry.state = headphones.state?.mode == mode ? .on : .off
            entry.keyEquivalent = String(mode.rawValue + 1)
        }
        if !headphones.isNothing {
        let levelMenu = NSMenu(); levelMenu.autoenablesItems = false
        let levelItem = add("Ambient level: \(headphones.state.map { String($0.level) } ?? "Unknown")", #selector(noop), enabled: enabled && !headphones.ambientLevels.isEmpty)
        levelItem.submenu = levelMenu
        for level in headphones.ambientLevels {
            let entry = NSMenuItem(title: "\(level)", action: #selector(levelSelected(_:)), keyEquivalent: "")
            entry.isEnabled = enabled; entry.tag = level; entry.target = self; entry.state = headphones.state?.level == level ? .on : .off
            levelMenu.addItem(entry)
        }
        let voice = add("Focus on voices", #selector(toggleVoice), enabled: enabled && headphones.state?.mode == .ambient && headphones.supportsVoice)
        voice.state = headphones.state?.voice == true ? .on : .off
        }
        menu.addItem(.separator())
        let deviceMenu = NSMenu(); deviceMenu.autoenablesItems = false
        let deviceItem = add("Headphones", #selector(noop)); deviceItem.submenu = deviceMenu
        let automatic = NSMenuItem(title: "Choose connected headphones automatically", action: #selector(selectDevice(_:)), keyEquivalent: "")
        automatic.target = self; automatic.state = headphones.selectedAddress == nil ? .on : .off
        deviceMenu.addItem(automatic)
        for device in headphones.devices {
            let entry = NSMenuItem(title: "\(device.name) · \(device.backend.label)" + (device.connected ? "" : " · Disconnected"), action: #selector(selectDevice(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = device.address
            entry.state = headphones.activeAddress == device.address ? .on : .off
            deviceMenu.addItem(entry)
        }
        add("Refresh", #selector(refresh), enabled: headphones.ready && !headphones.busy)
        add("Reconnect", #selector(reconnect))
        add("Bluetooth settings…", #selector(bluetooth))
        menu.addItem(.separator())
        let login = add("Open at login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add("Quit Sound Control", #selector(quit)).keyEquivalent = "q"
    }
    @objc func selectDevice(_ sender: NSMenuItem) {
        do { try headphones.select(sender.representedObject as? String) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Could not save your headphone selection"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    @objc func noop() {}
    @objc func modeSelected(_ sender: NSMenuItem) { if let mode = SoundMode(rawValue: sender.tag) { headphones.set(mode) } }
    @objc func levelSelected(_ sender: NSMenuItem) { headphones.set(.ambient, level: sender.tag) }
    @objc func toggleVoice() { headphones.set(.ambient, voice: !(headphones.state?.voice ?? false)) }
    @objc func refresh() { headphones.refresh() }
    @objc func reconnect() { headphones.retry() }
    @objc func bluetooth() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Could not change the login setting"; alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
