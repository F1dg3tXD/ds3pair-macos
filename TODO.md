# TODO

Ideas and pending work for ds3pair-macos.

## Raspberry Pi Bluetooth DS3 controller forwarder

**Status:** Idea — not started.

### Goal

Use a Raspberry Pi as a wireless bridge so a knockoff (or genuine) DS3 can be
used over Bluetooth with full pressure + motion, even though macOS refuses to
pair clones.

### How it works

The controller stays plugged into the Pi over USB. The Pi reads **all SDL
events** from it (SDL0 is the PS3 pressure/motion interface) and re-emits them
as a Bluetooth HID device that looks like a DualShock 3. The PC pairs to the
Pi and sees a normal Bluetooth DS3.

Flow:

1. Controller plugged into the Pi's USB port.
2. The forwarder reads SDL events from the controller.
3. A **user-configurable button combo** (e.g. PS + Share held ~3s) makes the
   forwarder enter pairing/scan mode.
4. The Pi advertises as a Bluetooth HID device carrying the DS3's SDP record
   and report descriptor.
5. Once the PC connects, every SDL event (sticks, digital buttons, L2/R2 and
   face-button pressure, sixaxis motion) is translated into the 49-byte DS3
   input report and pushed over the HID interrupt channel. Reports from the
   PC (LED / rumble) are forwarded back over USB.

### Key technical notes

- **Reading SDL events:** mirror what PCSX2 does — SDL with
  `SDL_HINT_JOYSTICK_HIDAPI_PS3=1` exposes the DS3's pressure as joystick
  axes. On Linux the HIDAPI PS3 driver yields a joystick with 16 axes and 11
  buttons; JoyAxis6..15 are the analog pressure for Cross / Circle / Square /
  Triangle / L1 / R1 / D-Pad.
- **Emitting Bluetooth HID from the Pi:** BlueZ is normally a host, not a
  peripheral, so acting *as* a DS3 needs a classic-BT HID gadget:
  - `bthid` kernel module (exposes a Bluetooth HID device on older kernels),
  - a userspace HID-over-L2CAP server (HID Control PSM 0x11, HID Interrupt
    PSM 0x13) with the DS3's SDP record, or
  - a Bluetooth USB dongle flashed as a peripheral.
  Classic Bluetooth (BR/EDR) HID is the required transport — a BLE-only path
  won't work for a DS3.
- **Sixaxis motion:** the 49-byte report carries accel/gyro bytes; confirm
  whether SDL exposes them (extra axes) and forward them as-is.
- **Button combo to trigger pairing:** a config file (e.g.
  `/etc/forwarder.conf`) listing combos like `PS + Share` with a hold time; on
  match the forwarder starts advertising / accepting a new connection and
  lights a status LED.

### Risks / open questions

- Classic-BT HID gadget support on current Raspberry Pi OS / BlueZ is the main
  unknown — need a prototype to see which path (bthid module vs userspace
  L2CAP server) works on the target kernel.
- The PC must not already have the Pi paired as a generic HID device.
- Clones may only expose pressure on the SDL0 interface; SDL1 stays
  unforwarded.
- Latency budget: USB polling + BT HID should stay well under ~10ms per report.

### References

- PCSX2 SDL source (`pcsx2/pcsx2/Input/SDLInputSource.cpp`) — the exact SDL
  pressure handling is documented in the next section.

---

## PCSX2 SDL input research (why our tool missed pressure)

**Status:** Done — root cause fixed.

PCSX2 reads the DS3 through **SDL3** (`SDL_InitSubSystem(SDL_INIT_JOYSTICK |
SDL_INIT_GAMEPAD | SDL_INIT_HAPTIC)`). Controllers are opened as gamepads or
raw joysticks; DS3 pressure is exposed as **joystick axes**, not buttons:

- `SDL_HINT_JOYSTICK_HIDAPI_PS3=1` is set on non-Windows — this is what makes
  pressure work (on Windows the Sixaxis / DsHidMini driver is used).
- A real PS3 HID device shows up as **16 axes + 11 buttons**
  (`IsControllerSixaxis`). Axes JoyAxis6..15 are analog pressure:
  Cross, Circle, Square, Triangle, L1, R1, D-Pad Up/Down/Left/Right.
- PCSX2 binds them as `FullAxis` inputs (`SDL-{n}/FullJoyAxis{6..15}`) mapped
  to the same bindings as the digital button presses.
- On macOS PCSX2 also enables the IOKit and MFI joystick drivers.

### Root cause in our tool

`DS3Controller.startMonitoring` registered an IOHID input-report callback but
never called `IOHIDDeviceScheduleWithRunLoop`. IOKit therefore never delivered
a single report, so `monitor`, `play`, and the `ps3mode` pressure probe all
silently collected **0 samples** — the tool reported "no pressure" even when
the controller was in true DS3 mode.

**Fix:** schedule the device on the main run loop in `startMonitoring` and
unschedule in `stopMonitoring` / `close` (done in `DS3Controller.swift`).

### Verification

- [ ] Re-run `ps3mode` with the controller connected and Cross held during the
      probe — expect live pressure bytes on the DS3 interface.
- [ ] Confirm `monitor` now shows reports.
- [ ] Surface pressure axes directly (like PCSX2's JoyAxis6..15) in `monitor`
      output so SDL-pressure vs raw-byte pressure can be compared.
- [ ] Improve the HID descriptor walker in `PS3Mode.swift` (the clone's
      descriptor parsed to "unknown" — likely non-1-byte report count
      encodings); advisory only, observed report lengths are the real signal.
