@testable import DualSenseCore
import XCTest

final class TrackpadEngineTests: XCTestCase {
    private let dt = 0.004 // 250 Hz, the DualSense report rate

    private var engine: TrackpadEngine!
    private var time = 0.0

    override func setUp() {
        var config = TrackpadConfig()
        config.acceleration = 0
        engine = TrackpadEngine(config: config)
        time = 0
    }

    @discardableResult
    private func frame(_ touches: [TouchPoint], clicked: Bool = false) -> [TrackpadAction] {
        time += dt
        return engine.process(TouchFrame(touches: touches, clicked: clicked, timestamp: time))
    }

    private func finger(_ x: Int, _ y: Int, id: UInt8 = 1) -> TouchPoint {
        TouchPoint(id: id, x: x, y: y)
    }

    private func moves(_ actions: [TrackpadAction]) -> [(Double, Double)] {
        actions.compactMap { if case let .move(dx, dy) = $0 { return (dx, dy) } else { return nil } }
    }

    private func scrolls(_ actions: [TrackpadAction]) -> [(Double, Double)] {
        actions.compactMap { if case let .scroll(dx, dy) = $0 { return (dx, dy) } else { return nil } }
    }

    func testOneFingerMovesPointer() {
        XCTAssertEqual(frame([finger(100, 100)]), [])
        let actions = frame([finger(110, 95)])
        XCTAssertEqual(actions, [.move(dx: 6, dy: -3)])
    }

    func testNewFingerIDDoesNotJump() {
        frame([finger(100, 100, id: 1)])
        frame([])
        time += 1
        XCTAssertEqual(frame([finger(1500, 900, id: 2)]), [])
    }

    func testAccelerationAmplifiesFastSwipes() {
        engine.config.acceleration = 1
        frame([finger(0, 0)])
        let slow = moves(frame([finger(1, 0)]))[0].0
        let fast = moves(frame([finger(41, 0)]))[0].0
        XCTAssertEqual(slow, 0.6, accuracy: 1e-9)
        XCTAssertGreaterThan(fast / 40, slow * 2)
    }

    func testTapClicks() {
        frame([finger(500, 500)])
        frame([finger(502, 501)])
        XCTAssertEqual(frame([]), [.click(.left)])
    }

    func testTwoFingerTapRightClicks() {
        frame([finger(500, 500, id: 1), finger(900, 500, id: 2)])
        XCTAssertEqual(frame([]), [.click(.right)])
    }

    func testLongTouchIsNotATap() {
        frame([finger(500, 500)])
        time += 0.5
        frame([finger(500, 500)])
        XCTAssertEqual(frame([]), [])
    }

    func testMovingTouchIsNotATap() {
        frame([finger(500, 500)])
        frame([finger(600, 500)])
        XCTAssertEqual(frame([]).filter { if case .click = $0 { return true } else { return false } }, [])
    }

    func testTapToClickCanBeDisabled() {
        engine.config.tapToClick = false
        frame([finger(500, 500)])
        XCTAssertEqual(frame([]), [])
    }

    func testPhysicalClickAndDrag() {
        frame([finger(500, 500)])
        XCTAssertEqual(frame([finger(500, 500)], clicked: true), [.buttonDown(.left)])
        XCTAssertEqual(frame([finger(520, 500)], clicked: true), [.move(dx: 12, dy: 0)])
        XCTAssertEqual(frame([finger(520, 500)], clicked: false), [.buttonUp(.left)])
        // A physical click is never also reported as a tap.
        XCTAssertEqual(frame([]), [])
    }

    func testDragEndsAtFinalFingerPosition() {
        frame([finger(500, 500)])
        frame([finger(500, 500)], clicked: true)
        XCTAssertEqual(frame([finger(510, 500)], clicked: false), [.move(dx: 6, dy: 0), .buttonUp(.left)])
    }

    func testDragWithSecondFingerWhileThumbHoldsClick() {
        frame([finger(200, 900, id: 1)])
        frame([finger(200, 900, id: 1)], clicked: true)
        frame([finger(200, 900, id: 1), finger(1000, 300, id: 2)], clicked: true)
        let actions = frame([finger(201, 900, id: 1), finger(1050, 300, id: 2)], clicked: true)
        XCTAssertEqual(actions, [.move(dx: 30, dy: 0)])
    }

    func testTwoFingerClickIsRightClick() {
        let fingers = [finger(500, 500, id: 1), finger(800, 500, id: 2)]
        frame(fingers)
        XCTAssertEqual(frame(fingers, clicked: true), [.buttonDown(.right)])
        XCTAssertEqual(frame(fingers), [.buttonUp(.right)])
    }

    func testSecondaryClickCanBeDisabled() {
        engine.config.twoFingerSecondaryClick = false
        let fingers = [finger(500, 500, id: 1), finger(800, 500, id: 2)]
        frame(fingers)
        XCTAssertEqual(frame(fingers, clicked: true), [.buttonDown(.left)])
    }

    func testTwoFingersScrollNaturally() {
        frame([finger(500, 500, id: 1), finger(800, 500, id: 2)])
        // Fingers move up: content follows, so the wheel scrolls down (negative).
        let actions = frame([finger(500, 480, id: 1), finger(800, 480, id: 2)])
        XCTAssertEqual(actions, [.scroll(dx: 0, dy: -10)])
    }

    func testTraditionalScrollDirection() {
        engine.config.naturalScrolling = false
        frame([finger(500, 500, id: 1), finger(800, 500, id: 2)])
        let actions = frame([finger(520, 480, id: 1), finger(820, 480, id: 2)])
        XCTAssertEqual(actions, [.scroll(dx: -10, dy: 10)])
    }

    func testLiftingOneFingerAfterScrollDoesNotMovePointer() {
        frame([finger(500, 500, id: 1), finger(800, 500, id: 2)])
        frame([finger(500, 400, id: 1), finger(800, 400, id: 2)])
        frame([finger(500, 400, id: 1)])
        XCTAssertEqual(frame([finger(500, 300, id: 1)]), [])
    }

    func testMomentumScrollingCoastsAndStops() {
        var y = 800
        frame([finger(500, y, id: 1), finger(800, y, id: 2)])
        for _ in 0..<20 {
            y -= 20
            frame([finger(500, y, id: 1), finger(800, y, id: 2)])
        }
        let lift = frame([])
        XCTAssertTrue(engine.isCoasting)
        XCTAssertEqual(scrolls(lift).count, 1)
        XCTAssertLessThan(scrolls(lift)[0].1, 0)

        var previous = abs(scrolls(lift)[0].1)
        var coastFrames = 0
        while engine.isCoasting && coastFrames < 10_000 {
            if let step = scrolls(frame([])).first {
                XCTAssertLessThan(abs(step.1), previous)
                previous = abs(step.1)
            }
            coastFrames += 1
        }
        XCTAssertFalse(engine.isCoasting)
        XCTAssertGreaterThan(coastFrames, 50)
    }

    func testTouchStopsMomentum() {
        frame([finger(500, 800, id: 1), finger(800, 800, id: 2)])
        for step in 1...10 {
            frame([finger(500, 800 - step * 20, id: 1), finger(800, 800 - step * 20, id: 2)])
        }
        frame([])
        XCTAssertTrue(engine.isCoasting)
        frame([finger(500, 500)])
        XCTAssertFalse(engine.isCoasting)
    }

    func testNoMomentumAfterFingersPause() {
        frame([finger(500, 800, id: 1), finger(800, 800, id: 2)])
        for step in 1...10 {
            frame([finger(500, 800 - step * 20, id: 1), finger(800, 800 - step * 20, id: 2)])
        }
        for _ in 0..<50 {
            frame([finger(500, 600, id: 1), finger(800, 600, id: 2)])
        }
        frame([])
        XCTAssertFalse(engine.isCoasting)
    }

    func testMomentumCanBeDisabled() {
        engine.config.momentumScrolling = false
        frame([finger(500, 800, id: 1), finger(800, 800, id: 2)])
        for step in 1...10 {
            frame([finger(500, 800 - step * 20, id: 1), finger(800, 800 - step * 20, id: 2)])
        }
        XCTAssertEqual(frame([]), [])
        XCTAssertFalse(engine.isCoasting)
    }

    func testResetReleasesHeldButton() {
        frame([finger(500, 500)])
        frame([finger(500, 500)], clicked: true)
        XCTAssertEqual(engine.reset(), [.buttonUp(.left)])
        XCTAssertEqual(engine.reset(), [])
    }
}
