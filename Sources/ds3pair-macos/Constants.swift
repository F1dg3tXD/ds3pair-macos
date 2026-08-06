import Foundation

enum DS3Constants {
    static let version = "0.0.3a"
    static let sonyVID: Int = 0x054C
    static let ds3PID: Int = 0x0268
    static let pairingReportID: UInt8 = 0xF5
    static let pairingReportSize = 64
    static let inputReportID: UInt8 = 0x01
    static let inputReportSize = 49
}

enum DS4Constants {
    static let sonyVID: UInt32 = 0x054C
    static let ds4v1PID: UInt32 = 0x05C4
    static let ds4v2PID: UInt32 = 0x09CC
    static let inputReportID: UInt8 = 0x01
    static let inputReportSize = 64
}
