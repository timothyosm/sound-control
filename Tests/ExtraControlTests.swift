import Foundation

@main struct ExtraControlTests {
    struct Fixture: Decodable { let type: UInt8; let payload: [UInt8] }
    static func main() throws {
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        check(SonyGeneration.v2.supportsSecondTable([1,0,3,0,0x20,0x15,0,0]), "Second table advertised")
        check(!SonyGeneration.v2.supportsSecondTable([1,0,3,0,0x20,0x15,0,1]), "No unsupported second-table query")
        check(!SonyGeneration.v1.supportsSecondTable([1,0,1,0]), "No V2 tables on V1")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/linkbuds-s-4.3.1-extras.json")))
        var sony = SonyExtras()
        var queries: [SonyQuery] = []
        for f in fixtures where f.payload.first == 7 {
            let caps = SonyCapabilities(generation: .v2, payload: f.payload)!
            queries += sony.discover(functions: caps.functions, type: f.type)
        }
        for f in fixtures where f.payload.first != 7 {
            if let query = queries.first(where: { $0.type == f.type && $0.reply == f.payload[0] && $0.payload[1] == f.payload[1] }) {
                sony.receive(f.payload, for: query)
            }
        }
        let expected = ["Equaliser","Clear Bass","Speak-to-Chat","Automatic pause","Automatic power off","Multipoint","Left touch control","Right touch control","Voice guidance","DSEE Extreme","Connection preference"]
        for title in expected { check(sony.controls.contains { $0.title == title }, "Live capture enables \(title)") }
        for control in sony.controls {
            check(sony.edit(id: control.id, value: -999) == nil, "Invalid choice rejected")
            for choice in control.choices {
                guard let edit = sony.edit(id: control.id, value: choice.value) else { preconditionFailure(control.title) }
                var reply = edit.payload; reply[0] = edit.query.reply
                check(edit.matches(reply), "Read-back matches requested value")
                check(!edit.matches([]), "Truncated read-back rejected")
                var wrong = reply
                let offset = edit.expected.keys.sorted().first!
                wrong[offset] ^= 1
                check(!edit.matches(wrong), "Wrong read-back rejected")
                if control.title.contains("touch control") {
                    let original = sony.features.first { $0.query == edit.query }!.raw!
                    let untouched = offset == 3 ? 4 : 3
                    check(edit.payload[untouched] == original[untouched], "Other earbud assignment preserved")
                }
                if control.title == "Voice guidance" {
                    check(edit.query.type == 14 && edit.payload[3] == 1, "Voice guidance preserves language on second transport type")
                }
            }
        }
        let bass = sony.controls.first { $0.title == "Clear Bass" }!
        let bassEdit = sony.edit(id: bass.id, value: 12)!
        check(bassEdit.payload == [0x58,0,0xa0,6,12,10,10,10,10,10], "Clear Bass preserves five EQ bands")
        let power = sony.controls.first { $0.title == "Automatic power off" }!
        check(sony.edit(id: power.id, value: 17)!.payload == [0x28,5,17,0], "Power-off disable preserves last timer")
        check(sony.edit(id: power.id, value: 16)!.payload == [0x28,5,16,0], "Wear detection preserves the last timer")
        // Every truncated capability must leave its dependent controls unavailable.
        for f in fixtures {
            guard let query = queries.first(where: { $0.type == f.type && $0.reply == f.payload[0] && $0.payload[1] == f.payload[1] }) else { continue }
            for length in 0..<f.payload.count {
                var broken = sony
                broken.receive(Array(f.payload.prefix(length)), for: query)
                check(!broken.features.contains { $0.query == query && $0.raw != nil }, "Truncated settings rejected")
                if broken.features.contains(where: { $0.capability == query }) {
                    check(broken.features.first { $0.capability == query }!.cap == nil, "Truncated capabilities rejected")
                }
            }
        }
        var nothing = NothingExtras()
        let samples: [(UInt16,[UInt8])] = [(0xc00e,[1,1,1]),(0xc041,[2]),(0xc027,[0]),(0xc01f,[0]),(0xc050,[3]),(0xc04e,[1,6]),(0xc020,[0]),(0xc04c,[0]),(0xc01e,[1,1,0])]
        for (command,payload) in samples { check(nothing.receive(command,payload:payload), "Valid Nothing reply") }
        for control in nothing.controls {
            for choice in control.choices {
                let edit = nothing.edit(id: control.id, value: choice.value)!
                check(edit.matches(edit.payload), "Nothing read-back expected bytes")
                check(!edit.matches([]), "Nothing truncated verification rejected")
                check(!edit.matches(Array(repeating: 255, count: edit.payload.count)), "Nothing mismatch rejected")
            }
        }
        let enhanced = nothing.controls.first { $0.title == "Bass enhancement" }!
        check(nothing.edit(id: enhanced.id, value: 0)!.payload == [0,6], "Nothing bass strength preserved")
        let advanced = nothing.controls.first { $0.title == "Advanced equaliser" }!
        check(nothing.edit(id: advanced.id, value: 1)!.payload == [1,0], "Advanced EQ trailing byte")
        _ = nothing.receive(0xc04c,payload:[1])
        check(!nothing.controls.contains { $0.title == "Equaliser" }, "Advanced EQ hides inactive basic presets")
        _ = nothing.receive(0xc00e,payload:[1,1,3])
        check(!nothing.controls.contains { $0.title == "Automatic pause" }, "Malformed replies revoke controls")

        var session = NothingSession(probeSound: false)
        let first = session.start(now:0)[0]
        _ = session.receive(NothingFrame(command:0x4007,operation:first.operation,payload:[1,2,70]),now:0.1)
        var requests = session.loadExtras(now:0.2)
        var time = 1.0
        while let request = requests.first {
            let sample = samples.first { $0.0 == request.command }!.1
            requests = session.receive(NothingFrame(command:request.command & 0x7fff,operation:request.operation,payload:sample),now:time)
            time += 1
        }
        let toggle = session.extras.controls.first { $0.title == "Automatic pause" }!
        let write = session.setExtra(id:toggle.id,value:0,now:20)[0]
        check(write.command == 0xf004 && write.payload == [1,1,0], "Nothing write encoding")
        check(session.setExtra(id:toggle.id,value:1,now:20.1).isEmpty, "Writes serialised")
        let read = session.tick(now:20.3)[0]
        _ = session.receive(NothingFrame(command:0x400e,operation:read.operation &+ 1,payload:[1,1,0]),now:20.4)
        check(session.busy, "Stale operation cannot verify write")
        _ = session.receive(NothingFrame(command:0x400e,operation:read.operation,payload:[1,1,0]),now:20.5)
        check(!session.busy && session.status == "Setting applied", "Matched read confirms write")
        _ = session.setExtra(id:toggle.id,value:1,now:21)
        let mismatch = session.tick(now:21.3)[0]
        _ = session.receive(NothingFrame(command:0x400e,operation:mismatch.operation,payload:[1,1,0]),now:21.4)
        check(session.status == "Setting did not apply – try again", "Rejected setting reported")
        _ = session.setExtra(id:toggle.id,value:1,now:22)
        _ = session.tick(now:22.3)
        _ = session.tick(now:27)
        check(!session.extras.controls.contains { $0.id == toggle.id }, "Timeout clears stale writable state")
        print("PASS: \(count) extra control assertions")
    }
}
