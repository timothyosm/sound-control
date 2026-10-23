import Foundation
import IOBluetooth

final class Headphones: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var changed: (() -> Void)?
    var status = "Looking for LinkBuds S…" { didSet { changed?(); log(status) } }
    var state: SoundState?
    var left: Int?, right: Int?, caseBattery: Int?
    var ready = false
    var busy: Bool { current != nil || !queue.isEmpty }
    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = SonyDecoder()
    private var sequence: UInt8 = 0
    private struct Request {
        var payload: [UInt8]
        var reply: UInt8?
        var completion: (([UInt8]?) -> Void)?
    }
    private var queue: [Request] = []
    private var current: Request?
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

    func connect() {
        guard channel == nil, !opening else { return }
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
              let device = devices.first(where: { $0.name?.localizedCaseInsensitiveContains("LinkBuds S") == true && $0.isConnected() }) else {
            status = "Connect LinkBuds S in Bluetooth Settings"; return
        }
        let bytes: [UInt8] = [0x95,0x6c,0x7b,0x26,0xd4,0x9a,0x4b,0xa8,0xb0,0x3f,0xb1,0x7d,0x39,0x3c,0xb6,0xe2]
        let uuid = bytes.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        guard let service = device.getServiceRecord(for: uuid) else { status = "Sony control service unavailable. Reconnect earbuds."; return }
        var id: BluetoothRFCOMMChannelID = 0
        guard service.getRFCOMMChannelID(&id) == kIOReturnSuccess else { status = "Sony control channel unavailable"; return }
        opening = true; status = "Connecting to earbuds…"
        let result = device.openRFCOMMChannelAsync(&channel, withChannelID: id, delegate: self)
        if result != kIOReturnSuccess { fail("Bluetooth connection failed (\(result))") }
        else {
            timeout = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                if self?.opening == true { self?.fail("Connection timed out. Close other Sony control apps.") }
            }
        }
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        timeout?.invalidate(); opening = false
        guard error == kIOReturnSuccess else { fail("Bluetooth connection failed (\(error))"); return }
        channel = rfcommChannel; sequence = 0; decoder = SonyDecoder()
        enqueue([0x00, 0x00], reply: 0x01) { [weak self] response in
            guard let self, response != nil else { return }
            self.ready = true; self.status = "Reading settings…"; self.refresh()
        }
    }
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) { fail("Disconnected — reconnecting automatically") }
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        for frame in decoder.feed(bytes) {
            log("RX \(frame.type) \(frame.sequence) " + frame.payload.map { String(format: "%02x", $0) }.joined(separator: " "))
            if frame.type == 1 {
                guard frame.sequence == (sequence ^ 1) else { continue }
                sequence = frame.sequence
                if current?.reply == nil { finish([]) }
            } else if frame.type == 12 {
                guard write(SonyFrame(type: 1, sequence: frame.sequence ^ 1, payload: []).encoded) else { return }
                parse(frame.payload)
                if let request = current, frame.payload.first == request.reply,
                   frame.payload.count > 1, frame.payload[1] == request.payload[1] { finish(frame.payload) }
            }
        }
    }
    private func parse(_ p: [UInt8]) {
        if let newState = SoundState(payload: p) {
            state = newState
            if let wanted { status = newState == wanted ? "Connected · \(newState.mode.title)" : "Setting did not apply — try again"; self.wanted = nil }
            else { status = "Connected · \(newState.mode.title)" }
        }
        if p.count >= 4, [0x23,0x25].contains(p[0]) {
            if p[1] == 9, p.count >= 6 { left = p[2] <= 100 ? Int(p[2]) : nil; right = p[4] <= 100 ? Int(p[4]) : nil }
            if p[1] == 10 { caseBattery = p[2] <= 100 ? Int(p[2]) : nil }
        }
        changed?()
    }
    func refresh() {
        guard ready, !busy else { return }
        enqueue([0x66,0x17], reply: 0x67)
        enqueue([0x22,0x09], reply: 0x23)
        enqueue([0x22,0x0a], reply: 0x23)
    }
    func set(_ mode: SoundMode, level: Int? = nil, voice: Bool? = nil) {
        guard ready, state != nil, !busy else { return }
        wanted = SoundState(payload: [0x67] + mode.command(level: level ?? state!.level, voice: voice ?? state!.voice).dropFirst()); status = "Applying \(mode.title)…"
        enqueue(mode.command(level: level ?? state!.level, voice: voice ?? state!.voice), reply: nil) { [weak self] ack in
            guard let self, ack != nil else { return }
            self.enqueue([0x66,0x17], reply: 0x67)
        }
    }
    private func enqueue(_ payload: [UInt8], reply: UInt8?, completion: (([UInt8]?) -> Void)? = nil) {
        queue.append(Request(payload: payload, reply: reply, completion: completion)); pump()
    }
    private func pump() {
        guard current == nil, !queue.isEmpty, channel != nil else { return }
        current = queue.removeFirst()
        let payload = current!.payload
        log("TX " + payload.map { String(format: "%02x", $0) }.joined(separator: " "))
        guard write(SonyFrame(type: 12, sequence: sequence, payload: payload).encoded) else { return }
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.fail("Earbuds did not respond. Close Sony Sound Connect and retry.")
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
        let done = current?.completion; current = nil; done?(response)
        // Defer the next request until this batch of incoming frames has been handled.
        DispatchQueue.main.async { [weak self] in self?.pump(); self?.changed?() }
    }
    func retry() { fail("Reconnecting…"); connect() }
    private func fail(_ message: String) {
        timeout?.invalidate(); timeout = nil
        channel?.setDelegate(nil); channel?.close(); channel = nil
        opening = false; ready = false; state = nil; wanted = nil
        left = nil; right = nil; caseBattery = nil
        let completion = current?.completion
        current = nil; queue = []; decoder = SonyDecoder()
        status = message; completion?(nil)
    }
}
