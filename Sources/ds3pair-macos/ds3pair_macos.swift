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
    
    static func macString(from bytes: ArraySlice<UInt8>) -> String {
        bytes.map { String(format: "%02X", $0) }
            .joined(separator: ":")
    }
    
    static func parseMAC(_ string: String) -> [UInt8]? {
        let parts = string.split(separator: ":")
        
        guard parts.count == 6 else {
            return nil
        }
        
        var mac: [UInt8] = []
        
        for part in parts {
            guard let value = UInt8(part, radix: 16) else {
                return nil
            }
            mac.append(value)
        }
        
        return mac
    }
    
    static func readPairingReport(device: IOHIDDevice) -> [UInt8]? {
        
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = 0xF5
        
        var length = report.count
        
        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            CFIndex(report[0]),
            &report,
            &length
        )
        
        guard result == kIOReturnSuccess else {
            return nil
        }
        
        return report
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
        
        guard var report = readPairingReport(device: ds3) else {
            print("Failed to read pairing report.")
            return
        }
        
        print()
        print("Current paired host:")
        print(macString(from: report[2...7]))
        print()
        
        hexDump(report, length: report.count)
        
        let args = CommandLine.arguments
        
        guard args.count >= 2 else {
            print("""
        Usage:
        
          ds3pair-macos read
          ds3pair-macos pair AA:BB:CC:DD:EE:FF
        """)
            return
        }
        
        switch args[1].lowercased() {
            
        case "read":
            
            break
            
        case "pair":
            
            guard args.count >= 3 else {
                print("Missing Bluetooth MAC address.")
                return
            }
            
            guard let mac = parseMAC(args[2]) else {
                print("Invalid MAC address.")
                return
            }
            
            report[0] = 0x01
            report[1] = 0x00
            
            for i in 0..<6 {
                report[2 + i] = mac[i]
            }
            
            var writeReport = Array(report[0..<8])
            
            let writeResult = IOHIDDeviceSetReport(
                ds3,
                kIOHIDReportTypeFeature,
                0xF5,
                &writeReport,
                writeReport.count
            )
            
            print()
            print("Write Result:")
            print(writeResult)
            
            if let verify = readPairingReport(device: ds3) {
                
                print()
                print("Controller now reports paired host:")
                print(macString(from: verify[2...7]))
                
                if verify[2...7].elementsEqual(mac) {
                    print()
                    print("✓ Pairing appears successful.")
                } else {
                    print()
                    print("⚠ Write completed, but the controller still reports a different host.")
                }
                
            } else {
                print("Could not verify write.")
            }
            
        default:
            
            print("Unknown command.")
        }
    }
}
