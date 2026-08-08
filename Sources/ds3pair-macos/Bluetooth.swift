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
