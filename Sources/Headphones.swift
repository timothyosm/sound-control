import Foundation
import IOBluetooth

final class Headphones: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var changed: (() -> Void)?
    var status = "Looking for headphones…" { didSet { changed?(); log(status) } }
    var state: SoundState?
    var left: Int?, right: Int?, caseBattery: Int?, battery: Int?
    var deviceName = "Headphones"
    var generation: SonyGeneration = .v2
    var capabilities: SonyCapabilities?
    var control: SoundControl?
    enum Backend {
        case sony(SonyGeneration), nothing
        var label: String { switch self { case .sony(let generation): return "Sony " + generation.rawValue; case .nothing: return "Nothing / CMF" } }
        var serviceBytes: [UInt8] { switch self { case .sony(let generation): return generation.serviceBytes; case .nothing: return NothingFrame.serviceBytes } }
    }
    var isNothing = false
    private var nothingSession: NothingSession?
    private var nothingDecoder = NothingDecoder()
    private var nothingTimer: Timer?
    private struct NothingView: Equatable {
        let ready: Bool
        let busy: Bool
        let mode: SoundMode?
        let batteries: NothingBatteries?
        let status: String
    }
    private var lastNothingView: NothingView?
    var availableModes: [SoundMode] { isNothing ? (state == nil ? [] : SoundMode.allCases) : (control?.modes ?? []) }
    var ambientLevels: [Int] { isNothing ? [] : (control?.levels[state?.voice ?? false] ?? []) }
    var supportsVoice: Bool { !isNothing && control?.hasVoice == true }
    func title(for mode: SoundMode) -> String { isNothing && mode == .ambient ? "Transparency" : mode.title }
    struct Device {
        let address: String
        let name: String
        let connected: Bool
        let backend: Backend
        let device: IOBluetoothDevice
        let service: IOBluetoothSDPServiceRecord
    }
    var devices: [Device] = []
    var selectedAddress: String? { UserDefaults.standard.string(forKey: "selectedDevice") }
    var activeAddress: String?
    private var disabledReads: Set<[UInt8]> = []
    private var lastInboundSequence: UInt8?
    private var pumpingDeferred = false
    var ready = false
    var busy: Bool { isNothing ? (nothingSession?.busy ?? false) : (current != nil || !queue.isEmpty) }
    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = SonyDecoder()
    private var sequence: UInt8 = 0
    private struct Request {
        var payload: [UInt8]
        var reply: UInt8?
        var optional = false
        var completion: (([UInt8]?) -> Void)?
    }
    private var queue: [Request] = []
    private var current: Request?
    private var acknowledged = false
    private var response: [UInt8]?
    private var timeout: Timer?
    private var reconnectTimer: Timer?
    private var opening = false
    private var wanted: SoundState?
    var logURL: URL?

    func log(_ text: String) {
        guard let logURL else { return }
        let data = Data(("\(Date()) \(text)\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data)
        } else { try? data.write(to: logURL) }
    }

    func start() {
        connect()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.channel == nil && !self.opening { self.connect() }
            else if self.ready && !self.busy { self.refresh() }
        }
    }

    func scan() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        devices = paired.compactMap { device in
            for backend in [Backend.sony(.v2), .sony(.v1), .nothing] {
                let uuid = backend.serviceBytes.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
                if let service = device.getServiceRecord(for: uuid), let address = device.addressString {
                    return Device(address: address, name: device.name ?? "Headphones", connected: device.isConnected(), backend: backend, device: device, service: service)
                }
            }
            return nil
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func select(_ address: String?) {
        if let address { UserDefaults.standard.set(address, forKey: "selectedDevice") }
        else { UserDefaults.standard.removeObject(forKey: "selectedDevice") }
        retry()
    }
    func connect() {
        guard channel == nil, !opening else { return }
        scan()
        let candidate = selectedAddress.flatMap { address in devices.first { $0.address == address } }
        guard let selected = selectedAddress != nil ? candidate : devices.first(where: { $0.connected }) else {
            status = "Connect a compatible Sony or Nothing headset in Bluetooth Settings"; return
        }
        deviceName = selected.name; activeAddress = selected.address
        switch selected.backend {
        case .sony(let version): isNothing = false; generation = version
        case .nothing: isNothing = true
        }
        guard selected.connected else { status = "Connect \(deviceName) in Bluetooth Settings"; return }
        var id: BluetoothRFCOMMChannelID = 0
        guard selected.service.getRFCOMMChannelID(&id) == kIOReturnSuccess else { status = "Headphone control channel unavailable"; return }
        opening = true; status = "Connecting to \(deviceName)…"
        let result = selected.device.openRFCOMMChannelAsync(&channel, withChannelID: id, delegate: self)
        if result != kIOReturnSuccess { fail("Bluetooth connection failed (\(result))") }
        else if opening {
            timeout = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                if self?.opening == true { self?.fail("Connection timed out. Close other headphone control apps.") }
            }
        }
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard opening else { return }
        timeout?.invalidate(); opening = false
        guard error == kIOReturnSuccess else { fail("Bluetooth connection failed (\(error))"); return }
        channel = rfcommChannel; sequence = 0; decoder = SonyDecoder()
        if isNothing { startNothing(); return }
        enqueue([0x00, 0x00], reply: 0x01) { [weak self] response in
            guard let self, let response else { return }
            guard self.generation.acceptsHandshake(response) else {
                self.fail("Unsupported Sony protocol version"); return
            }
            self.enqueue([0x06,0x00], reply: 0x07) { [weak self] response in
                guard let self, let response else { return }
                guard let caps = SonyCapabilities(generation: self.generation, payload: response) else {
                    self.fail("Unrecognized Sony capabilities — controls disabled"); return
                }
                self.capabilities = caps
                if let type = caps.soundType {
                    self.enqueue([0x60,type], reply: 0x61, optional: true) { [weak self] response in
                        guard let self else { return }
                        if let response { self.control = SoundControl(generation: self.generation, type: type, capability: response) }
                        self.didInitialize()
                    }
                } else { self.didInitialize() }
            }
        }
    }
    private func didInitialize() {
        guard channel != nil else { return }
        ready = true
        status = control == nil ? "Connected · sound controls unavailable" : "Reading settings…"
        refresh()
    }
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) { guard rfcommChannel === channel else { return }; fail("Disconnected — reconnecting automatically") }
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard rfcommChannel === channel else { return }
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        if isNothing {
            for frame in nothingDecoder.feed(bytes) {
                let frames = nothingSession?.receive(frame, now: ProcessInfo.processInfo.systemUptime) ?? []
                sendNothing(frames)
            }
            syncNothing()
            return
        }
        for frame in decoder.feed(bytes) {
            log("RX \(frame.type) \(frame.sequence) " + frame.payload.map { String(format: "%02x", $0) }.joined(separator: " "))
            if frame.type == 1 {
                guard current != nil, !acknowledged, frame.sequence == (sequence ^ 1) else { continue }
                sequence = frame.sequence; acknowledged = true
                if current?.reply == nil { finish([]) }
                else if let response { finish(response) }
            } else if frame.type == 12, frame.sequence <= 1 {
                guard write(SonyFrame(type: 1, sequence: frame.sequence ^ 1, payload: []).encoded) else { return }
                guard lastInboundSequence != frame.sequence else { continue }
                lastInboundSequence = frame.sequence
                parse(frame.payload)
                if let request = current, frame.payload.first == request.reply,
                   frame.payload.count > 1, frame.payload[1] == request.payload[1] {
                    response = frame.payload
                    if acknowledged { finish(frame.payload) }
                }
            }
        }
    }
    private func parse(_ p: [UInt8]) {
        if let newState = control?.decode(p) {
            control?.raw = p; state = newState
            if p.first == 0x67, let wanted {
                status = newState.matches(wanted) ? "Connected · \(newState.mode.title)" : "Setting did not apply — try again"
                self.wanted = nil
            } else if wanted == nil { status = "Connected · \(newState.mode.title)" }
        }
        if p.first == 0x67, let control, p.count > 1, p[1] == control.type, control.decode(p) == nil {
            state = nil; self.control = nil; wanted = nil
            status = "Connected · unrecognized sound settings"
        }
        if let reading = BatteryReading(generation: generation, payload: p) {
            switch reading.kind {
            case .single: battery = reading.first
            case .pair: left = reading.first; right = reading.second
            case .cradle: caseBattery = reading.first
            }
        }
        changed?()
    }
    func refresh() {
        if isNothing {
            sendNothing(nothingSession?.refresh(now: ProcessInfo.processInfo.systemUptime) ?? [])
            syncNothing(); return
        }
        guard ready, !busy else { return }
        if let control { enqueue([0x66,control.type], reply: 0x67, optional: true) }
        for type in capabilities?.batteryTypes ?? [] {
            enqueue([generation.batteryGet,type], reply: generation.batteryReply, optional: true)
        }
    }
    func set(_ mode: SoundMode, level: Int? = nil, voice: Bool? = nil) {
        if isNothing {
            guard level == nil, voice == nil else { return }
            sendNothing(nothingSession?.set(mode, now: ProcessInfo.processInfo.systemUptime) ?? [])
            syncNothing(); return
        }
        guard ready, !busy, let control,
              let command = control.command(mode, level: level, voice: voice), let expected = control.decode(command) else { return }
        wanted = expected; status = "Applying \(mode.title)…"
        enqueue(command, reply: nil) { [weak self] ack in
            guard let self, ack != nil else { return }
            self.enqueue([0x66,control.type], reply: 0x67)
        }
    }
    private func enqueue(_ payload: [UInt8], reply: UInt8?, optional: Bool = false, completion: (([UInt8]?) -> Void)? = nil) {
        if optional && disabledReads.contains(payload) { completion?(nil); return }
        queue.append(Request(payload: payload, reply: reply, optional: optional, completion: completion)); pump()
    }
    private func pump() {
        guard !pumpingDeferred, current == nil, !queue.isEmpty, channel != nil else { return }
        current = queue.removeFirst(); acknowledged = false; response = nil
        let payload = current!.payload
        log("TX " + payload.map { String(format: "%02x", $0) }.joined(separator: " "))
        guard write(SonyFrame(type: 12, sequence: sequence, payload: payload).encoded) else { return }
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.current?.optional == true && self.acknowledged {
                if let payload = self.current?.payload {
                    self.disabledReads.insert(payload)
                    if payload[0] == 0x66 { self.control = nil; self.state = nil; self.status = "Connected · sound controls unavailable" }
                }
                self.finish(nil)
            } else { self.fail("Headset did not respond. Close Sony Sound Connect and retry.") }
        }
        changed?()
    }
    @discardableResult private func write(_ bytes: [UInt8]) -> Bool {
        var bytes = bytes
        let result = bytes.withUnsafeMutableBytes { channel?.writeSync($0.baseAddress, length: UInt16($0.count)) ?? kIOReturnNotOpen }
        if result != kIOReturnSuccess { fail("Bluetooth write failed (\(result))"); return false }
        return true
    }
    private func finish(_ response: [UInt8]?) {
        timeout?.invalidate(); timeout = nil
        let done = current?.completion; current = nil; self.response = nil; pumpingDeferred = true; done?(response)
        // Defer the next request until this batch of incoming frames has been handled.
        DispatchQueue.main.async { [weak self] in self?.pumpingDeferred = false; self?.pump(); self?.changed?() }
    }
    private func startNothing() {
        nothingDecoder = NothingDecoder()
        nothingSession = NothingSession(probeSound: NothingSession.shouldProbeSound(deviceName: deviceName))
        sendNothing(nothingSession!.start(now: ProcessInfo.processInfo.systemUptime))
        syncNothing()
        guard channel != nil, nothingSession != nil else { return }
        nothingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.channel != nil, self.isNothing else { return }
            let frames = self.nothingSession?.tick(now: ProcessInfo.processInfo.systemUptime) ?? []
            self.sendNothing(frames); self.syncNothing()
        }
    }
    private func sendNothing(_ frames: [NothingFrame]) {
        for frame in frames {
            log(String(format: "Nothing TX %04x operation=%d", frame.command, frame.operation))
            guard write(frame.encoded) else { return }
        }
    }
    private func syncNothing() {
        guard let session = nothingSession else { return }
        if session.failed { fail(session.status); return }
        let snapshot = NothingView(ready: session.ready, busy: session.busy, mode: session.sound?.mode, batteries: session.batteries, status: session.status)
        guard snapshot != lastNothingView else { return }
        lastNothingView = snapshot
        ready = session.ready
        state = session.sound.map { SoundState(mode: $0.mode, level: 0, voice: false) }
        left = session.batteries?.left; right = session.batteries?.right
        caseBattery = session.batteries?.cradle; battery = session.batteries?.single
        if status != session.status { status = session.status }
        changed?()
    }
    func retry() { fail("Reconnecting…"); connect() }
    private func fail(_ message: String) {
        nothingTimer?.invalidate(); nothingTimer = nil; nothingSession = nil; nothingDecoder = NothingDecoder(); lastNothingView = nil
        timeout?.invalidate(); timeout = nil
        channel?.setDelegate(nil); channel?.close(); channel = nil
        opening = false; ready = false; state = nil; wanted = nil
        left = nil; right = nil; caseBattery = nil; battery = nil
        capabilities = nil; control = nil; disabledReads = []; lastInboundSequence = nil; response = nil; activeAddress = nil
        let completion = current?.completion
        current = nil; queue = []; decoder = SonyDecoder()
        status = message; completion?(nil)
    }
}
