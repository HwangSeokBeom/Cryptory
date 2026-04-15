import Foundation

enum ExchangeConnectionPermission: String, CaseIterable {
    case readOnly = "read_only"
    case tradeEnabled = "trade_enabled"

    var title: String {
        switch self {
        case .readOnly:
            return "조회 전용"
        case .tradeEnabled:
            return "주문 가능"
        }
    }

    var description: String {
        switch self {
        case .readOnly:
            return "잔고와 체결 내역만 조회할 수 있어요."
        case .tradeEnabled:
            return "잔고 조회와 주문 실행을 모두 사용할 수 있어요."
        }
    }
}

struct ExchangeConnection: Identifiable {
    let id: String
    let exchange: Exchange
    let permission: ExchangeConnectionPermission
    let nickname: String?
    let isActive: Bool
    let updatedAt: String?
}

struct ExchangeConnectionCreateRequest {
    let exchange: Exchange
    let apiKey: String
    let secret: String
    let permission: ExchangeConnectionPermission
    let nickname: String?
}

struct ExchangeConnectionCRUDCapability {
    let canCreate: Bool
    let canDelete: Bool

    static let readOnly = ExchangeConnectionCRUDCapability(canCreate: false, canDelete: false)
}
