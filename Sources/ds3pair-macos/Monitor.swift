import Foundation

func decodeAndPrintReport(_ report: [UInt8], counter: Int) {
    print("──────────────────────────────")
    print("Report #\(counter) (\(report.count) bytes)")
    print("──────────────────────────────")
    print()

    if report.count > 7 {
        let byte6 = report[6]
        let byte7 = report[7]

        print("Buttons:")
        print("  Cross     \(bitIsSet(byte6, 6) ? "✓" : "-")")
        print("  Circle    \(bitIsSet(byte6, 5) ? "✓" : "-")")
        print("  Square    \(bitIsSet(byte6, 7) ? "✓" : "-")")
        print("  Triangle  \(bitIsSet(byte6, 4) ? "✓" : "-")")
        print("  L1        \(bitIsSet(byte6, 2) ? "✓" : "-")")
        print("  R1        \(bitIsSet(byte6, 3) ? "✓" : "-")")
        print("  L2        \(bitIsSet(byte6, 0) ? "✓" : "-")")
        print("  R2        \(bitIsSet(byte6, 1) ? "✓" : "-")")
        print("  Select    \(bitIsSet(byte7, 0) ? "✓" : "-")")
        print("  Start     \(bitIsSet(byte7, 3) ? "✓" : "-")")
        print("  PS        \(bitIsSet(byte7, 4) ? "✓" : "-")")
        print("  L3        \(bitIsSet(byte7, 1) ? "✓" : "-")")
        print("  R3        \(bitIsSet(byte7, 2) ? "✓" : "-")")
        print()
    }

    if report.count > 5 {
        let hat = report[5]
        let (up, down, left, right) = decodeHat(hat)
        print("D-Pad:")
        print("  Up        \(up ? "✓" : "-")")
        print("  Down      \(down ? "✓" : "-")")
        print("  Left      \(left ? "✓" : "-")")
        print("  Right     \(right ? "✓" : "-")")
        print()
    }

    if report.count > 4 {
        print("Axes:")
        print("  LX: \(report[1])")
        print("  LY: \(report[2])")
        print("  RX: \(report[3])")
        print("  RY: \(report[4])")
        print()
    }

    if report.count > 22 {
        print("Pressure:")
        print("  Right      : \(report[9])")
        print("  Left       : \(report[10])")
        print("  Up         : \(report[11])")
        print("  Down       : \(report[12])")
        print("  Triangle   : \(report[13])")
        print("  Circle     : \(report[14])")
        print("  Cross      : \(report[15])")
        print("  Square     : \(report[16])")
        print("  L1         : \(report[17])")
        print("  R1         : \(report[18])")
        print("  L2         : \(report[19])")
        print("  R2         : \(report[20])")
        print("  L3         : \(report[21])")
        print("  R3         : \(report[22])")
        print()
    }
}

private func bitIsSet(_ byte: UInt8, _ bit: Int) -> Bool {
    (byte >> bit) & 1 == 1
}

private func decodeHat(_ value: UInt8) -> (up: Bool, down: Bool, left: Bool, right: Bool) {
    switch value {
    case 0: return (true,  false, false, false)
    case 1: return (true,  false, false, true)
    case 2: return (false, false, false, true)
    case 3: return (false, true,  false, true)
    case 4: return (false, true,  false, false)
    case 5: return (false, true,  true,  false)
    case 6: return (false, false, true,  false)
    case 7: return (true,  false, true,  false)
    default: return (false, false, false, false)
    }
}

func decodeAndPrintDS4Report(_ report: [UInt8], counter: Int) {
    guard report.count >= 10 else { return }
    print("──────────────────────────────")
    print("DS4 Report #\(counter)")
    print("──────────────────────────────")
    print()

    print("Sticks:")
    print(String(format: "  LX: %3d  LY: %3d", report[1], report[2]))
    print(String(format: "  RX: %3d  RY: %3d", report[3], report[4]))
    print()

    print("Triggers:")
    print(String(format: "  L2: %3d  R2: %3d", report[5], report[6]))
    print()

    let hat = (report[7] >> 0) & 0x0F
    let (up, down, left, right) = decodeHat(hat == 8 ? 0xFF : hat)
    print("D-Pad:")
    print("  Up        \(up ? "✓" : "-")")
    print("  Down      \(down ? "✓" : "-")")
    print("  Left      \(left ? "✓" : "-")")
    print("  Right     \(right ? "✓" : "-")")
    print()

    let b7 = report[7]
    let b8 = report[8]
    let b9 = report[9]
    print("Buttons:")
    print("  Square    \(bitIsSet(b7, 4) ? "✓" : "-")")
    print("  Cross     \(bitIsSet(b7, 5) ? "✓" : "-")")
    print("  Circle    \(bitIsSet(b7, 6) ? "✓" : "-")")
    print("  Triangle  \(bitIsSet(b7, 7) ? "✓" : "-")")
    print("  L1        \(bitIsSet(b8, 0) ? "✓" : "-")")
    print("  R1        \(bitIsSet(b8, 1) ? "✓" : "-")")
    print("  L2 btn    \(bitIsSet(b8, 2) ? "✓" : "-")")
    print("  R2 btn    \(bitIsSet(b8, 3) ? "✓" : "-")")
    print("  Share     \(bitIsSet(b8, 4) ? "✓" : "-")")
    print("  Options   \(bitIsSet(b8, 5) ? "✓" : "-")")
    print("  L3        \(bitIsSet(b8, 6) ? "✓" : "-")")
    print("  R3        \(bitIsSet(b8, 7) ? "✓" : "-")")
    print("  PS        \(bitIsSet(b9, 0) ? "✓" : "-")")
    print("  Touchpad  \(bitIsSet(b9, 1) ? "✓" : "-")")
    print()
}
