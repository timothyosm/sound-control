import Foundation

// Explicit opt-in. Keep restoration data in SQLite in case the app is interrupted.
final class ExtraHardwareTest {
    struct Restore: Codable {
        let address: String
        let title: String
        let value: Int
    }
    let headphones: Headphones
    let store: SettingsStore
    var timer: Timer?
    var plan: [(String, Int, Int)] = []
    var original: Restore?
    var target: Int?
    var restoring = false
    var started = Date()
    var initialised = false
    var testAddress: String?
    var failures = 0
    init(_ headphones: Headphones, store: SettingsStore) {
        self.headphones = headphones; self.store = store
    }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }
    func stop(_ message: String) {
        headphones.log(message); timer?.invalidate(); timer = nil
    }
    func tick() {
        if Date().timeIntervalSince(started) > 150 {
            stop("EXTRA TEST TIMEOUT: restoration record retained; reconnect and rerun --extra-hardware-test")
            return
        }
        guard headphones.ready, !headphones.busy else { return }
        guard !headphones.isNothing, let address = headphones.activeAddress else {
            stop("EXTRA TEST SKIPPED: this hardware test covers Sony only"); return
        }
        if let testAddress, testAddress != address {
            stop("EXTRA TEST STOPPED: the connected device changed"); return
        }
        testAddress = address
        do {
            if !initialised {
                initialised = true
                if let saved = try store.string(forKey: "hardware-test.restore"),
                   let data = saved.data(using: .utf8) {
                    original = try JSONDecoder().decode(Restore.self, from: data)
                    guard original?.address == address else {
                        stop("EXTRA TEST STOPPED: connect the device with pending restoration"); return
                    }
                    restoring = true; target = original!.value
                    guard let control = headphones.extraControls.first(where: { $0.title == original!.title }) else {
                        stop("EXTRA TEST STOPPED: restoration control is unavailable"); return
                    }
                    headphones.setExtra(id: control.id, value: original!.value)
                    return
                }
                let toggle = ["DSEE Extreme","DSEE","Speak-to-Chat","Automatic pause","Voice guidance"]
                let sameValue = ["Equaliser","Automatic power off","Multipoint","Left touch control","Right touch control","Connection preference"]
                for control in headphones.extraControls {
                    if toggle.contains(control.title), let alternative = control.choices.first(where: { $0.value != control.selected }) {
                        plan.append((control.title, alternative.value, control.selected))
                    } else if sameValue.contains(control.title) {
                        plan.append((control.title, control.selected, control.selected))
                    }
                }
                headphones.log("EXTRA TEST: \(plan.count) controls; connection, touch, power and EQ checks write the current value")
            }
            if let original, let target {
                let actual = headphones.extraControls.first { $0.title == original.title }?.selected
                let passed = actual == target && headphones.status == "Setting applied"
                if !passed { failures += 1 }
                headphones.log("EXTRA \(passed ? "PASS" : "FAIL"): \(original.title), expected=\(target), actual=\(String(describing: actual)), restoring=\(restoring)")
                if !restoring {
                    restoring = true; self.target = original.value
                    guard let control = headphones.extraControls.first(where: { $0.title == original.title }) else {
                        stop("EXTRA TEST STOPPED: restoration control is unavailable"); return
                    }
                    headphones.setExtra(id: control.id, value: original.value)
                    return
                }
                guard passed else {
                    stop("EXTRA TEST STOPPED: restoration was not confirmed; record retained"); return
                }
                try store.set(nil, forKey: "hardware-test.restore")
                self.original = nil; self.target = nil; restoring = false
            }
            guard !plan.isEmpty else {
                stop("EXTRA TEST COMPLETE failures=\(failures); original settings restored")
                return
            }
            let next = plan.removeFirst()
            guard let control = headphones.extraControls.first(where: { $0.title == next.0 }) else {
                failures += 1; return
            }
            let restore = Restore(address: address, title: next.0, value: next.2)
            try store.set(String(data: JSONEncoder().encode(restore), encoding: .utf8)!, forKey: "hardware-test.restore")
            original = restore; target = next.1
            headphones.setExtra(id: control.id, value: next.1)
        } catch {
            stop("EXTRA TEST STOPPED: could not save restoration data")
        }
    }
}
