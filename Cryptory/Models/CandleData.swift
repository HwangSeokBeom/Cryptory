import Foundation

struct CandleData: Identifiable {
    let id = UUID()
    let time: Int
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
}
