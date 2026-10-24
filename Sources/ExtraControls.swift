import Foundation

struct ControlChoice: Equatable {
    let value: Int
    let title: String
}
struct ExtraControl: Equatable {
    let id: String
    let title: String
    let choices: [ControlChoice]
    let selected: Int
}
struct SonyQuery: Hashable {
    var type: UInt8 = 12
    let payload: [UInt8]
    var reply: UInt8 { payload[0] + 1 }
}
struct SonyEdit {
    let query: SonyQuery
    let payload: [UInt8]
    let expected: [Int: UInt8]
    func matches(_ reply: [UInt8]) -> Bool {
        expected.allSatisfy { reply.indices.contains($0.key) && reply[$0.key] == $0.value }
    }
}

// A bounded reader for variable-length capability records.
struct ByteReader {
    let bytes: [UInt8]
    var index: Int = 0
    mutating func byte() -> UInt8? {
        guard index < bytes.count else { return nil }
        defer { index += 1 }; return bytes[index]
    }
    mutating func take(_ count: Int) -> [UInt8]? {
        guard count >= 0, count <= bytes.count - index else { return nil }
        defer { index += count }; return Array(bytes[index..<index + count])
    }
    mutating func string() -> String? {
        guard let count = byte(), let data = take(Int(count)) else { return nil }
        return String(bytes: data, encoding: .utf8)
    }
    var atEnd: Bool { index == bytes.count }
}

struct SonyExtras {
    enum Kind { case simple, power, equaliser, touch, general, voice }
    struct Feature {
        var name: String
        let kind: Kind
        let query: SonyQuery
        let capability: SonyQuery?
        var choices: [ControlChoice]
        var cap: [UInt8]?
        var raw: [UInt8]?
        var touchChoices: [[ControlChoice]] = []
        var touchNames: [String] = []
        var bands = 0
        var steps = 0
        var length = 3
    }
    private(set) var features: [Feature] = []
    static let onOff = [ControlChoice(value: 0, title: "On"), ControlChoice(value: 1, title: "Off")]
    static func options(_ pairs: [(Int, String)]) -> [ControlChoice] { pairs.map { ControlChoice(value: $0.0, title: $0.1) } }

    mutating func discover(functions: Set<UInt8>, type: UInt8 = 12) -> [SonyQuery] {
        func add(_ name: String, _ kind: Kind, _ get: UInt8, _ subtype: UInt8,
                 _ cap: UInt8? = nil, _ choices: [ControlChoice] = [], length: Int = 3) {
            guard !features.contains(where: { $0.query == SonyQuery(type: type, payload: [get, subtype]) }) else { return }
            let language: [UInt8] = kind == .equaliser || kind == .general ? [1] : []
            features.append(Feature(name: name, kind: kind,
                query: SonyQuery(type: type, payload: [get, subtype]),
                capability: cap.map { SonyQuery(type: type, payload: [$0, subtype] + language) },
                choices: choices, length: length))
        }
        if type == 12 {
            if functions.contains(0x50) || functions.contains(0x52) { add("Equaliser", .equaliser, 0x56, functions.contains(0x50) ? 0 : 2, 0x50) }
            if functions.contains(0xe2) { add("DSEE", .simple, 0xe6, 1, 0xe0, Self.options([(0,"Off"),(1,"Auto")])) }
            if functions.contains(0xe1) { add("Connection preference", .simple, 0xe6, 0, nil, Self.options([(0,"Sound quality"),(1,"Stable connection")])) }
            if functions.contains(0xf1) { add("Automatic pause", .simple, 0xf6, 1, nil, Self.onOff) }
            if functions.contains(0xfc) || functions.contains(0xf2) {
                add("Speak-to-Chat", .simple, 0xf6, functions.contains(0xfc) ? 0x0c : 2, nil, Self.onOff, length: 4)
            }
            if functions.contains(0x25) || functions.contains(0x24) {
                add("Automatic power off", .power, 0x26, functions.contains(0x25) ? 5 : 4, 0x20, length: 4)
            }
            if functions.contains(0xf3) || functions.contains(0xfe) {
                add("Touch controls", .touch, 0xf6, functions.contains(0xfe) ? 0x0e : 3, 0xf0)
            }
            for subtype: UInt8 in [0xd1,0xd2,0xd3,0xd4] where functions.contains(subtype) {
                add("Multipoint", .general, 0xd6, subtype, 0xd0, Self.onOff, length: 4)
            }
        } else {
            let voice: [(UInt8,UInt8)] = [(0x45,3),(0x44,2),(0x42,1),(0x41,1),(0x40,0)]
            if let pair = voice.first(where: { functions.contains($0.0) }) {
                add("Voice guidance", .voice, 0x46, pair.1, 0x40, Self.onOff, length: [1,2].contains(pair.1) ? 4 : 3)
            }
        }
        return features.filter { $0.query.type == type }.flatMap { feature in
            feature.capability.map { [$0, feature.query] } ?? [feature.query]
        }
    }

    var queries: [SonyQuery] { features.filter { $0.raw != nil }.map(\.query) }
    mutating func receive(_ p: [UInt8]?, for query: SonyQuery) {
        for i in features.indices {
            if features[i].capability == query {
                guard let p, p.count >= 2, p[0] == query.reply, p[1] == query.payload[1],
                      configure(&features[i], capability: p) else { features[i].cap = nil; features[i].raw = nil; continue }
                features[i].cap = p
            } else if features[i].query == query {
                features[i].raw = p.flatMap { validate($0, feature: features[i]) ? $0 : nil }
            }
        }
    }
    private func configure(_ f: inout Feature, capability p: [UInt8]) -> Bool {
        switch f.kind {
        case .power:
            guard p.count >= 3, p.count == 3 + Int(p[2]) else { return false }
            let names = [0:"After 5 minutes",1:"After 30 minutes",2:"After 60 minutes",3:"After 180 minutes",4:"After 15 minutes",16:"When removed",17:"Never"]
            f.choices = p.dropFirst(3).compactMap { n in names[Int(n)].map { ControlChoice(value: Int(n), title: $0) } }
            return !f.choices.isEmpty
        case .equaliser:
            guard p.count >= 5, p[2] > 0, p[2] <= 12, p[3] > 0, p[3] <= 127 else { return false }
            f.bands = Int(p[2]); f.steps = Int(p[3])
            var reader = ByteReader(bytes: Array(p.dropFirst(5)))
            var choices: [ControlChoice] = []
            for _ in 0..<Int(p[4]) {
                guard let id = reader.byte(), let name = reader.string() else { return false }
                let known = Self.eqNames[Int(id)]
                // Keep manufacturer preset names when no local label is defined.
                let title = known ?? name
                guard !title.isEmpty, !choices.contains(where: { $0.value == Int(id) }) else { return false }
                choices.append(ControlChoice(value: Int(id), title: title))
            }
            guard reader.atEnd, !choices.isEmpty else { return false }
            f.choices = choices; return true
        case .general:
            guard p.count >= 6, p[2] == 0 else { return false }
            var reader = ByteReader(bytes: Array(p.dropFirst(4)))
            guard let title = reader.string(), reader.string() != nil, reader.atEnd else { return false }
            // General slots differ between models. Never assume a slot is multipoint.
            return title == "MULTIPOINT_SETTING" || title.lowercased() == "connect to 2 devices simultaneously"
        case .voice:
            let subtype = f.query.payload[1]
            if subtype == 3 { return p.count == 2 }
            let switchIndex = subtype == 2 ? 2 : 6
            guard p.indices.contains(switchIndex), p[switchIndex] == 1 else { return false }
            if subtype == 0 { return p.count == 7 }
            let countIndex = switchIndex + 1
            return p.indices.contains(countIndex) && p.count == countIndex + 1 + Int(p[countIndex])
        case .touch:
            let start = f.query.payload[1] == 0x0e ? 3 : 2
            guard p.count > start, start != 3 || p[2] == 0 else { return false }
            var reader = ByteReader(bytes: Array(p.dropFirst(start)))
            guard let count = reader.byte(), count > 0, count <= 6 else { return false }
            var choices: [[ControlChoice]] = [], names: [String] = []
            for _ in 0..<count {
                guard let key = reader.byte(), let kind = reader.byte(), reader.byte() != nil,
                      let presets = reader.byte(), kind <= 1 else { return false }
                var available: [ControlChoice] = []
                for _ in 0..<presets {
                    guard let preset = reader.byte(), let fixed = reader.byte(), let custom = reader.byte(),
                          reader.take(Int(fixed) * 2) != nil else { return false }
                    for _ in 0..<custom {
                        guard reader.take(2) != nil, let count = reader.byte(), reader.take(Int(count)) != nil else { return false }
                    }
                    if let name = Self.touchNames[Int(preset)] { available.append(ControlChoice(value: Int(preset), title: name)) }
                }
                guard !available.isEmpty else { return false }
                choices.append(available); names.append([0:"Left touch control",1:"Right touch control",2:"Custom button",3:"C button",4:"Noise control button",5:"Ambient sound button"][Int(key)] ?? "Touch control")
            }
            guard reader.atEnd else { return false }
            f.touchChoices = choices; f.touchNames = names; return true
        case .simple:
            guard p.count == 3, p[2] <= 3 else { return false }
            f.name = ["DSEE HX","DSEE","DSEE Extreme","DSEE Ultimate"][Int(p[2])]
            return true
        }
    }
    private func validate(_ p: [UInt8], feature f: Feature) -> Bool {
        guard p.count >= 2, p[0] == f.query.reply, p[1] == f.query.payload[1],
              f.capability == nil || f.cap != nil else { return false }
        switch f.kind {
        case .equaliser:
            return p.count == 4 + f.bands && p[3] == f.bands && f.choices.contains { $0.value == p[2] } && p.dropFirst(4).allSatisfy { Int($0) < f.steps }
        case .touch:
            return p.count == 3 + f.touchChoices.count && p[2] == f.touchChoices.count &&
                f.touchChoices.enumerated().allSatisfy { index, choices in choices.contains { $0.value == p[index+3] } }
        case .general: return p.count == 4 && p[2] == 0 && p[3] <= 1
        default:
            guard p.count == f.length, f.choices.contains(where: { $0.value == p[2] }) else { return false }
            if f.name == "Speak-to-Chat" { return p[3] <= 1 }
            if f.kind == .power { return [UInt8(0),1,2,3,4,16,17].contains(p[3]) }
            return true
        }
    }
    var controls: [ExtraControl] {
        features.enumerated().flatMap { index, f -> [ExtraControl] in
            guard let p = f.raw else { return [] }
            let prefix = "sony.\(index)."
            if f.kind == .touch {
                return f.touchChoices.enumerated().map { i, choices in
                    ExtraControl(id: prefix + String(i+3), title: f.touchNames[i], choices: choices, selected: Int(p[i+3]))
                }
            }
            var result = [ExtraControl(id: prefix + (f.kind == .general ? "3" : "2"), title: f.name, choices: f.choices, selected: Int(p[f.kind == .general ? 3 : 2]))]
            if f.kind == .equaliser, f.bands == 6, f.steps == 21, f.choices.contains(where: { $0.value == 0xa0 }) {
                let labels = ["Clear Bass","400 Hz","1 kHz","2.5 kHz","6.3 kHz","16 kHz"]
                for i in 0..<6 {
                    result.append(ExtraControl(id: prefix + String(4+i), title: labels[i],
                        choices: (0...20).map { ControlChoice(value: $0, title: String($0-10)) }, selected: Int(p[4+i])))
                }
            }
            return result
        }
    }
    func edit(id: String, value: Int) -> SonyEdit? {
        guard let control = controls.first(where: { $0.id == id }), control.choices.contains(where: { $0.value == value }) else { return nil }
        let parts = id.split(separator: ".")
        guard parts.count == 3, let index = Int(parts[1]), let offset = Int(parts[2]), features.indices.contains(index),
              var p = features[index].raw else { return nil }
        let f = features[index]; p[0] = f.query.payload[0] + 2
        p[offset] = UInt8(value)
        var expected = [offset: UInt8(value)]
        if f.kind == .equaliser {
            if offset >= 4 { p[2] = 0xa0; expected[2] = 0xa0 }
            else { p = [p[0],p[1],UInt8(value),0] }
        }
        if f.name == "Speak-to-Chat" { p[3] = 1 } // Never start preview mode.
        if f.kind == .power, value <= 4 { p[3] = UInt8(value) }
        return SonyEdit(query: f.query, payload: p, expected: expected)
    }
    static let eqNames = [0:"Off",1:"Rock",2:"Pop",3:"Jazz",4:"Dance",5:"EDM",6:"R&B and hip-hop",7:"Acoustic",16:"Bright",17:"Excited",18:"Mellow",19:"Relaxed",20:"Vocal",21:"Treble boost",22:"Bass boost",23:"Speech",0xa0:"Manual",0xa1:"Custom 1",0xa2:"Custom 2",0xa3:"Custom 3",0xa4:"Custom 4",0xa5:"Custom 5",0x20:"Gaming",0x21:"FPS 1",0x22:"FPS 2",0x23:"FPS 3",0x30:"Heavy",0x31:"Clear",0x32:"Hard",0x33:"Soft"]
    static let touchNames = [0:"Ambient sound",0x10:"Volume",0x20:"Playback",0x21:"Tracks",0x22:"Playback",0x30:"Voice assistant",0x31:"Google Assistant",0x32:"Amazon Alexa",0x35:"Ambient sound and Quick Access",0x36:"Quick Access",0x42:"Quick Access",0x43:"Ambient sound and Quick Access",0xff:"None"]
}
