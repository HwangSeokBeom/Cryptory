import Foundation

struct CandleData: Identifiable, Equatable {
    let id = UUID()
    let time: Int
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int

    static func == (lhs: CandleData, rhs: CandleData) -> Bool {
        lhs.time == rhs.time
            && lhs.open == rhs.open
            && lhs.high == rhs.high
            && lhs.low == rhs.low
            && lhs.close == rhs.close
            && lhs.volume == rhs.volume
    }
}
