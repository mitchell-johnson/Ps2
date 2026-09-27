# DualSense Trackpad

Use a PS5 DualSense controller's touchpad as a Mac trackpad — over USB or Bluetooth.

| Gesture | Action |
| --- | --- |
| One finger | Move the pointer (with acceleration) |
| Press the touchpad | Click; keep pressed and slide to drag |
| Press with two fingers | Right click |
| Tap / two-finger tap | Click / right click |
| Two fingers | Scroll, with momentum when you lift |
| Thumb holds the click, other finger moves | Drag (like a MacBook trackpad) |
| **Mute button** | Toggle trackpad mode on/off (e.g. while gaming) |

Works with the DualSense and DualSense Edge on macOS 12+.

## How it works

It's a user-space driver — no kernel extension or DriverKit entitlement needed:

1. **`HIDInput`** (IOKit `IOHIDManager`) finds the controller and receives its raw input reports.
   Over Bluetooth it reads feature report `0x05`, which switches the controller from its reduced
   report into the full `0x31` report that includes touchpad data.
2. **`DualSenseReport`** decodes the report: up to two touch points (1920×1080 resolution) and the
   touchpad click.
3. **`TrackpadEngine`** turns touch frames into pointer moves, clicks, taps and scrolls.
4. **`EventInjector`** posts them as CoreGraphics mouse/scroll events, including double-click
   detection and clamping the pointer to your displays.

`DualSenseCore` (steps 2–3) is plain Swift with unit tests; the macOS-only parts live in
`Sources/DualSenseTrackpad`.

## Install

Requires Xcode or the Xcode Command Line Tools (`xcode-select --install`).

```sh
./scripts/install.sh
```

This builds a release binary to `~/.local/bin/dualsense-trackpad` and registers a LaunchAgent so
it starts at login. macOS will then ask for two permissions for `dualsense-trackpad`:

- **Input Monitoring** — to read the controller
- **Accessibility** — to move the pointer and click

Grant both in **System Settings → Privacy & Security**, then restart the agent:

```sh
launchctl kickstart -k gui/$(id -u)/com.dualsense-trackpad
```

Logs go to `/tmp/dualsense-trackpad.log`. Remove everything with `./scripts/uninstall.sh`.

> Re-running the installer after changing the code produces a new signature, so macOS may ask for
> the permissions again (remove the old entry and re-add it if the toggle looks on but it doesn't work).

## Run from a terminal

```sh
swift run -c release dualsense-trackpad --help
swift run -c release dualsense-trackpad --pointer-speed 1.5 --scroll-speed 0.8
```

When run this way, the permissions apply to your terminal app instead.

```
--pointer-speed <x>      Pointer speed multiplier (default 1.0)
--acceleration <x>       Pointer acceleration, 0 disables (default 1.0)
--scroll-speed <x>       Scroll speed multiplier (default 1.0)
--no-natural-scrolling   Fingers move the scroll bar instead of the content
--no-tap-to-click        Only physical presses click
--no-momentum            Stop scrolling as soon as fingers lift
--no-secondary-click     Two-finger click/tap is a normal left click
--debug                  Print parsed touch data instead of moving the pointer
```

To use options with the LaunchAgent, add them as extra `<string>` entries under
`ProgramArguments` in `~/Library/LaunchAgents/com.dualsense-trackpad.plist` and restart it.

## Troubleshooting

- **Nothing happens** — run with `--debug` and touch the pad. No output means the controller isn't
  being read: check Input Monitoring, and that the controller is connected (System Settings →
  Bluetooth, or a data-capable USB-C cable).
- **Touches print but the pointer doesn't move** — Accessibility permission is missing.
- **Games also react to the touchpad** — press the mute button to turn trackpad mode off.

## Development

```sh
swift test
```

The core logic tests also run on Linux.
