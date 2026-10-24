import Foundation

// Independent wire-format implementation. Protocol facts and captured-packet
// references are documented in docs/nothing-protocol.md. No external runtime.
struct NothingFrame: Equatable {
    static let serviceBytes: [UInt8] = [0xae,0xac,0x4a,0x03,0xdf,0xf5,0x49,0x8f,0x84,0x3a,0x34,0x48,0x7c,0xf1,0x33,0xeb]
    var command: UInt16
    var operation: UInt8
    var payload: [UInt8]
    var flags: UInt8 = 0x60
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        bytes.reduce(UInt16.max) { accumulator, byte in
            (0..<8).reduce(accumulator ^ UInt16(byte)) { value, _ in
                (value >> 1) ^ (value & 1 == 0 ? 0 : 0xa001)
            }
        }
    }
    var encoded: [UInt8] {
        precondition(payload.count <= 4096)
        var bytes: [UInt8] = [0x55, flags, 1, UInt8(truncatingIfNeeded: command), UInt8(command >> 8), UInt8(truncatingIfNeeded: payload.count), UInt8(payload.count >> 8), operation]
        bytes += payload
        let crc = Self.checksum(bytes)
        bytes += [UInt8(truncatingIfNeeded: crc), UInt8(crc >> 8)]
        return bytes
    }
}

struct NothingDecoder {
    private var buffer: [UInt8] = []
    mutating func feed(_ bytes: [UInt8]) -> [NothingFrame] {
        var result: [NothingFrame] = []
        for byte in bytes {
            buffer.append(byte)
            while buffer.count >= 8 {
                guard buffer[0] == 0x55, [0,0x60].contains(buffer[1]), buffer[2] == 1 else { buffer.removeFirst(); continue }
                let count = Int(buffer[5]) | Int(buffer[6]) << 8
                guard count <= 4096 else { buffer.removeFirst(); continue }
                let end = 8 + count
                guard buffer.count >= end + 2 else { break }
                let crc = UInt16(buffer[end]) | UInt16(buffer[end+1]) << 8
                guard NothingFrame.checksum(Array(buffer[..<end])) == crc else { buffer.removeFirst(); continue }
                result.append(NothingFrame(command: UInt16(buffer[3]) | UInt16(buffer[4]) << 8, operation: buffer[7], payload: Array(buffer[8..<end]), flags: buffer[1]))
                buffer.removeFirst(end + 2)
            }
        }
        return result
    }
}

struct NothingSound: Equatable {
    let value: UInt8
    init?(payload: [UInt8]) {
        // Other records may follow the ANC record (e.g. personalized ANC).
        guard payload.count >= 3, payload[0] == 1, [1,2,3,4,5,7].contains(payload[1]), payload[2] == 0 else { return nil }
        value = payload[1]
    }
    var mode: SoundMode { value == 5 ? .off : value == 7 ? .ambient : .cancelling }
    static func command(_ mode: SoundMode, cancellationValue: UInt8) -> [UInt8] {
        let strength = (1...4).contains(cancellationValue) ? cancellationValue : 1
        return [1, mode == .off ? 5 : mode == .ambient ? 7 : strength, 0]
    }
}

struct NothingBatteries: Equatable {
    var left: Int?, right: Int?, cradle: Int?, single: Int?
    init?(payload p: [UInt8]) {
        guard let count = p.first, p.count == 1 + Int(count) * 2 else { return nil }
        var ids = Set<UInt8>()
        for i in stride(from: 1, to: p.count, by: 2) {
            guard ids.insert(p[i]).inserted else { return nil }
            let percent = Int(p[i+1] & 0x7f)
            let reading: Int? = percent <= 100 ? percent : nil
            switch p[i] {
            case 2: left = reading
            case 3: right = reading
            case 4: cradle = reading
            case 6: single = reading
            default: break
            }
        }
    }
}

// Deterministic session engine: all I/O and timing are supplied by Headphones.
// Poll replies must echo their operation ID; unsolicited reports update state
// but cannot certify a write. A write is followed by a separately matched read.
struct NothingSession {
    enum Read {
        case battery, sound, verify(SoundMode), extra(UInt16, NothingEdit?)
        var command: UInt16 { if case .battery = self { return 0xc007 }; if case .extra(let command, _) = self { return command }; return 0xc01e }
        var reply: UInt16 { command & 0x7fff }
    }
    struct Pending { let read: Read; let operation: UInt8; let deadline: TimeInterval }
    let probeSound: Bool
    private(set) var extras = NothingExtras()
    private var extrasStarted = false
    private var extraVerification: (edit: NothingEdit, at: TimeInterval)?
    private(set) var sound: NothingSound?
    private(set) var batteries: NothingBatteries?
    private(set) var status = "Reading Nothing settings…"
    private(set) var ready = false
    private(set) var failed = false
    private var queue: [Read] = []
    private var pending: Pending?
    private var verification: (mode: SoundMode, at: TimeInterval)?
    private var operation: UInt8 = 0
    private var cancellationValue: UInt8 = 1
    var busy: Bool { pending != nil || !queue.isEmpty || verification != nil || extraVerification != nil }
    init(probeSound: Bool = true) { self.probeSound = probeSound }
    static func shouldProbeSound(deviceName: String) -> Bool {
        let compact = deviceName.lowercased().filter { $0.isLetter || $0.isNumber }
        return !compact.contains("earopen") && !compact.contains("earstick")
    }
    mutating func start(now: TimeInterval) -> [NothingFrame] {
        queue = [.battery] + (probeSound ? [.sound] : [])
        return advance(now: now)
    }
    private mutating func nextID() -> UInt8 {
        operation = operation >= 250 ? 1 : operation + 1; return operation
    }
    private mutating func advance(now: TimeInterval) -> [NothingFrame] {
        guard pending == nil, verification == nil, extraVerification == nil else { return [] }
        guard !queue.isEmpty else {
            ready = batteries != nil || sound != nil
            failed = !ready
            if failed { status = "Could not read settings from your Nothing or CMF device" }
            return []
        }
        let read = queue.removeFirst(), id = nextID()
        pending = Pending(read: read, operation: id, deadline: now + 4)
        return [NothingFrame(command: read.command, operation: id, payload: [])]
    }
    mutating func refresh(now: TimeInterval) -> [NothingFrame] {
        guard ready, !busy else { return [] }
        queue = [.battery] + (probeSound ? [.sound] : []) + (extrasStarted ? NothingExtras.probes.filter { extras.values[$0] != nil }.map { .extra($0, nil) } : [])
        return advance(now: now)
    }
    mutating func set(_ mode: SoundMode, now: TimeInterval) -> [NothingFrame] {
        guard ready, sound != nil, !busy, probeSound else { return [] }
        let frame = NothingFrame(command: 0xf00f, operation: nextID(), payload: NothingSound.command(mode, cancellationValue: cancellationValue))
        status = "Applying \(mode == .ambient ? "transparency" : mode.title.lowercased())…"
        verification = (mode, now + 0.2)
        return [frame]
    }
    mutating func loadExtras(now: TimeInterval) -> [NothingFrame] {
        guard ready, !busy, !extrasStarted else { return [] }
        extrasStarted = true
        queue = NothingExtras.probes.map { .extra($0, nil) }
        return advance(now: now)
    }
    mutating func setExtra(id: String, value: Int, now: TimeInterval) -> [NothingFrame] {
        guard ready, !busy, let edit = extras.edit(id: id, value: value) else { return [] }
        extraVerification = (edit, now + 0.2)
        status = "Applying setting…"
        return [NothingFrame(command: edit.write, operation: nextID(), payload: edit.payload)]
    }
    mutating func tick(now: TimeInterval) -> [NothingFrame] {
        if let extraVerification, now >= extraVerification.at {
            self.extraVerification = nil
            queue.insert(.extra(extraVerification.edit.read, extraVerification.edit), at: 0)
        }
        if let verification, now >= verification.at {
            self.verification = nil; queue.insert(.verify(verification.mode), at: 0)
        }
        if let pending, now >= pending.deadline {
            switch pending.read {
            case .extra(let command, let edit):
                _ = extras.receive(command, payload: nil)
                if command == 0xc01e { sound = nil }
                if edit != nil { status = "Could not confirm the setting – choose Refresh" }
            case .battery: batteries = nil
            case .sound: sound = nil; _ = extras.receive(0xc01e, payload: nil); status = "Connected · sound controls unavailable"
            case .verify: sound = nil; _ = extras.receive(0xc01e, payload: nil); status = "Could not confirm the sound change – choose Refresh"
            }
            self.pending = nil
        }
        return advance(now: now)
    }
    mutating func receive(_ frame: NothingFrame, now: TimeInterval) -> [NothingFrame] {
        let matching = pending.map { frame.command == $0.read.reply && frame.operation == $0.operation } ?? false
        if matching, case .extra(let command, let edit)? = pending?.read {
            guard extras.receive(command, payload: frame.payload) else { return [] }
            if command == 0xc01e, let sound = NothingSound(payload: frame.payload) {
                self.sound = sound
                if sound.mode == .cancelling { cancellationValue = sound.value }
            }
            if let edit { status = edit.matches(frame.payload) ? "Setting applied" : "Setting did not apply – try again" }
            pending = nil
            return advance(now: now)
        }
        let batteryEvent = frame.command == 0xe001
        let soundEvent = [UInt16(0xe003),0x6003].contains(frame.command)
        var valid = false
        if (matching && frame.command == 0x4007) || batteryEvent {
            if let value = NothingBatteries(payload: frame.payload) { batteries = value; valid = true }
        }
        if ((matching && frame.command == 0x401e) || soundEvent) && probeSound {
            if let value = NothingSound(payload: frame.payload) {
                sound = value; valid = true
                _ = extras.receive(0xc01e, payload: frame.payload)
                if value.mode == .cancelling { cancellationValue = value.value }
                if verification == nil {
                    if case .verify(let wanted)? = pending?.read {
                        if matching { status = value.mode == wanted ? connectedStatus : "Setting did not apply – try again" }
                    } else { status = connectedStatus }
                }
            }
        }
        guard matching && valid else { return [] }
        if frame.command == 0x4007 && !probeSound { status = "Connected · battery information" }
        pending = nil
        return advance(now: now)
    }
    private var connectedStatus: String {
        "Connected · " + (sound?.mode == .ambient ? "Transparency" : sound?.mode.title ?? "Nothing")
    }
}
