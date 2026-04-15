import Foundation

struct OrderRecord: Identifiable {
    let id: String
    let symbol: String
    let side: String
    let price: Double
    let qty: Double
    let total: Double
    let time: String
    let exchange: String
    let status: String
}
