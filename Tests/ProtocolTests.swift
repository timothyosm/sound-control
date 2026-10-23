import Foundation

@main struct ProtocolTests {
    static func main() {
        var assertions = 0
        func check(_ condition: Bool, _ label: String) {
            assertions += 1
            guard condition else { fatalError("FAIL: \(label)") }
        }
        let frame = SonyFrame(type: 12, sequence: 1, payload: Array(UInt8.min...UInt8.max))
        for split in 0...frame.encoded.count {
            var decoder = SonyDecoder()
            let a = decoder.feed(Array(frame.encoded.prefix(split)))
            let b = decoder.feed(Array(frame.encoded.dropFirst(split)))
            check(a + b == [frame], "split frame at \(split)")
        }
        var decoder = SonyDecoder()
        check(decoder.feed(frame.encoded + frame.encoded) == [frame, frame], "coalesced frames")
        var bad = SonyFrame(type: 12, sequence: 0, payload: [0x66,0x17]).encoded
        bad[7] ^= 1
        check(decoder.feed(bad).isEmpty, "reject corrupt checksum")
        check(decoder.feed([0x3e, 0x3d, 0x11, 0x3c] + frame.encoded) == [frame], "recover malformed escape")
        check(decoder.feed([0x3e] + Array(repeating: 0, count: 9000) + frame.encoded) == [frame], "bounded stream buffer")
        var lengthMismatch: [UInt8] = [12,0,0,0,0,5,0x66,0x17]
        lengthMismatch.append(lengthMismatch.reduce(0, &+))
        check(decoder.feed([0x3e] + lengthMismatch + [0x3c]).isEmpty, "reject incorrect declared length")
        for mode in SoundMode.allCases {
            for level in [1,10,20] {
                for voice in [false,true] {
                    let state = SoundState(payload: [0x67] + mode.command(level: level, voice: voice).dropFirst())
                    check(state?.mode == mode && state?.level == level && state?.voice == voice, "sound state roundtrip")
                }
            }
        }
        check(SoundState(payload: [0x67,0x17]) == nil, "short state rejected")
        check(SoundState(payload: [0x67,0x17,1,1,1,0,255]) == nil, "invalid level rejected")
        check(SoundState(payload: [0x67,0x17,1,1,1,0,17])?.level == 17, "captured LinkBuds S response")
        check(SoundMode.ambient.command(level: -100, voice: false).last == 1, "clamp low")
        check(SoundMode.ambient.command(level: 1000, voice: false).last == 20, "clamp high")
        print("PASS: \(assertions) protocol assertions")
    }
}
