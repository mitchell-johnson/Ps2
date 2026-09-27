import Foundation

public enum MouseButton: Equatable {
    case left
    case right
}

/// Output of the gesture engine, independent of how events get injected.
public enum TrackpadAction: Equatable {
    /// Relative pointer movement in screen points (+y is down).
    case move(dx: Double, dy: Double)
    /// Scroll in pixels using scroll-wheel convention (+y scrolls up, +x scrolls left).
    case scroll(dx: Double, dy: Double)
    case buttonDown(MouseButton)
    case buttonUp(MouseButton)
    case click(MouseButton)
}

public struct TouchFrame: Equatable {
    public var touches: [TouchPoint]
    public var clicked: Bool
    /// Seconds, monotonic.
    public var timestamp: Double

    public init(touches: [TouchPoint], clicked: Bool, timestamp: Double) {
        self.touches = touches
        self.clicked = clicked
        self.timestamp = timestamp
    }
}

public struct TrackpadConfig: Equatable {
    /// Pointer multiplier; 1.0 moves ~0.6 points per touchpad unit at low speed.
    public var pointerSpeed = 1.0
    /// How much fast swipes are amplified. 0 disables acceleration.
    public var acceleration = 1.0
    /// Scroll multiplier; 1.0 scrolls ~0.5 pixels per touchpad unit.
    public var scrollSpeed = 1.0
    public var naturalScrolling = true
    public var tapToClick = true
    /// Clicking or tapping with two fingers produces a right click.
    public var twoFingerSecondaryClick = true
    public var momentumScrolling = true

    public var tapMaxDuration = 0.2
    /// Touchpad units a finger may travel and still count as a tap.
    public var tapMaxTravel = 40.0
    /// Seconds for momentum scrolling to decay to ~37% speed.
    public var momentumTimeConstant = 0.35

    public init() {}
}

/// Turns touchpad frames into pointer/scroll/click actions, emulating a Mac trackpad:
/// one finger moves, two fingers scroll, pressing the pad clicks (two fingers = right click),
/// quick taps click, and scrolling coasts after the fingers lift.
public final class TrackpadEngine {
    public var config: TrackpadConfig

    private enum Mode {
        case undecided
        case pointing
        case scrolling
    }

    private struct Session {
        var start: Double
        var maxFingers: Int
        var travel = 0.0
        var physicalClick = false
        var mode = Mode.undecided
    }

    private static let basePointerGain = 0.6
    private static let baseScrollGain = 0.5
    /// Touchpad units/second where acceleration starts, and the span over which it ramps.
    private static let accelerationStart = 300.0
    private static let accelerationSpan = 3000.0
    private static let maxAccelerationBoost = 2.0
    private static let minMomentumSpeed = 150.0
    private static let stopMomentumSpeed = 20.0
    private static let maxFrameInterval = 0.05

    private var previous: [UInt8: TouchPoint] = [:]
    private var lastTimestamp: Double?
    private var wasClicked = false
    private var heldButton: MouseButton?
    private var session: Session?
    private var scrollVelocity = (x: 0.0, y: 0.0)
    private var momentum: (x: Double, y: Double)?

    public init(config: TrackpadConfig = TrackpadConfig()) {
        self.config = config
    }

    public var isCoasting: Bool { momentum != nil }

    /// Clears all state, returning actions needed to leave the system consistent
    /// (i.e. releasing a held button).
    public func reset() -> [TrackpadAction] {
        let actions = heldButton.map { [TrackpadAction.buttonUp($0)] } ?? []
        previous = [:]
        lastTimestamp = nil
        wasClicked = false
        heldButton = nil
        session = nil
        scrollVelocity = (0, 0)
        momentum = nil
        return actions
    }

    public func process(_ frame: TouchFrame) -> [TrackpadAction] {
        var actions: [TrackpadAction] = []

        let dt = lastTimestamp.map { min(max(frame.timestamp - $0, 0), Self.maxFrameInterval) } ?? 0
        lastTimestamp = frame.timestamp

        let fingerCount = frame.touches.count
        if fingerCount > 0 {
            if session == nil {
                session = Session(start: frame.timestamp, maxFingers: fingerCount)
                momentum = nil
                scrollVelocity = (0, 0)
            }
            session!.maxFingers = max(session!.maxFingers, fingerCount)
        }

        // Movement of fingers that were also down in the previous frame.
        let deltas: [(x: Double, y: Double)] = frame.touches.compactMap { touch in
            previous[touch.id].map { (Double(touch.x - $0.x), Double(touch.y - $0.y)) }
        }
        if let largest = deltas.map(magnitude).max() {
            session?.travel += largest
        }

        // Physical click on the touchpad.
        if frame.clicked && !wasClicked {
            let button: MouseButton =
                config.twoFingerSecondaryClick && fingerCount >= 2 ? .right : .left
            heldButton = button
            session?.physicalClick = true
            momentum = nil
            actions.append(.buttonDown(button))
        } else if !frame.clicked && wasClicked, let button = heldButton {
            heldButton = nil
            actions.append(.buttonUp(button))
        }
        wasClicked = frame.clicked

        if heldButton != nil {
            // Dragging: follow whichever finger moved most, so one finger can hold the
            // click while another drags (like a Mac trackpad).
            if let delta = deltas.max(by: { magnitude($0) < magnitude($1) }) {
                appendMove(delta, dt: dt, to: &actions)
            }
        } else if fingerCount >= 2 {
            session?.mode = .scrolling
            if deltas.count >= 2 {
                let average = (
                    x: deltas.reduce(0) { $0 + $1.x } / Double(deltas.count),
                    y: deltas.reduce(0) { $0 + $1.y } / Double(deltas.count)
                )
                appendScroll(average, dt: dt, to: &actions)
            }
        } else if fingerCount == 1 {
            // After a two-finger scroll, a lingering finger shouldn't jerk the pointer.
            if session?.mode != .scrolling {
                session?.mode = .pointing
                if let delta = deltas.first {
                    appendMove(delta, dt: dt, to: &actions)
                }
            }
        } else {
            if let ended = session {
                finishSession(ended, at: frame.timestamp, actions: &actions)
                session = nil
            }
            coast(dt: dt, actions: &actions)
        }

        previous = Dictionary(frame.touches.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        return actions
    }

    // MARK: - Helpers

    private func appendMove(_ delta: (x: Double, y: Double), dt: Double, to actions: inout [TrackpadAction]) {
        guard delta.x != 0 || delta.y != 0 else { return }
        var gain = Self.basePointerGain * config.pointerSpeed
        if dt > 0, config.acceleration > 0 {
            let speed = magnitude(delta) / dt
            let ramp = (speed - Self.accelerationStart) / Self.accelerationSpan
            gain *= 1 + config.acceleration * min(max(ramp, 0), Self.maxAccelerationBoost)
        }
        actions.append(.move(dx: delta.x * gain, dy: delta.y * gain))
    }

    private func appendScroll(_ delta: (x: Double, y: Double), dt: Double, to actions: inout [TrackpadAction]) {
        // Natural scrolling: content follows the fingers. Fingers moving up (-y) means
        // content moves up, i.e. a negative wheel delta.
        let sign = config.naturalScrolling ? 1.0 : -1.0
        let gain = Self.baseScrollGain * config.scrollSpeed * sign
        let pixels = (x: delta.x * gain, y: delta.y * gain)

        if dt > 0 {
            // Smoothed velocity, used to seed momentum when the fingers lift.
            let blend = 0.4
            scrollVelocity.x += (pixels.x / dt - scrollVelocity.x) * blend
            scrollVelocity.y += (pixels.y / dt - scrollVelocity.y) * blend
        }
        if pixels.x != 0 || pixels.y != 0 {
            actions.append(.scroll(dx: pixels.x, dy: pixels.y))
        }
    }

    private func finishSession(_ ended: Session, at timestamp: Double, actions: inout [TrackpadAction]) {
        let isTap = config.tapToClick
            && !ended.physicalClick
            && timestamp - ended.start <= config.tapMaxDuration
            && ended.travel <= config.tapMaxTravel
        if isTap {
            let button: MouseButton =
                config.twoFingerSecondaryClick && ended.maxFingers >= 2 ? .right : .left
            actions.append(.click(button))
            return
        }

        if ended.mode == .scrolling, config.momentumScrolling,
           magnitude(scrollVelocity) >= Self.minMomentumSpeed {
            momentum = scrollVelocity
        }
        scrollVelocity = (0, 0)
    }

    private func coast(dt: Double, actions: inout [TrackpadAction]) {
        guard var velocity = momentum, dt > 0 else { return }
        let decay = exp(-dt / config.momentumTimeConstant)
        velocity.x *= decay
        velocity.y *= decay
        if magnitude(velocity) < Self.stopMomentumSpeed {
            momentum = nil
            return
        }
        momentum = velocity
        actions.append(.scroll(dx: velocity.x * dt, dy: velocity.y * dt))
    }
}

private func magnitude(_ v: (x: Double, y: Double)) -> Double {
    (v.x * v.x + v.y * v.y).squareRoot()
}
