import Foundation

enum DS3Constants {
    static let version = "0.0.4a"
    static let sonyVID: Int = 0x054C
    static let ds3PID: Int = 0x0268
    static let pairingReportID: UInt8 = 0xF5
    static let pairingReportSize = 64
    static let inputReportID: UInt8 = 0x01
    static let inputReportSize = 49

    /// Legacy pairing PINs to try during the wireless handshake, in order.
    /// Genuine controllers use "0000"; many clones use "1234" or other
    /// defaults, so we cycle through these until the link forms.
    static let pairingPINs = [
        "0000",
        "1234",
        "1111",
        "0001",
        "8888",
        "000000",
        "123456",
        "00000000",
        "12345678",
    ]
}

enum DS4Constants {
    static let sonyVID: UInt32 = 0x054C
    static let ds4v1PID: UInt32 = 0x05C4
    static let ds4v2PID: UInt32 = 0x09CC
    static let inputReportID: UInt8 = 0x01
    static let inputReportSize = 64
}
