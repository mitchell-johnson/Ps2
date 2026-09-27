import DualSenseCore
import Foundation
#if canImport(IOKit) && canImport(AppKit)
import ApplicationServices
import IOKit.hid
#endif

let usage = """
Usage: dualsense-trackpad [options]

Use a PS5 DualSense controller's touchpad as a Mac trackpad.

  One finger ............ move the pointer
  Press the pad ......... click (hold and drag to drag)
  Two-finger press ...... right click
  Tap / two-finger tap .. click / right click
  Two fingers ........... scroll (with momentum)
  Mute button ........... toggle trackpad mode on/off (e.g. while gaming)

Options:
  --pointer-speed <x>      Pointer speed multiplier (default 1.0)
  --acceleration <x>       Pointer acceleration, 0 disables (default 1.0)
  --scroll-speed <x>       Scroll speed multiplier (default 1.0)
  --no-natural-scrolling   Fingers move the scroll bar instead of the content
  --no-tap-to-click        Only physical presses click
  --no-momentum            Stop scrolling as soon as fingers lift
  --no-secondary-click     Two-finger click/tap is a normal left click
  --debug                  Print parsed touch data instead of moving the pointer
  -h, --help               Show this help
"""

struct Options {
    var config = TrackpadConfig()
    var debug = false

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()

        func number(for flag: String) -> Double {
            guard let text = iterator.next(), let value = Double(text), value.isFinite, value >= 0 else {
                fail("\(flag) needs a finite, non-negative number")
            }
            return value
        }

        while let argument = iterator.next() {
            switch argument {
            case "--pointer-speed": options.config.pointerSpeed = number(for: argument)
            case "--acceleration": options.config.acceleration = number(for: argument)
            case "--scroll-speed": options.config.scrollSpeed = number(for: argument)
            case "--no-natural-scrolling": options.config.naturalScrolling = false
            case "--no-tap-to-click": options.config.tapToClick = false
            case "--no-momentum": options.config.momentumScrolling = false
            case "--no-secondary-click": options.config.twoFingerSecondaryClick = false
            case "--debug": options.debug = true
            case "-h", "--help":
                print(usage)
                exit(0)
            default:
                fail("unknown option \(argument)")
            }
        }
        return options
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n\n\(usage)\n".utf8))
    exit(2)
}

func log(_ message: String) {
    print("[dualsense-trackpad] \(message)")
    fflush(stdout)
}

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))

#if canImport(IOKit) && canImport(AppKit)
// Input Monitoring lets us read the controller; Accessibility (event posting) lets us move the pointer.
if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
}
if !options.debug && !CGPreflightPostEventAccess() {
    CGRequestPostEventAccess()
    log("""
        Waiting for Accessibility permission. Enable it in System Settings → \
        Privacy & Security → Accessibility, then restart this program.
        """)
}

let input = HIDInput()
let injector = EventInjector()

/// Gesture state is kept per controller so reports from several connected controllers
/// don't interleave into one touch stream.
final class Controller {
    let engine: TrackpadEngine
    var muteWasDown = false

    init(config: TrackpadConfig) {
        engine = TrackpadEngine(config: config)
    }
}
var controllers: [HIDInput.ControllerID: Controller] = [:]
var enabled = true

func resetAll() {
    for controller in controllers.values {
        controller.engine.reset().forEach(injector.perform)
    }
}

input.onConnectionChange = { id, name, connected in
    log("\(connected ? "Connected" : "Disconnected"): \(name)")
    if connected {
        controllers[id] = Controller(config: options.config)
    } else {
        controllers.removeValue(forKey: id)?.engine.reset().forEach(injector.perform)
    }
}

input.onReport = { id, report in
    guard let controller = controllers[id], let state = DualSenseReport.parse(report) else { return }

    if state.muteButton && !controller.muteWasDown {
        enabled.toggle()
        resetAll()
        log("Trackpad mode \(enabled ? "on" : "off")")
    }
    controller.muteWasDown = state.muteButton

    if options.debug {
        let touches = state.touches.map { "#\($0.id) (\($0.x), \($0.y))" }.joined(separator: "  ")
        log("touches: [\(touches)] click: \(state.touchpadClicked)")
        return
    }
    guard enabled else { return }

    let frame = TouchFrame(
        touches: state.touches,
        clicked: state.touchpadClicked,
        timestamp: ProcessInfo.processInfo.systemUptime
    )
    controller.engine.process(frame).forEach(injector.perform)
}

guard input.start() else {
    log("""
        Could not open HID devices. Grant Input Monitoring in System Settings → \
        Privacy & Security → Input Monitoring (for this app or your terminal), then restart.
        """)
    exit(1)
}

// Release any held button on Ctrl-C / launchctl stop so the system isn't left mid-drag.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let signalSources = [SIGINT, SIGTERM].map { signalNumber -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        resetAll()
        log("Stopped")
        exit(0)
    }
    source.resume()
    return source
}

log("Running. Connect a DualSense over USB or Bluetooth. Press the mute button to toggle. Ctrl-C to quit.")
CFRunLoopRun()
#else
log("This program uses IOKit and CoreGraphics and only runs on macOS.")
exit(1)
#endif
