#if canImport(CoreGraphics) && canImport(AppKit)
import AppKit
import CoreGraphics
import DualSenseCore

/// Posts synthetic mouse and scroll events into the macOS event stream.
final class EventInjector {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var position: CGPoint?
    private var heldButton: MouseButton?
    private var scrollRemainder = (x: 0.0, y: 0.0)

    private var lastClick: (time: TimeInterval, point: CGPoint, button: MouseButton)?
    private var clickCount = 1

    func perform(_ action: TrackpadAction) {
        switch action {
        case let .move(dx, dy):
            move(dx: dx, dy: dy)
        case let .scroll(dx, dy):
            scroll(dx: dx, dy: dy)
        case let .buttonDown(button):
            press(button)
        case let .buttonUp(button):
            release(button)
        case let .click(button):
            press(button)
            release(button)
        }
    }

    // MARK: - Pointer

    private func move(dx: Double, dy: Double) {
        let current = currentPosition()
        let target = clampToScreens(CGPoint(x: current.x + dx, y: current.y + dy), from: current)
        position = target

        let type: CGEventType
        let cgButton: CGMouseButton
        switch heldButton {
        case .left?: (type, cgButton) = (.leftMouseDragged, .left)
        case .right?: (type, cgButton) = (.rightMouseDragged, .right)
        case nil: (type, cgButton) = (.mouseMoved, .left)
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: target, mouseButton: cgButton) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        if heldButton != nil {
            event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        }
        event.post(tap: .cghidEventTap)
    }

    private func press(_ button: MouseButton) {
        let point = currentPosition()
        let now = ProcessInfo.processInfo.systemUptime

        // Multi-click detection so double/triple clicks work.
        if let last = lastClick, last.button == button,
           now - last.time <= NSEvent.doubleClickInterval,
           hypot(point.x - last.point.x, point.y - last.point.y) <= 5 {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClick = (now, point, button)
        heldButton = button

        postButton(button, down: true, at: point)
    }

    private func release(_ button: MouseButton) {
        heldButton = nil
        postButton(button, down: false, at: currentPosition())
    }

    private func postButton(_ button: MouseButton, down: Bool, at point: CGPoint) {
        let type: CGEventType
        let cgButton: CGMouseButton
        switch button {
        case .left: (type, cgButton) = (down ? .leftMouseDown : .leftMouseUp, .left)
        case .right: (type, cgButton) = (down ? .rightMouseDown : .rightMouseUp, .right)
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: cgButton) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Scrolling

    private func scroll(dx: Double, dy: Double) {
        // Scroll events carry whole pixels; keep the fractional part for next time.
        scrollRemainder.x += dx
        scrollRemainder.y += dy
        let wholeX = scrollRemainder.x.rounded(.towardZero)
        let wholeY = scrollRemainder.y.rounded(.towardZero)
        guard wholeX != 0 || wholeY != 0 else { return }
        scrollRemainder.x -= wholeX
        scrollRemainder.y -= wholeY

        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(wholeY), wheel2: Int32(wholeX), wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Screen geometry

    /// Tracks the pointer with sub-point precision, resyncing if another device moved it.
    private func currentPosition() -> CGPoint {
        let actual = CGEvent(source: nil)?.location ?? .zero
        if let position, abs(position.x - actual.x) < 2, abs(position.y - actual.y) < 2 {
            return position
        }
        position = actual
        return actual
    }

    private func clampToScreens(_ point: CGPoint, from origin: CGPoint) -> CGPoint {
        let displays = activeDisplayBounds()
        if displays.contains(where: { $0.contains(point) }) {
            return point
        }
        // Off every screen: clamp inside the display the pointer is currently on.
        guard let bounds = displays.first(where: { $0.contains(origin) }) ?? displays.first else {
            return point
        }
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX - 1),
            y: min(max(point.y, bounds.minY), bounds.maxY - 1)
        )
    }

    private func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }
}
#endif
