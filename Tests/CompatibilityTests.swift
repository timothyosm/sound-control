import Foundation

@main struct CompatibilityTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            count += 1; if !condition { fatalError("FAIL: \(name)") }
        }
        func caps(_ generation: SonyGeneration, _ functions: [UInt8]) -> SonyCapabilities? {
            SonyCapabilities(generation: generation, payload: [7,0,UInt8(functions.count)] + functions.flatMap { generation == .v1 ? [$0] : [$0,0xff] })
        }
        check(SonyGeneration.v1.acceptsHandshake([1,0,1,0]), "legacy handshake")
        check(!SonyGeneration.v2.acceptsHandshake([1,0,1,0]), "do not confuse protocol families")
        check(SonyGeneration.v2.acceptsHandshake([1,0,3,0,0x20,0x15,0,0]), "captured LinkBuds handshake")
        check(!SonyGeneration.v2.acceptsHandshake([1,0,3,0,0,0,1,0]), "reject missing table one")
        check(caps(.v1,[0x62,0x11])?.soundType == 2, "legacy combined control")
        check(caps(.v1,[0x62,0x11])?.batteryTypes == [0], "legacy single battery")
        check(caps(.v2,[0x29,0x2a,0x6b])?.batteryTypes == [9,10], "earbud battery features")
        check(caps(.v2,[0x20])?.soundType == nil, "battery-only models have no sound controls")
        check(caps(.v2,[0x6d])?.soundType == 0x19, "noise-adaptive format")
        check(caps(.v2,[0x6a])?.soundType == 0x16, "dual-single format")
        check(caps(.v2,[0x67])?.soundType == 0x22, "ambient-only format")
        check(caps(.v2,[0xfe])?.soundType == nil, "unknown features cannot enable writes")
        check(SonyCapabilities(generation: .v2, payload: [7,0,2,0x6b,0xff]) == nil, "truncated capabilities")
        check(SonyCapabilities(generation: .v1, payload: [7,0,0,0x62]) == nil, "extra capability bytes rejected")
        check(SonyGeneration.v1.batteryGet == 0x10, "never send V2 power opcode to V1")
        // Captured capability response from this user's LinkBuds S.
        let cap: [UInt8] = [0x61,0x17,2,0,1,20,1,1,1,20,1]
        var v2 = SoundControl(generation: .v2, type: 0x17, capability: cap)!
        v2.raw = [0x67,0x17,1,1,1,0,10]
        check(v2.levels[false] == Array(1...20) && v2.hasVoice, "actual ambient capabilities")
        check(v2.command(.cancelling, level: nil, voice: nil) == [0x68,0x17,1,1,0,0,10], "golden V2 NC write")
        check(v2.command(.ambient, level: 21, voice: nil) == nil, "reject unsupported level")
        check(v2.decode([0x67,0x17,1,1,1,0,21]) == nil, "reject unsupported reported ambient level")
        check(v2.decode([0x67,0x17,1,1,0,0,1])!.matches(SoundState(mode: .cancelling, level: 10, voice: false)), "inactive ambient normalization")
        check(!SoundState(mode: .ambient, level: 1, voice: false).matches(SoundState(mode: .ambient, level: 10, voice: false)), "active level must match")
        for type: UInt8 in [0x13,0x14,0x16,0x17,0x18,0x19,0x22] {
            var c = cap; c[1] = type
            var control = SoundControl(generation: .v2, type: type, capability: c)!
            let raw: [UInt8]
            switch type {
            case 0x13,0x14: raw = [0x67,type,1,1,0,0,10]
            case 0x16: raw = [0x67,type,1,1,1,0,0,10]
            case 0x19: raw = [0x67,type,1,1,1,0,10,1,2]
            case 0x22: raw = [0x67,type,1,1,0,10]
            default: raw = [0x67,type,1,1,1,0,10]
            }
            control.raw = raw
            for mode in control.modes {
                let command = control.command(mode, level: 5, voice: true)!
                let decoded = control.decode(command)!
                check(decoded.mode == mode, "V2 mode \(type) \(mode)")
                if mode == .ambient { check(decoded.level == 5 && decoded.voice, "V2 level and voice") }
                if type == 0x19 { check(Array(command.suffix(2)) == [1,2], "preserve noise adaptation") }
            }
            for length in 0..<raw.count { check(control.decode(Array(raw.prefix(length))) == nil, "truncated state \(type)") }
        }
        var stepped = cap; stepped = [0x61,0x22,1,0,2,8,2]
        var ambient = SoundControl(generation: .v2, type: 0x22, capability: stepped)!
        ambient.raw = [0x67,0x22,1,1,0,4]
        check(ambient.levels[false] == [2,4,6,8], "device-specific range and step")
        check(ambient.command(.cancelling, level: nil, voice: nil) == nil, "ambient-only cannot cancel noise")
        check(ambient.command(.ambient, level: 3, voice: nil) == nil, "respect step")
        check(ambient.command(.ambient, level: nil, voice: true) == nil, "no unadvertised voice focus")
        var v2NC = SoundControl(generation: .v2, type: 1, capability: [0x61,1])!
        v2NC.raw = [0x67,1,1,1,1]
        check(v2NC.command(.off, level: nil, voice: nil) == [0x68,1,1,0,0], "V2 NC-only write")
        check(v2NC.command(.ambient, level: nil, voice: nil) == nil, "V2 NC-only rejects ambient")
        var v2ASM = SoundControl(generation: .v2, type: 0x21, capability: [0x61,0x21,2,0,1])!
        v2ASM.raw = [0x67,0x21,1,1,0,1]
        check(v2ASM.command(.ambient, level: 1, voice: true) == [0x68,0x21,1,1,1,1], "V2 ambient on/off write")
        check(v2ASM.decode([0x67,0x21,1,0,0,1])?.mode == .off, "V2 ambient off state")
        check(v2ASM.command(.cancelling, level: nil, voice: nil) == nil, "V2 ambient only rejects NC")
        var legacy = SoundControl(generation: .v1, type: 2, capability: [0x61,2,2,2,1,2,0,20,1,20])!
        legacy.raw = [0x67,2,1,2,0,1,0,10]
        check(legacy.command(.cancelling, level: nil, voice: nil) == [0x68,2,1,2,2,1,0,0], "golden legacy NC write")
        check(legacy.command(.ambient, level: 7, voice: true) == [0x68,2,1,2,0,1,1,7], "golden legacy ambient write")
        check(legacy.command(.off, level: nil, voice: nil) == [0x68,2,0,2,0,1,0,0], "golden legacy off write")
        for mode in legacy.modes { check(legacy.decode(legacy.command(mode, level: 7, voice: true)!)?.mode == mode, "legacy roundtrip") }
        var nc = SoundControl(generation: .v1, type: 1, capability: [0x61,1,0])!
        nc.raw = [0x67,1,0,1]
        check(nc.command(.off, level: nil, voice: nil) == [0x68,1,0,0], "legacy NC-only off")
        check(nc.command(.ambient, level: nil, voice: nil) == nil, "legacy NC-only ambient disabled")
        var asm = SoundControl(generation: .v1, type: 3, capability: [0x61,3,1,1,0,10])!
        asm.raw = [0x67,3,1,1,0,5]
        check(asm.command(.ambient, level: 7, voice: nil) == [0x68,3,1,1,0,7], "legacy ambient only")
        check(SoundControl(generation: .v2, type: 0x17, capability: [0x61,0x17,1,0,1,20,0]) == nil, "zero step rejected")
        check(SoundControl(generation: .v2, type: 0x17, capability: [0x61,0x17,2,0,1,20,1]) == nil, "short capability rejected")
        for gen in SonyGeneration.allCases {
            let op = gen.batteryReply
            check(BatteryReading(generation: gen, payload: [op,0,84,0])?.first == 84, "single battery")
            let dual = BatteryReading(generation: gen, payload: [op,1,73,0,62,1])
            check(dual?.first == 73 && dual?.second == 62, "dual battery")
            check(BatteryReading(generation: gen, payload: [op,2,255,0])?.first == nil, "unknown is not zero battery")
            check(BatteryReading(generation: gen, payload: [op,1,73,0]) == nil, "short dual battery")
        }
        check(BatteryReading(generation: .v2, payload: [0x23,9,7,0,8,0,100,100])?.second == 8, "threshold battery layout")
        check(BatteryReading(generation: .v1, payload: [0x23,0,84,0]) == nil, "reject other generation battery")
        print("PASS: \(count) compatibility assertions")
    }
}
