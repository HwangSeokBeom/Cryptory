import Foundation

struct PublicTrade: Identifiable {
    let id: String
    let price: Double
    let quantity: Double
    let side: String
    let executedAt: String
}
