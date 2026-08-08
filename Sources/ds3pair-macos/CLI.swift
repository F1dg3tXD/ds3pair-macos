import Foundation

// MARK: - Argument Parsing

struct CLIOptions {
    var command = "menu"
    var args: [String] = []
    var raw = false
    var mac: String?
    var pin: String?
    var wireless = true
}

func parseArguments() -> CLIOptions {
    var raw = false
    var mac: String?
    var pin: String?
    var wireless = true
    var positional: [String] = []

    let arguments = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--raw":
            raw = true
        case "--mac":
            if index + 1 < arguments.count {
                mac = arguments[index + 1]
                index += 1
            }
        case "--pin":
            if index + 1 < arguments.count {
                pin = arguments[index + 1]
                index += 1
            }
        case "--no-wireless":
            wireless = false
        default:
            positional.append(arguments[index])
        }
        index += 1
    }

    var options = CLIOptions(raw: raw, mac: mac, pin: pin, wireless: wireless)
    if let first = positional.first {
        options.command = first
        options.args = Array(positional.dropFirst())
    }
    return options
}

// MARK: - Dispatch

func execute(options: CLIOptions) {
    switch options.command {
    case "menu":
        runMenu()

    case "help":
        printHelp()

    case "info", "read":
        executeInfo(raw: options.raw)

    case "inspect":
        executeInspect(raw: options.raw)

    case "pair":
        executePair(options: options)

    case "unpair":
        executeUnpair(raw: options.raw)

    case "monitor":
        executeMonitor()

    case "play":
        executePlay()

    case "ps3mode", "mode":
        executePS3Mode()

    case "--version", "version":
        print("ds3pair-macos \(DS3Constants.version)")

    default:
        print("Unknown command: \(options.command)\n")
        printHelp()
    }
}

// MARK: - Interactive Menu

private func runMenu() {
    while true {
        printHeader()
        print("1. Read controller information")
        print("2. Pair controller")
        print("3. Pair controller to a specific MAC")
        print("4. Remove pairing")
        print("5. Monitor input reports")
        print("6. Bridge to virtual DS4 (play)")
        print("7. Check controller mode (pressure / DS3 vs DS4)")
        print("8. Exit")
        print()
        print("Select an option (1-8): ", terminator: "")

        guard let input = readLine() else { return }

        switch input.trimmingCharacters(in: .whitespaces) {
        case "1":
            print()
            executeInfo(raw: false)
        case "2":
            print()
            executePair(options: CLIOptions(command: "pair"))
        case "3":
            print()
            executePair(options: CLIOptions(command: "pair", mac: promptForMAC()))
        case "4":
            print()
            executeUnpair(raw: false)
        case "5":
            print()
            executeMonitor()
        case "6":
            print()
            executePlay()
        case "7":
            print()
            executePS3Mode()
        case "8":
            print("Goodbye.")
            return
        default:
            print("Invalid option.")
        }
        print()
    }
}

private func promptForMAC() -> String? {
    print("Enter Bluetooth MAC address (e.g. AA:BB:CC:DD:EE:FF): ", terminator: "")
    guard let input = readLine() else { return nil }
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: - Commands

private func executeInfo(raw: Bool) {
    do {
        let controller = try DS3Controller()
        defer { controller.close() }

        printHeader()
        printControllerInfo(controller)

        let report = try controller.readPairingReport()
        let host = BTAddress.fromReportBytes(Array(report[2...7]))
        let controllerAddr = try controller.controllerAddress()

        printBluetoothInfo(host, controllerAddr: controllerAddr)
        printLinkKey(controller)

        printStatus(opened: true, readable: true)

        if raw {
            hexDump(report)
        }
    } catch {
        print("Error: \(error)")
    }
}

private func printLinkKey(_ controller: DS3Controller) {
    if let key = try? controller.linkKey() {
        let keyHex = key.map { String(format: "%02X", $0) }.joined()
        let keyState = key.allSatisfy { $0 == 0 } ? " (none stored)" : ""
        print("Link Key    : \(keyHex)\(keyState)")
        print()
    }
}

// MARK: - Mode diagnosis

/// Detects whether the controller is presenting as a real DualShock 3 HID
/// device (with live analog pressure on the face buttons) or as the DS4-clone
/// mask many knockoffs expose, then guides the user into PS3 mode.
///
/// Clones expose two HID interfaces (SDL0 "PS3 Controller" + SDL1 "HID");
/// the pressure lives on the second one, so every interface is monitored and
/// analyzed independently.
private func executePS3Mode() {
    let devices = DS3Controller.allDS3Devices()
    guard !devices.isEmpty else {
        printHeader()
        print("Error: \(DS3Error.deviceNotFound.description)")
        print()
        return
    }

    printHeader()
    print("HID interfaces detected: \(devices.count)")
    if devices.count > 1 {
        print("This controller exposes multiple HID interfaces (PCSX2 shows these as")
        print("SDL0 \"PS3 Controller\" and SDL1 \"HID\"). The SDL numbering may differ")
        print("from the listing below — the analog pressure lives on the HID interface.")
    }
    print()

    struct Interface {
        var controller: DS3Controller
        var collector: PressureCollector
        var label: String
        var descriptorSizes: [Int]
    }

    var interfaces: [Interface] = []

    for (index, device) in devices.enumerated() {
        do {
            let controller = try DS3Controller(device: device)
            let name = DS3Controller.productName(of: device)
            let collector = PressureCollector()
            try controller.startMonitoring(callback: { collector.add($0) })
            let sizes = controller.reportDescriptor().map(inputReportSizes) ?? []
            interfaces.append(Interface(
                controller: controller,
                collector: collector,
                label: "Interface #\(index) — \(name)",
                descriptorSizes: sizes
            ))
            print("  Interface #\(index) — \(name) (input reports \(sizes.isEmpty ? "unknown" : sizes.map(String.init).joined(separator: ", ")) bytes)")
        } catch {
            print("  Interface #\(index) — \(DS3Controller.productName(of: device)): failed to open (\(error))")
        }
    }
    print()

    guard !interfaces.isEmpty else {
        print("No interface could be opened for monitoring.")
        print()
        return
    }

    print("Pressure probe")
    print("──────────────")
    print("Press and hold the X (Cross) button, varying how hard you press")
    print("it (light → firm → light) for about 6 seconds. Do not touch the")
    print("sticks or any other button.")
    print("Press Enter to start the probe, or q to skip.")
    print()
    let skip = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "q"

    if !skip {
        interfaces.forEach { $0.collector.begin() }
        let start = Date()
        while Date().timeIntervalSince(start) < 6.0 {
            CFRunLoopRunInMode(.defaultMode, 0.25, false)
        }
        interfaces.forEach { $0.collector.finish() }
        print()
    }

    var pressureFound = false
    for interface in interfaces {
        let snapshot = interface.collector.snapshot()
        let cross = detectCross(in: snapshot.samples)
        let diagnosis = analyzeDevice(
            snapshot.samples,
            lengths: snapshot.lengths,
            label: interface.label,
            descriptorSizes: interface.descriptorSizes,
            cross: cross
        )
        printModeDiagnosis(diagnosis)
        if diagnosis.pressureResolved { pressureFound = true }
    }

    if pressureFound {
        print("✓ Pressure data found — the controller is in (or close to) DualShock 3 mode.")
        print("  SDL will expose the analog pressure over USB right away. For Bluetooth,")
        print("  run `pair` to write the host address, then connect via BlueZ sixaxis on")
        print("  Linux (or the macOS wireless handshake for genuine controllers).")
    } else {
        print("✗ No analog pressure seen on any interface — the controller is showing the")
        print("  DS4-clone mask. Try the combos below, then re-run this command.")
    }
    print()

    printModeSwitchGuide()

    interfaces.forEach { $0.controller.close() }
}

private func executePair(options: CLIOptions) {
    printHeader()
    print("DS3 Pairing\n")

    var targetAddress: BTAddress

    if let macString = options.args.first ?? options.mac {
        guard let addr = BTAddress(string: macString) else {
            print("Invalid MAC address: \(macString)")
            return
        }
        targetAddress = addr
    } else if let localAddr = discoverLocalBluetoothAddress() {
        print("Target: this Mac (\(localAddr.display))\n")
        targetAddress = localAddr
    } else {
        print("Could not discover local Bluetooth address.")
        guard let input = promptForMAC(), let addr = BTAddress(string: input) else {
            print("Invalid address.")
            return
        }
        targetAddress = addr
    }

    do {
        let watcher = DS3Watcher()
        try watcher.start()
        defer { watcher.stop() }

        if !watcher.currentDevices().isEmpty {
            print("A DualShock 3 is currently connected.")
            print("Please disconnect it from USB/Bluetooth.\n")
            print("Waiting for disconnect...")
            watcher.waitForDisconnect()
            print("Controller disconnected.\n")
        }

        print("1. Disconnect the controller from USB/Bluetooth.")
        print("2. Press the PS button when instructed.\n")
        print("Waiting for controller...")

        guard let device = watcher.waitForAppearance() else {
            print("Cancelled.")
            return
        }

        print("Controller detected.\n")

        let controller = try DS3Controller(device: device)
        defer { controller.close() }

        let controllerAddr = try controller.controllerAddress()
        print("Controller address: \(controllerAddr.display)\n")

        if controller.transport == "USB" {
            print("Pairing controller with this Mac...")
            try controller.setPairedHost(targetAddress)
            print("Pairing address written.\n")

            if options.raw {
                let report = try controller.readPairingReport()
                hexDump(report)
            }

            if options.wireless {
                runWirelessHandshake(controllerAddr, pins: options.pin.map { [$0] } ?? DS3Constants.pairingPINs)
            } else {
                print("Wireless handshake skipped (--no-wireless).\n")
                print("The pairing address is saved in the controller. It is now paired")
                print("to this Mac over USB; run `play` to bridge it to a virtual DS4.")
            }
            print("Done.")
        } else {
            print("Controller is already connected via Bluetooth.")
            print("Pairing successful.\n")
            print("Done.")
        }
    } catch {
        print("Error: \(error)")
    }
}

private func runWirelessHandshake(_ controllerAddr: BTAddress, pins: [String]) {
    print("Wireless handshake")
    print("──────────────────")
    print("1. Unplug the USB cable, then press and hold the PS button to power")
    print("   the controller on.")
    print("   (Many clones also page the host while still on USB — you can try")
    print("   pressing PS with it plugged in first, then unplug if nothing links.)")
    print("2. Keep it off USB while this tool registers it with the macOS")
    print("   Bluetooth stack. Genuine controllers use PIN 0000; clones may use")
    print("   another legacy PIN, so candidate PINs are tried in turn.")
    print("   Candidates: \(pins.joined(separator: ", "))\n")

    print("Note: while the controller stays on USB it will not answer Bluetooth")
    print("pages. For a wireless link it must be off USB and powered (PS held).")
    print("If every attempt fails instantly with a daemon error (0x…), the macOS")
    print("Bluetooth stack is rejecting this controller, not the PIN.\n")

    let systemPairer = SystemPairer()
    switch systemPairer.pairPersistent(with: controllerAddr, pinList: pins) {
    case .success:
        print()
        print("✓ Controller paired with the macOS Bluetooth stack")
        if let pin = systemPairer.lastSuccessfulPIN {
            print("  (legacy PIN \(pin)).")
        }
        print("Press the PS button any time to connect it wirelessly.")
    case .failure(let message):
        print("⚠ \(message)")
        print()
        print("The pairing address is saved in the controller. On modern macOS the")
        print("classic Bluetooth 2 wireless link may not complete; use the controller")
        print("over USB, or bridge it with the virtual DS4 (`play` command).")
    }
    print()
}

private func executeUnpair(raw: Bool) {
    do {
        let controller = try DS3Controller()
        defer { controller.close() }

        printHeader()
        printControllerInfo(controller)

        try controller.setPairedHost(.zero)
        let host = try controller.pairedHost()

        printBluetoothInfo(host)
        printStatus(opened: true, written: true, verified: host.isZero)

        if host.isZero {
            print("✓ Controller unpaired successfully.")
        } else {
            print("⚠ Write completed, but controller still reports a paired host.")
        }

        if raw {
            let report = try controller.readPairingReport()
            hexDump(report)
        }
    } catch {
        print("Error: \(error)")
    }
}

private func executeInspect(raw: Bool) {
    do {
        let controller = try DS3Controller()
        defer { controller.close() }

        let report = try controller.readPairingReport()
        let host = BTAddress.fromReportBytes(Array(report[2...7]))
        let controllerAddr = try controller.controllerAddress()

        printHeader()

        printSection("Controller Information")
        printField("Manufacturer", controller.manufacturer)
        printField("Product", controller.product)
        printField("Board Revision", controller.boardRevision)
        print()

        printSection("USB")
        printField("VID", String(format: "%04X", controller.vendorID))
        printField("PID", String(format: "%04X", controller.productID))
        print()

        printSection("Bluetooth")
        printField("Controller BD_ADDR", controllerAddr.display)
        printField("Paired Host", host.display)
        print()

        printSection("Status")
        let isUSB = controller.transport == "USB"
        let isBluetooth = controller.transport == "Bluetooth"
        printField("USB Connected", isUSB ? "✓" : "✗")
        printField("Bluetooth Connected", isBluetooth ? "✓" : "✗")
        printField("Battery", controller.battery)
        printField("Sixaxis", "Supported")
        printField("Pressure Buttons", "Supported")
        printField("Rumble", "Supported")
        print()

        if raw {
            hexDump(report)
        }
    } catch {
        print("Error: \(error)")
    }
}

private func executeMonitor() {
    do {
        let controller = try DS3Controller()
        defer { controller.close() }

        printHeader()
        printControllerInfo(controller)
        print("Monitoring input reports... Press Ctrl+C to stop.\n")

        var counter = 0

        try controller.startMonitoring { report in
            counter += 1
            decodeAndPrintReport(report, counter: counter)
        }

        CFRunLoopRun()
    } catch {
        print("Error: \(error)")
    }
}

private func executePlay() {
    do {
        let controller = try DS3Controller()

        printHeader()
        printControllerInfo(controller)
        print("Starting virtual DualShock 4 gamepad...")
        print("Press Ctrl+C to stop.\n")

        #if canImport(CoreHID)
        if #available(macOS 15, *) {
            let gamepad = VirtualGamepad()
            do {
                try gamepad.start()
                print("Virtual DS4 device created (VID: 054C PID: 05C4)")
                print("Bridging DS3 input to virtual DS4...\n")
            } catch {
                print("⚠ \(error)\n")
                print("Falling back to monitor-only mode.\n")
            }

            var counter = 0
            try controller.startMonitoring { report in
                counter += 1
                let ds4Report = DS3ToDS4Mapper.mapToReport(report)
                Task {
                    try? await gamepad.sendInputReport(ds4Report)
                }
                decodeAndPrintDS4Report(ds4Report, counter: counter)
            }

            CFRunLoopRun()
            gamepad.stop()
        } else {
            print("play command requires macOS 15 or later.")
        }
        #else
        print("play command requires CoreHID framework (macOS 15+).")
        #endif

        controller.close()
    } catch {
        print("Error: \(error)")
    }
}

// MARK: - Output Helpers

private func printHeader() {
    print("DualShock 3 Pair Utility")
    print("Version \(DS3Constants.version)\n")
}

private func printSection(_ title: String) {
    print(title)
    print(String(repeating: "─", count: 32))
}

private func printField(_ label: String, _ value: String) {
    print("\(label.padding(toLength: 20, withPad: " ", startingAt: 0))\(value)")
}

private func printControllerInfo(_ controller: DS3Controller) {
    print("Controller")
    print("──────────")
    print("Manufacturer : \(controller.manufacturer)")
    print("Product      : \(controller.product)")
    print(String(format: "USB VID/PID  : %04X:%04X", controller.vendorID, controller.productID))
    print()
}

private func printBluetoothInfo(_ host: BTAddress, controllerAddr: BTAddress? = nil) {
    print("Bluetooth")
    print("─────────")
    print("Paired Host  : \(host.display)")
    if let controllerAddr = controllerAddr {
        print("Controller   : \(controllerAddr.display)")
    }
    print()
}

private func printStatus(
    opened: Bool = false,
    readable: Bool = false,
    written: Bool = false,
    verified: Bool = false
) {
    print("Status")
    print("──────")
    if opened   { print("✓ Controller opened") }
    if readable { print("✓ Pairing report readable") }
    if written  { print("✓ Pairing address written") }
    if verified { print("✓ Pairing verified") }
    print()
}

func hexDump(_ data: [UInt8], label: String = "Feature Report") {
    print("\(label) (\(data.count) bytes):")
    for i in 0..<data.count {
        if i % 16 == 0 {
            print(String(format: "%04X: ", i), terminator: "")
        }
        print(String(format: "%02X ", data[i]), terminator: "")
        if i % 16 == 15 || i == data.count - 1 {
            print()
        }
    }
    print()
}

func printHelp() {
    print("DualShock 3 Pair Utility")
    print("Version \(DS3Constants.version)\n")
    print("Usage:\n")
    print("  ds3pair-macos                     Show interactive menu")
    print("  ds3pair-macos info                Show controller information")
    print("  ds3pair-macos read                Read pairing information")
    print("  ds3pair-macos inspect             Inspect controller details")
    print("  ds3pair-macos pair                Auto-discover and pair")
    print("  ds3pair-macos pair <MAC>          Pair to specific address")
    print("  ds3pair-macos unpair              Unpair controller")
    print("  ds3pair-macos monitor             Monitor input reports")
    print("  ds3pair-macos play                Bridge DS3 to virtual DS4")
    print("  ds3pair-macos ps3mode             Detect DS3 vs DS4-clone HID mode")
    print("  ds3pair-macos help                Show this help\n")
    print("Flags:\n")
    print("  --raw                             Show raw hex dumps")
    print("  --mac <MAC>                       Pair to a specific MAC address")
    print("  --pin <PIN>                       Use only this legacy pairing PIN")
    print("  --no-wireless                     Skip the wireless handshake")
    print("Examples:\n")
    print("  ds3pair-macos pair AA:BB:CC:DD:EE:FF")
    print("  ds3pair-macos pair --mac AA:BB:CC:DD:EE:FF")
    print("  ds3pair-macos pair --pin 1234     Try a clone controller's PIN")
    print("  ds3pair-macos pair --no-wireless")
    print("  ds3pair-macos info --raw")
    print("  ds3pair-macos monitor")
}
