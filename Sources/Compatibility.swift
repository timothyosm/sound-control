import Foundation

enum SonyGeneration: String, CaseIterable {
    case v1 = "V1", v2 = "V2"
    var serviceBytes: [UInt8] {
        self == .v1
        ? [0x96,0xcc,0x20,0x3e,0x50,0x68,0x46,0xad,0xb3,0x2d,0xe3,0x16,0xf5,0xe0,0x69,0xba]
        : [0x95,0x6c,0x7b,0x26,0xd4,0x9a,0x4b,0xa8,0xb0,0x3f,0xb1,0x7d,0x39,0x3c,0xb6,0xe2]
    }
    func acceptsHandshake(_ p: [UInt8]) -> Bool {
        guard p.count >= 2, p[0] == 1, p[1] == 0 else { return false }
        return self == .v1 ? p.count == 4 : (p.count == 8 && p[6] == 0)
    }
    func supportsSecondTable(_ payload: [UInt8]) -> Bool {
        self == .v2 && acceptsHandshake(payload) && payload[7] == 0
    }
    var batteryGet: UInt8 { self == .v1 ? 0x10 : 0x22 }
    var batteryReply: UInt8 { self == .v1 ? 0x11 : 0x23 }
}

struct SonyCapabilities {
    let generation: SonyGeneration
    let functions: Set<UInt8>
    let soundType: UInt8?
    let batteryTypes: [UInt8]
    init?(generation: SonyGeneration, payload p: [UInt8]) {
        let width = generation == .v1 ? 1 : 2
        guard p.count >= 3, p[0] == 7, p[1] == 0, p.count == 3 + Int(p[2]) * width else { return nil }
        self.generation = generation
        let functions = Set(stride(from: 3, to: p.count, by: width).map { p[$0] })
        self.functions = functions
        // Prefer the most complete advertised format. Unknown formats remain read-only.
        let soundMap: [(UInt8, UInt8)] = generation == .v1
            ? [(0x62,2),(0x61,1),(0x63,3)]
            : [(0x6d,0x19),(0x6c,0x18),(0x6b,0x17),(0x6a,0x16),(0x65,0x14),(0x64,0x13),(0x67,0x22),(0x66,0x21),(0x61,1)]
        soundType = soundMap.first { functions.contains($0.0) }?.1
        let batteryMap: [(UInt8, UInt8)] = generation == .v1
            ? [(0x11,0),(0x15,1),(0x18,2)]
            : [(0x20,0),(0x21,1),(0x22,2),(0x28,8),(0x29,9),(0x2a,10)]
        batteryTypes = batteryMap.filter { functions.contains($0.0) }.map { $0.1 }
    }
}

// Capability-validated settings. Retain the original packet so newer fields (e.g.
// noise adaptation) survive changes to the controls this app understands.
struct SoundControl {
    let generation: SonyGeneration
    let type: UInt8
    var levels: [Bool: [Int]] = [:]
    var ncType: UInt8 = 0
    var ncMaximum: UInt8 = 1
    var asmType: UInt8 = 0
    var raw: [UInt8] = []
    var hasNC: Bool { generation == .v1 ? type != 3 : ![0x21,0x22].contains(type) }
    var hasAmbient: Bool { type != 1 }
    var hasVoice: Bool { levels[true] != nil }
    var modes: [SoundMode] { SoundMode.allCases.filter { $0 == .off || ($0 == .cancelling ? hasNC : hasAmbient) } }
    init?(generation: SonyGeneration, type: UInt8, capability p: [UInt8]) {
        guard p.count >= 2, p[0] == 0x61, p[1] == type else { return nil }
        self.generation = generation; self.type = type
        if generation == .v1 {
            if type == 1 {
                guard p.count == 3, p[2] == 0 else { return nil } // only defined on/off NC writes
            } else {
                let offset: Int
                if type == 2 {
                    guard p.count >= 6, p[2] <= 2, p[3] > 0, p[4] <= 1 else { return nil }
                    ncType = p[2]; ncMaximum = p[3]; asmType = p[4]; offset = 5
                } else if type == 3 {
                    guard p.count >= 4, p[2] <= 1 else { return nil }
                    asmType = p[2]; offset = 3
                } else { return nil }
                guard p.count == offset + 1 + Int(p[offset]) * 2 else { return nil }
                for i in stride(from: offset + 1, to: p.count, by: 2) where p[i] <= 1 && p[i+1] > 0 {
                    levels[p[i] == 1] = Array(1...Int(asmType == 0 ? 1 : p[i+1]))
                }
                guard levels[false] != nil else { return nil }
            }
        } else {
            if type == 1 { guard p.count == 2 else { return nil }; return }
            guard [0x13,0x14,0x16,0x17,0x18,0x19,0x21,0x22].contains(type), p.count >= 3 else { return nil }
            let width = type == 0x21 ? 1 : 4
            guard p.count == 3 + Int(p[2]) * width else { return nil }
            for i in stride(from: 3, to: p.count, by: width) where p[i] <= 1 {
                if width == 1 { levels[p[i] == 1] = [1] }
                else {
                    let low = Int(p[i+1]), high = Int(p[i+2]), step = Int(p[i+3])
                    guard step > 0, high >= low else { return nil }
                    levels[p[i] == 1] = Array(stride(from: low, through: high, by: step))
                }
            }
            guard levels[false] != nil else { return nil }
        }
    }
    func decode(_ p: [UInt8]) -> SoundState? {
        guard p.count >= 2, [0x67,0x69,0x68].contains(p[0]), p[1] == type else { return nil }
        var mode: SoundMode, level = 1, voice = false
        if generation == .v1 {
            if type == 1 {
                guard p.count == 4, p[2] == 0, p[3] <= 1 else { return nil }
                mode = p[3] == 0 ? .off : .cancelling
            } else {
                let vi = type == 2 ? 6 : 4, li = vi + 1
                guard p.count == li + 1, p[2] <= 1, p[vi] <= 1 else { return nil }
                if type == 2 { guard p[3] == ncType, p[5] == asmType, p[4] <= ncMaximum else { return nil } }
                else { guard p[3] == asmType else { return nil } }
                voice = p[vi] == 1; level = Int(p[li])
                mode = p[2] == 0 ? .off : (type == 2 && p[4] > 0 ? .cancelling : .ambient)
            }
        } else {
            let size = [UInt8(1):5,0x13:7,0x14:7,0x16:8,0x17:7,0x18:7,0x19:9,0x21:6,0x22:6][type]!
            guard p.count == size, p[2] <= 1, p[3] <= 1 else { return nil }
            if type == 1 {
                guard p[4] <= 1 else { return nil }; mode = p[3] == 0 || p[4] == 0 ? .off : .cancelling
            } else {
                let vi = type == 0x16 ? 6 : (hasNC ? 5 : 4), li = vi + 1
                guard p[vi] <= 1 else { return nil }
                if hasNC { guard p[4] <= (type == 0x14 ? 2 : 1) else { return nil } }
                if type == 0x16 { guard p[5] <= 2 else { return nil } }
                voice = p[vi] == 1; level = Int(p[li])
                let cancelling = [0x13,0x14].contains(type) ? p[4] > 0 : (hasNC && p[4] == 0)
                mode = p[3] == 0 ? .off : (cancelling ? .cancelling : .ambient)
            }
        }
        if mode == .ambient { guard levels[voice]?.contains(level) == true else { return nil } }
        return SoundState(mode: mode, level: level, voice: voice)
    }
    func command(_ mode: SoundMode, level: Int?, voice: Bool?) -> [UInt8]? {
        guard modes.contains(mode), let state = decode(raw) else { return nil }
        let focus = voice ?? state.voice
        let allowed = levels[focus] ?? []
        if voice == true && !hasVoice { return nil }
        let value = level ?? (allowed.contains(state.level) ? state.level : (allowed.last ?? 1))
        if mode == .ambient && !allowed.contains(value) { return nil }
        var p = raw; p[0] = 0x68
        if generation == .v1 {
            if type == 1 { p[3] = mode == .off ? 0 : 1 }
            else {
                p[2] = mode == .off ? 0 : 1
                if type == 2 { p[4] = mode == .cancelling ? ncMaximum : 0 }
                let vi = type == 2 ? 6 : 4
                p[vi] = focus ? 1 : 0
                p[vi+1] = mode == .ambient ? UInt8(value) : 0
            }
        } else {
            p[2] = 1; p[3] = mode == .off ? 0 : 1
            if type == 1 { p[4] = mode == .off ? 0 : 1 }
            else {
                if [0x13,0x14].contains(type) { p[4] = mode == .cancelling ? (type == 0x14 ? 2 : 1) : 0 }
                else if hasNC { p[4] = mode == .ambient ? 1 : 0 }
                if type == 0x16 { p[5] = mode == .cancelling ? 2 : 0 }
                let vi = type == 0x16 ? 6 : (hasNC ? 5 : 4)
                p[vi] = focus ? 1 : 0; p[vi+1] = UInt8(value)
            }
        }
        return p
    }
}

struct BatteryReading: Equatable {
    enum Kind { case single, pair, cradle }
    let kind: Kind
    let first: Int?
    let second: Int?
    init?(generation: SonyGeneration, payload p: [UInt8]) {
        guard p.count >= 4, [generation.batteryReply, generation.batteryReply + 2].contains(p[0]) else { return nil }
        let subtype = p[1]
        guard generation == .v1 ? subtype <= 2 : [0,1,2,8,9,10].contains(subtype) else { return nil }
        let base = subtype >= 8 ? subtype - 8 : subtype
        kind = base == 0 ? .single : base == 1 ? .pair : .cradle
        let expected = (base == 1 ? 6 : 4) + (subtype >= 8 ? (base == 1 ? 2 : 1) : 0)
        guard p.count == expected else { return nil }
        first = p[2] <= 100 ? Int(p[2]) : nil
        second = base == 1 && p[4] <= 100 ? Int(p[4]) : nil
    }
}
