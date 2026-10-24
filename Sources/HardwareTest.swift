import Foundation

// Explicitly opt-in: exercise only advertised controls, then restore the original state.
final class HardwareTest {
    let headphones: Headphones
    var timer: Timer?
    var original: SoundState?
    var expected: SoundState?
    var plan: [SoundState] = []
    var started = Date()
    var failures = 0
    init(_ headphones: Headphones) { self.headphones = headphones }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }
    func tick() {
        if headphones.isNothing {
            headphones.log("HARDWARE TEST SKIPPED: automated hardware checks currently cover Sony only")
            timer?.invalidate(); return
        }
        if Date().timeIntervalSince(started) > 60 {
            headphones.log("HARDWARE TEST TIMEOUT — restore original settings manually if disconnected")
            if let original { headphones.set(original.mode, level: original.level, voice: original.voice) }
            timer?.invalidate(); return
        }
        guard headphones.ready, !headphones.busy, let state = headphones.state, let control = headphones.control else { return }
        if original == nil {
            original = state; headphones.log("HARDWARE TEST original: \(state)")
            for mode in control.modes {
                let level = control.levels[false].flatMap { $0.isEmpty ? nil : $0[$0.count / 2] } ?? 1
                plan.append(SoundState(mode: mode, level: level, voice: false))
            }
            if let levels = control.levels[true], let level = levels.first {
                plan.append(SoundState(mode: .ambient, level: level, voice: true))
            }
            plan.append(state)
        }
        if let expected {
            if !state.matches(expected) { failures += 1; headphones.log("HARDWARE FAIL expected \(expected), got \(state)") }
            else { headphones.log("HARDWARE PASS \(state)") }
            self.expected = nil
        }
        guard !plan.isEmpty else {
            headphones.log("HARDWARE TEST COMPLETE failures=\(failures), original settings restored=\(original.map { state.matches($0) } == true)")
            timer?.invalidate(); return
        }
        let target = plan.removeFirst()
        guard let command = control.command(target.mode, level: target.level, voice: target.voice), let expectation = control.decode(command) else {
            failures += 1; headphones.log("HARDWARE FAIL cannot encode \(target)"); return
        }
        expected = expectation
        headphones.set(target.mode, level: target.level, voice: target.voice)
    }
}
