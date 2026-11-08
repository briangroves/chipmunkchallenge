import CoreHaptics
import UIKit

/// The game's taps and pickup clicks, played through Core Haptics.
///
/// They used to go through UIImpactFeedbackGenerator, and on fast-forward with lots of chipmunks out the clicks would
/// stop for the rest of the game, even with them capped at 10 a second: iOS can quietly drop an app's feedback
/// generators, and nothing tells the app. A Core Haptics engine reports when it stops or resets, so this restarts it
/// and keeps going. Clicks are also spaced out (pickups at most 10 a second, every click at least 30 ms apart), and
/// fall back to UIKit on a phone without a haptic engine.
@MainActor
final class Haptics {
    private var engine: CHHapticEngine?
    private var running = false
    private var lastAny: CFTimeInterval = 0
    private var lastPickup: CFTimeInterval = 0
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)

    init() {
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics, let e = try? CHHapticEngine() {
            e.playsHapticsOnly = true
            e.isAutoShutdownEnabled = false
            e.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.running = false }
            }
            e.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.running = false
                    self?.start()
                }
            }
            engine = e
            start()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        }
    }

    private func start() {
        guard let engine, !running else { return }
        do {
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    /// Get ready to play (a new board, or back in the app).
    func wake() {
        start()
        light.prepare()
        medium.prepare()
    }

    /// The light tap: loading a nest, small confirmations.
    func tap() { click(intensity: 0.55, sharpness: 0.5, fallback: light) }

    /// A chipmunk picks up its block: one step heavier, at most 10 a second.
    func pickup() {
        let now = CACurrentMediaTime()
        guard now - lastPickup >= 0.1 else { return }
        if click(intensity: 1, sharpness: 0.55, fallback: medium) { lastPickup = now }
    }

    @discardableResult
    private func click(intensity: Float, sharpness: Float, fallback: UIImpactFeedbackGenerator) -> Bool {
        let now = CACurrentMediaTime()
        guard now - lastAny >= 0.03 else { return false }
        lastAny = now
        guard let engine else {
            fallback.impactOccurred(intensity: CGFloat(intensity))
            fallback.prepare()
            return true
        }
        if !running { start() }
        do {
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: 0)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // The engine stopped without saying so: start it again for the next click, and use UIKit for this one.
            running = false
            start()
            fallback.impactOccurred(intensity: CGFloat(intensity))
        }
        return true
    }
}
