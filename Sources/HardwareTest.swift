import Foundation

// Opt-in integration check against real earbuds; restores the original sound settings.
final class HardwareTest {
    let headphones: Headphones
    var timer: Timer?
    var original: SoundState?
    var expected: SoundState?
    var step = 0
    var elapsed = 0
    var failures = 0
    init(_ headphones: Headphones) { self.headphones = headphones }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }
    func tick() {
        elapsed += 1
        if elapsed > 60 {
            headphones.log("HARDWARE TEST TIMEOUT — restore original settings manually if disconnected")
            if let original { headphones.set(original.mode, level: original.level, voice: original.voice) }
            timer?.invalidate(); return
        }
        guard headphones.ready, !headphones.busy, let state = headphones.state else { return }
        if original == nil { original = state; headphones.log("HARDWARE TEST original: \(state)") }
        if let expected {
            if expected != state { failures += 1; headphones.log("HARDWARE FAIL expected \(expected), got \(state)") }
            else { headphones.log("HARDWARE PASS \(state)") }
            self.expected = nil
        }
        let mode: SoundMode
        let level: Int
        let voice: Bool
        switch step {
        case 0: mode = .cancelling; level = state.level; voice = false
        case 1: mode = .off; level = state.level; voice = false
        case 2: mode = .ambient; level = 10; voice = false
        case 3: mode = .ambient; level = 10; voice = true
        case 4: mode = original!.mode; level = original!.level; voice = original!.voice
        default:
            headphones.log("HARDWARE TEST COMPLETE failures=\(failures), original settings restored=\(state == original)")
            timer?.invalidate(); return
        }
        expected = SoundState(payload: [0x67] + mode.command(level: level, voice: voice).dropFirst())
        headphones.set(mode, level: level, voice: voice); step += 1
    }
}
