import Foundation
#if canImport(CoreHID)
import CoreHID
#endif

enum VirtualGamepadError: Error, CustomStringConvertible {
    case entitlementRequired
    case deviceCreationFailed
    case activationFailed(Error)

    var description: String {
        switch self {
        case .entitlementRequired:
            return """
            Virtual HID device requires the 'com.apple.developer.hid.virtual.device' entitlement.
            To use this feature you must:
              1. Join the Apple Developer Program
              2. Enable the 'DriverKit' and 'HID Virtual Device' entitlements
              3. Code-sign the binary with those entitlements
            Alternatively, disable SIP and use ad-hoc signing:
              sudo nvram boot-args="amfi_get_out_of_my_way=1"
              codesign --force --sign - .build/debug/ds3pair-macos
            """
        case .deviceCreationFailed:
            return "Failed to create virtual HID device."
        case .activationFailed(let error):
            return "Failed to activate virtual device: \(error)"
        }
    }
}

#if canImport(CoreHID)
@available(macOS 15, *)
class VirtualGamepad: NSObject, HIDVirtualDeviceDelegate, @unchecked Sendable {
    private var device: HIDVirtualDevice?
    private let vendorID: UInt32
    private let productID: UInt32
    private let productName: String

    init(vendorID: UInt32 = DS4Constants.sonyVID,
         productID: UInt32 = DS4Constants.ds4v1PID,
         productName: String = "Wireless Controller") {
        self.vendorID = vendorID
        self.productID = productID
        self.productName = productName
    }

    func start() throws {
        let descriptorData = Data(DS4HIDDescriptor.descriptor)

        let properties = HIDVirtualDevice.Properties(
            descriptor: descriptorData,
            vendorID: vendorID,
            productID: productID,
            transport: .usb,
            product: productName,
            manufacturer: "Sony Computer Entertainment",
            serialNumber: "DS3Pair-Virtual"
        )

        guard let vdev = HIDVirtualDevice(properties: properties) else {
            throw VirtualGamepadError.deviceCreationFailed
        }

        self.device = vdev

        Task {
            await vdev.activate(delegate: self)
        }
    }

    func stop() {
        device = nil
    }

    func sendInputReport(_ report: [UInt8]) async throws {
        guard let device = device else { return }
        let data = Data(report)
        try await device.dispatchInputReport(
            data: data,
            timestamp: SuspendingClock.Instant.now
        )
    }

    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedSetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        data: Data
    ) async throws {
    }

    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedGetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        maxSize: Int
    ) async throws -> Data {
        return Data(repeating: 0, count: maxSize)
    }
}
#endif
