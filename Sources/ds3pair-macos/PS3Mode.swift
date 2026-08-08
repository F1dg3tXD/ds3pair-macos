import Foundation
import IOKit.hid

enum ControllerPersonality: String {
    case ds3 = "DualShock 3 HID (pressure-capable)"
    case ds4Clone = "DualShock 4 clone HID (digital face buttons)"
    case unknown = "Unknown HID layout"
}

struct ModeDiagnosis {
    var label: String
    var descriptorInputSizes: [Int]
    var observedReportLengths: [Int]
    var sampleCount: Int
    var crossSeen: Bool
    var varying: [(index: Int, range: ClosedRange<Int>, levels: Int)]
    var pressureIndices: [Int]
    var pressureResolved: Bool
}

/// Collects input reports while the user exercises the controller, so we can
/// tell whether live analog pressure data is present on a given interface.
final class PressureCollector {
    private let lock = NSLock()
    private var lengths: [Int] = []
    private var samples: [[UInt8]] = []
    var active = false

    func begin() { lock.lock(); active = true; samples.removeAll(); lengths.removeAll(); lock.unlock() }
    func finish() { lock.lock(); active = false; lock.unlock() }

    func add(_ report: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        if !lengths.contains(report.count) { lengths.append(report.count) }
        if samples.count < 8000 { samples.append(report) }
    }

    func snapshot() -> (lengths: [Int], samples: [[UInt8]]) {
        lock.lock(); defer { lock.unlock() }
        return (lengths, samples)
    }
}

private func bitIsSet(_ byte: UInt8, _ bit: Int) -> Bool {
    (byte >> bit) & 1 == 1
}

/// Minimal HID descriptor walker that returns the byte length of every Input
/// (0x81) main item. Used as supporting evidence for personality detection;
/// the live pressure probe is the authoritative check.
func inputReportSizes(in descriptor: [UInt8]) -> [Int] {
    var sizes: [Int] = []
    var reportSize = 0
    var reportCount = 0
    var i = 0

    while i < descriptor.count {
        let item = descriptor[i]
        i += 1
        let sizeCode = item & 0x03
        let type = (item >> 2) & 0x03
        let tag = (item >> 4) & 0x0F

        let dataLength: Int
        switch sizeCode {
        case 0: dataLength = 0
        case 1: dataLength = 1
        case 2: dataLength = 2
        default: dataLength = 4
        }
        guard i + dataLength <= descriptor.count else { break }
        let data = Array(descriptor[i..<(i + dataLength)])
        i += dataLength

        if type == 0 { // global
            switch tag {
            case 0x08: reportSize = Int(data.first ?? 0)
            case 0x09: reportCount = Int(data.first ?? 0)
            default: break
            }
        } else if type == 2, tag == 0x08 { // main: Input
            let bits = reportSize * reportCount
            let bytes = (bits + 7) / 8
            if bytes > 0 { sizes.append(bytes) }
        }
    }
    return sizes
}

/// Classifies the controller's current HID personality. The genuine DS3's
/// input report is 49 bytes; DS4-clone masks use 64-byte reports. The live
/// probe output is the deciding factor, so this is only advisory.
func classifyPersonality(descriptor: [UInt8]?, observed: [Int]) -> ControllerPersonality {
    let sizes = descriptor.map(inputReportSizes) ?? []
    let has49 = sizes.contains(49) || observed.contains(49)
    let has64 = sizes.contains(64) || observed.contains(64)
    if has49 { return .ds3 }
    if has64 { return .ds4Clone }
    return .unknown
}

// DS3 pressure windows recognized across the two common layouts:
// the Monitor.swift layout (buttons at 6, pressure at 9...22) and the
// canonical layout (buttons at 5-6, pressure at 7...18).
private let ds3PressureWindows: [ClosedRange<Int>] = [9...22, 7...18]

struct CrossDetection {
    enum Layout { case none, ds3, ds4 }
    var layout: Layout
    var present: Bool

    func isPressed(_ r: [UInt8]) -> Bool {
        switch layout {
        case .ds3: return r.count > 6 && bitIsSet(r[6], 6)
        case .ds4: return r.count > 7 && bitIsSet(r[7], 5)
        case .none: return false
        }
    }
}

/// Locates the Cross button's digital bit across the DS3 and DS4 layouts.
func detectCross(in samples: [[UInt8]]) -> CrossDetection {
    if samples.contains(where: { $0.count > 6 && bitIsSet($0[6], 6) }) {
        return CrossDetection(layout: .ds3, present: true)
    }
    if samples.contains(where: { $0.count > 7 && bitIsSet($0[7], 5) }) {
        return CrossDetection(layout: .ds4, present: true)
    }
    return CrossDetection(layout: .none, present: false)
}

/// Analyzes one interface's collected samples. If the Cross button lives on
/// this interface, only cross-held samples are used (so stick noise doesn't
/// register as pressure); otherwise the whole capture is used — the probe
/// instructions tell the user to touch only Cross, so any byte that varies
/// there is press-force data.
func analyzeDevice(
    _ samples: [[UInt8]],
    lengths: [Int],
    label: String,
    descriptorSizes: [Int],
    cross: CrossDetection
) -> ModeDiagnosis {
    let detected = cross.present ? cross : detectCross(in: samples)
    var pool = samples
    if detected.present {
        let held = samples.filter { detected.isPressed($0) }
        if !held.isEmpty { pool = held }
    }

    var varying: [(index: Int, range: ClosedRange<Int>, levels: Int)] = []
    let maxIndex = pool.compactMap { $0.count }.max() ?? 0
    if maxIndex > 1 {
        for idx in 1..<maxIndex {
            let values = pool.compactMap { $0.count > idx ? Int($0[idx]) : nil }
            guard let lo = values.min(), let hi = values.max(), hi - lo >= 6 else { continue }
            varying.append((idx, lo...hi, Set(values).count))
        }
    }

    let pressureIndices = varying.map { $0.index }.filter { idx in
        ds3PressureWindows.contains { $0.contains(idx) }
    }

    return ModeDiagnosis(
        label: label,
        descriptorInputSizes: descriptorSizes,
        observedReportLengths: lengths,
        sampleCount: samples.count,
        crossSeen: detected.present,
        varying: varying,
        pressureIndices: pressureIndices,
        pressureResolved: !pressureIndices.isEmpty
    )
}

// MARK: - Diagnostics output

func printModeDiagnosis(_ diagnosis: ModeDiagnosis) {
    print(diagnosis.label)
    print(String(repeating: "─", count: diagnosis.label.count))
    print("  Report lengths observed : \(diagnosis.observedReportLengths.isEmpty ? "none" : diagnosis.observedReportLengths.map(String.init).joined(separator: ", ")) bytes")
    print("  Samples collected       : \(diagnosis.sampleCount)")
    print("  Cross (X) button seen   : \(diagnosis.crossSeen ? "✓" : "no")")
    if diagnosis.varying.isEmpty {
        print("  Analog bytes            : none")
    } else {
        let lines = diagnosis.varying.map { entry in
            let tag = diagnosis.pressureIndices.contains(entry.index) ? "  ← pressure" : ""
            return "    byte \(String(format: "%2d", entry.index)): \(entry.range.lowerBound)→\(entry.range.upperBound) (\(entry.levels) levels)\(tag)"
        }.joined(separator: "\n")
        print("  Analog bytes            :")
        print(lines)
    }
    print("  Pressure-capable        : \(diagnosis.pressureResolved ? "✓" : "✗")")
    print()
}

func printModeSwitchGuide() {
    print("Switching the controller into DualShock 3 mode")
    print("───────────────────────────────────────────────")
    print("Clone firmware hides its real mode behind button combos. There is no")
    print("USB command to change it, and the firmware cannot be dumped or patched")
    print("over USB. Try each combo, then re-run this command to confirm pressure")
    print("appears. Combos vary by clone, so go in order:\n")
    print("  1. Power on holding PS + Start        (also puts it into BT pairing mode)")
    print("  2. Power on holding PS + Share/Select (toggles DS3 / DS4 / Xbox masks on")
    print("                                         many multi-mode clones)")
    print("  3. Hold Start while plugging the USB cable in — you noticed the LEDs")
    print("     blink faster, which is the clone entering a different mode")
    print("     (likely a BT-pairing or alternate HID personality).")
    print("  4. Hold PS + Share for ~5s while powered (factory/mode reset)")
    print("  5. Genuine DS3 behavior: press PS while unpaired\n")
    print("Once pressure appears:")
    print("  • Over USB the pressure is exposed to SDL/evdev immediately — no")
    print("    pairing needed.")
    print("  • For Bluetooth, write the host address first (`pair --no-wireless`),")
    print("    then pair with a Linux host using BlueZ's sixaxis plugin, or try the")
    print("    wireless handshake on macOS (genuine controllers only).\n")
}
