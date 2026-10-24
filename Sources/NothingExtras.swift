import Foundation

struct NothingEdit {
    let read: UInt16
    let write: UInt16
    let payload: [UInt8]
    let expected: [Int: UInt8]
    func matches(_ reply: [UInt8]) -> Bool {
        expected.allSatisfy { reply.indices.contains($0.key) && reply[$0.key] == $0.value }
    }
}
struct NothingExtras: Equatable {
    // Read-only probes. A missing or malformed reply never enables a write.
    static let probes: [UInt16] = [0xc00e,0xc041,0xc027,0xc01f,0xc050,0xc04e,0xc020,0xc04c]
    private var deviceTuningPreset: UInt8?
    private(set) var values: [UInt16: [UInt8]] = [:]
    mutating func receive(_ command: UInt16, payload p: [UInt8]?) -> Bool {
        guard let p, Self.valid(command, p) else { values[command] = nil; return false }
        if command == 0xc050, [UInt8(0),7].contains(p[0]) { deviceTuningPreset = p[0] }
        values[command] = p; return true
    }
    static func valid(_ command: UInt16, _ p: [UInt8]) -> Bool {
        switch command {
        case 0xc01e: return p.count >= 3 && p[0] == 1 && [1,2,3,4,5,7].contains(p[1]) && p[2] == 0
        case 0xc00e: return p.count == 3 && p[0] == 1 && p[1] == 1 && p[2] <= 1
        case 0xc041: return (p.count == 1 || (p.count == 2 && p[1] == 0)) && [1,2].contains(p[0])
        case 0xc04c: return (p.count == 1 || (p.count == 2 && p[1] == 0)) && p[0] <= 1
        case 0xc027,0xc020: return p.count == 1 && p[0] <= 1
        case 0xc01f: return (p.count == 1 || (p.count == 2 && p[1] == 0)) && [0,1,2,3,5,6].contains(p[0])
        case 0xc050: return (p.count == 1 || (p.count == 2 && p[1] == 0)) && [0,1,2,3,4,5,6,7].contains(p[0])
        case 0xc04e: return p.count == 2 && p[0] <= 1 && p[1] <= 10
        default: return false
        }
    }
    var controls: [ExtraControl] {
        var controls: [ExtraControl] = []
        func add(_ read: UInt16, _ title: String, _ options: [(Int,String)], offset: Int = 0) {
            guard let p = values[read] else { return }
            controls.append(ExtraControl(id: "nothing.\(read).\(offset)", title: title,
                choices: SonyExtras.options(options), selected: Int(p[offset])))
        }
        add(0xc01e,"Noise cancelling strength",[(1,"High"),(2,"Medium"),(3,"Low"),(4,"Adaptive")], offset: 1)
        add(0xc00e,"Automatic pause",[(0,"Off"),(1,"On")], offset: 2)
        add(0xc041,"Low-lag mode",[(2,"Off"),(1,"On")])
        add(0xc027,"Dual connection",[(0,"Off"),(1,"On")])
        add(0xc04c,"Advanced equaliser",[(0,"Off"),(1,"On")])
        // Advanced EQ takes priority on some models. Do not claim that a basic
        // preset is audible while advanced EQ remains active.
        if values[0xc04c]?.first != 1 {
            add(0xc01f,"Equaliser",[(0,"Balanced"),(1,"Voice"),(2,"Treble"),(3,"Bass"),(5,"Custom")])
            // CMF listening-mode values differ: expose known common presets only.
            if values[0xc01f] == nil {
                add(0xc050,"Equaliser", (deviceTuningPreset.map { [(Int($0), "Device tuning")] } ?? []) + [(1,"Rock"),(2,"Electronic"),(3,"Pop"),(4,"Voice"),(5,"Classical"),(6,"Custom")])
            }
        }
        add(0xc04e,"Bass enhancement",[(0,"Off"),(1,"On")])
        // Keep the reported strength: newer models have different level scales.
        add(0xc020,"Personalised noise cancelling",[(0,"Off"),(1,"On")])
        return controls
    }
    func edit(id: String, value: Int) -> NothingEdit? {
        guard let control = controls.first(where: { $0.id == id }), control.choices.contains(where: { $0.value == value }) else { return nil }
        let parts = id.split(separator: ".")
        guard parts.count == 3, let read = UInt16(parts[1]), let offset = Int(parts[2]), let raw = values[read] else { return nil }
        let writes: [UInt16: UInt16] = [0xc01e:0xf00f,0xc00e:0xf004,0xc041:0xf040,0xc027:0xf01a,0xc01f:0xf010,0xc050:0xf01d,0xc04e:0xf051,0xc020:0xf011,0xc04c:0xf04f]
        guard let write = writes[read] else { return nil }
        var p = raw; p[offset] = UInt8(value)
        if [UInt16(0xc041),0xc01f,0xc050,0xc04c].contains(read) { p = [UInt8(value),0] }
        if read == 0xc01e { p = [1, UInt8(value), 0] }
        return NothingEdit(read: read, write: write, payload: p, expected: [offset: UInt8(value)])
    }
}
