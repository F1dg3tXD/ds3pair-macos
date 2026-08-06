import Foundation

struct BTAddress: Equatable, Sendable {
    let bytes: [UInt8]

    init(bytes: [UInt8]) {
        precondition(bytes.count == 6, "BTAddress requires exactly 6 bytes")
        self.bytes = bytes
    }

    var display: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    init?(string: String) {
        let parts = string
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ":")
            .map(String.init)
        guard parts.count == 6 else { return nil }
        var result: [UInt8] = []
        for part in parts {
            guard let value = UInt8(part, radix: 16) else { return nil }
            result.append(value)
        }
        self.bytes = result
    }

    var isZero: Bool {
        bytes.allSatisfy { $0 == 0 }
    }

    static let zero = BTAddress(bytes: [UInt8](repeating: 0, count: 6))

    var reportBytes: [UInt8] {
        bytes.reversed()
    }

    static func fromReportBytes(_ data: [UInt8]) -> BTAddress {
        BTAddress(bytes: Array(data.prefix(6)).reversed())
    }
}
