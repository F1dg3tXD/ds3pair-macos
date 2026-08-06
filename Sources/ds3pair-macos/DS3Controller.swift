import Foundation
import IOKit
import IOKit.hid

enum DS3Error: Error, CustomStringConvertible {
    case deviceNotFound
    case openFailed(IOReturn)
    case reportReadFailed(IOReturn)
    case reportWriteFailed(IOReturn)

    var description: String {
        switch self {
        case .deviceNotFound:
            return "DualShock 3 controller not found. Make sure it is connected via USB."
        case .openFailed(let code):
            return "Failed to open controller (error: 0x\(String(code, radix: 16, uppercase: true)))."
        case .reportReadFailed(let code):
            return "Failed to read report (error: 0x\(String(code, radix: 16, uppercase: true)))."
        case .reportWriteFailed(let code):
            return "Failed to write report (error: 0x\(String(code, radix: 16, uppercase: true)))."
        }
    }
}

class DS3Controller: @unchecked Sendable {
    private var hidManager: IOHIDManager?
    private var device: IOHIDDevice?
    private var monitorSession: MonitorSession?

    init() throws {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(manager, nil)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            throw DS3Error.deviceNotFound
        }

        guard let found = devices.first(where: {
            let vid: Int = IOHIDDeviceGetProperty($0, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let pid: Int = IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? Int ?? 0
            return vid == DS3Constants.sonyVID && pid == DS3Constants.ds3PID
        }) else {
            throw DS3Error.deviceNotFound
        }

        let result = IOHIDDeviceOpen(found, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw DS3Error.openFailed(result)
        }

        self.hidManager = manager
        self.device = found
    }

    func close() {
        if let device = device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            self.device = nil
        }
        monitorSession = nil
    }

    deinit { close() }

    // MARK: - Properties

    private func getProperty<T>(_ key: String) -> T? {
        guard let device = device else { return nil }
        return IOHIDDeviceGetProperty(device, key as CFString) as? T
    }

    var manufacturer: String {
        getProperty(kIOHIDManufacturerKey) ?? "Unknown"
    }

    var product: String {
        getProperty(kIOHIDProductKey) ?? "Unknown"
    }

    var vendorID: Int {
        getProperty(kIOHIDVendorIDKey) ?? 0
    }

    var productID: Int {
        getProperty(kIOHIDProductIDKey) ?? 0
    }

    var transport: String {
        let value: String? = getProperty(kIOHIDTransportKey)
        return value ?? "Unknown"
    }

    var boardRevision: String {
        guard let report = try? readPairingReport() else { return "Unknown" }
        return decodeBoardRevision(report)
    }

    var battery: String {
        let level: NSNumber? = getProperty("BatteryLevel")
        if let level = level {
            return "\(level.intValue)%"
        }
        return transport == "USB" ? "Charging" : "Unknown"
    }

    // MARK: - Feature Reports

    func readPairingReport() throws -> [UInt8] {
        guard let device = device else { throw DS3Error.deviceNotFound }

        var report = [UInt8](repeating: 0, count: DS3Constants.pairingReportSize)
        report[0] = DS3Constants.pairingReportID
        var length = report.count

        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            CFIndex(report[0]),
            &report,
            &length
        )

        guard result == kIOReturnSuccess else {
            throw DS3Error.reportReadFailed(result)
        }

        return report
    }

    func writeFeatureReport(_ report: [UInt8]) throws {
        guard let device = device else { throw DS3Error.deviceNotFound }

        var buffer = report
        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeFeature,
            CFIndex(DS3Constants.pairingReportID),
            &buffer,
            buffer.count
        )

        guard result == kIOReturnSuccess else {
            throw DS3Error.reportWriteFailed(result)
        }
    }

    // MARK: - Bluetooth Address

    func pairedHost() throws -> BTAddress {
        let report = try readPairingReport()
        return BTAddress.fromReportBytes(Array(report[2...7]))
    }

    func controllerAddress() throws -> BTAddress {
        let report = try readPairingReport()
        return BTAddress.fromReportBytes(Array(report[8...13]))
    }

    func setPairedHost(_ address: BTAddress) throws {
        var report = try readPairingReport()
        report[0] = 0x01
        report[1] = 0x00
        let addrBytes = address.reportBytes
        for i in 0..<6 {
            report[2 + i] = addrBytes[i]
        }
        try writeFeatureReport(Array(report[0..<8]))

        let controllerAddr = try controllerAddress()
        _ = registerPairing(with: controllerAddr)
    }

    // MARK: - Monitor

    func startMonitoring(callback: @escaping ([UInt8]) -> Void) throws {
        guard let device = device else { throw DS3Error.deviceNotFound }

        let session = MonitorSession(callback: callback)
        self.monitorSession = session

        let context = Unmanaged.passUnretained(session).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(
            device,
            session.buffer,
            CFIndex(session.bufferSize),
            ds3MonitorCallback,
            context
        )
    }

    func stopMonitoring() {
        monitorSession = nil
    }
}

// MARK: - Monitor Session

class MonitorSession: @unchecked Sendable {
    let buffer: UnsafeMutablePointer<UInt8>
    let bufferSize: Int
    let callback: ([UInt8]) -> Void

    init(bufferSize: Int = 64, callback: @escaping ([UInt8]) -> Void) {
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        self.bufferSize = bufferSize
        self.buffer.initialize(repeating: 0, count: bufferSize)
        self.callback = callback
    }

    deinit {
        buffer.deinitialize(count: bufferSize)
        buffer.deallocate()
    }
}

private let ds3MonitorCallback: IOHIDReportCallback = { context, _, _, _, _, report, length in
    guard let context = context else { return }
    let session = Unmanaged<MonitorSession>.fromOpaque(context).takeUnretainedValue()
    let data = Array(UnsafeBufferPointer(
        start: report,
        count: Int(length)
    ))
    session.callback(data)
}

// MARK: - Board Revision

func decodeBoardRevision(_ report: [UInt8]) -> String {
    guard report.count >= 16 else { return "Unknown" }
    let raw = (UInt16(report[14]) << 8) | UInt16(report[15])
    let code = report[15]
    let generation = code >> 4
    if report[14] == 0x01, generation == 0xA || generation == 0xB || generation == 0xC {
        let gen = UnicodeScalar(55 + Int(generation)).map { Character($0) } ?? "?"
        let rev = Int(code & 0x0F) + 1
        return "\(gen)\(rev)"
    }
    return String(format: "0x%04X", raw)
}
