import Foundation

struct SonyFrame: Equatable {
    let type: UInt8
    let sequence: UInt8
    let payload: [UInt8]
    var encoded: [UInt8] {
        let n = UInt32(payload.count)
        var bytes: [UInt8] = [type, sequence, UInt8(n >> 24), UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)] + payload
        bytes.append(bytes.reduce(0, &+))
        return [0x3e] + bytes.flatMap { (0x3c...0x3e).contains($0) ? [0x3d, $0 ^ 0x10] : [$0] } + [0x3c]
    }
}

struct SonyDecoder {
    private var buffer: [UInt8] = []
    private var started = false
    private var escaped = false
    mutating func feed(_ bytes: [UInt8]) -> [SonyFrame] {
        var frames: [SonyFrame] = []
        for byte in bytes {
            if byte == 0x3e { buffer = []; started = true; escaped = false; continue }
            guard started else { continue }
            if byte == 0x3c {
                if !escaped, buffer.count >= 7 {
                    let length = buffer[2...5].reduce(0) { ($0 << 8) | Int($1) }
                    if length == buffer.count - 7, buffer.dropLast().reduce(UInt8(0), &+) == buffer.last! {
                        frames.append(SonyFrame(type: buffer[0], sequence: buffer[1], payload: Array(buffer[6..<(6 + length)])))
                    }
                }
                buffer = []; started = false; escaped = false
            } else if escaped {
                guard (0x2c...0x2e).contains(byte) else { started = false; buffer = []; escaped = false; continue }
                buffer.append(byte ^ 0x10); escaped = false
            } else if byte == 0x3d { escaped = true }
            else { buffer.append(byte) }
            if buffer.count > 8192 { buffer = []; started = false; escaped = false }
        }
        return frames
    }
}

enum SoundMode: Int, CaseIterable {
    case cancelling, ambient, off
    var title: String { ["Noise cancelling", "Ambient sound", "Off"][rawValue] }
    func command(level: Int, voice: Bool) -> [UInt8] {
        [0x68, 0x17, 1, self == .off ? 0 : 1, self == .ambient ? 1 : 0, voice ? 1 : 0, UInt8(max(1, min(20, level)))]
    }
}

struct SoundState: Equatable {
    var mode: SoundMode
    var level: Int
    var voice: Bool
    // Devices may normalize inactive ambient fields when NC or Off is selected.
    func matches(_ other: SoundState) -> Bool {
        mode == other.mode && (mode != .ambient || (level == other.level && voice == other.voice))
    }
    init(mode: SoundMode, level: Int, voice: Bool) { self.mode = mode; self.level = level; self.voice = voice }
    init?(payload: [UInt8]) {
        guard payload.count >= 7, [0x67, 0x69].contains(payload[0]), payload[1] == 0x17,
              payload[3] <= 1, payload[4] <= 1, payload[5] <= 1, payload[6] <= 20 else { return nil }
        mode = payload[3] == 0 ? .off : (payload[4] == 0 ? .cancelling : .ambient)
        level = max(1, Int(payload[6])); voice = payload[5] == 1
    }
}
