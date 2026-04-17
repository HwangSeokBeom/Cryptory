import Foundation

struct PublicTrade: Identifiable {
    let id: String
    let price: Double
    let quantity: Double
    let side: String
    let executedAt: String
    let executedDate: Date?

    init(
        id: String,
        price: Double,
        quantity: Double,
        side: String,
        executedAt: String,
        executedDate: Date? = nil
    ) {
        self.id = id
        self.price = price
        self.quantity = quantity
        self.side = side
        self.executedAt = executedAt
        self.executedDate = executedDate
    }
}
