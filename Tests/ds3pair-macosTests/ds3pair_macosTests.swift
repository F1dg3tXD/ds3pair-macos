import Testing
@testable import ds3pair_macos

@Test func btAddressDisplay() {
    let addr = BTAddress(bytes: [0x1C, 0x91, 0x80, 0xD1, 0xB7, 0xCD])
    #expect(addr.display == "1C:91:80:D1:B7:CD")
}

@Test func btAddressParse() {
    let addr = BTAddress(string: "AA:BB:CC:DD:EE:FF")
    #expect(addr != nil)
    #expect(addr?.bytes == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
}

@Test func btAddressParseInvalid() {
    #expect(BTAddress(string: "not-a-mac") == nil)
    #expect(BTAddress(string: "AA:BB:CC:DD:EE") == nil)
    #expect(BTAddress(string: "AA:BB:CC:DD:EE:FF:GG") == nil)
}

@Test func btAddressZero() {
    #expect(BTAddress.zero.isZero)
    #expect(!BTAddress(string: "AA:BB:CC:DD:EE:FF")!.isZero)
}

@Test func btAddressReportRoundTrip() {
    let original = BTAddress(bytes: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
    let reportBytes = original.reportBytes
    let restored = BTAddress.fromReportBytes(reportBytes)
    #expect(original == restored)
}

@Test func btAddressSonyByteOrder() {
    let addr = BTAddress(bytes: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
    let reportBytes = addr.reportBytes
    #expect(reportBytes == [0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA])
}

@Test func btAddressEquality() {
    let a = BTAddress(bytes: [1, 2, 3, 4, 5, 6])
    let b = BTAddress(bytes: [1, 2, 3, 4, 5, 6])
    let c = BTAddress(bytes: [1, 2, 3, 4, 5, 7])
    #expect(a == b)
    #expect(a != c)
}

// MARK: - DS3→DS4 Mapper Tests

func makeDS3Report(
    lx: UInt8 = 128, ly: UInt8 = 128,
    rx: UInt8 = 128, ry: UInt8 = 128,
    hat: UInt8 = 8,
    b6: UInt8 = 0, b7: UInt8 = 0,
    l2Pressure: UInt8 = 0, r2Pressure: UInt8 = 0
) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 49)
    report[0] = 0x01
    report[1] = lx
    report[2] = ly
    report[3] = rx
    report[4] = ry
    report[5] = hat
    report[6] = b6
    report[7] = b7
    report[19] = l2Pressure
    report[20] = r2Pressure
    return report
}

@Test func ds4MapperNeutralSticks() {
    let report = DS3ToDS4Mapper.mapToReport(makeDS3Report())
    #expect(report[1] == 128)
    #expect(report[2] == 128)
    #expect(report[3] == 128)
    #expect(report[4] == 128)
    #expect(report[5] == 0)
    #expect(report[6] == 0)
}

@Test func ds4MapperFullDeflection() {
    let report = DS3ToDS4Mapper.mapToReport(makeDS3Report(lx: 0, ly: 255, rx: 255, ry: 0))
    #expect(report[1] == 0)
    #expect(report[2] == 255)
    #expect(report[3] == 255)
    #expect(report[4] == 0)
}

@Test func ds4MapperButtons() {
    let b6: UInt8 = (1 << 7) | (1 << 6) | (1 << 5) | (1 << 4) | (1 << 2) | (1 << 3) | (1 << 0) | (1 << 1)
    let report = DS3ToDS4Mapper.mapToReport(makeDS3Report(b6: b6))
    #expect(bitIsSetPublic(report[7], 4))
    #expect(bitIsSetPublic(report[7], 5))
    #expect(bitIsSetPublic(report[7], 6))
    #expect(bitIsSetPublic(report[7], 7))
    #expect(bitIsSetPublic(report[8], 0))
    #expect(bitIsSetPublic(report[8], 1))
    #expect(bitIsSetPublic(report[8], 2))
    #expect(bitIsSetPublic(report[8], 3))
}

@Test func ds4MapperSystemButtons() {
    let b7: UInt8 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
    let report = DS3ToDS4Mapper.mapToReport(makeDS3Report(b7: b7))
    #expect(bitIsSetPublic(report[8], 4))
    #expect(bitIsSetPublic(report[8], 5))
    #expect(bitIsSetPublic(report[8], 6))
    #expect(bitIsSetPublic(report[8], 7))
    #expect(bitIsSetPublic(report[9], 0))
}

@Test func ds4MapperDpadHat() {
    let report0 = DS3ToDS4Mapper.mapToReport(makeDS3Report(hat: 0))
    #expect((report0[7] & 0x0F) == 0)
    let report3 = DS3ToDS4Mapper.mapToReport(makeDS3Report(hat: 3))
    #expect((report3[7] & 0x0F) == 3)
    let reportNeutral = DS3ToDS4Mapper.mapToReport(makeDS3Report(hat: 8))
    #expect((reportNeutral[7] & 0x0F) == 8)
}

@Test func ds4MapperTriggers() {
    let report = DS3ToDS4Mapper.mapToReport(makeDS3Report(l2Pressure: 200, r2Pressure: 128))
    #expect(report[5] == 200)
    #expect(report[6] == 128)
}

@Test func ds4MapperReportSize() {
    let report = DS3ToDS4Mapper.mapToReport(makeDS3Report())
    #expect(report.count == 64)
    #expect(report[0] == 0x01)
}

@Test func ds4MapperUndershoot() {
    let report = DS3ToDS4Mapper.mapToReport([UInt8](repeating: 0, count: 10))
    #expect(report[1] == 128)
    #expect(report[2] == 128)
}

func bitIsSetPublic(_ byte: UInt8, _ bit: Int) -> Bool {
    (byte >> bit) & 1 == 1
}

// MARK: - Board Revision Tests

func makePairingReport(byte14: UInt8 = 0x01, byte15: UInt8 = 0xA0) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 0xF5
    report[14] = byte14
    report[15] = byte15
    return report
}

@Test func boardRevisionA1() {
    #expect(decodeBoardRevision(makePairingReport(byte15: 0xA0)) == "A1")
}

@Test func boardRevisionA2() {
    #expect(decodeBoardRevision(makePairingReport(byte15: 0xA1)) == "A2")
}

@Test func boardRevisionB1() {
    #expect(decodeBoardRevision(makePairingReport(byte15: 0xB0)) == "B1")
}

@Test func boardRevisionC4() {
    #expect(decodeBoardRevision(makePairingReport(byte15: 0xC3)) == "C4")
}

@Test func boardRevisionUnknownShowsHex() {
    #expect(decodeBoardRevision(makePairingReport(byte14: 0x02, byte15: 0x42)) == "0x0242")
}

@Test func boardRevisionShortReport() {
    #expect(decodeBoardRevision([0xF5, 0x01]) == "Unknown")
}
