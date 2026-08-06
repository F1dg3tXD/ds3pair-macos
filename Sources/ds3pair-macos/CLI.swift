import Foundation

// MARK: - Argument Parsing

func parseArguments() -> (command: String, args: [String], raw: Bool) {
    var raw = false
    var positional: [String] = []

    for arg in CommandLine.arguments.dropFirst() {
        if arg == "--raw" {
            raw = true
        } else {
            positional.append(arg)
        }
    }

    let command = positional.first ?? "help"
    let args = Array(positional.dropFirst())
    return (command, args, raw)
}

// MARK: - Dispatch

func execute(command: String, args: [String], raw: Bool) {
    switch command {
    case "help":
        printHelp()

    case "info", "read":
        executeInfo(raw: raw)

    case "inspect":
        executeInspect(raw: raw)

    case "pair":
        executePair(args: args, raw: raw)

    case "unpair":
        executeUnpair(raw: raw)

    case "monitor":
        executeMonitor()

    case "play":
        executePlay()

    default:
        print("Unknown command: \(command)\n")
        printHelp()
    }
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
        printStatus(opened: true, readable: true)

        if raw {
            hexDump(report)
        }
    } catch {
        print("Error: \(error)")
    }
}

private func executePair(args: [String], raw: Bool) {
    do {
        let controller = try DS3Controller()
        defer { controller.close() }

        printHeader()
        printControllerInfo(controller)

        var targetAddress: BTAddress

        if let macString = args.first {
            guard let addr = BTAddress(string: macString) else {
                print("Invalid MAC address: \(macString)")
                return
            }
            targetAddress = addr
        } else {
            print("Discovering local Bluetooth adapter...")
            if let localAddr = discoverLocalBluetoothAddress() {
                print("Found: \(localAddr.display)\n")
                targetAddress = localAddr
            } else {
                print("Could not discover local Bluetooth address.")
                print("Enter Bluetooth MAC address: ", terminator: "")
                guard let input = readLine(), let addr = BTAddress(string: input) else {
                    print("Invalid address.")
                    return
                }
                targetAddress = addr
            }
        }

        try controller.setPairedHost(targetAddress)
        let hostAfter = try controller.pairedHost()

        printBluetoothInfo(hostAfter)
        printStatus(opened: true, readable: true, written: true, verified: hostAfter == targetAddress)

        if hostAfter == targetAddress {
            print("✓ Pairing appears successful.")
        } else {
            print("⚠ Write completed, but controller reports a different host.")
        }

        if raw {
            let report = try controller.readPairingReport()
            hexDump(report)
        }
    } catch {
        print("Error: \(error)")
    }
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
    print("  ds3pair-macos info                Show controller information")
    print("  ds3pair-macos read                Read pairing information")
    print("  ds3pair-macos inspect             Inspect controller details")
    print("  ds3pair-macos pair                Auto-discover and pair")
    print("  ds3pair-macos pair <MAC>          Pair to specific address")
    print("  ds3pair-macos unpair              Unpair controller")
    print("  ds3pair-macos monitor             Monitor input reports")
    print("  ds3pair-macos play                Bridge DS3 to virtual DS4")
    print("  ds3pair-macos help                Show this help\n")
    print("Flags:\n")
    print("  --raw                             Show raw hex dumps\n")
    print("Examples:\n")
    print("  ds3pair-macos pair AA:BB:CC:DD:EE:FF")
    print("  ds3pair-macos info --raw")
    print("  ds3pair-macos monitor")
}
