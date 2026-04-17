import Foundation

enum StatusBadgeTone: Equatable {
    case neutral
    case success
    case warning
    case error
}

struct StatusBadgeViewState: Identifiable, Equatable {
    var id: String { title }

    let title: String
    let tone: StatusBadgeTone
}

enum RemoteErrorCategory: Equatable {
    case authenticationFailed
    case permissionDenied
    case rateLimited
    case maintenance
    case staleData
    case connectivity
    case unknown
}

enum DataRefreshMode: Equatable {
    case streaming
    case pollingFallback
    case snapshot
}

enum StreamingStatus: Equatable {
    case live
    case pollingFallback
    case disconnected
    case snapshotOnly
}

struct ScreenStatusViewState: Equatable {
    let badges: [StatusBadgeViewState]
    let message: String?
    let lastUpdatedText: String?
    let refreshMode: DataRefreshMode

    static let idle = ScreenStatusViewState(
        badges: [],
        message: nil,
        lastUpdatedText: nil,
        refreshMode: .snapshot
    )
}

struct KimchiPremiumExchangeCellViewState: Identifiable, Equatable {
    var id: String { exchange.rawValue }

    let exchange: Exchange
    let premiumText: String
    let domesticPriceText: String
    let referencePriceText: String
    let warningMessage: String?
    let isStale: Bool
}

struct KimchiPremiumCoinViewState: Identifiable, Equatable {
    var id: String { symbol }

    let symbol: String
    let displayName: String
    let referenceLabel: String
    let cells: [KimchiPremiumExchangeCellViewState]
}
