import Foundation
import IOBluetooth

enum PS3PairError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): return message
        }
    }
}

/// Registers the controller with the macOS Bluetooth stack by performing the
/// system pairing and supplying the DS3's legacy pairing PIN on its behalf.
///
/// The DualShock 3 predates Secure Simple Pairing and expects a legacy PIN
/// ("0000"). The system would normally stop and ask the user for it; this
/// translation layer answers automatically so the controller ends up properly
/// paired and can reconnect wirelessly.
final class SystemPairer: NSObject, IOBluetoothDevicePairDelegate {
    private var pair: IOBluetoothDevicePair?
    private var isFinished = false
    private var pairError: IOReturn = kIOReturnSuccess
    private var currentPIN = "0000"
    private var lastError: IOReturn = kIOReturnSuccess
    private var lastAttemptTimedOut = false

    /// The PIN that successfully paired, if any.
    private(set) var lastSuccessfulPIN: String?

    /// Retries the system pairing until the controller is registered or the
    /// deadline passes, cycling through `pinList` so clones that use a legacy
    /// PIN other than "0000" still have a chance. The controller only answers
    /// pages while it is powered on and (for genuine units) off USB, so we keep
    /// retrying while the user holds the PS button.
    ///
    /// If macOS's Bluetooth daemon rejects the controller instantly three times
    /// in a row (typical of clones that use unencrypted/non-standard links), we
    /// abort early instead of wasting the whole timeout — no PIN can change a
    /// daemon-level rejection.
    func pairPersistent(
        with address: BTAddress,
        pinList: [String],
        timeout: TimeInterval = 90
    ) -> Result<Void, PS3PairError> {
        if let device = IOBluetoothDevice(addressString: address.display), device.isConnected() {
            return .success(())
        }
        guard !pinList.isEmpty else {
            return .failure(.message("No pairing PINs provided."))
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastMessage = "System pairing failed."
        var attempts = 0
        var pinIndex = 0
        var consecutiveRejects = 0

        while Date() < deadline {
            let pin = pinList[pinIndex % pinList.count]
            pinIndex += 1
            attempts += 1
            print("Attempt \(attempts): pairing with PIN \(pin)...")

            let started = Date()
            switch pair(with: address, pin: pin, timeout: 12) {
            case .success:
                lastSuccessfulPIN = pin
                return .success(())
            case .failure(let message):
                lastMessage = message.description
                print("   → \(message.description)")
            }
            let elapsed = Date().timeIntervalSince(started)

            if !lastAttemptTimedOut && lastError != kIOReturnOffline && elapsed < 6 {
                consecutiveRejects += 1
            } else {
                consecutiveRejects = 0
            }

            if consecutiveRejects >= 3 {
                return .failure(.message(
                    "macOS's Bluetooth stack rejected this controller three times in a row " +
                    "(\(lastMessage)). This is typical of clone controllers that macOS refuses " +
                    "to pair wirelessly — no PIN can fix it. Use the `play` command to bridge " +
                    "the controller over USB, or pair it with a Linux host (BlueZ sixaxis)."
                ))
            }

            Thread.sleep(forTimeInterval: 0.75)
        }

        let covered = pinIndex < pinList.count ? Array(pinList[0..<pinIndex]) : pinList
        let tried = covered.isEmpty ? "" : " Tried PINs: \(covered.joined(separator: ", "))"
        return .failure(.message(
            "No wireless link after \(Int(timeout))s. \(lastMessage)\(tried)"
        ))
    }

    func pair(
        with address: BTAddress,
        pin: String = "0000",
        timeout: TimeInterval = 12
    ) -> Result<Void, PS3PairError> {
        guard let device = IOBluetoothDevice(addressString: address.display) else {
            return .failure(.message("Could not resolve controller address \(address.display)"))
        }

        currentPIN = pin
        lastError = kIOReturnSuccess
        lastAttemptTimedOut = false

        let pair = IOBluetoothDevicePair()
        pair.setDevice(device)
        pair.delegate = self
        self.pair = pair
        self.isFinished = false
        self.pairError = kIOReturnSuccess

        let result = pair.start()
        guard result == kIOReturnSuccess else {
            self.pair = nil
            lastError = result
            return .failure(.message("Could not start system pairing (\(describe(result)))."))
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !isFinished && Date() < deadline {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.25, true)
        }

        self.pair = nil

        guard isFinished else {
            lastError = kIOReturnTimeout
            lastAttemptTimedOut = true
            return .failure(.message("System pairing timed out after \(Int(timeout))s."))
        }
        lastError = pairError
        guard pairError == kIOReturnSuccess else {
            return .failure(.message("System pairing failed (\(describe(pairError)))."))
        }
        return .success(())
    }

    // MARK: - IOBluetoothDevicePairDelegate

    func devicePairingStarted(_ sender: Any) {
        print("   Pairing started...")
    }

    func devicePairingConnected(_ sender: Any) {
        print("   Connected to controller...")
    }

    func devicePairingPINCodeRequest(_ sender: Any) {
        guard let pair = pair else { return }
        print("   Supplying legacy pairing PIN \(currentPIN)...")
        var pin = BluetoothPINCode()
        withUnsafeMutableBytes(of: &pin) { raw in
            raw.copyBytes(from: currentPIN.utf8)
        }
        pair.replyPINCode(currentPIN.count, pinCode: &pin)
    }

    func devicePairingFinished(_ sender: Any, error: IOReturn) {
        pairError = error
        isFinished = true
    }
}

private func describe(_ error: IOReturn) -> String {
    switch error {
    case kIOReturnOffline:
        return "kIOReturnOffline (controller not responding to pages)"
    case kIOReturnTimeout:
        return "kIOReturnTimeout"
    case kIOReturnSuccess:
        return "kIOReturnSuccess"
    default:
        return String(format: "0x%08X", error)
    }
}
