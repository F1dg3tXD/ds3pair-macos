# ds3pair-macos

A DualShock 3 (PS3 controller) utility for macOS. It can read controller
information, write the Bluetooth pairing address over USB, bridge the
controller to a virtual DualShock 4 so games recognize it, and more.

## Why this exists

The DualShock 3 predates modern Bluetooth pairing. It uses **legacy pairing
with a PIN** instead of Secure Simple Pairing, and it expects a specific
"pairing host" Bluetooth address to be stored in its firmware. macOS has no
built-in way to set that address — that is what this tool does over USB.

## Building

Requires macOS 15+ for the `play` command (CoreHID) and Xcode 16 / Swift 5.10+.

```sh
swift build
swift build -c release --arch arm64 --arch x86_64   # universal binary
```

Run the menu with no arguments:

```sh
.build/debug/ds3pair-macos
```

## Commands

| Command | Description |
| --- | --- |
| *(no args)* | Interactive menu |
| `info` / `read` | Show controller, Bluetooth pairing, and link-key information |
| `inspect` | Same as `info` with extra raw detail |
| `pair` | Auto-discover the Mac's address, write it to the controller over USB |
| `pair <MAC>` | Pair to a specific address (`AA:BB:CC:DD:EE:FF`) |
| `unpair` | Clear the stored pairing address |
| `monitor` | Stream input reports from the controller |
| `play` | Bridge the DS3's input to a virtual DualShock 4 |
| `ps3mode` | Detect DS3 vs DS4-clone HID mode and probe for live button pressure |
| `help` | Show usage |

Flags:

| Flag | Description |
| --- | --- |
| `--raw` | Print raw hex dumps of feature reports |
| `--mac <MAC>` | Pair to a specific MAC address |
| `--pin <PIN>` | Use only this legacy pairing PIN during the wireless handshake |
| `--no-wireless` | Write the pairing address only; skip the wireless handshake |

Examples:

```sh
ds3pair-macos pair AA:BB:CC:DD:EE:FF
ds3pair-macos pair --mac AA:BB:CC:DD:EE:FF
ds3pair-macos pair --pin 1234
ds3pair-macos pair --no-wireless
ds3pair-macos info --raw
ds3pair-macos monitor
```

## How pairing works

1. Connect the controller via USB and run `pair`.
2. The tool reads the controller's pairing report over USB and writes your
   Mac's Bluetooth address into it. This part works for **every** controller,
   genuine or clone.
3. Then it attempts the **wireless handshake**: you press the PS button and the
   tool registers the controller with macOS's Bluetooth stack, supplying the
   DS3's legacy PIN (`0000` for genuine units, other candidates for clones).

The key write is report `0xF5` (via IOHID feature reports), the same technique
as the classic Linux `sixpair` utility.

## Genuine vs clone controllers

This is the most important thing to understand about DS3s.

| | Genuine Sony | Clone / reproduction |
| --- | --- | --- |
| USB address write | Works | Works (most clones) |
| Wireless pairing on macOS | Usually works (legacy PIN `0000`) | **Almost never** |
| Virtual DS4 bridge (`play`) | Works | Works |

A genuine controller answers the legacy PIN exchange, so after you write the
address it can connect wirelessly and stay connected. Clones implement the USB
address write but their Bluetooth behavior varies wildly: many use a different
PIN (`1234`, `1111`, `8888`…), and a significant class uses **unencrypted or
non-standard links that macOS's Bluetooth daemon rejects outright** — the tool
cannot bypass that, and neither can any user-space program.

### Why clones never complete the wireless step

The tool's detection and the wireless handshake have an ordering problem that
only genuine controllers can resolve:

1. The tool detects the controller over USB and writes the pairing address.
2. It then runs `IOBluetoothDevicePair` to register the controller wirelessly.
3. **macOS's Bluetooth daemon rejects the clone during pairing** — typically
   within a couple of seconds, before any PIN is even exchanged. The symptom
   is an instant `XPC connection invalid` from the daemon.
4. Because the clone never forms a link, it can never appear to macOS as a
   paired Bluetooth controller, so the handshake retries until it times out.

If you see every attempt fail within a few seconds with a daemon error
(e.g. `XPC connection invalid`, `0x…`), the PIN is irrelevant — **macOS is
refusing to pair this controller at all**. No amount of PIN guessing will fix
it. The tool now stops after repeated instant rejections instead of wasting
the full timeout.

### What to do instead

- **For a clone you already own:** use `play`. It bridges the controller's USB
  input to a virtual DualShock 4 (VID `054C`, PID `05C4`) that any game
  recognizes as a native controller. No Bluetooth involved.
- **For true wireless:** use a Linux device (Raspberry Pi, etc.) with BlueZ's
  `sixaxis` plugin. The Linux Bluetooth stack supports the DS3's key exchange
  properly, including clones that store the address over USB. See
  <https://www.pabr.org/sixlinux/sixlinux.en.html> and
  <https://wiki.archlinux.org/title/Gamepad#Pairing_via_Bluetooth>.

## Recovering full DS3 pressure sensitivity on a clone

Many knockoff controllers ship in a DualShock 4 mask by default: over Bluetooth
they pair as a PS4 controller (digital face buttons), so SDL never sees the
DS3's analog button pressure. The pressure data is still in the hardware — it
is gated behind the clone's hidden mode, not something that can be unlocked by
writing to the firmware over USB.

There is **no firmware read or write path over USB** (the DS3 HID interface has
no firmware commands and no public exploit), so the tool instead detects the
current mode and helps you switch it:

```sh
ds3pair-macos ps3mode
```

This command:

1. Enumerates **every** HID interface the controller exposes. Clones present
   two (PCSX2 shows them as SDL0 "PS3 Controller" and SDL1 "HID"); the
   pressure data is carried on the second one, so each interface is read,
   fingerprinted and probed independently. (SDL numbering may differ from the
   tool's listing — report lengths disambiguate: genuine DS3 input reports are
   49 bytes, DS4-clone masks are 64.)
2. Runs a **pressure probe** on all interfaces for ~6 seconds: hold the Cross
   button and vary your press force while it watches the report bytes. If
   pressure bytes change with force, that interface is in true DS3 mode and
   SDL will expose the analog axes.
3. Prints the known mode-switch button combos to try (they vary by clone), e.g.
   power-on holding **PS + Start**, **PS + Share/Select**, or holding **Start**
   while plugging in USB (the faster LED blink you saw is the clone switching
   HID personalities).

Once the probe reports live pressure:

- **Over USB** the analog pressure is available to SDL/evdev immediately — no
  pairing involved.
- **Over Bluetooth**, write the host address with `pair --no-wireless`, then
  connect on Linux via BlueZ sixaxis (or the macOS wireless handshake, which
  genuine controllers only).

A clone that reports digital buttons and no pressure after trying the combos
either has no true DS3 mode or uses an unencrypted link macOS refuses to pair —
in which case `play` is the reliable fallback.

## Troubleshooting

### `XPC connection invalid`

Printed by macOS's Bluetooth daemon when it tears down a legacy pairing. With
a clone controller this is expected and means the daemon rejected the device,
not that the PIN was wrong.

### Link key shows firmware-looking bytes

The `info` command prints the 16-byte link-key region from the pairing report.
On a genuine controller a fresh write zeros this region; on clones it often
holds fixed firmware/config bytes and never changes. A non-zero key that
survives address writes is a strong indicator of a clone.

### Controller not found

Make sure it is connected via USB and the OS has enumerated it. Clone
controllers often need the USB cable unplugged and replugged before they
appear.

## Limitations

- The wireless handshake is best-effort. Modern macOS frequently blocks legacy
  Bluetooth pairing regardless of controller, so genuine controllers may also
  fail with daemon errors.
- The `play` virtual DS4 bridge requires macOS 15+ (CoreHID).
- This project is not affiliated with Sony Interactive Entertainment.
