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

    init(device: IOHIDDevice) throws {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw DS3Error.openFailed(result)
        }
        self.hidManager = nil
        self.device = device
        self.monitorSession = nil
    }

    convenience init() throws {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(manager, nil)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            throw DS3Error.deviceNotFound
        }

        guard let found = devices.first(where: { DS3Controller.isDS3($0) }) else {
            throw DS3Error.deviceNotFound
        }

        try self.init(device: found)
        self.hidManager = manager
    }

    static func isDS3(_ device: IOHIDDevice) -> Bool {
        let vid: Int = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid: Int = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        return vid == DS3Constants.sonyVID && pid == DS3Constants.ds3PID
    }

    /// Every HID interface belonging to the controller. Clones expose two
    /// (a "PS3 Controller" and a plain "HID" interface — SDL0/SDL1); the
    /// genuine DS3 exposes one.
    static func allDS3Devices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(manager, nil)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }
        return devices.filter { isDS3($0) }
    }

    /// Product name for a raw device handle (e.g. "PS3 Controller", "HID").
    static func productName(of device: IOHIDDevice) -> String {
        (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "HID"
    }

    func close() {
        stopMonitoring()
        if let device = device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            self.device = nil
        }
    }

    /// The raw HID report descriptor, used to fingerprint the controller's
    /// current HID personality (DS3 vs DS4-clone mask).
    func reportDescriptor() -> [UInt8]? {
        guard let device = device else { return nil }
        guard let data = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data else {
            return nil
        }
        return Array(data)
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

    /// The stored Bluetooth link key (16 bytes) read from the pairing report.
    /// All zeros means the controller has no key yet and will negotiate a fresh
    /// legacy pairing (PIN exchange) on its next wireless connection.
    func linkKey() throws -> [UInt8] {
        let report = try readPairingReport()
        guard report.count >= 32 else { return [] }
        return Array(report[16..<32])
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
    }

    // MARK: - Monitor

    func startMonitoring(callback: @escaping ([UInt8]) -> Void) throws {
        guard let device = device else { throw DS3Error.deviceNotFound }

        let session = MonitorSession(callback: callback)
        self.monitorSession = session

        let context = Unmanaged.passUnretained(session).toOpaque()

        // The device must be scheduled on a run loop or IOKit never delivers
        // input reports to the callback — monitoring (and the pressure probe)
        // would silently collect zero samples.
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        IOHIDDeviceRegisterInputReportCallback(
            device,
            session.buffer,
            CFIndex(session.bufferSize),
            ds3MonitorCallback,
            context
        )
    }

    func stopMonitoring() {
        if let device = device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
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
