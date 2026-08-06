import Foundation

struct DS4InputState {
    var lx: UInt8 = 128
    var ly: UInt8 = 128
    var rx: UInt8 = 128
    var ry: UInt8 = 128
    var l2: UInt8 = 0
    var r2: UInt8 = 0
    var hat: UInt8 = 8
    var square: Bool = false
    var cross: Bool = false
    var circle: Bool = false
    var triangle: Bool = false
    var l1: Bool = false
    var r1: Bool = false
    var l2Button: Bool = false
    var r2Button: Bool = false
    var share: Bool = false
    var options: Bool = false
    var l3: Bool = false
    var r3: Bool = false
    var ps: Bool = false
    var touchpad: Bool = false

    func toReport() -> [UInt8] {
        var report = [UInt8](repeating: 0, count: DS4Constants.inputReportSize)
        report[0] = DS4Constants.inputReportID
        report[1] = lx
        report[2] = ly
        report[3] = rx
        report[4] = ry
        report[5] = l2
        report[6] = r2

        var hatByte = hat & 0x0F
        if square  { hatByte |= 1 << 4 }
        if cross   { hatByte |= 1 << 5 }
        if circle  { hatByte |= 1 << 6 }
        if triangle { hatByte |= 1 << 7 }
        report[7] = hatByte

        var btn8: UInt8 = 0
        if l1      { btn8 |= 1 << 0 }
        if r1      { btn8 |= 1 << 1 }
        if l2Button { btn8 |= 1 << 2 }
        if r2Button { btn8 |= 1 << 3 }
        if share   { btn8 |= 1 << 4 }
        if options { btn8 |= 1 << 5 }
        if l3      { btn8 |= 1 << 6 }
        if r3      { btn8 |= 1 << 7 }
        report[8] = btn8

        var btn9: UInt8 = 0
        if ps      { btn9 |= 1 << 0 }
        if touchpad { btn9 |= 1 << 1 }
        report[9] = btn9

        return report
    }
}

struct DS3ToDS4Mapper {

    static func map(_ ds3Report: [UInt8]) -> DS4InputState {
        var state = DS4InputState()

        guard ds3Report.count >= DS3Constants.inputReportSize else { return state }

        state.lx = ds3Report[1]
        state.ly = ds3Report[2]
        state.rx = ds3Report[3]
        state.ry = ds3Report[4]

        let ds3Hat = ds3Report[5]
        state.hat = ds3Hat <= 7 ? ds3Hat : 8

        let b6 = ds3Report[6]
        let b7 = ds3Report[7]

        state.square   = (b6 >> 7) & 1 == 1
        state.cross    = (b6 >> 6) & 1 == 1
        state.circle   = (b6 >> 5) & 1 == 1
        state.triangle = (b6 >> 4) & 1 == 1
        state.l1       = (b6 >> 2) & 1 == 1
        state.r1       = (b6 >> 3) & 1 == 1
        state.l2Button = (b6 >> 0) & 1 == 1
        state.r2Button = (b6 >> 1) & 1 == 1

        state.share  = (b7 >> 0) & 1 == 1
        state.l3     = (b7 >> 1) & 1 == 1
        state.r3     = (b7 >> 2) & 1 == 1
        state.options = (b7 >> 3) & 1 == 1
        state.ps     = (b7 >> 4) & 1 == 1

        if ds3Report.count > 19 {
            state.l2 = ds3Report[19]
            state.r2 = ds3Report[20]
        } else {
            state.l2 = state.l2Button ? 255 : 0
            state.r2 = state.r2Button ? 255 : 0
        }

        return state
    }

    static func mapToReport(_ ds3Report: [UInt8]) -> [UInt8] {
        map(ds3Report).toReport()
    }
}
