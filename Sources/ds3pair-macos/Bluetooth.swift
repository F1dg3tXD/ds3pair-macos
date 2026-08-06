import Foundation

#if canImport(IOBluetooth)
import IOBluetooth
#endif

func discoverLocalBluetoothAddress() -> BTAddress? {
    #if canImport(IOBluetooth)
    guard let controller = IOBluetoothHostController.default() else { return nil }
    guard let raw = controller.addressAsString() else { return nil }
    let normalized = raw.replacingOccurrences(of: "-", with: ":")
    return BTAddress(string: normalized)
    #else
    return nil
    #endif
}

func registerPairing(with address: BTAddress) -> Bool {
    #if canImport(IOBluetooth)
    guard let device = IOBluetoothDevice(addressString: address.display) else { return false }
    let pair = IOBluetoothDevicePair()
    pair.setDevice(device)
    let result = pair.start()
    return result == kIOReturnSuccess
    #else
    return false
    #endif
}
