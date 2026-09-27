# DualSense Trackpad

**Turn your PS5 controller's touchpad into a Mac trackpad.**

[![CI](https://github.com/mitchell-johnson/dualsense-trackpad/actions/workflows/ci.yml/badge.svg)](https://github.com/mitchell-johnson/dualsense-trackpad/actions/workflows/ci.yml)
![macOS 12+](https://img.shields.io/badge/macOS-12%2B-black?logo=apple)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)

Sitting back from your Mac with a DualSense in hand? Point, click, drag and scroll from the
couch without reaching for the mouse. It works over **USB or Bluetooth** and needs no kernel
extension. It's a small background program you can remove at any time.

---

## Contents

- [Gestures](#gestures)
- [Quick start](#quick-start)
- [Permissions](#permissions)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Development](#development)
- [Uninstall](#uninstall)

## Gestures

The gestures copy a MacBook trackpad, so there's nothing new to learn.

| Gesture | What happens |
| --- | --- |
| ☝️ Slide one finger | Move the pointer. Faster swipes travel further. |
| 👇 Press the touchpad | Click. Keep it pressed and slide to **drag**. |
| ✌️ Press with two fingers | Right click |
| 👆 Tap | Click. Tap twice quickly to double-click. |
| ✌️ Tap with two fingers | Right click |
| ✌️ Slide two fingers | Scroll in any direction. Scrolling keeps coasting after you lift your fingers. |
| 👍 Hold the click with your thumb, slide another finger | Drag, like on a MacBook |
| 🔇 **Mute button** | Turn trackpad mode off and on, for example while you play a game |

Works with the **DualSense** and **DualSense Edge**. You can connect several controllers at once,
and each one is tracked separately.

## Quick start

You'll need macOS 12 (Monterey) or later and Apple's command-line developer tools. If you don't
have Xcode, install the tools with:

```sh
xcode-select --install
```

**1. Connect the controller.** Plug it in with a USB-C cable that carries data, or pair it over
Bluetooth: hold **PS + Create** until the light bar flashes, then choose it in
**System Settings → Bluetooth**.

**2. Download and install.**

```sh
git clone https://github.com/mitchell-johnson/dualsense-trackpad.git
cd dualsense-trackpad
./scripts/install.sh
```

The installer builds the program to `~/.local/bin/dualsense-trackpad` and sets it to start
automatically every time you log in.

**3. Grant permissions.** macOS will ask for two permissions (see [Permissions](#permissions)).
Once you've granted them, restart the program:

```sh
launchctl kickstart -k gui/$(id -u)/com.dualsense-trackpad
```

**4. Touch the pad.** The pointer should move. Press the **mute button** whenever you want the
controller back for gaming.

### Just want to try it first?

Run it straight from the source folder without installing anything:

```sh
swift run -c release dualsense-trackpad
```

Press **Ctrl-C** to stop it. When you run it this way, macOS asks for the permissions for your
terminal app (Terminal, iTerm, and so on) instead.

## Permissions

macOS protects both reading input devices and controlling the pointer. The program needs:

| Permission | Why | Where |
| --- | --- | --- |
| **Input Monitoring** | To read touches from the controller | System Settings → Privacy & Security → Input Monitoring |
| **Accessibility** | To move the pointer, click and scroll | System Settings → Privacy & Security → Accessibility |

If `dualsense-trackpad` isn't listed, click **+** and pick `~/.local/bin/dualsense-trackpad`.
Press **Cmd-Shift-.** in the file picker to show hidden folders such as `.local`.

> [!NOTE]
> If you rebuild or reinstall, macOS may treat it as a new program. If a permission looks switched
> on but nothing works, remove the entry with **−**, add it again, then restart the program.

## Configuration

Every setting is a command-line option:

| Option | Default | What it does |
| --- | --- | --- |
| `--pointer-speed <x>` | `1.0` | Multiplier for how far the pointer moves |
| `--acceleration <x>` | `1.0` | How much faster swipes are boosted. `0` turns acceleration off. |
| `--scroll-speed <x>` | `1.0` | Multiplier for scroll distance |
| `--no-natural-scrolling` | off | Scroll like a mouse wheel: fingers move the scroll bar, not the content |
| `--no-tap-to-click` | off | Only a physical press of the touchpad clicks |
| `--no-momentum` | off | Stop scrolling the moment your fingers lift |
| `--no-secondary-click` | off | Two-finger clicks and taps become normal left clicks |
| `--debug` | off | Print what the touchpad reports instead of moving the pointer |

For example:

```sh
# Faster pointer, gentler scrolling, no tap-to-click
swift run -c release dualsense-trackpad --pointer-speed 1.6 --scroll-speed 0.7 --no-tap-to-click
```

### Changing settings for the installed version

The installed program reads its options from its LaunchAgent file. Open
`~/Library/LaunchAgents/com.dualsense-trackpad.plist` and add each option as its own `<string>`
under `ProgramArguments`:

```xml
<key>ProgramArguments</key>
<array>
    <string>/Users/you/.local/bin/dualsense-trackpad</string>
    <string>--pointer-speed</string>
    <string>1.6</string>
    <string>--no-tap-to-click</string>
</array>
```

Then restart it:

```sh
launchctl kickstart -k gui/$(id -u)/com.dualsense-trackpad
```

## Troubleshooting

Start by watching what the program sees:

```sh
tail -f /tmp/dualsense-trackpad.log            # installed version
swift run -c release dualsense-trackpad --debug  # or run it in the foreground
```

<details>
<summary><b>Nothing happens when I touch the pad</b></summary>

Run with `--debug` and touch the pad.

- **No `Connected:` line** means macOS isn't passing the controller through. Check that it appears
  in System Settings → Bluetooth, or try another USB-C cable, since some cables only charge.
- **"Could not open HID devices"** means Input Monitoring is missing. Grant it and restart.
- **Connected, but no touch lines over Bluetooth**: turn the controller off by holding PS for
  10 seconds, then reconnect it. The program switches the controller into its full reporting mode
  when it connects.

</details>

<details>
<summary><b>Touches show up in <code>--debug</code> but the pointer doesn't move</b></summary>

Accessibility permission is missing, or it belongs to an older build. Remove the entry, add it
again, then restart the program.

</details>

<details>
<summary><b>A game reacts to the touchpad too</b></summary>

Press the **mute button** to turn trackpad mode off while you play, and press it again when you're
done. The log shows `Trackpad mode off` and `Trackpad mode on`.

</details>

<details>
<summary><b>The pointer is too fast, too slow or too jumpy</b></summary>

Adjust `--pointer-speed` first. If small, precise movements feel fine but big swipes overshoot,
lower `--acceleration`, or set it to `0` for a constant speed.

</details>

<details>
<summary><b>Scrolling goes the wrong way</b></summary>

The default matches a Mac trackpad's "natural" scrolling. Add `--no-natural-scrolling` if you
prefer scroll-wheel direction.

</details>

## How it works

This is a *user-space* driver. It reads the controller through Apple's standard HID APIs and
creates ordinary mouse events, so it needs no kernel extension, DriverKit entitlement or
reduced system security.

```
 DualSense ──USB/Bluetooth──▶ HIDInput ──raw report──▶ DualSenseReport ──touches──▶ TrackpadEngine ──actions──▶ EventInjector ──▶ macOS
                              (IOKit)                   (parse bytes)                (gestures)                   (CGEvent)
```

| Component | Responsibility |
| --- | --- |
| [`HIDInput`](Sources/DualSenseTrackpad/HIDInput.swift) | Finds DualSense controllers with `IOHIDManager` and receives their input reports at about 250 Hz. Over Bluetooth it reads feature report `0x05`, which switches the controller from its reduced report into the full `0x31` report that includes touchpad data. |
| [`DualSenseReport`](Sources/DualSenseCore/DualSenseReport.swift) | Decodes a report: up to two touch points on a 1920 × 1080 grid, the touchpad click and a few buttons. |
| [`TrackpadEngine`](Sources/DualSenseCore/TrackpadEngine.swift) | The gesture state machine. It handles pointer acceleration, click and drag, tap detection, two-finger scrolling and momentum. |
| [`EventInjector`](Sources/DualSenseTrackpad/EventInjector.swift) | Posts `CGEvent` mouse and scroll events. It handles double-clicks, drag events, sub-pixel movement and keeping the pointer on your displays. |
| [`main.swift`](Sources/DualSenseTrackpad/main.swift) | Command-line options, permission prompts, the mute toggle and per-controller state. It releases any held button on exit. |

### DualSense report format

The touchpad data sits at the same place in the common input block on both connections. Over USB
the block starts after report ID `0x01`. Over Bluetooth it starts after report ID `0x31` plus
one tag byte.

| Offset in block | Contents |
| --- | --- |
| 0–5 | Sticks and triggers |
| 7–10 | Buttons. Byte 9 bit 1 is the touchpad click, bit 2 is mute. |
| 32–35, 36–39 | Touch points 0 and 1. Byte 0 bit 7 set means no finger, bits 0–6 are the contact ID. X and Y are 12-bit values packed into the next 3 bytes. |

The layout follows Linux's
[`hid-playstation`](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-playstation.c)
driver.

## Development

```sh
swift build        # build everything
swift test         # run the unit tests
```

```
Sources/
  DualSenseCore/       Portable Swift: report parsing and gesture engine (no Apple frameworks)
  DualSenseTrackpad/   macOS program: IOKit input, CoreGraphics output, command-line interface
Tests/
  DualSenseCoreTests/  Unit tests for the parser and every gesture
scripts/               install.sh and uninstall.sh
Resources/             LaunchAgent template
```

`DualSenseCore` has no Apple dependencies, so the parser and gesture tests also run on Linux.
Continuous integration builds and tests on both macOS and Linux for every push.

Ideas for contributions:

- A menu-bar icon with a settings panel instead of command-line options
- Mapping the sticks and buttons (for example, right stick to scroll, L1/R1 to back and forward)
- Scroll phase information so apps can show elastic "rubber band" bounces
- Lighting the light bar to show whether trackpad mode is on

## Uninstall

```sh
./scripts/uninstall.sh
```

This stops the program and removes the binary and its LaunchAgent. You can also remove
`dualsense-trackpad` from the Input Monitoring and Accessibility lists in System Settings.
