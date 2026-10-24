import Foundation

@main struct NothingTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ label: String) {
            count += 1; guard condition else { fatalError("FAIL: \(label)") }
        }
        func hex(_ text: String) -> [UInt8] { text.split(separator: " ").map { UInt8($0, radix: 16)! } }
        // Captured Ear (2) packets published by Bharadwaj Raju (2024-01-06).
        let transparency = NothingFrame(command: 0xf00f, operation: 0xcb, payload: [1,7,0])
        check(transparency.encoded == hex("55 60 01 0f f0 03 00 cb 01 07 00 c5 af"), "captured transparency command")
        check(NothingFrame(command: 0xf00f, operation: 0xcf, payload: [1,1,0]).encoded == hex("55 60 01 0f f0 03 00 cf 01 01 00 c7 3f"), "NC high command with recomputed CRC")
        check(NothingFrame(command: 0xc042, operation: 3, payload: []).encoded == hex("55 60 01 42 c0 00 00 03 e0 d1"), "captured firmware query")
        let actualReply = hex("55 60 01 1e 40 06 00 0c 01 07 00 02 04 00 10 7a")
        var decoder = NothingDecoder()
        let parsed = decoder.feed(actualReply)
        check(parsed.count == 1 && parsed[0].command == 0x401e && parsed[0].operation == 0x0c, "captured read response")
        check(NothingSound(payload: parsed[0].payload)?.mode == .ambient, "captured transparency status")
        let frame = NothingFrame(command: 0x4007, operation: 50, payload: [3,2,90,3,0x80|70,4,60])
        for split in 0...frame.encoded.count {
            var d = NothingDecoder()
            let first = d.feed(Array(frame.encoded.prefix(split)))
            check(first + d.feed(Array(frame.encoded.dropFirst(split))) == [frame], "fragmented frame \(split)")
        }
        let allBytes = NothingFrame(command: 0x4006, operation: 99, payload: Array(UInt8.min...UInt8.max))
        check(decoder.feed(allBytes.encoded) == [allBytes], "16-bit payload length and embedded sync bytes")
        check(decoder.feed([0,2,0x55,0xff] + frame.encoded + actualReply).count == 2, "noise and multiple frames")
        var corrupt = frame.encoded; corrupt[10] ^= 1
        check(decoder.feed(corrupt + frame.encoded) == [frame], "CRC failure recovery")
        let event = NothingFrame(command: 0xe003, operation: 0, payload: [1,5,0], flags: 0)
        check(decoder.feed(event.encoded) == [event], "notification framing")
        check(decoder.feed([0x55,0x60,1,7,0x40,0xff,0xff,1] + frame.encoded) == [frame], "oversize length rejected")
        check(decoder.feed(Array(repeating: 0x88, count: 10000) + frame.encoded) == [frame], "long garbage bounded")
        let b = NothingBatteries(payload: frame.payload)!
        check(b.left == 90 && b.right == 70 && b.cradle == 60, "charging bit masked")
        check(NothingBatteries(payload: [1,6,88])?.single == 88, "headphone single battery")
        check(NothingBatteries(payload: [2,2,90]) == nil, "truncated battery rejected")
        check(NothingBatteries(payload: [2,2,90,2,80]) == nil, "duplicate battery component rejected")
        check(NothingBatteries(payload: [1,2,255])?.left == nil, "unknown battery not 127 percent")
        check(NothingSound(payload: [1,6,0]) == nil, "unknown ANC mode disabled")
        check(NothingSound(payload: [1,7]) == nil, "truncated sound response")
        check(!NothingSession.shouldProbeSound(deviceName: "Nothing Ear (open)"), "open-ear has no ANC")
        check(!NothingSession.shouldProbeSound(deviceName: "ear (stick)"), "stick's different firmware feature excluded")
        check(NothingSession.shouldProbeSound(deviceName: "Nothing Ear (a)"), "Ear a probe")
        check(NothingSession.shouldProbeSound(deviceName: "CMF Buds Pro 2"), "CMF probe")
        for value: UInt8 in [1,2,3,4] {
            check(NothingSound(payload: [1,value,0])?.mode == .cancelling, "ANC strength \(value)")
            check(NothingSound.command(.cancelling, cancellationValue: value) == [1,value,0], "retain known strength")
        }
        var session = NothingSession()
        check(session.set(.off, now: 0).isEmpty, "no writes before successful discovery")
        let batteryRequest = session.start(now: 0)[0]
        check(batteryRequest.command == 0xc007, "read-only startup")
        check(session.receive(NothingFrame(command: 0x4007, operation: batteryRequest.operation + 1, payload: [1,6,80]), now: 1).isEmpty && session.batteries == nil, "reject stale reply ID")
        let soundRequest = session.receive(NothingFrame(command: 0x4007, operation: batteryRequest.operation, payload: [1,6,80]), now: 1)[0]
        check(soundRequest.command == 0xc01e, "probe ANC after batteries")
        _ = session.receive(NothingFrame(command: 0x401e, operation: soundRequest.operation, payload: [1,3,0]), now: 2)
        check(session.ready && !session.busy && session.sound?.mode == .cancelling, "enable only after valid sound read")
        let set = session.set(.ambient, now: 3)[0]
        check(set.command == 0xf00f && set.payload == [1,7,0], "transparency write")
        check(session.sound?.mode == .cancelling && session.busy, "do not optimistically change checkmark")
        check(session.tick(now: 3.1).isEmpty, "allow settling before read-back")
        let verify = session.tick(now: 3.3)[0]
        check(verify.command == 0xc01e, "read back every write")
        _ = session.receive(NothingFrame(command: 0xe003, operation: 0, payload: [1,7,0], flags: 0), now: 3.4)
        check(session.busy && session.status.hasPrefix("Applying"), "notification does not certify write")
        _ = session.receive(NothingFrame(command: 0x401e, operation: verify.operation, payload: [1,7,0]), now: 3.5)
        check(!session.busy && session.status == "Connected · Transparency", "matched verification succeeds")
        check(session.set(.cancelling, now: 4)[0].payload == [1,3,0], "remember NC strength after transparency")
        let verifyFailure = session.tick(now: 4.3)[0]
        _ = session.receive(NothingFrame(command: 0x401e, operation: verifyFailure.operation, payload: [1,7,0]), now: 4.5)
        check(session.status == "Setting did not apply – try again", "mismatched read-back reported")
        _ = session.set(.off, now: 5)
        _ = session.tick(now: 5.3)
        _ = session.tick(now: 10)
        check(session.sound == nil && !session.busy && session.ready, "verification timeout disables sound, keeps batteries")
        check(session.set(.off, now: 10).isEmpty, "cannot write after failed verification")
        let refreshBattery = session.refresh(now: 11)[0]
        let refreshSound = session.receive(NothingFrame(command: 0x4007, operation: refreshBattery.operation, payload: [1,6,70]), now: 12)[0]
        _ = session.receive(NothingFrame(command: 0x401e, operation: refreshSound.operation, payload: [1,5,0]), now: 13)
        check(session.ready && session.sound?.mode == .off, "refresh restores controls")
        var absent = NothingSession()
        _ = absent.start(now: 0)
        check(absent.tick(now: 5).first?.command == 0xc01e, "battery timeout continues discovery")
        _ = absent.tick(now: 10)
        check(absent.failed && !absent.ready, "silent device fails cleanly")
        var batteryOnly = NothingSession(probeSound: false)
        let only = batteryOnly.start(now: 0)[0]
        _ = batteryOnly.receive(NothingFrame(command: 0x4007, operation: only.operation, payload: [1,2,60]), now: 1)
        check(batteryOnly.ready && batteryOnly.sound == nil && batteryOnly.set(.cancelling, now: 2).isEmpty, "battery-only devices cannot enable ANC")
        // Exercise operation-ID wrap without accepting stale pending replies.
        for tick in 0..<300 {
            let outgoing = batteryOnly.refresh(now: Double(tick + 10))[0]
            check(outgoing.operation > 0 && outgoing.operation <= 250, "bounded operation ID")
            _ = batteryOnly.receive(NothingFrame(command: 0x4007, operation: outgoing.operation, payload: [1,2,60]), now: Double(tick + 10))
        }
        print("PASS: \(count) Nothing protocol/session assertions")
    }
}
