import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let headphones = Headphones()
    var item: NSStatusItem!
    var menu = NSMenu()
    var menuOpen = false
    var hardwareTest: HardwareTest?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--log"), args.count > index + 1 { headphones.logURL = URL(fileURLWithPath: args[index + 1]) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Sony headphone controls")
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
        if let battery = headphones.battery { add("Battery · \(battery)%") }
        if headphones.left != nil || headphones.right != nil {
            func value(_ n: Int?) -> String { n.map { "\($0)%" } ?? "—" }
            add("L \(value(headphones.left))   R \(value(headphones.right))   Case \(value(headphones.caseBattery))")
        }
        menu.addItem(.separator())
        let enabled = headphones.ready && headphones.state != nil && !headphones.busy
        for mode in SoundMode.allCases {
            let entry = add(mode.title, #selector(modeSelected(_:)), enabled: enabled && headphones.control?.modes.contains(mode) == true)
            entry.tag = mode.rawValue; entry.state = headphones.state?.mode == mode ? .on : .off
            entry.keyEquivalent = String(mode.rawValue + 1)
        }
        let levelMenu = NSMenu(); levelMenu.autoenablesItems = false
        let levelItem = add("Ambient level · \(headphones.state?.level ?? 10)", #selector(noop), enabled: enabled && headphones.control?.hasAmbient == true)
        levelItem.submenu = levelMenu
        for level in headphones.control?.levels[headphones.state?.voice ?? false] ?? [] {
            let entry = NSMenuItem(title: "\(level)", action: #selector(levelSelected(_:)), keyEquivalent: "")
            entry.isEnabled = enabled; entry.tag = level; entry.target = self; entry.state = headphones.state?.level == level ? .on : .off
            levelMenu.addItem(entry)
        }
        let voice = add("Focus on voices", #selector(toggleVoice), enabled: enabled && headphones.state?.mode == .ambient && headphones.control?.hasVoice == true)
        voice.state = headphones.state?.voice == true ? .on : .off
        menu.addItem(.separator())
        let deviceMenu = NSMenu(); deviceMenu.autoenablesItems = false
        let deviceItem = add("Headphones", #selector(noop)); deviceItem.submenu = deviceMenu
        let automatic = NSMenuItem(title: "Automatically choose connected headset", action: #selector(selectDevice(_:)), keyEquivalent: "")
        automatic.target = self; automatic.state = headphones.selectedAddress == nil ? .on : .off
        deviceMenu.addItem(automatic)
        for device in headphones.devices {
            let entry = NSMenuItem(title: "\(device.name) · \(device.generation.rawValue)" + (device.connected ? "" : " · Disconnected"), action: #selector(selectDevice(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = device.address
            entry.state = headphones.activeAddress == device.address ? .on : .off
            deviceMenu.addItem(entry)
        }
        add("Refresh", #selector(refresh), enabled: headphones.ready && !headphones.busy)
        add("Reconnect", #selector(reconnect))
        add("Bluetooth Settings…", #selector(bluetooth))
        menu.addItem(.separator())
        let login = add("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add("Quit LinkBudsBar", #selector(quit)).keyEquivalent = "q"
    }
    @objc func selectDevice(_ sender: NSMenuItem) { headphones.select(sender.representedObject as? String) }
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
            let alert = NSAlert(); alert.messageText = "Could not change Open at Login"; alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
