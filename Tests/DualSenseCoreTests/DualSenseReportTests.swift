@testable import DualSenseCore
import XCTest

/// Builds a report with the common input block at `base`.
func makeReport(
    bluetooth: Bool = false,
    touches: [TouchPoint?] = [nil, nil],
    buttons: (UInt8, UInt8, UInt8) = (0x08, 0, 0)
) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: bluetooth ? DualSenseReport.bluetoothReportSize : DualSenseReport.usbReportSize)
    report[0] = bluetooth ? DualSenseReport.bluetoothReportID : DualSenseReport.usbReportID
    let base = bluetooth ? 2 : 1
    report[base + 7] = buttons.0
    report[base + 8] = buttons.1
    report[base + 9] = buttons.2
    for (index, touch) in touches.enumerated() {
        let offset = base + 32 + index * 4
        guard let touch else {
            report[offset] = 0x80
            continue
        }
        report[offset] = touch.id & 0x7F
        report[offset + 1] = UInt8(touch.x & 0xFF)
        report[offset + 2] = UInt8((touch.x >> 8) & 0x0F) | UInt8((touch.y & 0x0F) << 4)
        report[offset + 3] = UInt8(touch.y >> 4)
    }
    return report
}

final class DualSenseReportTests: XCTestCase {
    func testParsesUSBTouches() {
        let report = makeReport(touches: [TouchPoint(id: 3, x: 1919, y: 1079), TouchPoint(id: 4, x: 0, y: 17)])
        let state = DualSenseReport.parse(report)
        XCTAssertEqual(state?.touches, [TouchPoint(id: 3, x: 1919, y: 1079), TouchPoint(id: 4, x: 0, y: 17)])
        XCTAssertEqual(state?.touchpadClicked, false)
    }

    func testParsesBluetoothTouchesAndButtons() {
        let report = makeReport(
            bluetooth: true,
            touches: [nil, TouchPoint(id: 9, x: 960, y: 540)],
            buttons: (0x28, 0, 0x07)
        )
        let state = DualSenseReport.parse(report)
        XCTAssertEqual(state?.touches, [TouchPoint(id: 9, x: 960, y: 540)])
        XCTAssertEqual(state?.touchpadClicked, true)
        XCTAssertEqual(state?.psButton, true)
        XCTAssertEqual(state?.muteButton, true)
        XCTAssertEqual(state?.cross, true)
        XCTAssertEqual(state?.circle, false)
    }

    func testNoFingers() {
        XCTAssertEqual(DualSenseReport.parse(makeReport())?.touches, [])
    }

    func testRejectsReducedBluetoothAndShortReports() {
        // Reduced Bluetooth mode: report 0x01 but only 10 bytes, no touch data.
        XCTAssertNil(DualSenseReport.parse([0x01, 0x80, 0x80, 0x80, 0x80, 0x08, 0, 0, 0, 0]))
        XCTAssertNil(DualSenseReport.parse(Array(makeReport(bluetooth: true).prefix(40))))
        XCTAssertNil(DualSenseReport.parse([]))
        XCTAssertNil(DualSenseReport.parse([0x05] + [UInt8](repeating: 0, count: 63)))
    }
}
