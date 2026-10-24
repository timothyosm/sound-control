import Foundation
import IOBluetooth

final class Headphones: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var changed: (() -> Void)?
    var status = "Looking for Sony headphones…" { didSet { changed?(); log(status) } }
    var state: SoundState?
    var left: Int?, right: Int?, caseBattery: Int?, battery: Int?
    var deviceName = "Sony headphones"
    var generation: SonyGeneration = .v2
    var capabilities: SonyCapabilities?
    var control: SoundControl?
    struct Device {
        let address: String
        let name: String
        let connected: Bool
        let generation: SonyGeneration
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
    var busy: Bool { current != nil || !queue.isEmpty }
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
            for generation in [SonyGeneration.v2, .v1] {
                let uuid = generation.serviceBytes.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
                if let service = device.getServiceRecord(for: uuid), let address = device.addressString {
                    return Device(address: address, name: device.name ?? "Sony headphones", connected: device.isConnected(), generation: generation, device: device, service: service)
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
            status = "Connect a compatible Sony headset in Bluetooth Settings"; return
        }
        deviceName = selected.name; activeAddress = selected.address; generation = selected.generation
        guard selected.connected else { status = "Connect \(deviceName) in Bluetooth Settings"; return }
        var id: BluetoothRFCOMMChannelID = 0
        guard selected.service.getRFCOMMChannelID(&id) == kIOReturnSuccess else { status = "Sony control channel unavailable"; return }
        opening = true; status = "Connecting to \(deviceName)…"
        let result = selected.device.openRFCOMMChannelAsync(&channel, withChannelID: id, delegate: self)
        if result != kIOReturnSuccess { fail("Bluetooth connection failed (\(result))") }
        else if opening {
            timeout = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                if self?.opening == true { self?.fail("Connection timed out. Close other Sony control apps.") }
            }
        }
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard opening else { return }
        timeout?.invalidate(); opening = false
        guard error == kIOReturnSuccess else { fail("Bluetooth connection failed (\(error))"); return }
        channel = rfcommChannel; sequence = 0; decoder = SonyDecoder()
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
        guard ready, !busy else { return }
        if let control { enqueue([0x66,control.type], reply: 0x67, optional: true) }
        for type in capabilities?.batteryTypes ?? [] {
            enqueue([generation.batteryGet,type], reply: generation.batteryReply, optional: true)
        }
    }
    func set(_ mode: SoundMode, level: Int? = nil, voice: Bool? = nil) {
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
    func retry() { fail("Reconnecting…"); connect() }
    private func fail(_ message: String) {
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
