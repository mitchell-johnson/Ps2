/// Parsing of DualSense (PS5 controller) HID input reports.
///
/// Layout follows the Linux `hid-playstation` driver. The common input block is:
///
///     0  left stick X        7-10  buttons[4]
///     1  left stick Y       11-14  reserved
///     2  right stick X      15-20  gyro (3 x int16)
///     3  right stick Y      21-26  accel (3 x int16)
///     4  L2 analog          27-30  sensor timestamp
///     5  R2 analog             31  reserved
///     6  sequence number    32-35  touch point 0
///                           36-39  touch point 1
///
/// Over USB the block follows report ID 0x01. Over Bluetooth it follows report
/// ID 0x31 plus one tag byte. Bluetooth controllers start in a reduced mode
/// (report 0x01, no touchpad data) until feature report 0x05 is read.

/// A finger on the touchpad. Coordinates are in touchpad units:
/// x in 0..<1920, y in 0..<1080, origin at the top-left.
public struct TouchPoint: Equatable {
    public var id: UInt8
    public var x: Int
    public var y: Int

    public init(id: UInt8, x: Int, y: Int) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public struct DualSenseState: Equatable {
    public var touches: [TouchPoint]
    public var touchpadClicked: Bool
    public var psButton: Bool
    public var muteButton: Bool
    public var cross: Bool
    public var circle: Bool

    public init(
        touches: [TouchPoint] = [],
        touchpadClicked: Bool = false,
        psButton: Bool = false,
        muteButton: Bool = false,
        cross: Bool = false,
        circle: Bool = false
    ) {
        self.touches = touches
        self.touchpadClicked = touchpadClicked
        self.psButton = psButton
        self.muteButton = muteButton
        self.cross = cross
        self.circle = circle
    }
}

public enum DualSenseReport {
    public static let vendorID = 0x054C
    public static let productIDs = [0x0CE6 /* DualSense */, 0x0DF2 /* DualSense Edge */]

    public static let touchpadWidth = 1920
    public static let touchpadHeight = 1080

    public static let usbReportID: UInt8 = 0x01
    public static let usbReportSize = 64
    public static let bluetoothReportID: UInt8 = 0x31
    public static let bluetoothReportSize = 78
    /// Reading this feature report switches a Bluetooth controller into full reporting mode.
    public static let calibrationFeatureReportID: UInt8 = 0x05

    private static let buttonsOffset = 7
    private static let touchOffset = 32
    private static let commonBlockSize = 40

    /// Parses a raw input report (first byte is the report ID).
    /// Returns nil for reports that don't carry touchpad data.
    public static func parse(_ report: [UInt8]) -> DualSenseState? {
        guard let first = report.first else { return nil }

        let base: Int
        switch first {
        case usbReportID where report.count >= usbReportSize:
            base = 1
        case bluetoothReportID where report.count >= bluetoothReportSize:
            base = 2
        default:
            return nil
        }
        guard report.count >= base + commonBlockSize else { return nil }

        let buttons0 = report[base + buttonsOffset]
        let buttons2 = report[base + buttonsOffset + 2]

        var touches: [TouchPoint] = []
        for index in 0..<2 {
            let offset = base + touchOffset + index * 4
            if let point = parseTouch(report, at: offset) {
                touches.append(point)
            }
        }

        return DualSenseState(
            touches: touches,
            touchpadClicked: buttons2 & 0x02 != 0,
            psButton: buttons2 & 0x01 != 0,
            muteButton: buttons2 & 0x04 != 0,
            cross: buttons0 & 0x20 != 0,
            circle: buttons0 & 0x40 != 0
        )
    }

    private static func parseTouch(_ report: [UInt8], at offset: Int) -> TouchPoint? {
        let contact = report[offset]
        // Bit 7 set means "no finger".
        guard contact & 0x80 == 0 else { return nil }
        let xLow = Int(report[offset + 1])
        let mixed = Int(report[offset + 2])
        let yHigh = Int(report[offset + 3])
        return TouchPoint(
            id: contact & 0x7F,
            x: xLow | (mixed & 0x0F) << 8,
            y: (mixed >> 4) | yHigh << 4
        )
    }
}
