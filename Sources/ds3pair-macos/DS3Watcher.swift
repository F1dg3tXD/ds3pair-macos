import Foundation
import IOKit
import IOKit.hid

final class DS3Watcher: @unchecked Sendable {
    private var hidManager: IOHIDManager?
    private var appearHandler: ((IOHIDDevice) -> Void)?

    func start() throws {
        guard hidManager == nil else { return }

        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: DS3Constants.sonyVID,
            kIOHIDProductIDKey as String: DS3Constants.ds3PID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            ds3MatchCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )

        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw DS3Error.openFailed(result)
        }

        hidManager = manager
    }

    func stop() {
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        appearHandler = nil
    }

    func currentDevices() -> Set<IOHIDDevice> {
        guard let manager = hidManager,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        else { return [] }
        return devices
    }

    func waitForDisconnect() {
        while !currentDevices().isEmpty {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.25, true)
        }
    }

    func waitForAppearance() -> IOHIDDevice? {
        var found: IOHIDDevice?
        appearHandler = { device in
            if found == nil { found = device }
        }

        while found == nil {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.25, true)
        }

        appearHandler = nil
        return found
    }

    fileprivate func deviceAppeared(_ device: IOHIDDevice) {
        appearHandler?(device)
    }
}

private let ds3MatchCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context = context else { return }
    let watcher = Unmanaged<DS3Watcher>.fromOpaque(context).takeUnretainedValue()
    watcher.deviceAppeared(device)
}
