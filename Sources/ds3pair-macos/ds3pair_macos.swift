// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation
import Darwin
import CoreFoundation
import IOKit
import IOKit.hid

@main
struct DS3PairMacOS {

    static let sonyVID = 0x054C
    static let ds3PID  = 0x0268

    static func property<T>(_ device: IOHIDDevice, key: CFString) -> T? {
        IOHIDDeviceGetProperty(device, key) as? T
    }

    static func hexDump(_ data: [UInt8], length: Int) {
        print("\nFeature Report (\(length) bytes):")

        for i in 0..<length {
            if i % 16 == 0 {
                print(String(format: "%04X: ", i), terminator: "")
            }

            print(String(format: "%02X ", data[i]), terminator: "")

            if i % 16 == 15 || i == length - 1 {
                print()
            }
        }
    }

    static func main() {

        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )

        IOHIDManagerSetDeviceMatching(manager, nil)

//        let openResult = IOHIDManagerOpen(
//            manager,
//            IOOptionBits(kIOHIDOptionsTypeNone)
//        )
//
//        guard openResult == kIOReturnSuccess else {
//            print(String(format: "Failed to open HID Manager: 0x%08X", openResult))
//            return
//        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            print("No HID devices.")
            return
        }

        guard let ds3 = devices.first(where: {
            let vid: Int = property($0, key: kIOHIDVendorIDKey as CFString) ?? 0
            let pid: Int = property($0, key: kIOHIDProductIDKey as CFString) ?? 0
            return vid == sonyVID && pid == ds3PID
        }) else {
            print("DualShock 3 not found.")
            return
        }

        print("Found DualShock 3!")

        let result = IOHIDDeviceOpen(
            ds3,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )

        guard result == kIOReturnSuccess else {
            print("Failed to open controller: \(result)")
            return
        }

        print("Successfully opened controller.")

        var report = [UInt8](repeating: 0, count: 64)
        report[0] = 0xF5

        var reportLength = report.count

        let readResult = IOHIDDeviceGetReport(
            ds3,
            kIOHIDReportTypeFeature,
            CFIndex(report[0]),
            &report,
            &reportLength
        )

        if readResult == kIOReturnSuccess {
            print("Successfully read Feature Report 0xF5")
            hexDump(report, length: reportLength)
        } else {
            print("Failed to read Feature Report.")
            print("IOReturn = \(readResult)")
        }

        IOHIDDeviceClose(
            ds3,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )

        IOHIDManagerClose(
            manager,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
    }
}
