import SwiftUI
import Combine
import AuthenticationServices
import UIKit

enum ScreenAccessRequirement: String, Equatable {
    case publicAccess = "public access"
    case authenticatedRequired = "authenticated required"
}

enum Tab: String, CaseIterable, Equatable {
    case market
    case chart
    case trade
    case portfolio
    case kimchi

    var systemImage: String {
        switch self {
        case .market: return "chart.line.uptrend.xyaxis"
        case .chart: return "chart.xyaxis.line"
        case .trade: return "arrow.left.arrow.right.circle"
        case .portfolio: return "wallet.pass"
        case .kimchi: return "flame"
        }
    }

    var title: String {
        switch self {
        case .market: return "시세"
        case .chart: return "차트"
        case .trade: return "주문"
        case .portfolio: return "자산"
        case .kimchi: return "김프"
        }
    }

    var accessRequirement: ScreenAccessRequirement {
        switch self {
        case .market, .chart, .kimchi:
            return .publicAccess
        case .trade, .portfolio:
            return .authenticatedRequired
        }
    }

    var showsExchangeSelector: Bool {
        switch self {
        case .market, .chart, .trade:
            return true
        case .portfolio, .kimchi:
            return false
        }
    }

    var protectedFeature: ProtectedFeature? {
        switch self {
        case .portfolio:
            return .portfolio
        case .trade:
            return .trade
        case .market, .chart, .kimchi:
            return nil
        }
    }
}

enum MarketFilter: String, CaseIterable {
    case all
    case fav

    var title: String {
        switch self {
        case .all: return "전체"
        case .fav: return "관심"
        }
    }
}

enum OrderSide: String, Hashable {
    case buy
    case sell
}

enum OrderType: String, CaseIterable, Equatable, Hashable {
    case limit
    case market

    var title: String {
        switch self {
        case .limit:
            return "지정가"
        case .market:
            return "시장가"
        }
    }
}

enum NotifType {
    case success
    case error
}

enum SocialSignInMethod: String, Equatable {
    case google
    case apple

    var title: String {
        switch self {
        case .google:
            return "Google"
        case .apple:
            return "Apple"
        }
    }
}

private struct ChartRequestContext: Equatable {
    let marketIdentity: MarketIdentity
    let requestedInterval: String
    let mappedInterval: String
    let window: String

    var exchange: Exchange { marketIdentity.exchange }
    var symbol: String { marketIdentity.symbol }
    var marketId: String? { marketIdentity.marketId }
}

private struct ChartRequestKey: Hashable, Equatable {
    let marketIdentity: MarketIdentity
    let interval: String
    let window: String

    var debugValue: String {
        "\(marketIdentity.cacheKey)|\(interval)|\(window)"
    }

    var exchange: Exchange { marketIdentity.exchange }
    var symbol: String { marketIdentity.symbol }
    var marketId: String? { marketIdentity.marketId }
}

private struct ChartResourceKey: Hashable, Equatable {
    let marketIdentity: MarketIdentity

    var debugValue: String {
        marketIdentity.cacheKey
    }

    var exchange: Exchange { marketIdentity.exchange }
    var symbol: String { marketIdentity.symbol }
    var marketId: String? { marketIdentity.marketId }
}

private struct OrderHeaderPriceCacheKey: Hashable, Equatable {
    let exchange: Exchange
    let symbol: String
}

enum OrderHeaderPriceSource: String, Equatable {
    case selectedTicker = "selected_ticker"
    case marketSnapshot = "market_snapshot"
    case graphLatestPoint = "graph_latest_point"
    case lastKnownGood = "last_known_good"
    case missing = "missing"
}

struct OrderHeaderPricePresentation: Equatable {
    let marketIdentity: MarketIdentity
    let price: Double?
    let source: OrderHeaderPriceSource
    let isFallbackApplied: Bool
    let isStale: Bool

    var secondaryText: String {
        guard price != nil else {
            return "가격 확인 중"
        }
        if source == .graphLatestPoint || source == .lastKnownGood {
            return "KRW · 최근 반영가"
        }
        return "KRW"
    }
}

private struct AssetHistoryFilterStats: Equatable {
    let rawCount: Int
    let filteredCount: Int
    let removedMockCount: Int
    let removedZeroValueCount: Int
    let removedUnknownSourceCount: Int
}

private struct CandleCacheEntry: Equatable {
    let key: ChartRequestKey
    let candles: [CandleData]
    let meta: ResponseMeta
    let fetchedAt: Date
}

private struct OrderbookCacheEntry: Equatable {
    let key: ChartResourceKey
    let orderbook: OrderbookData
    let meta: ResponseMeta
    let fetchedAt: Date
}

private struct TradesCacheEntry: Equatable {
    let key: ChartResourceKey
    let trades: [PublicTrade]
    let meta: ResponseMeta
    let fetchedAt: Date
}

private enum MarketUniverseSource: String, Equatable {
    case catalog
    case tickerSnapshot
    case cachedSnapshot
}

private struct MarketUniverseSnapshot: Equatable {
    let exchange: Exchange
    let source: MarketUniverseSource
    let serverCoins: [CoinInfo]
    let tradableCoins: [CoinInfo]
    let serverUniverseCount: Int
    let tradableCount: Int
    let droppedSymbols: [String]
    let filteredSymbols: [String]
    let pendingSymbols: [String]
    let symbolsHash: String
    let isProvisional: Bool
}

private struct MarketPresentationSnapshot: Equatable {
    let exchange: Exchange
    let generation: Int
    let universe: MarketUniverseSnapshot
    let rows: [MarketRowViewState]
    let meta: ResponseMeta
}

private struct MarketRequestContext: Equatable {
    let exchange: Exchange
    let route: Tab
    let universeVersion: String
    let generation: Int
}

private struct ScheduledHydrationContext: Equatable {
    let exchange: Exchange
    let generation: Int
}

private enum SparklineLayerSource: Equatable {
    case tickerSnapshot
    case candleSnapshot
    case stream
}

private struct SparklineLayerSnapshot: Equatable {
    let interval: String
    let points: [Double]
    let pointCount: Int
    let fetchedAt: Date
    let source: SparklineLayerSource

    nonisolated func graphState(staleInterval: TimeInterval, now: Date) -> MarketRowGraphState {
        guard MarketSparklineRenderPolicy.hasRenderableGraph(points: points, pointCount: pointCount) else {
            return .placeholder
        }
        if now.timeIntervalSince(fetchedAt) > staleInterval {
            return .staleVisible
        }
        switch source {
        case .candleSnapshot, .stream:
            return .liveVisible
        case .tickerSnapshot:
            return .cachedVisible
        }
    }
}

private struct SparklineCacheKey: Hashable, Equatable {
    let marketIdentity: MarketIdentity
    let interval: String

    var exchange: Exchange { marketIdentity.exchange }
    var symbol: String { marketIdentity.symbol }
    var marketId: String? { marketIdentity.marketId }
}

private struct MarketGraphBindingKey: Hashable, Equatable {
    let marketIdentity: MarketIdentity
    let interval: String

    var debugDescription: String {
        "\(marketIdentity.cacheKey):\(interval)"
    }

    var exchange: Exchange { marketIdentity.exchange }
    var symbol: String { marketIdentity.symbol }
    var marketId: String? { marketIdentity.marketId }
}

private struct StableSparklineDisplay: Equatable {
    let key: MarketGraphBindingKey
    let points: [Double]
    let pointCount: Int
    let graphState: MarketRowGraphState
    let generation: Int
    let updatedAt: Date
    let sourceVersion: Int

    nonisolated var hasRenderableGraph: Bool {
        graphState.keepsVisibleGraph
            && MarketSparklineRenderPolicy.hasRenderableGraph(points: points, pointCount: pointCount)
    }
}

private enum SparklineDisplayResolutionSource: Equatable {
    case snapshot
    case displayCache
    case rowState
    case unavailable
    case placeholder
    case none

    var logComponent: String {
        switch self {
        case .snapshot:
            return "live_cache"
        case .displayCache:
            return "display_cache"
        case .rowState:
            return "retained_store"
        case .unavailable:
            return "unavailable"
        case .placeholder:
            return "placeholder"
        case .none:
            return "none"
        }
    }
}

private struct SparklineResolutionCandidate {
    let points: [Double]
    let pointCount: Int
    let graphState: MarketRowGraphState
    let source: SparklineDisplayResolutionSource
    let sourceVersion: Int
}

private struct SparklineResolutionSelection {
    let candidate: SparklineResolutionCandidate?
    let skippedDisplayCacheForNewerCandidate: Bool
}

private struct MarketSparklinePatch {
    let marketIdentity: MarketIdentity
    let snapshot: SparklineLayerSnapshot?
    let graphState: MarketRowGraphState
    let reason: String
}

private struct MarketSymbolImagePatch {
    let marketIdentity: MarketIdentity
    let exchange: Exchange
    let generation: Int
    let expectedImageURL: String?
    let nextState: MarketRowSymbolImageState
    let reason: String
}

private struct MarketTickerDisplayPatch {
    let marketIdentity: MarketIdentity
    let exchange: Exchange
    let generation: Int
    let sourceExchange: Exchange
    let priceText: String
    let changeText: String
    let volumeText: String
    let isPricePlaceholder: Bool
    let isChangePlaceholder: Bool
    let isVolumePlaceholder: Bool
    let isUp: Bool
    let flash: FlashType?
    let dataState: MarketRowDataState
    let baseFreshnessState: MarketRowFreshnessState
    let reason: String
}

private struct PendingMarketRowPatch {
    let marketIdentity: MarketIdentity
    let exchange: Exchange
    let generation: Int
    var sparklinePatch: MarketSparklinePatch?
    var symbolImagePatch: MarketSymbolImagePatch?
    var tickerDisplayPatch: MarketTickerDisplayPatch?
    var rebuildReasons: [String] = []
    var sourcePatchCount = 0

    var reasons: [String] {
        var values = rebuildReasons
        if let tickerDisplayPatch {
            values.append(tickerDisplayPatch.reason)
        }
        if let sparklinePatch {
            values.append("graph_refined_patch:\(sparklinePatch.reason)")
        }
        if let symbolImagePatch {
            values.append("image_visible_patch:\(symbolImagePatch.reason)")
        }
        return values
    }

    var patchKind: String {
        let hasGraph = sparklinePatch != nil
        let hasImage = symbolImagePatch != nil
        let hasTickerDisplay = tickerDisplayPatch != nil
        let hasRebuild = rebuildReasons.isEmpty == false
        switch (hasGraph, hasImage, hasTickerDisplay, hasRebuild) {
        case (true, false, false, false):
            return "graph_only"
        case (false, true, false, false):
            return "image_only"
        case (false, false, true, false):
            return tickerDisplayPatch?.reason == "ticker_flash_reset"
                ? "flash_only"
                : "ticker_display_only"
        case (false, false, false, true):
            return rebuildReasons.contains("ticker_flash_reset") ? "flash_only" : "base_ticker_refresh"
        default:
            return "coalesced"
        }
    }

    mutating func merge(
        sparklinePatch incomingSparklinePatch: MarketSparklinePatch?,
        symbolImagePatch incomingSymbolImagePatch: MarketSymbolImagePatch?,
        tickerDisplayPatch incomingTickerDisplayPatch: MarketTickerDisplayPatch?,
        rebuildReason: String?,
        preferredSparklinePatch: (MarketSparklinePatch, MarketSparklinePatch) -> MarketSparklinePatch,
        preferredImagePatch: (MarketSymbolImagePatch, MarketSymbolImagePatch) -> MarketSymbolImagePatch,
        preferredTickerDisplayPatch: (MarketTickerDisplayPatch, MarketTickerDisplayPatch) -> MarketTickerDisplayPatch
    ) {
        var mergedAnyPatch = false
        if let incomingSparklinePatch {
            if let existingSparklinePatch = sparklinePatch {
                sparklinePatch = preferredSparklinePatch(existingSparklinePatch, incomingSparklinePatch)
            } else {
                sparklinePatch = incomingSparklinePatch
            }
            mergedAnyPatch = true
        }

        if let incomingSymbolImagePatch {
            if let existingSymbolImagePatch = symbolImagePatch {
                symbolImagePatch = preferredImagePatch(existingSymbolImagePatch, incomingSymbolImagePatch)
            } else {
                symbolImagePatch = incomingSymbolImagePatch
            }
            mergedAnyPatch = true
        }

        if let incomingTickerDisplayPatch {
            if let existingTickerDisplayPatch = tickerDisplayPatch {
                tickerDisplayPatch = preferredTickerDisplayPatch(existingTickerDisplayPatch, incomingTickerDisplayPatch)
            } else {
                tickerDisplayPatch = incomingTickerDisplayPatch
            }
            mergedAnyPatch = true
        }

        if let rebuildReason,
           rebuildReasons.contains(rebuildReason) == false {
            rebuildReasons.append(rebuildReason)
            mergedAnyPatch = true
        }

        if mergedAnyPatch {
            sourcePatchCount += 1
        }
    }
}

private enum SparklineQueuePriority: Int {
    case offscreen = 1
    case nearVisible = 2
    case visibleCoarse = 3
    case visibleMissing = 4

    var logValue: String {
        switch self {
        case .offscreen:
            return "offscreen"
        case .nearVisible:
            return "near_visible"
        case .visibleCoarse:
            return "visible_coarse"
        case .visibleMissing:
            return "visible_missing"
        }
    }
}

private struct ScheduledSparklineRequestState {
    let generation: Int
    var priority: SparklineQueuePriority
    var phase: String
}

private struct MarketRowReconfigureTrace {
    let marketIdentity: MarketIdentity
    let patchKind: String
    let reasons: [String]
    let previousGraphState: MarketRowGraphState
    let nextGraphState: MarketRowGraphState
    let previousImageState: MarketRowSymbolImageState
    let nextImageState: MarketRowSymbolImageState

    var reasonSummary: String {
        reasons.isEmpty ? "unknown" : reasons.joined(separator: "+")
    }
}

private struct MarketPresentationBuildInput {
    let exchange: Exchange
    let generation: Int
    let assetImageClient: AssetImageClient
    let catalogCoins: [CoinInfo]
    let tickerSnapshotCoins: [CoinInfo]
    let cachedRows: [MarketRowViewState]
    let pricesByMarketIdentity: [MarketIdentity: TickerData]
    let sparklineSnapshotsByMarketIdentity: [MarketIdentity: SparklineLayerSnapshot]
    let stableSparklineDisplaysByMarketIdentity: [MarketIdentity: StableSparklineDisplay]
    let loadingSparklineMarketIdentities: Set<MarketIdentity>
    let unavailableSparklineMarketIdentities: Set<MarketIdentity>
    let filteredMarketIdentities: [MarketIdentity]
    let filteredTickerIdentities: [MarketIdentity]
    let visiblePriorityMarketIdentities: [MarketIdentity]
    let selectedCoinIdentity: MarketIdentity?
    let favoriteSymbols: Set<String>
    let shouldLimitFirstPaint: Bool
    let preservesVisibleOrderDuringHydration: Bool
    let marketFirstPaintRowLimit: Int
    let sparklineStaleInterval: TimeInterval
    let now: Date
    let catalogMeta: ResponseMeta
    let tickerMeta: ResponseMeta
    let overrideMeta: ResponseMeta
}

private struct KimchiPremiumRequestContext: Hashable, Equatable {
    let exchange: Exchange
    let route: Tab
    let requestedSymbols: [String]
    let symbolsHash: String
    let generation: Int

    var signature: String {
        "\(exchange.rawValue)|\(route.rawValue)|\(symbolsHash)|\(generation)"
    }
}

private struct KimchiPresentationSnapshot: Equatable {
    let exchange: Exchange
    let comparableSymbols: [String]
    let symbolsHash: String
    let rows: [KimchiPremiumCoinViewState]
    let meta: ResponseMeta
    let phase: KimchiPremiumViewStateUseCase.PresentationPhase
}

private struct KimchiCacheEntry: Equatable {
    let exchange: Exchange
    let symbolsHash: String
    let presentation: KimchiPresentationSnapshot
    let fetchedAt: Date
}

private enum KimchiCacheTier {
    case representative
    case visible
    case full
}

private enum KimchiRepresentativeState: Equatable {
    case none
    case cachedReady
    case staleReady
    case loading
    case liveReady

    var isReadyEnough: Bool {
        switch self {
        case .cachedReady, .staleReady, .liveReady:
            return true
        case .none, .loading:
            return false
        }
    }
}

private enum KimchiFullHydrationState: Equatable {
    case idle
    case batching
    case partial
    case complete
    case degraded
}

private enum ChartSectionKind {
    case candles
    case orderbook
    case trades

    var displayName: String {
        switch self {
        case .candles:
            return "차트"
        case .orderbook:
            return "호가"
        case .trades:
            return "최근 체결"
        }
    }
}

private struct RouteRefreshContext: Equatable {
    let tab: Tab
    let exchange: Exchange
    let isAuthenticated: Bool
    let generation: Int
}

private struct PortfolioLoadContext: Equatable {
    let exchange: Exchange
    let accessToken: String
}

private struct TradingLoadContext: Equatable {
    let exchange: Exchange
    let symbol: String
    let accessToken: String
}

private struct ExchangeConnectionsLoadContext: Equatable {
    let accessToken: String
}

struct ExchangeConnectionsNoticeState: Equatable {
    let title: String
    let message: String
    let tone: StatusBadgeTone
}

private enum PrivateRequestEndpoint: String, Hashable {
    case exchangeConnections
    case portfolioSummary
    case portfolioHistory
    case tradingChance
    case openOrders
    case fills
}

private struct PrivateRequestKey: Hashable {
    let endpoint: PrivateRequestEndpoint
    let exchange: Exchange?
    let route: String
}

private enum PrivateRequestFailureSignature: Equatable {
    case http(statusCode: Int)
    case transport(category: RemoteErrorCategory)
    case other
}

private struct PrivateRequestFailureState {
    let signature: PrivateRequestFailureSignature
    let failureCount: Int
    let cooldownUntil: Date
    let isServerResponseFailure: Bool
}

enum SignUpServerErrorCode: String, Equatable {
    case invalidInput = "register_invalid_input"
    case duplicateAccount = "register_duplicate_account"
    case serverUnavailable = "register_server_unavailable"
    case timeout = "register_timeout"
    case transport = "register_transport"
    case decodingFailure = "register_decoding_failure"
    case unknown = "register_unknown"
}

struct SignUpServerErrorState: Equatable {
    let message: String
    let code: SignUpServerErrorCode
    let statusCode: Int?
}

@MainActor
final class CryptoViewModel: ObservableObject {
    @Published private(set) var activeTab: Tab = .market
    @Published private(set) var selectedExchange: Exchange = .upbit
    @Published var selectedCoin: CoinInfo?
    @Published var showExchangeMenu = false

    @Published private(set) var marketState: Loadable<[CoinInfo]> = .idle
    @Published private(set) var pricesByMarketIdentity: [MarketIdentity: TickerData] = [:]
    @Published private(set) var marketRowStates: [MarketRowViewState] = []
    @Published private(set) var marketStatusViewState: ScreenStatusViewState = .idle
    @Published private(set) var marketLoadState: SourceAwareLoadState = .initialLoading
    @Published private(set) var marketPresentationState: MarketScreenPresentationState = .initial(exchange: .upbit)
    @Published private(set) var marketTransitionMessage: String?
    @Published private(set) var marketDisplayModePreview: MarketListDisplayMode?
    @Published var searchQuery = "" {
        didSet {
            logMarketScreenCounts(reason: "search_query_changed")
            scheduleMarketSearchRefresh()
        }
    }
    @Published var marketFilter: MarketFilter = .all {
        didSet {
            logMarketScreenCounts(reason: "market_filter_changed")
            if activeTab == .market {
                updatePublicSubscriptions(reason: "market_filter_changed")
            }
        }
    }
    @Published private(set) var favCoins: Set<String> = []
    @Published private(set) var marketDisplayMode: MarketListDisplayMode

    @Published var chartPeriod = "1h"
    @Published private(set) var headerSummaryState: ChartSectionState<TickerData> = .idle
    @Published private(set) var candleChartState: ChartSectionState<[CandleData]> = .idle
    @Published private(set) var orderBookState: ChartSectionState<OrderbookData> = .idle
    @Published private(set) var marketStatsState: ChartSectionState<TickerData> = .idle
    @Published private(set) var candlesState: CandleState = .idle
    @Published private(set) var orderbookState: OrderBookState = .idle
    @Published private(set) var recentTradesState: TradesState = .idle
    @Published private(set) var chartStatusViewState: ScreenStatusViewState = .idle
    @Published private(set) var chartSettingsState: ChartSettingsState
    @Published private(set) var appliedChartSettingsState: ChartSettingsState
    @Published private(set) var comparedChartSeries: [ChartComparisonSeries] = []

    @Published var orderSide: OrderSide = .buy
    @Published var orderType: OrderType = .limit
    @Published var orderPrice = ""
    @Published var orderQty = ""
    @Published private(set) var selectedOrderRatioPercent: Double?
    @Published private(set) var isSubmittingOrder = false
    @Published private(set) var tradingChanceState: Loadable<TradingChance> = .idle
    @Published private(set) var orderHistoryState: Loadable<[OrderRecord]> = .idle
    @Published private(set) var fillsState: Loadable<[TradeFill]> = .idle
    @Published private(set) var selectedOrderDetailState: Loadable<OrderRecord> = .idle
    @Published private(set) var tradingStatusViewState: ScreenStatusViewState = .idle

    @Published private(set) var portfolioSummaryCardState: PortfolioSummaryCardState?
    @Published private(set) var portfolioOverviewViewState: PortfolioOverviewViewState?
    @Published private(set) var portfolioState: Loadable<PortfolioSnapshot> = .idle
    @Published private(set) var portfolioHistoryState: Loadable<[PortfolioHistoryItem]> = .idle
    @Published private(set) var portfolioStatusViewState: ScreenStatusViewState = .idle

    @Published private(set) var selectedDomesticKimchiExchange: Exchange = .upbit
    @Published private(set) var kimchiPremiumState: Loadable<[KimchiPremiumCoinViewState]> = .idle
    @Published private(set) var kimchiStatusViewState: ScreenStatusViewState = .idle
    @Published private(set) var kimchiLoadState: SourceAwareLoadState = .initialLoading
    @Published private(set) var kimchiPresentationState: KimchiScreenPresentationState = .initial(exchange: .upbit)
    @Published private(set) var kimchiHeaderState: KimchiHeaderViewState = .initial(exchange: .upbit)
    @Published private(set) var kimchiPremiumDebugMessage: String?
    @Published private(set) var kimchiTransitionMessage: String?

    @Published private(set) var exchangeConnectionsState: Loadable<[ExchangeConnectionCardViewState]> = .idle
    @Published private(set) var exchangeConnectionsNoticeState: ExchangeConnectionsNoticeState?
    @Published private(set) var isExchangeConnectionsRetrying = false
    @Published private(set) var authState: AuthState = .guest
    @Published private(set) var activeAuthGate: ProtectedFeature?
    @Published private(set) var publicWebSocketState: PublicWebSocketConnectionState = .disconnected
    @Published private(set) var privateWebSocketState: PrivateWebSocketConnectionState = .disconnected

    @Published var notification: (msg: String, type: NotifType)?
    @Published var isLoginPresented = false
    @Published var authFlowMode: AuthFlowMode = .login
    @Published var loginEmail = ""
    @Published var loginPassword = ""
    @Published var loginErrorMessage: String?
    @Published var signupEmail = ""
    @Published var signupPassword = ""
    @Published var signupPasswordConfirm = ""
    @Published var signupNickname = ""
    @Published var signupAcceptedTerms = false
    @Published private(set) var signupServerError: SignUpServerErrorState?
    @Published private(set) var isSigningUp = false
    @Published private(set) var activeSocialSignInMethod: SocialSignInMethod?
    @Published private(set) var isDeletingAccount = false

    private(set) var isExchangeConnectionsPresented = false

    private let marketRepository: MarketRepositoryProtocol
    private let tradingRepository: TradingRepositoryProtocol
    private let portfolioRepository: PortfolioRepositoryProtocol
    private let kimchiPremiumRepository: KimchiPremiumRepositoryProtocol
    private let exchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol
    private let authService: AuthenticationServiceProtocol
    private let authSessionStore: AuthSessionStoring?
    private let googleSignInProvider: GoogleSignInProviding
    private let publicWebSocketService: PublicWebSocketServicing
    private let privateWebSocketService: PrivateWebSocketServicing
    private let marketSnapshotCacheStore: MarketSnapshotCacheStoring?
    private let assetImageClient: AssetImageClient

    private let capabilityResolver = ExchangeCapabilityResolver()
    private let screenStatusFactory = ScreenStatusFactory()
    private let authInputValidator = AuthInputValidator()
    private let exchangeConnectionsUseCase = ExchangeConnectionsUseCase()
    private let exchangeConnectionFormValidator = ExchangeConnectionFormValidator()
    private let kimchiPremiumViewStateUseCase = KimchiPremiumViewStateUseCase()
    private let defaults: UserDefaults
    private let chartSettingsStorage: ChartSettingsStorage
    private var presentExchangeConnectionsSheet: (() -> Void)?
    private var dismissExchangeConnectionsSheet: (() -> Void)?

    private let favoritesKey = "guest.favorite.symbols"
    private let marketDisplayModeKey = "market.display.mode"
    private let marketDisplayGuideSeenKey = "market.display.guide.seen"
    private let instanceID = AppLogger.nextInstanceID(scope: "CryptoViewModel")
    private let marketCatalogStaleInterval: TimeInterval = 60 * 5
    private let tickerStaleInterval: TimeInterval = 4
    private let chartSnapshotStaleInterval: TimeInterval = 5
    private let sparklineCacheStaleInterval: TimeInterval = 60
    private let sparklineSchedulerDebounceNanoseconds: UInt64 = 80_000_000
    private let sparklineVisibleBatchSize = 8
    private let sparklineBackgroundBatchSize = 8
    private let sparklineRepresentativeLimit = 20
    private let sparklineFailureCooldownInterval: TimeInterval = 4
    private let sparklineRefreshThrottleInterval: TimeInterval = 1.2
    private let sparklineVisiblePriorityThrottleInterval: TimeInterval = 0.35
    private let sparklineNoImprovementBackoffInterval: TimeInterval = 0.75
    private let sparklineActiveScrollWindow: TimeInterval = 0.18
    private let sparklineFirstPaintHoldInterval: TimeInterval = 0.16
    private let sparklineScrollSettleDelayNanoseconds: UInt64 = 180_000_000
    private let sparklineMaxConcurrentFetchCount = 3
    private let marketRepresentativeRowLimit = 4
    private let marketFirstPaintRowLimit = 24
    private let marketHydrationDelayNanoseconds: UInt64 = 650_000_000
    private let marketImageHydrationDebounceNanoseconds: UInt64 = 90_000_000
    private let marketRowPatchCoalesceNanoseconds: UInt64 = 16_000_000
    private let marketImageVisibleBatchSize = 12
    private let marketImagePrefetchBatchSize = 18
    private let chartCacheStaleInterval: TimeInterval = 30
    private let chartSecondaryBootstrapDelayNanoseconds: UInt64 = 140_000_000
    private let chartWindow = "default"
    private let kimchiPremiumStaleInterval: TimeInterval = 15
    private let kimchiPremiumSettleInterval: TimeInterval = 1.5
    private let kimchiRepresentativeRowLimit = 3
    private let kimchiFirstPaintSymbolLimit = 5
    private let kimchiHydrationDelayNanoseconds: UInt64 = 450_000_000
    private let kimchiVisibleHydrationDebounceNanoseconds: UInt64 = 120_000_000
    private let kimchiVisibleBatchSize = 12
    private let kimchiBackgroundBatchSize = 24
    private let kimchiRecentVisibleThrottleInterval: TimeInterval = 0.3
    private let kimchiBadgeReadyMinimumHold: TimeInterval = 1.2
    private let kimchiBadgeSyncMinimumHold: TimeInterval = 0.65
    private let kimchiHeaderCopyMinimumHold: TimeInterval = 0.9
    private let serverFailureAutoRetryCooldownInterval: TimeInterval = 45
    private let transportFailureAutoRetryCooldownInterval: TimeInterval = 12
    private let terminalPrivateRequestCooldownInterval: TimeInterval = 300
    private let automaticPrivateRefreshMinimumInterval: TimeInterval = 2.5

    private var hasBootstrapped = false
    private var lastOrderModeTapAt: Date?
    private var lastOrderModeTappedSide: OrderSide?
    private var pendingPostLoginFeature: ProtectedFeature?
    private var sessionRefreshTask: Task<AuthSession, Error>?
    private var acceptedStaleAccessTokens: Set<String> = []
    private var marketsByExchange: [Exchange: [CoinInfo]] = [:]
    private var tickerSnapshotCoinsByExchange: [Exchange: [CoinInfo]] = [:]
    private var supportedIntervalsByExchangeAndMarketIdentity: [Exchange: [MarketIdentity: [String]]] = [:]
    private var filteredMarketIdentitiesByExchange: [Exchange: [MarketIdentity]] = [:]
    private var filteredTickerIdentitiesByExchange: [Exchange: [MarketIdentity]] = [:]
    private var loadedExchangeConnections: [ExchangeConnection] = []
    private var portfolioSummaryFetchTask: Task<PortfolioSnapshot, Error>?
    private var portfolioSummaryFetchTaskContext: PortfolioLoadContext?
    private var portfolioHistoryFetchTask: Task<PortfolioHistorySnapshot, Error>?
    private var portfolioHistoryFetchTaskContext: PortfolioLoadContext?
    private var tradingChanceFetchTask: Task<TradingChance, Error>?
    private var tradingChanceFetchTaskContext: TradingLoadContext?
    private var tradingOpenOrdersFetchTask: Task<OrderRecordsSnapshot, Error>?
    private var tradingOpenOrdersFetchTaskContext: TradingLoadContext?
    private var tradingFillsFetchTask: Task<TradeFillsSnapshot, Error>?
    private var tradingFillsFetchTaskContext: TradingLoadContext?
    private var exchangeConnectionsFetchTask: Task<ExchangeConnectionsSnapshot, Error>?
    private var exchangeConnectionsFetchTaskContext: ExchangeConnectionsLoadContext?
    private var lastResolvedPortfolioExchange: Exchange?
    private var lastResolvedPortfolioHistoryExchange: Exchange?
    private var portfolioSnapshotsByExchange: [Exchange: PortfolioSnapshot] = [:]
    private var portfolioSummaryResponseMeta: ResponseMeta = .empty
    private var portfolioHistoryResponseMeta: ResponseMeta = .empty
    private var portfolioRefreshWarningMessage: String?
    private var hasResolvedExchangeConnectionsState = false
    private var privateRequestFailureStates: [PrivateRequestKey: PrivateRequestFailureState] = [:]
    private var lastAutomaticPrivateRequestAtByKey: [PrivateRequestKey: Date] = [:]
    private var publicPollingTask: Task<Void, Never>?
    private var privatePollingTask: Task<Void, Never>?
    private var marketHydrationTask: Task<Void, Never>?
    private var marketImageHydrationTask: Task<Void, Never>?
    private var marketRowPatchTask: Task<Void, Never>?
    private var sparklineHydrationTask: Task<Void, Never>?
    private var priorityVisibleSparklineTask: Task<Void, Never>?
    private var chartSecondaryResourcesTask: Task<Void, Never>?
    private var chartDeferredSubscriptionTask: Task<Void, Never>?
    private var kimchiHydrationTask: Task<Void, Never>?
    private var kimchiVisibleHydrationTask: Task<Void, Never>?
    private var marketImageRetryTasksByMarketIdentity: [MarketIdentity: Task<Void, Never>] = [:]
    private var isPublicPollingFallbackActive = false
    private var isPrivatePollingFallbackActive = false
    private var marketCatalogFetchTasks: [Exchange: Task<MarketCatalogSnapshot, Error>] = [:]
    private var tickerFetchTasks: [Exchange: Task<MarketTickerSnapshot, Error>] = [:]
    private var lastMarketCatalogFetchedAtByExchange: [Exchange: Date] = [:]
    private var lastTickerFetchedAtByExchange: [Exchange: Date] = [:]
    private var marketCatalogResponseCountsByExchange: [Exchange: Int] = [:]
    private var marketTickerResponseCountsByExchange: [Exchange: Int] = [:]
    private var marketCatalogMetaByExchange: [Exchange: ResponseMeta] = [:]
    private var marketTickerMetaByExchange: [Exchange: ResponseMeta] = [:]
    private var hasLoadedTickerSnapshotByExchange: [Exchange: Bool] = [:]
    private var marketPresentationSnapshotsByExchange: [Exchange: MarketPresentationSnapshot] = [:]
    private var activeMarketPresentationSnapshot: MarketPresentationSnapshot?
    private var marketBasePhaseByExchange: [Exchange: DataLoadPhase] = [:]
    private var fullyHydratedMarketExchanges: Set<Exchange> = []
    private var scheduledMarketImageHydrationContext: ScheduledHydrationContext?
    private var scheduledSparklineHydrationContext: ScheduledHydrationContext?
    private var scheduledPriorityVisibleSparklineContext: ScheduledHydrationContext?
    private var visibleMarketIdentitiesByExchange: [Exchange: [MarketIdentity]] = [:]
    private var lastVisibleMarketRowAtByExchange: [Exchange: Date] = [:]
    private var lastMarketImageHydrationSignatureByExchange: [Exchange: String] = [:]
    private var sparklineSnapshotsByKey: [SparklineCacheKey: SparklineLayerSnapshot] = [:]
    // UI-only display cache: keeps the last renderable graph visible across SwiftUI row teardown/recreation.
    private var stableSparklineDisplaysByKey: [MarketGraphBindingKey: StableSparklineDisplay] = [:]
    private var loadingSparklineMarketIdentitiesByExchange: [Exchange: Set<MarketIdentity>] = [:]
    private var unavailableSparklineMarketIdentitiesByExchange: [Exchange: Set<MarketIdentity>] = [:]
    private var unsupportedSparklineMarketIdentitiesByExchange: [Exchange: Set<MarketIdentity>] = [:]
    private var sparklineFetchTasksByKey: [SparklineCacheKey: Task<SparklineLayerSnapshot, Error>] = [:]
    private var scheduledSparklineRequestsByKey: [SparklineCacheKey: ScheduledSparklineRequestState] = [:]
    private var sparklineFailureCooldownUntilByKey: [SparklineCacheKey: Date] = [:]
    private var lastSparklineRefreshAttemptAtByKey: [SparklineCacheKey: Date] = [:]
    private var lastPriorityVisibleSparklineEnqueueAtByKey: [SparklineCacheKey: Date] = [:]
    private var sparklineNoImprovementUntilByKey: [SparklineCacheKey: Date] = [:]
    private var sparklineFirstPaintHoldStartedAtByKey: [MarketGraphBindingKey: Date] = [:]
    private var sparklineFirstPaintHoldFallbackTasksByKey: [MarketGraphBindingKey: Task<Void, Never>] = [:]
    private var runningSparklineHydrationExchanges: Set<Exchange> = []
    private var pendingSparklineHydrationReasonsByExchange: [Exchange: String] = [:]
    private var lastLoggedGraphDisplaySignaturesByBindingKey: [String: String] = [:]
    private var lastLoggedGraphCacheHitSignatureByExchange: [Exchange: String] = [:]
    private var lastLoggedGraphDeferredSignatureByExchange: [Exchange: String] = [:]
    private var pendingMarketRowPatchesByExchange: [Exchange: [MarketIdentity: PendingMarketRowPatch]] = [:]
    private var marketPresentationGeneration = 0
    private var marketSwitchApplyCountByExchange: [Exchange: Int] = [:]
    private var marketStagedSwapCountByExchange: [Exchange: Int] = [:]
    private var marketFullReloadCountByExchange: [Exchange: Int] = [:]
    private var marketVisibleGraphPatchCountByExchange: [Exchange: Int] = [:]
    private var marketOffscreenDeferredGraphCountByExchange: [Exchange: Int] = [:]
    private var marketStaleCallbackDropCountByExchange: [Exchange: Int] = [:]
    private var marketPlaceholderFinalBaselineByExchange: [Exchange: Int] = [:]
    private var routeRefreshGeneration = 0
    private var activeChartRequestGeneration = 0
    private var activeChartRequestKey: ChartRequestKey?
    private var chartSecondarySubscriptionsEnabled = false
    private var chartEnterStartedAt: Date?
    private var lastLoggedChartFirstFrameKey: String?
    private var candleFetchTasksByKey: [ChartRequestKey: Task<CandleSnapshot, Error>] = [:]
    private var orderbookFetchTasksByKey: [ChartResourceKey: Task<OrderbookSnapshot, Error>] = [:]
    private var tradesFetchTasksByKey: [ChartResourceKey: Task<PublicTradesSnapshot, Error>] = [:]
    private var candleCacheByKey: [ChartRequestKey: CandleCacheEntry] = [:]
    private var orderbookCacheByKey: [ChartResourceKey: OrderbookCacheEntry] = [:]
    private var tradesCacheByKey: [ChartResourceKey: TradesCacheEntry] = [:]
    private var lastSuccessfulCandles: [ChartRequestKey: CandleCacheEntry] = [:]
    private var lastSuccessfulOrderBook: [ChartResourceKey: OrderbookCacheEntry] = [:]
    private var lastSuccessfulTrades: [ChartResourceKey: TradesCacheEntry] = [:]
    private var lastSuccessfulStats: [ChartResourceKey: TickerData] = [:]
    private var lastKnownGoodOrderHeaderTickerByKey: [OrderHeaderPriceCacheKey: TickerData] = [:]
    private var activeChartCandleMeta: ResponseMeta = .empty
    private var activeChartOrderbookMeta: ResponseMeta = .empty
    private var activeChartTradesMeta: ResponseMeta = .empty
    private var chartComparisonTask: Task<Void, Never>?
    private var activeChartComparisonSignature: String?
    private var kimchiPremiumFetchTasksByContext: [KimchiPremiumRequestContext: Task<KimchiPremiumSnapshot, Error>] = [:]
    private var kimchiPremiumFetchContext: KimchiPremiumRequestContext?
    private var lastSuccessfulKimchiPremiumRequestContext: KimchiPremiumRequestContext?
    private var lastKimchiPremiumFetchedAtByExchange: [Exchange: Date] = [:]
    private var kimchiSnapshotsByExchange: [Exchange: KimchiPremiumSnapshot] = [:]
    private var kimchiPresentationSnapshotsByExchange: [Exchange: KimchiPresentationSnapshot] = [:]
    private var representativeKimchiCacheByExchange: [Exchange: KimchiCacheEntry] = [:]
    private var visibleKimchiCacheByExchange: [Exchange: KimchiCacheEntry] = [:]
    private var fullKimchiCacheByExchange: [Exchange: KimchiCacheEntry] = [:]
    private var activeKimchiPresentationSnapshot: KimchiPresentationSnapshot?
    private var lastGoodKimchiSnapshotsByExchange: [Exchange: KimchiPremiumSnapshot] = [:]
    private var kimchiBasePhaseByExchange: [Exchange: DataLoadPhase] = [:]
    private var fullyHydratedKimchiSymbolsHashByExchange: [Exchange: String] = [:]
    private var kimchiPremiumSettleTask: Task<Void, Never>?
    private var kimchiPremiumRequestVersion = 0
    private var visibleKimchiSymbolsByExchange: [Exchange: [String]] = [:]
    private var lastVisibleKimchiRowAtByExchange: [Exchange: Date] = [:]
    private var lastChartSnapshotContext: ChartRequestContext?
    private var lastChartSnapshotFetchedAt: Date?
    private var lastAppliedPublicSubscriptions: Set<PublicMarketSubscription>?
    private var lastAppliedPrivateSubscriptions: Set<PrivateTradingSubscription>?
    private var lastLoggedMarketPipelineSignature: String?
    private var lastLoggedMarketUniverseSignatureByExchange: [Exchange: String] = [:]
    private var lastLoggedOrderHeaderPriceSignature: String?
    private var lastLoggedOrderHeaderMissingPriceSignature: String?
    private var marketSearchDebounceTask: Task<Void, Never>?
    private var firstTickerStreamEventsByExchange: Set<Exchange> = []
    private var marketSwitchStartedAtByExchange: [Exchange: Date] = [:]
    private var marketFirstVisibleLoggedExchanges: Set<Exchange> = []
    private var marketFullHydrationPendingExchanges: Set<Exchange> = []
    private var kimchiSwitchStartedAtByExchange: [Exchange: Date] = [:]
    private var kimchiFirstVisibleLoggedExchanges: Set<Exchange> = []
    private var lastKimchiBadgeTransitionAt: Date = .distantPast
    private var lastKimchiCopyTransitionAt: Date = .distantPast

    var exchange: Exchange {
        get { selectedExchange }
        set { updateExchange(newValue, source: "exchange_property") }
    }

    func setExchangeMenuVisible(_ isVisible: Bool) {
        guard showExchangeMenu != isVisible else {
            return
        }
        showExchangeMenu = isVisible
    }

    func toggleExchangeMenu() {
        setExchangeMenuVisible(!showExchangeMenu)
    }

    init(
        marketRepository: MarketRepositoryProtocol? = nil,
        tradingRepository: TradingRepositoryProtocol? = nil,
        portfolioRepository: PortfolioRepositoryProtocol? = nil,
        kimchiPremiumRepository: KimchiPremiumRepositoryProtocol? = nil,
        exchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol? = nil,
        authService: AuthenticationServiceProtocol? = nil,
        authSessionStore: AuthSessionStoring? = nil,
        googleSignInProvider: GoogleSignInProviding? = nil,
        publicWebSocketService: PublicWebSocketServicing? = nil,
        privateWebSocketService: PrivateWebSocketServicing? = nil,
        marketSnapshotCacheStore: MarketSnapshotCacheStoring? = nil,
        assetImageClient: AssetImageClient = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        let resolvedDisplayMode = Self.loadMarketDisplayMode(from: userDefaults)
        let chartSettingsStorage = ChartSettingsStorage(defaults: userDefaults)
        let restoredChartSettings = chartSettingsStorage.load()
        self.marketRepository = marketRepository ?? LiveMarketRepository()
        self.tradingRepository = tradingRepository ?? LiveTradingRepository()
        self.portfolioRepository = portfolioRepository ?? LivePortfolioRepository()
        self.kimchiPremiumRepository = kimchiPremiumRepository ?? LiveKimchiPremiumRepository()
        self.exchangeConnectionsRepository = exchangeConnectionsRepository ?? LiveExchangeConnectionsRepository()
        self.authService = authService ?? LiveAuthenticationService()
        self.authSessionStore = authSessionStore ?? Self.defaultAuthSessionStore()
        self.googleSignInProvider = googleSignInProvider ?? LiveGoogleSignInProvider.shared
        self.publicWebSocketService = publicWebSocketService ?? WebSocketService()
        self.privateWebSocketService = privateWebSocketService ?? PrivateWebSocketService()
        self.marketSnapshotCacheStore = marketSnapshotCacheStore ?? Self.defaultMarketSnapshotCacheStore()
        self.assetImageClient = assetImageClient
        self.defaults = userDefaults
        self.chartSettingsStorage = chartSettingsStorage
        self.chartSettingsState = restoredChartSettings
        self.appliedChartSettingsState = restoredChartSettings
        self.marketDisplayMode = resolvedDisplayMode
        self.favCoins = Set(userDefaults.stringArray(forKey: favoritesKey) ?? [])
        AppLogger.debug(.auth, "[AuthFlowDebug] action=session_restore_started")
        if let restoredSession = self.authSessionStore?.loadSession() {
            self.authState = .authenticated(restoredSession)
            AppLogger.debug(.auth, "[AuthFlowDebug] action=session_restore_success hasRefreshToken=\(restoredSession.hasRefreshToken)")
        } else {
            AppLogger.debug(.auth, "[AuthFlowDebug] action=session_restore_failed reason=no_saved_session")
        }

        hydratePersistedMarketSnapshots()
        AppLogger.debug(
            .lifecycle,
            "[MarketDisplayModeDebug] action=load_saved mode=\(resolvedDisplayMode.rawValue)"
        )
        AppLogger.debug(.lifecycle, "CryptoViewModel init #\(instanceID) selectedExchange=\(selectedExchange.rawValue)")
        bindPublicWebSocket()
        bindPrivateWebSocket()
        refreshPublicStatusViewStates()
        refreshKimchiHeaderState(reason: "init")
        updateAuthGate()

        if let restoredSession = self.authState.session {
            Task {
                await refreshRestoredSessionIfPossible(restoredSession)
            }
        }
    }

    deinit {
        AppLogger.debug(.lifecycle, "CryptoViewModel deinit #\(instanceID)")
        marketSearchDebounceTask?.cancel()
        portfolioSummaryFetchTask?.cancel()
        portfolioHistoryFetchTask?.cancel()
        tradingChanceFetchTask?.cancel()
        tradingOpenOrdersFetchTask?.cancel()
        tradingFillsFetchTask?.cancel()
        exchangeConnectionsFetchTask?.cancel()
        chartComparisonTask?.cancel()
        publicPollingTask?.cancel()
        privatePollingTask?.cancel()
        marketHydrationTask?.cancel()
        marketImageHydrationTask?.cancel()
        marketRowPatchTask?.cancel()
        sparklineHydrationTask?.cancel()
        priorityVisibleSparklineTask?.cancel()
        sparklineFetchTasksByKey.values.forEach { $0.cancel() }
        kimchiHydrationTask?.cancel()
        kimchiVisibleHydrationTask?.cancel()
        kimchiPremiumSettleTask?.cancel()
    }

    private func hydratePersistedMarketSnapshots() {
        guard let marketSnapshotCacheStore else {
            return
        }

        for exchange in Exchange.allCases {
            if let catalogSnapshot = marketSnapshotCacheStore.loadCatalogSnapshot(for: exchange) {
                marketsByExchange[exchange] = catalogSnapshot.markets
                supportedIntervalsByExchangeAndMarketIdentity[exchange] = catalogSupportedIntervalsByMarketIdentity(
                    from: catalogSnapshot
                )
                marketCatalogMetaByExchange[exchange] = catalogSnapshot.meta
                lastMarketCatalogFetchedAtByExchange[exchange] = catalogSnapshot.meta.fetchedAt
                marketCatalogResponseCountsByExchange[exchange] = catalogSnapshot.markets.count
                filteredMarketIdentitiesByExchange[exchange] = resolvedMarketIdentities(
                    exchange: exchange,
                    symbols: catalogSnapshot.filteredSymbols
                )
            }

            if let tickerSnapshot = marketSnapshotCacheStore.loadTickerSnapshot(for: exchange) {
                tickerSnapshotCoinsByExchange[exchange] = tickerSnapshot.coins
                marketTickerMetaByExchange[exchange] = tickerSnapshot.meta
                lastTickerFetchedAtByExchange[exchange] = tickerSnapshot.meta.fetchedAt
                marketTickerResponseCountsByExchange[exchange] = tickerSnapshot.tickers.count
                hasLoadedTickerSnapshotByExchange[exchange] = tickerSnapshot.tickers.isEmpty == false
                filteredTickerIdentitiesByExchange[exchange] = resolvedMarketIdentities(
                    exchange: exchange,
                    symbols: tickerSnapshot.filteredSymbols
                )

                for (symbol, ticker) in tickerSnapshot.tickers {
                    mergeTicker(
                        symbol: symbol,
                        exchange: exchange.rawValue,
                        incoming: ticker,
                        seedHistoryIfNeeded: true
                    )
                    seedSparklineSnapshotIfAvailable(
                        marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol),
                        ticker: ticker,
                        source: .tickerSnapshot,
                        fetchedAt: ticker.timestamp ?? tickerSnapshot.meta.fetchedAt ?? Date()
                    )
                }
            }

            seedCachedMarketPresentation(for: exchange, activate: exchange == selectedExchange)
        }
    }

    private func seedCachedMarketPresentation(for exchange: Exchange, activate: Bool) {
        let universe = marketUniverseSnapshot(for: exchange)
        guard !universe.tradableCoins.isEmpty else {
            return
        }

        var snapshot = makeMarketPresentationSnapshot(for: exchange, universe: universe)
        if activate, activeTab == .market, selectedExchange == exchange {
            snapshot = warmMarketImages(
                for: snapshot,
                reason: "seed_cached_presentation_pre_swap",
                visibleMode: .warmup,
                applyImmediateToSnapshot: true
            )
        }
        marketPresentationSnapshotsByExchange[exchange] = snapshot
        marketBasePhaseByExchange[exchange] = .showingCache
        persistStableSparklineDisplays(from: snapshot.rows, exchange: exchange, generation: snapshot.generation)

        guard activate else {
            return
        }

        activeMarketPresentationSnapshot = snapshot
        marketRowStates = snapshot.rows
        assignMarketState(snapshot.rows.isEmpty ? .empty : .loaded(snapshot.universe.tradableCoins))
        marketLoadState = SourceAwareLoadState(
            phase: .showingCache,
            hasPartialFailure: snapshot.meta.partialFailureMessage != nil
        )
        reconcileVisibleSparklines(
            exchange: exchange,
            reason: "display_cache_restore"
        )
        marketPresentationState = makeMarketPresentationState(
            from: snapshot,
            previousExchange: nil,
            sameExchangeStaleReuse: true,
            transitionPhase: .hydrated
        )
        scheduleMarketImageHydration(
            for: exchange,
            reason: "seed_cached_presentation"
        )
    }

    var isAuthenticated: Bool {
        authState.isAuthenticated
    }

    var isSigningIn: Bool {
        if case .signingIn = authState {
            return true
        }
        return false
    }

    var isAuthenticationBusy: Bool {
        isSigningIn || isSigningUp || activeSocialSignInMethod != nil
    }

    func isSigningIn(with method: SocialSignInMethod) -> Bool {
        activeSocialSignInMethod == method
    }

    var shouldShowExchangeSelector: Bool {
        guard activeTab.showsExchangeSelector else { return false }
        if activeTab.accessRequirement == .publicAccess {
            return true
        }
        return isAuthenticated
    }

    var statusButtonTitle: String {
        isAuthenticated ? "연결" : "로그인"
    }

    var signUpValidation: SignUpFormValidationResult {
        authInputValidator.signUpValidation(
            email: signupEmail,
            password: signupPassword,
            passwordConfirm: signupPasswordConfirm,
            nickname: signupNickname,
            acceptedTerms: signupAcceptedTerms
        )
    }

    var canSubmitLogin: Bool {
        authInputValidator.loginValidationMessage(
            email: loginEmail,
            password: loginPassword
        ) == nil && !isSigningIn
    }

    var canSubmitSignUp: Bool {
        !isSigningUp
    }

    var signupErrorMessage: String? {
        signupServerError?.message
    }

    private static func defaultMarketSnapshotCacheStore() -> MarketSnapshotCacheStoring? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }

        return UserDefaultsMarketSnapshotCacheStore()
    }

    private static func defaultAuthSessionStore() -> AuthSessionStoring? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }

        return KeychainAuthSessionStore()
    }

    private static func loadMarketDisplayMode(from defaults: UserDefaults) -> MarketListDisplayMode {
        guard let savedValue = defaults.string(forKey: "market.display.mode"),
              let savedMode = MarketListDisplayMode(rawValue: savedValue) else {
            return .chart
        }
        return savedMode
    }

    var debugOwnerID: String {
        "CryptoViewModel#\(instanceID)"
    }

    var prices: [String: [String: TickerData]] {
        var grouped = [String: [String: TickerData]]()
        for (marketIdentity, ticker) in pricesByMarketIdentity {
            var exchangeMap = grouped[marketIdentity.symbol] ?? [:]
            if let existing = exchangeMap[marketIdentity.exchange.rawValue] {
                exchangeMap[marketIdentity.exchange.rawValue] = Self.preferredTicker(existing, ticker)
            } else {
                exchangeMap[marketIdentity.exchange.rawValue] = ticker
            }
            grouped[marketIdentity.symbol] = exchangeMap
        }
        return grouped
    }

    var candles: [CandleData] {
        candlesState.value ?? []
    }

    var orderbook: OrderbookData? {
        orderbookState.value
    }

    var recentTrades: [PublicTrade] {
        recentTradesState.value ?? []
    }

    var recentTradeRows: [ChartTradeRowViewState] {
        recentTradeRows(for: recentTrades)
    }

    var chartComparisonCandidates: [ChartComparisonCandidate] {
        let exchange = selectedExchange
        let universe = resolvedMarketUniverse(for: exchange)
        var coinsBySymbol = Dictionary(
            uniqueKeysWithValues: CoinCatalog.fallbackTopSymbols.map {
                let coin = CoinCatalog.coin(symbol: $0, exchange: exchange)
                return (coin.symbol, coin)
            }
        )
        universe.forEach { coin in
            coinsBySymbol[coin.symbol] = coin
        }
        let orderedSymbols = prioritizedSymbols(from: Array(coinsBySymbol.keys), exchange: exchange)

        return orderedSymbols.compactMap { symbol in
            guard let coin = coinsBySymbol[symbol] else {
                return nil
            }
            return ChartComparisonCandidate(
                symbol: coin.symbol,
                name: coin.name,
                nameEn: coin.nameEn,
                isFavorite: favCoins.contains(coin.symbol)
            )
        }
    }

    var currentTradingChance: TradingChance? {
        tradingChanceState.value
    }

    var portfolio: [Holding] {
        portfolioState.value?.holdings ?? []
    }

    var cash: Double {
        portfolioState.value?.cash ?? 0
    }

    var currentSupportedOrderTypes: [OrderType] {
        let supportedOrderTypes = tradingChanceState.value?.supportedOrderTypes ?? [.limit, .market]
        return supportedOrderTypes.isEmpty ? [.limit, .market] : supportedOrderTypes
    }

    var availableChartIntervals: [CandleIntervalOption] {
        CandleIntervalCatalog.options(supportedIntervals: supportedIntervals)
    }

    var exchangeConnectionCRUDCapability: ExchangeConnectionCRUDCapability {
        exchangeConnectionsRepository.crudCapability
    }

    var exchangeConnections: [ExchangeConnection] {
        loadedExchangeConnections
    }

    var hasAnyExchangeConnection: Bool {
        !loadedExchangeConnections.isEmpty
    }

    var hasTradeEnabledConnection: Bool {
        loadedExchangeConnections.contains {
            $0.exchange == selectedExchange && $0.isActive && $0.permission == .tradeEnabled
        }
    }

    var selectedExchangeConnection: ExchangeConnection? {
        loadedExchangeConnections.first { $0.exchange == selectedExchange && $0.isActive }
    }

    var displayedMarketRows: [MarketRowViewState] {
        filteredMarketRows(from: marketRowStates)
    }

    var displayedMarketRowIDs: [String] {
        displayedMarketRows.map(\.id)
    }

    var representativeMarketRows: [MarketRowViewState] {
        representativeMarketRows(from: marketRowStates)
    }

    func recentTradeRows(for trades: [PublicTrade]) -> [ChartTradeRowViewState] {
        guard trades.isEmpty == false else {
            return []
        }

        let marketIdentity = activeChartRequestKey?.marketIdentity
            ?? selectedCoin?.marketIdentity(exchange: selectedExchange)
            ?? MarketIdentity(exchange: selectedExchange, symbol: "-")
        var occurrencesByBaseKey: [String: Int] = [:]

        return trades.map { trade in
            let baseKey = ChartTradeRowViewState.baseRenderKey(
                trade: trade,
                marketIdentity: marketIdentity
            )
            let occurrence = occurrencesByBaseKey[baseKey, default: 0]
            occurrencesByBaseKey[baseKey] = occurrence + 1
            return ChartTradeRowViewState(
                trade: trade,
                marketIdentity: marketIdentity,
                occurrence: occurrence
            )
        }
    }

    var activeMarketDisplayMode: MarketListDisplayMode {
        marketDisplayModePreview ?? marketDisplayMode
    }

    var marketDisplayConfiguration: MarketListDisplayConfiguration {
        activeMarketDisplayMode.configuration
    }

    func consumeMarketDisplayGuidePresentationIfNeeded(reason: String) -> Bool {
        guard defaults.bool(forKey: marketDisplayGuideSeenKey) == false else {
            return false
        }
        defaults.set(true, forKey: marketDisplayGuideSeenKey)
        AppLogger.debug(
            .lifecycle,
            "[MarketDisplayGuideDebug] action=present reason=\(reason)"
        )
        return true
    }

    func dismissMarketDisplayGuide(reason: String) {
        defaults.set(true, forKey: marketDisplayGuideSeenKey)
        AppLogger.debug(
            .lifecycle,
            "[MarketDisplayGuideDebug] action=dismiss reason=\(reason)"
        )
    }

    func beginMarketDisplayModePreview(source: String = "market_sheet") {
        marketDisplayModePreview = marketDisplayMode
        AppLogger.debug(
            .lifecycle,
            "[MarketDisplayModeDebug] action=preview_begin mode=\(marketDisplayMode.rawValue) source=\(source)"
        )
    }

    func previewMarketDisplayMode(_ mode: MarketListDisplayMode, source: String = "market_sheet") {
        guard marketDisplayModePreview != mode else {
            return
        }
        marketDisplayModePreview = mode
        AppLogger.debug(
            .lifecycle,
            "[MarketDisplayModeDebug] action=preview_render mode=\(mode.rawValue) source=\(source)"
        )
    }

    func cancelMarketDisplayModePreview(source: String = "market_sheet") {
        guard let previewMode = marketDisplayModePreview else {
            return
        }
        marketDisplayModePreview = nil
        AppLogger.debug(
            .lifecycle,
            "[MarketDisplayModeDebug] action=preview_cancel mode=\(previewMode.rawValue) restored=\(marketDisplayMode.rawValue) source=\(source)"
        )
    }

    func applyMarketDisplayModePreview(source: String = "market_sheet") {
        let mode = marketDisplayModePreview ?? marketDisplayMode
        marketDisplayModePreview = nil
        applyMarketDisplayMode(mode, source: source)
    }

    func applyMarketDisplayMode(_ mode: MarketListDisplayMode, source: String = "market_tab") {
        AppLogger.debug(
            .lifecycle,
            "[MarketDisplayModeDebug] action=apply mode=\(mode.rawValue) source=\(source)"
        )
        marketDisplayModePreview = nil
        defaults.set(mode.rawValue, forKey: marketDisplayModeKey)
        if marketDisplayMode != mode {
            marketDisplayMode = mode
        }
    }

    var representativeKimchiRows: [KimchiPremiumCoinViewState] {
        kimchiPresentationState.representativeRowsState.rows
    }

    private func marketIdentity(for coin: CoinInfo, exchange: Exchange) -> MarketIdentity {
        coin.marketIdentity(exchange: exchange)
    }

    private func resolvedMarketIdentity(
        exchange: Exchange,
        symbol: String,
        marketId: String? = nil,
        preferSelectedCoinIdentity: Bool = true
    ) -> MarketIdentity {
        if let marketId, marketId.isEmpty == false {
            return MarketIdentity(exchange: exchange, marketId: marketId, symbol: symbol)
        }

        if preferSelectedCoinIdentity,
           let selectedCoin,
           selectedExchange == exchange,
           selectedCoin.symbol == symbol {
            return selectedCoin.marketIdentity(exchange: exchange)
        }

        let candidates = (marketsByExchange[exchange] ?? [])
            + (tickerSnapshotCoinsByExchange[exchange] ?? [])
            + (marketPresentationSnapshotsByExchange[exchange]?.rows.map(\.coin) ?? [])

        let normalizedSymbolCandidates = normalizedGraphSymbolCandidates(symbol: symbol, marketId: marketId)
        let matchingCandidates = candidates.filter { coin in
            if coin.symbol == symbol || coin.marketId == marketId {
                return true
            }
            if normalizedSymbolCandidates.contains(coin.symbol) {
                return true
            }
            if let coinMarketId = coin.marketId,
               normalizedSymbolCandidates.contains(coinMarketId) {
                return true
            }
            return false
        }
        if let bestCandidate = matchingCandidates.max(by: {
            let leftScore = marketIdentityLookupScore(for: $0)
            let rightScore = marketIdentityLookupScore(for: $1)
            if leftScore == rightScore {
                return $0.marketIdentity(exchange: exchange).cacheKey < $1.marketIdentity(exchange: exchange).cacheKey
            }
            return leftScore < rightScore
        }) {
            let resolved = bestCandidate.marketIdentity(exchange: exchange)
            if resolved.symbol != symbol || (marketId != nil && resolved.marketId != marketId) {
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] exchange=\(exchange.rawValue) action=graph_identity_normalized from=\(marketId ?? symbol) to=\(resolved.cacheKey)"
                )
            }
            return resolved
        }

        return MarketIdentity(exchange: exchange, symbol: symbol)
    }

    private func normalizedGraphSymbolCandidates(symbol: String, marketId: String?) -> Set<String> {
        var values = Set<String>()

        func append(_ rawValue: String?) {
            guard let rawValue else { return }
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard trimmed.isEmpty == false else { return }
            values.insert(trimmed)
            if trimmed.contains("-") {
                let components = trimmed.split(separator: "-").map(String.init)
                components.forEach { values.insert($0) }
                if let last = components.last {
                    values.insert(last)
                }
            }
            if trimmed.contains("_") {
                let components = trimmed.split(separator: "_").map(String.init)
                components.forEach { values.insert($0) }
                if let first = components.first {
                    values.insert(first)
                }
            }
        }

        append(symbol)
        append(marketId)
        return values
    }

    private func marketLogFields(
        exchange: Exchange,
        symbol: String,
        marketId: String? = nil
    ) -> String {
        resolvedMarketIdentity(
            exchange: exchange,
            symbol: symbol,
            marketId: marketId
        ).logFields
    }

    private func orderHeaderPriceCacheKey(for exchange: Exchange, symbol: String) -> OrderHeaderPriceCacheKey {
        OrderHeaderPriceCacheKey(exchange: exchange, symbol: symbol.uppercased())
    }

    private func orderHeaderCandidateMarketIdentities(
        for coin: CoinInfo,
        exchange: Exchange
    ) -> [MarketIdentity] {
        var identities: [MarketIdentity] = []

        func append(_ marketIdentity: MarketIdentity?) {
            guard let marketIdentity else {
                return
            }
            if identities.contains(marketIdentity) == false {
                identities.append(marketIdentity)
            }
        }

        let selectedIdentity = coin.marketIdentity(exchange: exchange)
        append(selectedIdentity.marketId != nil ? selectedIdentity : nil)
        append(
            marketPresentationSnapshotsByExchange[exchange]?.rows.first(where: {
                $0.symbol == coin.symbol
            })?.marketIdentity
        )
        append(
            activeMarketPresentationSnapshot?.exchange == exchange
                ? activeMarketPresentationSnapshot?.rows.first(where: { $0.symbol == coin.symbol })?.marketIdentity
                : nil
        )
        append(
            resolvedMarketIdentity(
                exchange: exchange,
                symbol: coin.symbol,
                marketId: coin.marketId,
                preferSelectedCoinIdentity: false
            )
        )
        append(selectedIdentity)
        append(MarketIdentity(exchange: exchange, symbol: coin.symbol))

        return identities
    }

    private func isOrderHeaderTickerPreferred(_ incoming: TickerData, over existing: TickerData) -> Bool {
        let preferredTicker = Self.preferredTicker(existing, incoming)
        if preferredTicker.delivery != existing.delivery {
            return preferredTicker.delivery == incoming.delivery
        }
        if preferredTicker.isStale != existing.isStale {
            return preferredTicker.isStale == incoming.isStale
        }
        if preferredTicker.timestamp != existing.timestamp {
            return preferredTicker.timestamp == incoming.timestamp
        }
        if preferredTicker.sparklinePointCount != existing.sparklinePointCount {
            return preferredTicker.sparklinePointCount == incoming.sparklinePointCount
        }
        return preferredTicker.price == incoming.price
            && preferredTicker.change == incoming.change
            && preferredTicker.volume == incoming.volume
    }

    private func resolvedTickerForOrderHeader(
        coin: CoinInfo,
        exchange: Exchange
    ) -> (ticker: TickerData, marketIdentity: MarketIdentity, source: OrderHeaderPriceSource)? {
        let candidateIdentities = orderHeaderCandidateMarketIdentities(for: coin, exchange: exchange)
        var bestMatch: (ticker: TickerData, marketIdentity: MarketIdentity)?

        for marketIdentity in candidateIdentities {
            guard let ticker = pricesByMarketIdentity[marketIdentity], ticker.price > 0 else {
                continue
            }
            if let existing = bestMatch {
                if isOrderHeaderTickerPreferred(ticker, over: existing.ticker) {
                    bestMatch = (ticker, marketIdentity)
                }
            } else {
                bestMatch = (ticker, marketIdentity)
            }
        }

        guard let bestMatch else {
            return nil
        }

        let selectedSource: OrderHeaderPriceSource = bestMatch.ticker.delivery == .live && bestMatch.ticker.isStale == false
            ? .selectedTicker
            : .marketSnapshot
        return (bestMatch.ticker, bestMatch.marketIdentity, selectedSource)
    }

    private func lastGraphPriceForOrderHeader(
        coin: CoinInfo,
        exchange: Exchange
    ) -> (price: Double, marketIdentity: MarketIdentity)? {
        let candidateIdentities = orderHeaderCandidateMarketIdentities(for: coin, exchange: exchange)

        for marketIdentity in candidateIdentities {
            if let snapshotPrice = sparklineSnapshot(marketIdentity: marketIdentity)?.points.last,
               snapshotPrice.isNaN == false,
               snapshotPrice > 0 {
                return (snapshotPrice, marketIdentity)
            }
            if let displayPrice = stableSparklineDisplay(marketIdentity: marketIdentity)?.points.last,
               displayPrice.isNaN == false,
               displayPrice > 0 {
                return (displayPrice, marketIdentity)
            }
            if let rowPrice = marketPresentationSnapshotsByExchange[exchange]?.rows.first(where: {
                $0.marketIdentity == marketIdentity
            })?.sparkline.last,
               rowPrice.isNaN == false,
               rowPrice > 0 {
                return (rowPrice, marketIdentity)
            }
        }

        return nil
    }

    private func lastKnownGoodOrderHeaderTicker(
        coin: CoinInfo,
        exchange: Exchange
    ) -> TickerData? {
        let cacheKey = orderHeaderPriceCacheKey(for: exchange, symbol: coin.symbol)
        var candidates: [TickerData] = []
        if let cachedTicker = lastKnownGoodOrderHeaderTickerByKey[cacheKey], cachedTicker.price > 0 {
            candidates.append(cachedTicker)
        }
        for marketIdentity in orderHeaderCandidateMarketIdentities(for: coin, exchange: exchange) {
            let statsKey = ChartResourceKey(marketIdentity: marketIdentity)
            if let statsTicker = lastSuccessfulStats[statsKey], statsTicker.price > 0 {
                candidates.append(statsTicker)
            }
        }
        return candidates.reduce(nil) { partialResult, ticker in
            guard let partialResult else {
                return ticker
            }
            return Self.preferredTicker(partialResult, ticker)
        }
    }

    private func resolveOrderHeaderPricePresentation(
        coin: CoinInfo,
        exchange: Exchange
    ) -> OrderHeaderPricePresentation {
        let fallbackIdentity = MarketIdentity(exchange: exchange, symbol: coin.symbol)

        if let resolvedTicker = resolvedTickerForOrderHeader(coin: coin, exchange: exchange) {
            return OrderHeaderPricePresentation(
                marketIdentity: resolvedTicker.marketIdentity,
                price: resolvedTicker.ticker.price,
                source: resolvedTicker.source,
                isFallbackApplied: resolvedTicker.source != .selectedTicker,
                isStale: resolvedTicker.ticker.isStale
            )
        }

        if let graphPrice = lastGraphPriceForOrderHeader(coin: coin, exchange: exchange) {
            return OrderHeaderPricePresentation(
                marketIdentity: graphPrice.marketIdentity,
                price: graphPrice.price,
                source: .graphLatestPoint,
                isFallbackApplied: true,
                isStale: true
            )
        }

        if let cachedTicker = lastKnownGoodOrderHeaderTicker(coin: coin, exchange: exchange) {
            return OrderHeaderPricePresentation(
                marketIdentity: resolvedMarketIdentity(
                    exchange: exchange,
                    symbol: coin.symbol,
                    marketId: coin.marketId,
                    preferSelectedCoinIdentity: false
                ),
                price: cachedTicker.price,
                source: .lastKnownGood,
                isFallbackApplied: true,
                isStale: true
            )
        }

        return OrderHeaderPricePresentation(
            marketIdentity: fallbackIdentity,
            price: nil,
            source: .missing,
            isFallbackApplied: false,
            isStale: false
        )
    }

    private func rememberOrderHeaderLastKnownGoodPrice(
        ticker: TickerData,
        exchange: Exchange,
        symbol: String
    ) {
        guard ticker.price > 0 else {
            return
        }
        lastKnownGoodOrderHeaderTickerByKey[orderHeaderPriceCacheKey(for: exchange, symbol: symbol)] = ticker
    }

    func logOrderHeaderPriceDebug(reason: String, force: Bool = false) {
        guard let coin = selectedCoin else {
            return
        }

        let selectedIdentity = coin.marketIdentity(exchange: selectedExchange)
        let canonicalIdentity = resolvedMarketIdentity(
            exchange: selectedExchange,
            symbol: coin.symbol,
            marketId: coin.marketId,
            preferSelectedCoinIdentity: false
        )
        let marketRowIdentity = marketPresentationSnapshotsByExchange[selectedExchange]?.rows.first(where: {
            $0.symbol == coin.symbol
        })?.marketIdentity
        let graphIdentity = lastGraphPriceForOrderHeader(coin: coin, exchange: selectedExchange)?.marketIdentity
        let subscriptionIdentity = desiredPublicSubscriptions.first(where: {
            $0.channel == .ticker
                && $0.marketIdentity?.exchange == selectedExchange
                && $0.marketIdentity?.symbol == coin.symbol
        })?.marketIdentity
        let presentation = resolveOrderHeaderPricePresentation(coin: coin, exchange: selectedExchange)
        let marketIdText = presentation.marketIdentity.marketId ?? canonicalIdentity.marketId ?? selectedIdentity.marketId ?? "-"
        let signature = [
            reason,
            selectedExchange.rawValue,
            coin.symbol,
            marketIdText,
            presentation.source.rawValue,
            presentation.price.map { String(format: "%.8f", $0) } ?? "-",
            presentation.isFallbackApplied ? "1" : "0",
            selectedIdentity.cacheKey,
            canonicalIdentity.cacheKey,
            marketRowIdentity?.cacheKey ?? "-",
            graphIdentity?.cacheKey ?? "-",
            subscriptionIdentity?.cacheKey ?? "-"
        ].joined(separator: "|")

        if force == false, lastLoggedOrderHeaderPriceSignature == signature {
            return
        }
        lastLoggedOrderHeaderPriceSignature = signature

        AppLogger.debug(
            .network,
            "[OrderHeaderPriceDebug] exchange=\(selectedExchange.rawValue) symbol=\(coin.symbol) marketId=\(marketIdText) selectedSource=\(presentation.source.rawValue) priceValue=\(presentation.price.map { String($0) } ?? "-") fallbackApplied=\(presentation.isFallbackApplied) headerKey=\(selectedIdentity.cacheKey) canonicalKey=\(canonicalIdentity.cacheKey) marketListKey=\(marketRowIdentity?.cacheKey ?? "-") graphKey=\(graphIdentity?.cacheKey ?? "-") tickerSubscriptionKey=\(subscriptionIdentity?.cacheKey ?? "-") reason=\(reason)"
        )

        guard presentation.price == nil else {
            return
        }

        let missingReason = [
            resolvedTickerForOrderHeader(coin: coin, exchange: selectedExchange) == nil ? "no_ticker" : nil,
            lastGraphPriceForOrderHeader(coin: coin, exchange: selectedExchange) == nil ? "no_graph" : nil,
            lastKnownGoodOrderHeaderTicker(coin: coin, exchange: selectedExchange) == nil ? "no_last_known_good" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ",")
        let missingSignature = "\(selectedExchange.rawValue)|\(coin.symbol)|\(marketIdText)|\(missingReason)"
        guard force || lastLoggedOrderHeaderMissingPriceSignature != missingSignature else {
            return
        }
        lastLoggedOrderHeaderMissingPriceSignature = missingSignature
        AppLogger.debug(
            .network,
            "[OrderHeaderPriceDebug] action=missing_price reason=\(missingReason.isEmpty ? "no_valid_price_source" : missingReason) exchange=\(selectedExchange.rawValue) symbol=\(coin.symbol) marketId=\(marketIdText)"
        )
    }

    private nonisolated static func sparklineSourceVersion(from date: Date?) -> Int {
        guard let date else {
            return 0
        }
        return Int((date.timeIntervalSinceReferenceDate * 1_000).rounded())
    }

    private func marketIdentityLookupScore(for coin: CoinInfo) -> Int {
        var score = 0
        if coin.marketId != nil { score += 8 }
        if coin.iconURL != nil { score += 3 }
        if coin.name.isEmpty == false { score += 2 }
        if coin.nameEn.isEmpty == false { score += 2 }
        return score
    }

    private nonisolated static func sparklineQuality(
        for row: MarketRowViewState
    ) -> MarketSparklineQuality {
        MarketSparklineQuality(
            detailLevel: row.sparklinePayload.detailLevel,
            graphState: row.graphState,
            pointCount: row.sparklinePointCount,
            hasRenderableGraph: row.graphState.keepsVisibleGraph
                && MarketSparklineRenderPolicy.hasRenderableGraph(
                    points: row.sparkline,
                    pointCount: row.sparklinePointCount
            ),
            graphPathVersion: row.graphPathVersion,
            renderVersion: row.graphRenderVersion,
            sourceVersion: row.sparklinePayload.sourceVersion,
            shapeQuality: row.sparklinePayload.shapeQuality
        )
    }

    private nonisolated static func sparklineQuality(
        for snapshot: SparklineLayerSnapshot,
        staleInterval: TimeInterval,
        now: Date
    ) -> MarketSparklineQuality {
        let graphState = snapshot.graphState(staleInterval: staleInterval, now: now)
        return MarketSparklineQuality(
            graphState: graphState,
            points: snapshot.points,
            pointCount: snapshot.pointCount,
            sourceVersion: sparklineSourceVersion(from: snapshot.fetchedAt)
        )
    }

    private nonisolated static func sparklineQuality(
        for display: StableSparklineDisplay
    ) -> MarketSparklineQuality {
        MarketSparklineQuality(
            graphState: display.graphState,
            points: display.points,
            pointCount: display.pointCount,
            sourceVersion: display.sourceVersion
        )
    }

    private nonisolated static func logGraphQualityDecision(
        marketIdentity: MarketIdentity,
        existing: MarketSparklineQuality?,
        incoming: MarketSparklineQuality,
        decision: MarketSparklineQualityDecision,
        category: AppLogCategory = .network
    ) {
        AppLogger.debug(
            category,
            "[GraphQualityDebug] \(marketIdentity.logFields) action=promote_or_reject oldDetail=\(existing?.detailLevel.cacheComponent ?? "none") newDetail=\(incoming.detailLevel.cacheComponent) oldPointCount=\(existing?.pointCount ?? 0) newPointCount=\(incoming.pointCount) accepted=\(decision.accepted) reason=\(decision.reason)"
        )
    }

    private nonisolated static func preferredTicker(_ existing: TickerData, _ incoming: TickerData) -> TickerData {
        let existingLiveScore = existing.delivery == .live ? 2 : 0
        let incomingLiveScore = incoming.delivery == .live ? 2 : 0
        if existingLiveScore != incomingLiveScore {
            return incomingLiveScore > existingLiveScore ? incoming : existing
        }

        let existingStaleScore = existing.isStale ? 0 : 1
        let incomingStaleScore = incoming.isStale ? 0 : 1
        if existingStaleScore != incomingStaleScore {
            return incomingStaleScore > existingStaleScore ? incoming : existing
        }

        let existingPointCount = existing.sparklinePointCount ?? existing.sparkline.count
        let incomingPointCount = incoming.sparklinePointCount ?? incoming.sparkline.count
        if existingPointCount != incomingPointCount {
            return incomingPointCount > existingPointCount ? incoming : existing
        }

        let existingTimestamp = existing.timestamp ?? .distantPast
        let incomingTimestamp = incoming.timestamp ?? .distantPast
        if incomingTimestamp != existingTimestamp {
            return incomingTimestamp > existingTimestamp ? incoming : existing
        }

        return incoming
    }

    private nonisolated static func preferredStableSparklineDisplay(
        _ existing: StableSparklineDisplay,
        _ incoming: StableSparklineDisplay
    ) -> StableSparklineDisplay {
        let existingQuality = sparklineQuality(for: existing)
        let incomingQuality = sparklineQuality(for: incoming)
        let decision = incomingQuality.promotionDecision(over: existingQuality)
        if decision.accepted {
            return incoming
        }
        if decision.reason == "same_quality_skip",
           incoming.updatedAt > existing.updatedAt,
           incoming.generation >= existing.generation {
            return incoming
        }
        return existing
    }

    private func canonicalMarketIdentityMapping(for exchange: Exchange) -> [MarketIdentity: MarketIdentity] {
        let candidates = (marketsByExchange[exchange] ?? [])
            + (tickerSnapshotCoinsByExchange[exchange] ?? [])
            + (marketPresentationSnapshotsByExchange[exchange]?.rows.map(\.coin) ?? [])

        var bestByFallback = [MarketIdentity: (identity: MarketIdentity, score: Int)]()
        for coin in candidates {
            let exactIdentity = coin.marketIdentity(exchange: exchange)
            guard exactIdentity.marketId != nil else {
                continue
            }

            let fallbackIdentity = MarketIdentity(exchange: exchange, symbol: exactIdentity.symbol)
            guard fallbackIdentity != exactIdentity else {
                continue
            }

            let candidateScore = marketIdentityLookupScore(for: coin)
            if let existing = bestByFallback[fallbackIdentity] {
                if candidateScore > existing.score
                    || (candidateScore == existing.score && exactIdentity.cacheKey < existing.identity.cacheKey) {
                    bestByFallback[fallbackIdentity] = (exactIdentity, candidateScore)
                }
            } else {
                bestByFallback[fallbackIdentity] = (exactIdentity, candidateScore)
            }
        }

        return bestByFallback.mapValues(\.identity)
    }

    private func promoteResolvedMarketIdentityState(for exchange: Exchange) {
        let identityMapping = canonicalMarketIdentityMapping(for: exchange)
        guard identityMapping.isEmpty == false else {
            return
        }

        func remappedDictionary<K: Hashable, V>(
            _ dictionary: [K: V],
            transform: (K) -> K,
            merge: (V, V) -> V
        ) -> [K: V] {
            dictionary.reduce(into: [K: V]()) { partialResult, element in
                let remappedKey = transform(element.key)
                if let existing = partialResult[remappedKey] {
                    partialResult[remappedKey] = merge(existing, element.value)
                } else {
                    partialResult[remappedKey] = element.value
                }
            }
        }

        func remappedIdentities(_ identities: [MarketIdentity]) -> [MarketIdentity] {
            Self.deduplicatedMarketIdentities(identities.map { identityMapping[$0] ?? $0 })
        }

        func remappedIdentitySet(_ identities: Set<MarketIdentity>) -> Set<MarketIdentity> {
            Set(identities.map { identityMapping[$0] ?? $0 })
        }

        pricesByMarketIdentity = remappedDictionary(
            pricesByMarketIdentity,
            transform: { identityMapping[$0] ?? $0 },
            merge: Self.preferredTicker
        )

        if let supportedIntervals = supportedIntervalsByExchangeAndMarketIdentity[exchange] {
            supportedIntervalsByExchangeAndMarketIdentity[exchange] = remappedDictionary(
                supportedIntervals,
                transform: { identityMapping[$0] ?? $0 },
                merge: Self.mergedIntervals
            )
        }

        filteredMarketIdentitiesByExchange[exchange] = remappedIdentities(
            filteredMarketIdentitiesByExchange[exchange] ?? []
        )
        filteredTickerIdentitiesByExchange[exchange] = remappedIdentities(
            filteredTickerIdentitiesByExchange[exchange] ?? []
        )
        visibleMarketIdentitiesByExchange[exchange] = remappedIdentities(
            visibleMarketIdentitiesByExchange[exchange] ?? []
        )
        loadingSparklineMarketIdentitiesByExchange[exchange] = remappedIdentitySet(
            loadingSparklineMarketIdentitiesByExchange[exchange] ?? []
        )
        unavailableSparklineMarketIdentitiesByExchange[exchange] = remappedIdentitySet(
            unavailableSparklineMarketIdentitiesByExchange[exchange] ?? []
        )
        unsupportedSparklineMarketIdentitiesByExchange[exchange] = remappedIdentitySet(
            unsupportedSparklineMarketIdentitiesByExchange[exchange] ?? []
        )

        var remappedSparklineSnapshotsByKey = [SparklineCacheKey: SparklineLayerSnapshot]()
        for (key, snapshot) in sparklineSnapshotsByKey {
            let targetIdentity = identityMapping[key.marketIdentity] ?? key.marketIdentity
            let targetKey = SparklineCacheKey(marketIdentity: targetIdentity, interval: key.interval)
            if let existing = remappedSparklineSnapshotsByKey[targetKey] {
                remappedSparklineSnapshotsByKey[targetKey] = shouldReplaceSparklineSnapshot(
                    existing: existing,
                    incoming: snapshot,
                    marketIdentity: targetIdentity
                ) ? snapshot : existing
            } else {
                remappedSparklineSnapshotsByKey[targetKey] = snapshot
            }
        }
        sparklineSnapshotsByKey = remappedSparklineSnapshotsByKey

        var remappedStableSparklineDisplaysByKey = [MarketGraphBindingKey: StableSparklineDisplay]()
        for (key, display) in stableSparklineDisplaysByKey {
            let targetIdentity = identityMapping[key.marketIdentity] ?? key.marketIdentity
            let targetKey = MarketGraphBindingKey(marketIdentity: targetIdentity, interval: key.interval)
            let targetDisplay = StableSparklineDisplay(
                key: targetKey,
                points: display.points,
                pointCount: display.pointCount,
                graphState: display.graphState,
                generation: display.generation,
                updatedAt: display.updatedAt,
                sourceVersion: display.sourceVersion
            )
            if let existing = remappedStableSparklineDisplaysByKey[targetKey] {
                remappedStableSparklineDisplaysByKey[targetKey] = Self.preferredStableSparklineDisplay(
                    existing,
                    targetDisplay
                )
            } else {
                remappedStableSparklineDisplaysByKey[targetKey] = targetDisplay
            }
        }
        stableSparklineDisplaysByKey = remappedStableSparklineDisplaysByKey

        sparklineFetchTasksByKey = remappedDictionary(
            sparklineFetchTasksByKey,
            transform: { key in
                SparklineCacheKey(
                    marketIdentity: identityMapping[key.marketIdentity] ?? key.marketIdentity,
                    interval: key.interval
                )
            },
            merge: { existing, _ in existing }
        )
        sparklineFailureCooldownUntilByKey = remappedDictionary(
            sparklineFailureCooldownUntilByKey,
            transform: { key in
                SparklineCacheKey(
                    marketIdentity: identityMapping[key.marketIdentity] ?? key.marketIdentity,
                    interval: key.interval
                )
            },
            merge: max
        )
        lastSparklineRefreshAttemptAtByKey = remappedDictionary(
            lastSparklineRefreshAttemptAtByKey,
            transform: { key in
                SparklineCacheKey(
                    marketIdentity: identityMapping[key.marketIdentity] ?? key.marketIdentity,
                    interval: key.interval
                )
            },
            merge: max
        )

        AppLogger.debug(
            .network,
            "[MarketIdentity] exchange=\(exchange.rawValue) action=promote_state count=\(identityMapping.count)"
        )
    }

    private func catalogSupportedIntervalsByMarketIdentity(
        from snapshot: MarketCatalogSnapshot
    ) -> [MarketIdentity: [String]] {
        var intervalsByMarketIdentity = [MarketIdentity: [String]]()
        for coin in snapshot.markets {
            let marketIdentity = coin.marketIdentity(exchange: snapshot.exchange)
            let incomingIntervals = snapshot.supportedIntervalsBySymbol[coin.symbol] ?? []
            if let existingIntervals = intervalsByMarketIdentity[marketIdentity] {
                intervalsByMarketIdentity[marketIdentity] = Self.mergedIntervals(
                    existing: existingIntervals,
                    incoming: incomingIntervals
                )
            } else {
                intervalsByMarketIdentity[marketIdentity] = incomingIntervals
            }
        }

        for (symbol, intervals) in snapshot.supportedIntervalsBySymbol {
            let marketIdentity = resolvedMarketIdentity(exchange: snapshot.exchange, symbol: symbol)
            if let existingIntervals = intervalsByMarketIdentity[marketIdentity] {
                intervalsByMarketIdentity[marketIdentity] = Self.mergedIntervals(
                    existing: existingIntervals,
                    incoming: intervals
                )
            } else {
                intervalsByMarketIdentity[marketIdentity] = intervals
            }
        }

        return intervalsByMarketIdentity
    }

    private func resolvedMarketIdentities(exchange: Exchange, symbols: [String]) -> [MarketIdentity] {
        Self.deduplicatedMarketIdentities(
            symbols.map { resolvedMarketIdentity(exchange: exchange, symbol: $0) }
        )
    }

    private nonisolated static func deduplicatedMarketIdentities(
        _ marketIdentities: [MarketIdentity]
    ) -> [MarketIdentity] {
        var seen = Set<MarketIdentity>()
        return marketIdentities.filter { marketIdentity in
            seen.insert(marketIdentity).inserted
        }
    }

    private nonisolated static func mergedIntervals(
        existing: [String],
        incoming: [String]
    ) -> [String] {
        var merged = existing
        for interval in incoming where merged.contains(interval) == false {
            merged.append(interval)
        }
        return merged
    }

    func markMarketRowVisible(symbol: String, exchange: Exchange) {
        if let visibleRowIdentity = displayedMarketRows.first(where: {
            $0.exchange == exchange && $0.symbol == symbol
        })?.marketIdentity {
            markMarketRowVisible(marketIdentity: visibleRowIdentity)
            return
        }
        markMarketRowVisible(marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol))
    }

    func markMarketRowVisible(
        marketIdentity: MarketIdentity,
        surrounding surroundingMarketIdentities: [MarketIdentity] = []
    ) {
        let exchange = marketIdentity.exchange
        guard exchange == selectedExchange else {
            return
        }

        var orderedMarketIdentities = visibleMarketIdentitiesByExchange[exchange] ?? []
        let exposureBand = Self.deduplicatedMarketIdentities(
            [marketIdentity] + surroundingMarketIdentities.filter { $0.exchange == exchange }
        )
        for exposedIdentity in exposureBand.reversed() {
            orderedMarketIdentities.removeAll { $0 == exposedIdentity }
            orderedMarketIdentities.insert(exposedIdentity, at: 0)
        }
        visibleMarketIdentitiesByExchange[exchange] = Array(orderedMarketIdentities.prefix(48))
        lastVisibleMarketRowAtByExchange[exchange] = Date()
        reconcileVisibleSparklines(
            exchange: exchange,
            reason: "first_visible_rows"
        )
        enqueueVisiblePriorityRefineIfNeeded(
            for: marketIdentity,
            exchange: exchange,
            reason: "row_visible_priority_\(marketIdentity.cacheKey)"
        )
        scheduleVisibleSparklineHydration(
            for: exchange,
            reason: "row_visible_\(marketIdentity.cacheKey)"
        )
        scheduleMarketImageHydration(
            for: exchange,
            reason: "row_visible_\(marketIdentity.cacheKey)"
        )
    }

    private func resetPendingMarketRowPatches(reason: String) {
        let pendingCount = pendingMarketRowPatchesByExchange.values.reduce(0) { partialResult, patches in
            partialResult + patches.count
        }
        marketRowPatchTask?.cancel()
        marketRowPatchTask = nil
        pendingMarketRowPatchesByExchange.removeAll(keepingCapacity: true)
        guard pendingCount > 0 else {
            return
        }
        AppLogger.debug(
            .network,
            "[GraphPipeline] exchange=\(selectedExchange.rawValue) generation=\(marketPresentationGeneration) phase=patch_queue_reset dropped=\(pendingCount) reason=\(reason)"
        )
    }

    private func currentPlaceholderFinalTotal() -> Int {
        AssetImageDebugClient.shared.snapshotEventCounts()["placeholder_final"] ?? 0
    }

    func markKimchiRowVisible(symbol: String, exchange: Exchange) {
        guard activeTab == .kimchi, currentKimchiDomesticExchange == exchange else {
            return
        }

        var orderedSymbols = visibleKimchiSymbolsByExchange[exchange] ?? []
        orderedSymbols.removeAll { $0 == symbol }
        orderedSymbols.insert(symbol, at: 0)
        visibleKimchiSymbolsByExchange[exchange] = Array(orderedSymbols.prefix(48))
        lastVisibleKimchiRowAtByExchange[exchange] = Date()

        scheduleVisibleKimchiHydration(
            for: exchange,
            reason: "row_visible_\(symbol)"
        )
    }

    private func scheduleMarketImageHydration(
        for exchange: Exchange,
        reason: String
    ) {
        guard activeTab == .market, selectedExchange == exchange else {
            return
        }

        let generation = marketPresentationSnapshotsByExchange[exchange]?.generation ?? marketPresentationGeneration
        let context = ScheduledHydrationContext(exchange: exchange, generation: generation)
        if scheduledMarketImageHydrationContext == context, marketImageHydrationTask != nil {
            return
        }

        marketImageHydrationTask?.cancel()
        scheduledMarketImageHydrationContext = context
        marketImageHydrationTask = Task { @MainActor [weak self] in
            guard let self, Task.isCancelled == false else {
                return
            }
            defer {
                if self.scheduledMarketImageHydrationContext == context {
                    self.scheduledMarketImageHydrationContext = nil
                    self.marketImageHydrationTask = nil
                }
            }
            try? await Task.sleep(nanoseconds: self.marketImageHydrationDebounceNanoseconds)
            guard Task.isCancelled == false else {
                return
            }
            guard self.scheduledMarketImageHydrationContext == context else {
                return
            }
            await self.runMarketImageHydration(
                exchange: exchange,
                generation: generation,
                reason: reason
            )
        }
    }

    private func runMarketImageHydration(
        exchange: Exchange,
        generation: Int,
        reason: String
    ) async {
        guard activeTab == .market,
              selectedExchange == exchange,
              let snapshot = marketPresentationSnapshotsByExchange[exchange],
              snapshot.generation == generation else {
            return
        }

        _ = warmMarketImages(
            for: snapshot,
            reason: reason,
            visibleMode: .visible,
            applyImmediateToSnapshot: false
        )
    }

    private func warmMarketImages(
        for snapshot: MarketPresentationSnapshot,
        reason: String,
        visibleMode: AssetImageRequestMode,
        applyImmediateToSnapshot: Bool
    ) -> MarketPresentationSnapshot {
        guard activeTab == .market, selectedExchange == snapshot.exchange else {
            return snapshot
        }

        let visibleRows = Array(
            prioritizedVisibleImageRows(
                from: snapshot.rows,
                exchange: snapshot.exchange
            )
            .prefix(marketImageVisibleBatchSize)
        )
        let visibleIdentities = Set(visibleRows.map(\.marketIdentity))
        let canPrefetchNearVisible = applyImmediateToSnapshot == false
            && marketFullHydrationPendingExchanges.contains(snapshot.exchange) == false
        let nearVisibleRows: [MarketRowViewState]
        if canPrefetchNearVisible {
            nearVisibleRows = Array(
                prioritizedPrefetchImageRows(
                    from: snapshot.rows,
                    exchange: snapshot.exchange,
                    excluding: visibleIdentities
                )
                .prefix(marketImagePrefetchBatchSize)
            )
        } else {
            nearVisibleRows = []
        }

        guard visibleRows.isEmpty == false || nearVisibleRows.isEmpty == false else {
            return snapshot
        }

        if applyImmediateToSnapshot == false {
            let hydrationSignature = marketImageHydrationSignature(
                exchange: snapshot.exchange,
                generation: snapshot.generation,
                visibleRows: visibleRows,
                nearVisibleRows: nearVisibleRows
            )
            if lastMarketImageHydrationSignatureByExchange[snapshot.exchange] == hydrationSignature {
                return snapshot
            }
            lastMarketImageHydrationSignatureByExchange[snapshot.exchange] = hydrationSignature
        }

        AssetImageDebugClient.shared.log(
            .warmupStart,
            marketIdentity: nil,
            category: .network,
            details: [
                "exchange": snapshot.exchange.rawValue,
                "generation": "\(snapshot.generation)",
                "nearVisibleCount": "\(nearVisibleRows.count)",
                "reason": reason,
                "visibleCount": "\(visibleRows.count)"
            ]
        )

        var updatedRows = snapshot.rows
        let rowIndexByMarketIdentity = Dictionary(uniqueKeysWithValues: updatedRows.enumerated().map { ($0.element.marketIdentity, $0.offset) })

        func applyImmediateState(_ state: MarketRowSymbolImageState, to row: MarketRowViewState) {
            guard applyImmediateToSnapshot,
                  let rowIndex = rowIndexByMarketIdentity[row.marketIdentity],
                  updatedRows[rowIndex].imageURL == row.imageURL,
                  updatedRows[rowIndex].symbolImageState != state else {
                return
            }
            updatedRows[rowIndex] = updatedRows[rowIndex].replacingSymbolImage(state: state)
        }

        for row in visibleRows {
            guard Task.isCancelled == false else {
                return snapshot
            }
            let immediateState = startMarketImageWarmup(
                row: row,
                generation: snapshot.generation,
                mode: visibleMode,
                patchVisible: true,
                reason: "row_visible_\(row.marketIdentity.cacheKey)"
            )
            if let immediateState {
                applyImmediateState(immediateState, to: row)
            }
        }

        for row in nearVisibleRows {
            guard Task.isCancelled == false else {
                return snapshot
            }
            let immediateState = startMarketImageWarmup(
                row: row,
                generation: snapshot.generation,
                mode: .prefetch,
                patchVisible: false,
                reason: "near_visible_\(row.marketIdentity.cacheKey)"
            )
            if let immediateState {
                applyImmediateState(immediateState, to: row)
            }
        }

        guard applyImmediateToSnapshot, updatedRows != snapshot.rows else {
            return snapshot
        }

        return MarketPresentationSnapshot(
            exchange: snapshot.exchange,
            generation: snapshot.generation,
            universe: snapshot.universe,
            rows: updatedRows,
            meta: snapshot.meta
        )
    }

    private func marketImageHydrationSignature(
        exchange: Exchange,
        generation: Int,
        visibleRows: [MarketRowViewState],
        nearVisibleRows: [MarketRowViewState]
    ) -> String {
        let components = (visibleRows.map { row in
            "v:\(row.marketIdentity.cacheKey):\(row.imageURL ?? "-"):\(assetImageClient.assetState(for: row.symbolImageDescriptor).rawValue)"
        } + nearVisibleRows.map { row in
            "n:\(row.marketIdentity.cacheKey):\(row.imageURL ?? "-"):\(assetImageClient.assetState(for: row.symbolImageDescriptor).rawValue)"
        })
        return "\(exchange.rawValue)|\(generation)|" + components.joined(separator: ",")
    }

    private func startMarketImageWarmup(
        row: MarketRowViewState,
        generation: Int,
        mode: AssetImageRequestMode,
        patchVisible: Bool,
        reason: String
    ) -> MarketRowSymbolImageState? {
        guard shouldHydrateMarketImage(for: row) else {
            return nil
        }

        let handle = assetImageClient.prepareImageRequest(for: row.symbolImageDescriptor, mode: mode)
        if let immediateOutcome = handle.immediateOutcome {
            if immediateOutcome.state.showsRenderedImage {
                marketImageRetryTasksByMarketIdentity[row.marketIdentity]?.cancel()
                marketImageRetryTasksByMarketIdentity[row.marketIdentity] = nil
            } else if patchVisible {
                scheduleMarketImageRetryIfNeeded(
                    for: row,
                    generation: generation,
                    outcome: immediateOutcome
                )
            }
            if patchVisible, immediateOutcome.state != row.symbolImageState {
                enqueueSymbolImagePatch(
                    marketIdentity: row.marketIdentity,
                    exchange: row.exchange,
                    generation: generation,
                    expectedImageURL: row.imageURL,
                    nextState: immediateOutcome.state,
                    reason: reason
                )
            }
            return immediateOutcome.state
        }

        guard let task = handle.task, patchVisible else {
            return nil
        }

        Task { @MainActor [weak self] in
            let outcome = await task.value
            guard let self, Task.isCancelled == false else {
                return
            }
            if outcome.state.showsRenderedImage {
                self.marketImageRetryTasksByMarketIdentity[row.marketIdentity]?.cancel()
                self.marketImageRetryTasksByMarketIdentity[row.marketIdentity] = nil
            } else {
                self.scheduleMarketImageRetryIfNeeded(
                    for: row,
                    generation: generation,
                    outcome: outcome
                )
            }
            self.enqueueSymbolImagePatch(
                marketIdentity: row.marketIdentity,
                exchange: row.exchange,
                generation: generation,
                expectedImageURL: row.imageURL,
                nextState: outcome.state,
                reason: reason
            )
        }

        return nil
    }

    private func scheduleMarketImageRetryIfNeeded(
        for row: MarketRowViewState,
        generation: Int,
        outcome: AssetImageRequestOutcome
    ) {
        guard row.exchange == selectedExchange,
              activeTab == .market else {
            return
        }
        switch outcome.fallbackReason {
        case .some(.fetchFailed), .some(.cooldownBlocked):
            break
        default:
            return
        }
        guard marketImageRetryTasksByMarketIdentity[row.marketIdentity] == nil else {
            return
        }

        let retryDelay = max(assetImageClient.cooldownRemaining(for: row.symbolImageDescriptor) ?? 0.45, 0.45)
        marketImageRetryTasksByMarketIdentity[row.marketIdentity] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            guard let self else { return }
            self.marketImageRetryTasksByMarketIdentity[row.marketIdentity] = nil
            guard self.activeTab == .market,
                  self.selectedExchange == row.exchange,
                  self.marketPresentationSnapshotsByExchange[row.exchange]?.generation == generation,
                  (self.visibleMarketIdentitiesByExchange[row.exchange] ?? []).contains(row.marketIdentity) else {
                return
            }
            self.scheduleMarketImageHydration(
                for: row.exchange,
                reason: "image_retry_\(row.marketIdentity.cacheKey)"
            )
        }
    }

    private func prioritizedVisibleImageRows(
        from rows: [MarketRowViewState],
        exchange: Exchange
    ) -> [MarketRowViewState] {
        let rowsByMarketIdentity = Dictionary(uniqueKeysWithValues: rows.map { ($0.marketIdentity, $0) })
        var orderedRows = [MarketRowViewState]()
        var seen = Set<MarketIdentity>()

        func append(_ row: MarketRowViewState?) {
            guard let row,
                  shouldHydrateMarketImage(for: row),
                  seen.insert(row.marketIdentity).inserted else {
                return
            }
            orderedRows.append(row)
        }

        for marketIdentity in visibleMarketIdentitiesByExchange[exchange] ?? [] {
            append(rowsByMarketIdentity[marketIdentity])
        }
        for row in rows.prefix(marketImageVisibleBatchSize) {
            append(row)
        }

        return orderedRows
    }

    private func prioritizedPrefetchImageRows(
        from rows: [MarketRowViewState],
        exchange: Exchange,
        excluding excludedIdentities: Set<MarketIdentity>
    ) -> [MarketRowViewState] {
        let prioritySymbols = ["BTC", "ETH", "XRP", "SOL", "DOGE", "USDT", "USDC", "ADA"]
        var orderedRows = [MarketRowViewState]()
        var seen = excludedIdentities

        func append(_ row: MarketRowViewState?) {
            guard let row,
                  shouldHydrateMarketImage(for: row),
                  seen.insert(row.marketIdentity).inserted else {
                return
            }
            orderedRows.append(row)
        }

        if let selectedCoinIdentity = selectedExchange == exchange
            ? selectedCoin?.marketIdentity(exchange: exchange)
            : nil {
            append(rows.first { $0.marketIdentity == selectedCoinIdentity })
        }

        for favoriteSymbol in favCoins.sorted() {
            append(rows.first { $0.symbol == favoriteSymbol })
        }

        for prioritySymbol in prioritySymbols {
            append(rows.first { $0.symbol == prioritySymbol })
        }

        for row in rows.prefix(marketFirstPaintRowLimit + marketImagePrefetchBatchSize) {
            append(row)
        }

        return orderedRows
    }

    private func shouldPrioritizeVisibleSparklineHydration(marketIdentity: MarketIdentity) -> Bool {
        guard let row = marketPresentationSnapshotsByExchange[marketIdentity.exchange]?.rows.first(where: { $0.marketIdentity == marketIdentity }) else {
            return true
        }
        return row.graphState != .liveVisible || row.sparklinePayload.detailLevel.isDetailed == false
    }

    private func bestAvailableSparklineQuality(
        for marketIdentity: MarketIdentity,
        now: Date
    ) -> MarketSparklineQuality? {
        var bestQuality: MarketSparklineQuality?

        func consider(_ candidate: MarketSparklineQuality?) {
            guard let candidate else { return }
            guard let existing = bestQuality else {
                bestQuality = candidate
                return
            }
            if candidate.promotionDecision(over: existing).accepted {
                bestQuality = candidate
            }
        }

        if let display = stableSparklineDisplay(marketIdentity: marketIdentity),
           display.hasRenderableGraph {
            consider(Self.sparklineQuality(for: display))
        }

        if let snapshot = sparklineSnapshot(marketIdentity: marketIdentity) {
            consider(
                Self.sparklineQuality(
                    for: snapshot,
                    staleInterval: sparklineCacheStaleInterval,
                    now: now
                )
            )
        }

        if let row = marketPresentationSnapshotsByExchange[marketIdentity.exchange]?.rows.first(where: { $0.marketIdentity == marketIdentity }) {
            consider(Self.sparklineQuality(for: row))
        }

        return bestQuality
    }

    private func hasPotentialSparklineQualityGain(
        for marketIdentity: MarketIdentity,
        now: Date
    ) -> Bool {
        guard let bestQuality = bestAvailableSparklineQuality(for: marketIdentity, now: now) else {
            return true
        }

        if bestQuality.isUsableGraph == false {
            return true
        }
        if bestQuality.detailLevel.isDetailed == false {
            return true
        }
        if bestQuality.graphState != .liveVisible {
            return true
        }
        if bestQuality.pointCount < MarketSparklineRenderPolicy.promotedGraphPointCountThreshold {
            return true
        }
        if let snapshot = sparklineSnapshot(marketIdentity: marketIdentity) {
            return now.timeIntervalSince(snapshot.fetchedAt) > sparklineCacheStaleInterval
        }
        return false
    }

    private func noteSparklineNoImprovement(
        for marketIdentity: MarketIdentity,
        now: Date = Date()
    ) {
        sparklineNoImprovementUntilByKey[sparklineCacheKey(marketIdentity: marketIdentity)] = now
            .addingTimeInterval(sparklineNoImprovementBackoffInterval)
    }

    private func clearSparklineNoImprovement(
        for marketIdentity: MarketIdentity
    ) {
        sparklineNoImprovementUntilByKey.removeValue(forKey: sparklineCacheKey(marketIdentity: marketIdentity))
    }

    private func clearSparklineFirstPaintHold(for marketIdentity: MarketIdentity) {
        let key = stableSparklineDisplayKey(marketIdentity: marketIdentity)
        sparklineFirstPaintHoldStartedAtByKey.removeValue(forKey: key)
        sparklineFirstPaintHoldFallbackTasksByKey[key]?.cancel()
        sparklineFirstPaintHoldFallbackTasksByKey.removeValue(forKey: key)
    }

    private func cancelSparklineFirstPaintHolds(for exchange: Exchange? = nil) {
        let keys = sparklineFirstPaintHoldFallbackTasksByKey.keys.filter { key in
            exchange == nil || key.exchange == exchange
        }
        for key in keys {
            sparklineFirstPaintHoldFallbackTasksByKey[key]?.cancel()
            sparklineFirstPaintHoldFallbackTasksByKey.removeValue(forKey: key)
            sparklineFirstPaintHoldStartedAtByKey.removeValue(forKey: key)
        }
        if let exchange {
            sparklineFirstPaintHoldStartedAtByKey = sparklineFirstPaintHoldStartedAtByKey.filter { $0.key.exchange != exchange }
        } else {
            sparklineFirstPaintHoldStartedAtByKey.removeAll(keepingCapacity: true)
        }
    }

    private func enqueueVisiblePriorityRefineIfNeeded(
        for marketIdentity: MarketIdentity,
        exchange: Exchange,
        reason: String
    ) {
        let now = Date()
        let generation = marketPresentationGeneration
        let key = sparklineCacheKey(marketIdentity: marketIdentity)

        let skipReason: String?
        if shouldPrioritizeVisibleSparklineHydration(marketIdentity: marketIdentity) == false {
            skipReason = "no_quality_gain"
        } else if sparklineFetchTasksByKey[key] != nil {
            skipReason = "inflight_duplicate"
        } else if let scheduled = scheduledSparklineRequestsByKey[key], scheduled.generation == generation {
            skipReason = "queued_duplicate"
        } else if let noImprovementUntil = sparklineNoImprovementUntilByKey[key],
                  noImprovementUntil > now,
                  hasUsableSparklineGraph(marketIdentity: marketIdentity),
                  hasPotentialSparklineQualityGain(for: marketIdentity, now: now) == false,
                  isVisibleSparklineRedrawTarget(marketIdentity, exchange: exchange) == false {
            skipReason = "no_quality_gain"
        } else if let lastEnqueueAt = lastPriorityVisibleSparklineEnqueueAtByKey[key],
                  now.timeIntervalSince(lastEnqueueAt) < sparklineVisiblePriorityThrottleInterval {
            skipReason = "throttled"
        } else if hasPotentialSparklineQualityGain(for: marketIdentity, now: now) == false {
            skipReason = "no_quality_gain"
        } else {
            skipReason = nil
        }

        if let skipReason {
            AppLogger.debug(
                .network,
                "[GraphEnqueueDebug] \(marketIdentity.logFields) action=skip reason=\(skipReason)"
            )
            return
        }

        lastPriorityVisibleSparklineEnqueueAtByKey[key] = now
        let scheduled = schedulePriorityVisibleSparklineRefresh(
            for: exchange,
            reason: reason
        )
        if scheduled {
            AppLogger.debug(
                .network,
                "[GraphEnqueueDebug] \(marketIdentity.logFields) action=enqueue reason=visible_priority"
            )
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(marketIdentity.logFields) action=visible_priority_refine queued=true"
            )
        } else {
            AppLogger.debug(
                .network,
                "[GraphEnqueueDebug] \(marketIdentity.logFields) action=skip reason=queued_duplicate"
            )
        }
    }

    private func visibleSparklineReconcileIdentities(
        for exchange: Exchange,
        rows: [MarketRowViewState]
    ) -> [MarketIdentity] {
        let visibleMarketIdentities = visibleMarketIdentitiesByExchange[exchange] ?? []
        let firstScreenMarketIdentities = displayedMarketRows
            .filter { $0.exchange == exchange }
            .prefix(sparklineRepresentativeLimit)
            .map(\.marketIdentity)
        let representativeMarketIdentities = rows.prefix(marketRepresentativeRowLimit).map(\.marketIdentity)
        let selectedMarketIdentities = selectedExchange == exchange
            ? [selectedCoin?.marketIdentity(exchange: exchange)].compactMap { $0 }
            : []

        return Self.deduplicatedMarketIdentities(
            visibleMarketIdentities
                + firstScreenMarketIdentities
                + representativeMarketIdentities
                + selectedMarketIdentities
        )
    }

    private func isVisibleSparklineRedrawTarget(
        _ marketIdentity: MarketIdentity,
        exchange: Exchange
    ) -> Bool {
        guard activeTab == .market, selectedExchange == exchange else {
            return false
        }
        if visibleMarketIdentitiesByExchange[exchange]?.contains(marketIdentity) == true {
            return true
        }
        if displayedMarketRows
            .filter({ $0.exchange == exchange })
            .prefix(sparklineRepresentativeLimit)
            .contains(where: { $0.marketIdentity == marketIdentity }) {
            return true
        }
        if representativeMarketRows.contains(where: { $0.marketIdentity == marketIdentity }) {
            return true
        }
        return selectedCoin?.marketIdentity(exchange: exchange) == marketIdentity
    }

    private func isActivelyScrollingMarketRows(
        for exchange: Exchange,
        now: Date
    ) -> Bool {
        guard let lastVisibleAt = lastVisibleMarketRowAtByExchange[exchange] else {
            return false
        }
        return now.timeIntervalSince(lastVisibleAt) < sparklineActiveScrollWindow
    }

    private func priorityVisibleSparklineMarketIdentities(
        for exchange: Exchange,
        rows: [MarketRowViewState]
    ) -> [MarketIdentity] {
        let selectedMarketIdentities = selectedExchange == exchange
            ? [selectedCoin?.marketIdentity(exchange: exchange)].compactMap { $0 }
            : []
        let representativeMarketIdentities = rows.prefix(marketRepresentativeRowLimit).map(\.marketIdentity)
        let visibleMarketIdentities = visibleMarketIdentitiesByExchange[exchange] ?? []
        let nearVisibleMarketIdentities = nearVisibleSparklineMarketIdentities(
            rows: rows,
            visibleMarketIdentities: visibleMarketIdentities,
            radius: 2
        )
        let firstScreenMarketIdentities = rows.prefix(sparklineRepresentativeLimit).map(\.marketIdentity)
        return Self.deduplicatedMarketIdentities(
            selectedMarketIdentities
                + representativeMarketIdentities
                + visibleMarketIdentities
                + nearVisibleMarketIdentities
                + firstScreenMarketIdentities
        )
    }

    private func shouldHydrateMarketImage(for row: MarketRowViewState) -> Bool {
        guard row.hasImage != false || row.imageURL != nil else {
            return row.symbolImageState != .missing
        }

        guard row.imageURL != nil else {
            return row.symbolImageState != .missing
        }

        switch row.symbolImageState {
        case .placeholder:
            return true
        case .missing:
            let assetState = assetImageClient.assetState(for: row.symbolImageDescriptor)
            if assetState == .placeholderPending || assetState == .warming {
                return true
            }
            return assetImageClient.hasTerminalFallback(for: row.symbolImageDescriptor) == false
        case .cached, .live:
            return false
        }
    }

    var kimchiDomesticExchanges: [Exchange] {
        Exchange.allCases.filter { $0.isDomestic && $0.supportsKimchiPremium }
    }

    private var currentKimchiDomesticExchange: Exchange {
        if selectedExchange.isDomestic, selectedExchange.supportsKimchiPremium {
            return selectedExchange
        }
        return selectedDomesticKimchiExchange
    }

    private func chartRequestKey(
        marketIdentity: MarketIdentity,
        interval: String
    ) -> ChartRequestKey {
        ChartRequestKey(
            marketIdentity: marketIdentity,
            interval: interval.lowercased(),
            window: chartWindow
        )
    }

    private func chartRequestKey(
        exchange: Exchange,
        symbol: String,
        interval: String
    ) -> ChartRequestKey {
        chartRequestKey(
            marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol),
            interval: interval
        )
    }

    private func chartResourceKey(marketIdentity: MarketIdentity) -> ChartResourceKey {
        ChartResourceKey(marketIdentity: marketIdentity)
    }

    private func chartResourceKey(exchange: Exchange, symbol: String) -> ChartResourceKey {
        chartResourceKey(marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol))
    }

    private func chartDetailFallbackRequestKey(
        coin: CoinInfo,
        context: ChartRequestContext
    ) -> ChartRequestKey? {
        let primaryKey = chartRequestKey(
            marketIdentity: context.marketIdentity,
            interval: context.mappedInterval
        )
        let fallbackSymbol = SymbolNormalization.canonicalAssetCode(
            exchange: context.exchange,
            rawSymbol: context.symbol,
            marketId: context.marketId,
            canonicalSymbol: coin.canonicalSymbol
        )
        let fallbackKey = chartRequestKey(
            marketIdentity: MarketIdentity(
                exchange: context.exchange,
                symbol: fallbackSymbol
            ),
            interval: context.mappedInterval
        )
        return fallbackKey == primaryKey ? nil : fallbackKey
    }

    private func chartDetailRetainedCandleEntry(
        primaryKey: ChartRequestKey,
        fallbackKey: ChartRequestKey?
    ) -> (key: ChartRequestKey, entry: CandleCacheEntry)? {
        let candidateKeys = [primaryKey, fallbackKey].compactMap { $0 }
        for cache in [lastSuccessfulCandles, candleCacheByKey] {
            for key in candidateKeys {
                if let entry = cache[key],
                   entry.candles.isEmpty == false {
                    return (key, entry)
                }
            }
        }

        let candidateSymbols = Set(candidateKeys.map(\.symbol))
        let candidateMarketIDs = Set(candidateKeys.compactMap(\.marketId))
        func matches(_ entry: CandleCacheEntry) -> Bool {
            guard entry.key.exchange == primaryKey.exchange,
                  entry.key.interval == primaryKey.interval,
                  entry.candles.isEmpty == false else {
                return false
            }
            if let marketID = entry.key.marketId,
               candidateMarketIDs.contains(marketID) {
                return true
            }
            return candidateSymbols.contains(entry.key.symbol)
        }

        if let entry = lastSuccessfulCandles.values
            .filter(matches)
            .sorted(by: { $0.fetchedAt > $1.fetchedAt })
            .first {
            return (entry.key, entry)
        }
        if let entry = candleCacheByKey.values
            .filter(matches)
            .sorted(by: { $0.fetchedAt > $1.fetchedAt })
            .first {
            return (entry.key, entry)
        }
        return nil
    }

    private func storeChartDetailCandleEntry(
        candles: [CandleData],
        meta: ResponseMeta,
        fetchedAt: Date,
        keys: [ChartRequestKey],
        rememberSuccess: Bool
    ) {
        let uniqueKeys = Array(Set(keys))
        for key in uniqueKeys {
            let entry = CandleCacheEntry(
                key: key,
                candles: candles,
                meta: meta,
                fetchedAt: fetchedAt
            )
            candleCacheByKey[key] = entry
            if rememberSuccess, candles.isEmpty == false {
                lastSuccessfulCandles[key] = entry
            }
        }
    }

    private func shouldRetryChartDetailWithFallback(
        _ response: Result<CandleSnapshot, Error>
    ) -> Bool {
        switch response {
        case .success(let snapshot):
            return snapshot.meta.isChartAvailable == false || snapshot.candles.isEmpty
        case .failure:
            return true
        }
    }

    private func isUsableChartDetailSnapshot(_ snapshot: CandleSnapshot) -> Bool {
        snapshot.meta.isChartAvailable != false && snapshot.candles.isEmpty == false
    }

    private func chartDetailRenderVersion(for candles: [CandleData]) -> Int {
        let lastTimestamp = candles.last?.time ?? 0
        return abs((lastTimestamp * 31) + (candles.count * 101))
    }

    private func chartDetailStateDetailLabel(_ state: CandleState) -> String {
        switch state {
        case .loaded:
            return "liveDetailed"
        case .staleCache, .refreshing:
            return "retainedDetailed"
        case .empty:
            return "empty"
        case .idle, .loading, .unavailable, .failed:
            return "none"
        }
    }

    private func chartIntervals(for symbol: String, exchange: Exchange) -> [String] {
        let marketIdentity = resolvedMarketIdentity(exchange: exchange, symbol: symbol)
        return supportedIntervalsByExchangeAndMarketIdentity[exchange]?[marketIdentity]?.map { $0.lowercased() } ?? []
    }

    private func resolvedChartInterval(
        requestedInterval: String,
        symbol: String,
        exchange: Exchange
    ) -> String {
        let normalizedRequested = requestedInterval.lowercased()
        let supported = chartIntervals(for: symbol, exchange: exchange)
        guard supported.isEmpty == false else {
            return normalizedRequested
        }
        if supported.contains(normalizedRequested) {
            return normalizedRequested
        }

        let orderedDefaults = CandleIntervalCatalog.defaultOptions.map(\.value)
        if let requestedIndex = orderedDefaults.firstIndex(of: normalizedRequested) {
            let fallback = supported.min { lhs, rhs in
                let lhsIndex = orderedDefaults.firstIndex(of: lhs) ?? Int.max
                let rhsIndex = orderedDefaults.firstIndex(of: rhs) ?? Int.max
                return abs(lhsIndex - requestedIndex) < abs(rhsIndex - requestedIndex)
            }
            return fallback ?? supported.first ?? normalizedRequested
        }

        return supported.first ?? normalizedRequested
    }

    private func updateChartIntervalIfNeeded(_ interval: String, reason: String) {
        guard chartPeriod.lowercased() != interval.lowercased() else {
            return
        }
        let previous = chartPeriod
        chartPeriod = interval
        let logFields = selectedCoin?.marketIdentity(exchange: selectedExchange).logFields
            ?? "exchange=\(selectedExchange.rawValue) marketId=- symbol=-"
        AppLogger.debug(
            .route,
            "[ChartPipeline] \(logFields) interval=\(previous.uppercased()) phase=interval_remap mappedInterval=\(interval.uppercased()) reason=\(reason)"
        )
    }

    private func describe(_ state: CandleState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded(let candles):
            return "loaded(\(candles.count))"
        case .empty:
            return "empty"
        case .unavailable(let message):
            return "unavailable(\(message))"
        case .failed(let message):
            return "failed(\(message))"
        case .staleCache(let candles):
            return "staleCache(\(candles.count))"
        case .refreshing(let candles):
            return "refreshing(\(candles.count))"
        }
    }

    private func updateCandleState(
        _ newState: CandleState,
        exchange: Exchange,
        symbol: String,
        interval: String,
        phase: String
    ) {
        let previousState = candlesState
        guard previousState != newState else {
            return
        }
        candlesState = newState
        candleChartState = newState.sectionState
        AppLogger.debug(
            .network,
            "[ChartPipeline] \(marketLogFields(exchange: exchange, symbol: symbol)) interval=\(interval.uppercased()) phase=\(phase) state_transition=\(describe(previousState))->\(describe(newState))"
        )
    }

    private func updateOrderbookState(_ newState: OrderBookState) {
        guard orderbookState != newState else { return }
        orderbookState = newState
        orderBookState = newState.sectionState
    }

    private func updateTradesState(_ newState: TradesState) {
        guard recentTradesState != newState else { return }
        recentTradesState = newState
    }

    private func refreshChartSummaryStates(reason: String) {
        guard let coin = selectedCoin else {
            headerSummaryState = .idle
            marketStatsState = .idle
            return
        }

        let marketIdentity = coin.marketIdentity(exchange: selectedExchange)
        let key = chartResourceKey(exchange: selectedExchange, symbol: coin.symbol)
        if let ticker = currentTicker {
            headerSummaryState = .loaded(ticker)
            marketStatsState = .loaded(ticker)
            lastSuccessfulStats[key] = ticker
        } else if let ticker = lastSuccessfulStats[key] {
            headerSummaryState = .loaded(ticker)
            marketStatsState = .loaded(ticker)
        } else {
            headerSummaryState = .empty
            marketStatsState = .empty
        }

        AppLogger.debug(
            .network,
            "[ChartPipeline] \(marketIdentity.logFields) phase=summary_state_refresh reason=\(reason) hasTicker=\(currentTicker != nil)"
        )
    }

    private func userFacingChartMessage(
        for error: Error,
        kind: ChartSectionKind,
        exchange: Exchange
    ) -> (isUnavailable: Bool, message: String) {
        if let networkError = error as? NetworkServiceError {
            switch networkError {
            case .httpError(let statusCode, let rawMessage, let category):
                let normalizedMessage = rawMessage.lowercased()
                let isUnavailable = statusCode == 503
                    || statusCode == 501
                    || category == .maintenance
                    || normalizedMessage.contains("unavailable")
                    || normalizedMessage.contains("temporarily")
                    || normalizedMessage.contains("not supported")
                if isUnavailable {
                    return (true, chartUnavailableMessage(kind: kind, exchange: exchange))
                }
            case .parsingFailed:
                return (false, "\(kind.displayName) 데이터 형식을 해석하지 못했어요. 잠시 후 다시 시도해주세요.")
            case .transportError:
                return (false, "\(kind.displayName) 데이터를 불러오지 못했어요. 네트워크 상태를 확인해주세요.")
            case .invalidURL, .invalidResponse, .authenticationRequired:
                break
            }
        }

        return (false, "\(kind.displayName) 데이터를 불러오지 못했어요. 잠시 후 다시 시도해주세요.")
    }

    private func chartUnavailableMessage(kind: ChartSectionKind, exchange: Exchange) -> String {
        switch kind {
        case .candles:
            return "\(exchange.displayName) 차트 데이터가 일시적으로 제공되지 않고 있어요."
        case .orderbook:
            return "\(exchange.displayName) 호가 데이터가 일시적으로 제공되지 않고 있어요."
        case .trades:
            return "\(exchange.displayName) 최근 체결 데이터가 일시적으로 제공되지 않고 있어요."
        }
    }

    private func staleWarningMessage(kind: ChartSectionKind) -> String {
        switch kind {
        case .candles:
            return "최신 차트 데이터를 불러오지 못했어요. 마지막 데이터를 표시 중입니다."
        case .orderbook:
            return "최신 호가 데이터를 불러오지 못했어요. 마지막 데이터를 표시 중입니다."
        case .trades:
            return "최신 체결 데이터를 불러오지 못했어요. 마지막 데이터를 표시 중입니다."
        }
    }

    private func shouldApplyChartResult(generation: Int, key: ChartRequestKey) -> Bool {
        generation == activeChartRequestGeneration && activeChartRequestKey == key
    }

    private func beginChartBootstrapSession(reason: String) {
        guard activeTab == .chart else {
            return
        }
        chartSecondaryResourcesTask?.cancel()
        chartDeferredSubscriptionTask?.cancel()
        chartSecondarySubscriptionsEnabled = false
        chartEnterStartedAt = Date()
        lastLoggedChartFirstFrameKey = nil
        AppLogger.debug(
            .route,
            "[ChartTab] bootstrap_started exchange=\(selectedExchange.rawValue) symbol=\(selectedCoin?.symbol ?? "-") reason=\(reason)"
        )
    }

    private func cancelChartBootstrapTasks() {
        chartSecondaryResourcesTask?.cancel()
        chartSecondaryResourcesTask = nil
        chartDeferredSubscriptionTask?.cancel()
        chartDeferredSubscriptionTask = nil
    }

    private func logChartFirstUsableFrameIfNeeded(
        context: ChartRequestContext,
        phase: String
    ) {
        guard activeTab == .chart,
              selectedExchange == context.exchange,
              selectedCoin?.marketIdentity(exchange: context.exchange) == context.marketIdentity,
              let startedAt = chartEnterStartedAt else {
            return
        }

        let logKey = "\(context.marketIdentity.cacheKey)|\(context.mappedInterval)"
        guard lastLoggedChartFirstFrameKey != logKey else {
            return
        }

        lastLoggedChartFirstFrameKey = logKey
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        AppLogger.debug(
            .lifecycle,
            "[ChartTab] first frame exchange=\(context.exchange.rawValue) symbol=\(context.symbol) interval=\(context.mappedInterval.uppercased()) elapsedMs=\(elapsedMs) phase=\(phase)"
        )
    }

    private func shouldRunChartSecondaryBootstrap(
        generation: Int,
        requestKey: ChartRequestKey
    ) -> Bool {
        activeTab == .chart
            && shouldApplyChartResult(generation: generation, key: requestKey)
            && Task.isCancelled == false
    }

    private func scheduleChartSecondaryBootstrap(
        context: ChartRequestContext,
        requestKey: ChartRequestKey,
        resourceKey: ChartResourceKey,
        generation: Int,
        reason: String
    ) {
        chartSecondaryResourcesTask?.cancel()
        chartSecondaryResourcesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.chartSecondaryBootstrapDelayNanoseconds)
            guard self.shouldRunChartSecondaryBootstrap(generation: generation, requestKey: requestKey) else {
                return
            }

            self.chartSecondarySubscriptionsEnabled = true
            self.updatePublicSubscriptions(reason: "\(reason)_chart_secondary_streaming")

            async let orderbookResult: Result<OrderbookSnapshot, Error> = self.fetchOrderbookSnapshot(for: resourceKey)
            async let tradesResult: Result<PublicTradesSnapshot, Error> = self.fetchTradesSnapshot(for: resourceKey)

            let orderbookResponse = await orderbookResult
            guard self.shouldRunChartSecondaryBootstrap(generation: generation, requestKey: requestKey) else {
                return
            }
            self.applyChartOrderbookResponse(
                orderbookResponse,
                resourceKey: resourceKey,
                context: context
            )

            let tradesResponse = await tradesResult
            guard self.shouldRunChartSecondaryBootstrap(generation: generation, requestKey: requestKey) else {
                return
            }
            self.applyChartTradesResponse(
                tradesResponse,
                resourceKey: resourceKey,
                context: context
            )

            self.refreshPublicStatusViewStates()
        }
    }

    private func scheduleChartSecondarySubscriptions(reason: String) {
        chartDeferredSubscriptionTask?.cancel()
        chartDeferredSubscriptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.chartSecondaryBootstrapDelayNanoseconds)
            guard self.activeTab == .chart, Task.isCancelled == false else {
                return
            }
            self.chartSecondarySubscriptionsEnabled = true
            self.updatePublicSubscriptions(reason: "\(reason)_chart_secondary_streaming")
        }
    }

    private func cancelInFlightChartRequests(except key: ChartRequestKey, resourceKey: ChartResourceKey) {
        for (existingKey, task) in candleFetchTasksByKey where existingKey != key {
            task.cancel()
        }
        candleFetchTasksByKey = candleFetchTasksByKey.filter { $0.key == key }

        for (existingKey, task) in orderbookFetchTasksByKey where existingKey != resourceKey {
            task.cancel()
        }
        orderbookFetchTasksByKey = orderbookFetchTasksByKey.filter { $0.key == resourceKey }

        for (existingKey, task) in tradesFetchTasksByKey where existingKey != resourceKey {
            task.cancel()
        }
        tradesFetchTasksByKey = tradesFetchTasksByKey.filter { $0.key == resourceKey }
    }

    private func fetchCandleSnapshot(for key: ChartRequestKey) async -> Result<CandleSnapshot, Error> {
        if let task = candleFetchTasksByKey[key] {
            AppLogger.debug(
                .network,
                "[ChartPipeline] \(key.marketIdentity.logFields) interval=\(key.interval.uppercased()) phase=request_deduped key=\(key.debugValue)"
            )
            do {
                return .success(try await task.value)
            } catch {
                return .failure(error)
            }
        }

        let task = Task<CandleSnapshot, Error> { [marketRepository] in
            try await marketRepository.fetchCandles(
                symbol: key.marketId ?? key.symbol,
                exchange: key.exchange,
                interval: key.interval
            )
        }
        candleFetchTasksByKey[key] = task
        let result: Result<CandleSnapshot, Error>
        do {
            result = .success(try await task.value)
        } catch {
            result = .failure(error)
        }
        candleFetchTasksByKey[key] = nil
        return result
    }

    private func isUnsupportedSparklineError(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkServiceError else {
            return false
        }

        switch networkError {
        case .httpError(let statusCode, let rawMessage, let category):
            let normalizedMessage = rawMessage.lowercased()
            return statusCode == 400
                || statusCode == 404
                || statusCode == 501
                || statusCode == 503
                || category == .maintenance
                || normalizedMessage.contains("market_data_unsupported")
                || normalizedMessage.contains("unsupported")
                || normalizedMessage.contains("not supported")
        case .transportError, .invalidURL, .invalidResponse, .authenticationRequired, .parsingFailed:
            return false
        }
    }

    private func fetchOrderbookSnapshot(for key: ChartResourceKey) async -> Result<OrderbookSnapshot, Error> {
        if let task = orderbookFetchTasksByKey[key] {
            do {
                return .success(try await task.value)
            } catch {
                return .failure(error)
            }
        }

        let task = Task<OrderbookSnapshot, Error> { [marketRepository] in
            try await marketRepository.fetchOrderbook(symbol: key.symbol, exchange: key.exchange)
        }
        orderbookFetchTasksByKey[key] = task
        let result: Result<OrderbookSnapshot, Error>
        do {
            result = .success(try await task.value)
        } catch {
            result = .failure(error)
        }
        orderbookFetchTasksByKey[key] = nil
        return result
    }

    private func fetchTradesSnapshot(for key: ChartResourceKey) async -> Result<PublicTradesSnapshot, Error> {
        if let task = tradesFetchTasksByKey[key] {
            do {
                return .success(try await task.value)
            } catch {
                return .failure(error)
            }
        }

        let task = Task<PublicTradesSnapshot, Error> { [marketRepository] in
            try await marketRepository.fetchTrades(symbol: key.symbol, exchange: key.exchange)
        }
        tradesFetchTasksByKey[key] = task
        let result: Result<PublicTradesSnapshot, Error>
        do {
            result = .success(try await task.value)
        } catch {
            result = .failure(error)
        }
        tradesFetchTasksByKey[key] = nil
        return result
    }

    var currentTicker: TickerData? {
        guard let coin = selectedCoin else { return nil }
        return resolvedTickerForOrderHeader(coin: coin, exchange: exchange)?.ticker
    }

    var currentPrice: Double {
        orderHeaderPricePresentation.price ?? currentTicker?.price ?? 0
    }

    var orderHeaderPricePresentation: OrderHeaderPricePresentation {
        guard let coin = selectedCoin else {
            return OrderHeaderPricePresentation(
                marketIdentity: MarketIdentity(exchange: selectedExchange, symbol: "-"),
                price: nil,
                source: .missing,
                isFallbackApplied: false,
                isStale: false
            )
        }
        return resolveOrderHeaderPricePresentation(coin: coin, exchange: selectedExchange)
    }

    var totalAsset: Double {
        portfolioSummaryCardState?.totalAsset ?? portfolioState.value?.totalAsset ?? 0
    }

    var totalPnl: Double {
        portfolioSummaryCardState?.totalPnl ?? portfolio.reduce(0) { $0 + $1.profitLoss }
    }

    var totalPnlPercent: Double {
        if let summary = portfolioSummaryCardState {
            return summary.totalPnlPercent
        }
        let investedAmount = totalAsset - totalPnl
        guard investedAmount > 0 else { return 0 }
        return (totalPnl / investedAmount) * 100
    }

    var isSelectedExchangeTradingUnsupported: Bool {
        !capabilityResolver.supportsTrading(on: selectedExchange)
    }

    var isSelectedExchangePortfolioUnsupported: Bool {
        !capabilityResolver.supportsPortfolio(on: selectedExchange)
    }

    var isSelectedExchangeChartUnsupported: Bool {
        !capabilityResolver.supportsChart(on: selectedExchange)
    }

    func onAppear() {
        AppLogger.debug(.lifecycle, "CryptoViewModel onAppear #\(instanceID) hasBootstrapped=\(hasBootstrapped)")
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        AppLogger.debug(.lifecycle, "[ScreenEnter] market exchange=\(selectedExchange.rawValue)")
        applyCachedMarketPresentationIfAvailable(for: selectedExchange, reason: "content_on_appear_cached")
        connectPublicMarketFeed(reason: "content_on_appear")
        let refreshContext = beginRouteRefresh(reason: "content_on_appear")

        Task {
            await bootstrapPublicData(reason: "content_on_appear")
            await runRouteRefreshIfCurrent(
                refreshContext,
                forceRefresh: false,
                reason: "content_on_appear"
            )
        }
    }

    func onScenePhaseChanged(_ scenePhase: ScenePhase) {
        AppLogger.debug(.lifecycle, "Scene phase changed #\(instanceID) -> \(String(describing: scenePhase))")
        guard scenePhase == .active else { return }
        guard hasBootstrapped else {
            AppLogger.debug(.lifecycle, "Scene active ignored until bootstrap completes #\(instanceID)")
            return
        }

        if authState.session != nil {
            connectPrivateTradingFeedIfNeeded(reason: "scene_active")
        }
        if requiresPublicStreaming {
            connectPublicMarketFeed(reason: "scene_active")
        } else {
            AppLogger.debug(.websocket, "connectPublicMarketFeed skipped -> reason=scene_active route=\(activeTab.rawValue) mode=snapshot")
        }

        let refreshContext = beginRouteRefresh(reason: "scene_active")
        Task {
            await runRouteRefreshIfCurrent(
                refreshContext,
                forceRefresh: activeTab == .chart,
                reason: "scene_active"
            )
        }
    }

    func setActiveTab(_ tab: Tab) {
        guard activeTab != tab else {
            AppLogger.debug(.route, "[TabState] activeTab unchanged -> \(tab.rawValue)")
            return
        }
        let previousTab = activeTab
        activeTab = tab
        setExchangeMenuVisible(false)

        AppLogger.debug(.route, "[TabState] activeTab changed \(previousTab.rawValue) -> \(tab.rawValue)")
        AppLogger.debug(.lifecycle, "[ScreenEnter] \(tab.rawValue) exchange=\(selectedExchange.rawValue)")
        if previousTab == .market, tab != .market {
            marketHydrationTask?.cancel()
            marketImageHydrationTask?.cancel()
            sparklineHydrationTask?.cancel()
            priorityVisibleSparklineTask?.cancel()
            marketImageRetryTasksByMarketIdentity.values.forEach { $0.cancel() }
            marketImageRetryTasksByMarketIdentity.removeAll()
            cancelSparklineFirstPaintHolds(for: selectedExchange)
            resetPendingMarketRowPatches(reason: "tab_changed")
            scheduledMarketImageHydrationContext = nil
            scheduledSparklineHydrationContext = nil
            scheduledPriorityVisibleSparklineContext = nil
            lastMarketImageHydrationSignatureByExchange.removeValue(forKey: selectedExchange)
            AppLogger.debug(
                .network,
                "[GraphPipeline] exchange=\(selectedExchange.rawValue) generation=\(marketPresentationGeneration) phase=cancel reason=tab_changed"
            )
        }
        if previousTab == .chart, tab != .chart {
            cancelChartBootstrapTasks()
            chartSecondarySubscriptionsEnabled = false
        }
        if tab == .chart {
            beginChartBootstrapSession(reason: "tab_changed")
        }
        updateAuthGate()
        updatePublicSubscriptions(reason: "tab_changed")
        updatePrivateSubscriptions(reason: "tab_changed")
        updatePublicPollingIfNeeded()
        updatePrivatePollingIfNeeded()
        refreshPublicStatusViewStates()
        refreshPrivateStatusViewStates()

        if tab == .kimchi,
           (!selectedExchange.isDomestic || !selectedExchange.supportsKimchiPremium) {
            updateExchange(selectedDomesticKimchiExchange, source: "kimchi_tab_sync")
        }

        if tab == .market {
            applyCachedMarketPresentationIfAvailable(for: selectedExchange, reason: "tab_changed_cached")
        } else if tab == .kimchi {
            applyCachedKimchiPresentationIfAvailable(for: currentKimchiDomesticExchange, reason: "tab_changed_cached")
        }

        let refreshContext = beginRouteRefresh(reason: "tab_changed")

        if tab.accessRequirement == .authenticatedRequired, !isAuthenticated {
            return
        }

        Task {
            await runRouteRefreshIfCurrent(
                refreshContext,
                forceRefresh: false,
                reason: "tab_changed"
            )
        }
    }

    func updateExchange(_ exchange: Exchange, source: String = "user") {
        guard selectedExchange != exchange else {
            AppLogger.debug(.route, "Exchange change ignored -> \(exchange.rawValue) (source=\(source))")
            return
        }
        let previousExchange = selectedExchange
        selectedExchange = exchange
        marketPresentationGeneration += 1
        marketHydrationTask?.cancel()
        marketImageHydrationTask?.cancel()
        sparklineHydrationTask?.cancel()
        priorityVisibleSparklineTask?.cancel()
        marketImageRetryTasksByMarketIdentity.values.forEach { $0.cancel() }
        marketImageRetryTasksByMarketIdentity.removeAll()
        cancelSparklineFirstPaintHolds(for: previousExchange)
        cancelSparklineFirstPaintHolds(for: exchange)
        resetPendingMarketRowPatches(reason: "exchange_changed")
        scheduledMarketImageHydrationContext = nil
        scheduledSparklineHydrationContext = nil
        scheduledPriorityVisibleSparklineContext = nil
        lastMarketImageHydrationSignatureByExchange.removeValue(forKey: previousExchange)
        lastMarketImageHydrationSignatureByExchange.removeValue(forKey: exchange)
        fullyHydratedMarketExchanges.remove(exchange)
        loadingSparklineMarketIdentitiesByExchange[previousExchange] = []
        loadingSparklineMarketIdentitiesByExchange[exchange] = []
        pendingSparklineHydrationReasonsByExchange.removeValue(forKey: previousExchange)
        pendingSparklineHydrationReasonsByExchange.removeValue(forKey: exchange)
        runningSparklineHydrationExchanges.remove(previousExchange)
        runningSparklineHydrationExchanges.remove(exchange)
        lastLoggedGraphCacheHitSignatureByExchange.removeValue(forKey: previousExchange)
        lastLoggedGraphCacheHitSignatureByExchange.removeValue(forKey: exchange)
        lastLoggedGraphDeferredSignatureByExchange.removeValue(forKey: previousExchange)
        lastLoggedGraphDeferredSignatureByExchange.removeValue(forKey: exchange)
        AppLogger.debug(.route, "Exchange changed \(previousExchange.rawValue) -> \(exchange.rawValue) (source=\(source))")
        AppLogger.debug(
            .route,
            "[ExchangeDebug] selected exchange changed previous=\(previousExchange.rawValue) selected=\(exchange.rawValue) source=\(source)"
        )
        marketSwitchStartedAtByExchange[exchange] = Date()
        marketFirstVisibleLoggedExchanges.remove(exchange)
        marketFullHydrationPendingExchanges.insert(exchange)
        marketStagedSwapCountByExchange[exchange] = 0
        marketFullReloadCountByExchange[exchange] = 0
        marketVisibleGraphPatchCountByExchange[exchange] = 0
        marketOffscreenDeferredGraphCountByExchange[exchange] = 0
        marketStaleCallbackDropCountByExchange[exchange] = 0
        marketPlaceholderFinalBaselineByExchange[exchange] = currentPlaceholderFinalTotal()
        hasLoadedTickerSnapshotByExchange[exchange] = false
        AppLogger.debug(
            .lifecycle,
            "[ExchangeSwitch] started exchange=\(exchange.rawValue) previous=\(previousExchange.rawValue) source=\(source)"
        )
        AppLogger.debug(
            .network,
            "[GraphPipeline] exchange=\(previousExchange.rawValue) generation=\(marketPresentationGeneration) phase=cancel reason=exchange_changed targetExchange=\(exchange.rawValue)"
        )
        marketSwitchApplyCountByExchange[exchange] = 0
        if activeTab == .chart {
            beginChartBootstrapSession(reason: "exchange_changed")
        } else {
            cancelChartBootstrapTasks()
            chartSecondarySubscriptionsEnabled = false
        }

        if exchange.isDomestic, exchange.supportsKimchiPremium {
            if selectedDomesticKimchiExchange != exchange {
                AppLogger.debug(
                    .route,
                    "[KimchiView] selectedDomesticExchange changed \(selectedDomesticKimchiExchange.rawValue) -> \(exchange.rawValue)"
                )
            }
            selectedDomesticKimchiExchange = exchange
        }

        beginMarketTransition(to: exchange, from: previousExchange, reason: "exchange_changed")
        reconcileVisibleSparklines(
            exchange: exchange,
            reason: "exchange_switched"
        )

        if activeTab == .kimchi, exchange.isDomestic {
            kimchiSwitchStartedAtByExchange[exchange] = Date()
            kimchiFirstVisibleLoggedExchanges.remove(exchange)
            AppLogger.debug(
                .network,
                "[KimchiSwitch] started exchange=\(exchange.rawValue) previous=\(previousExchange.rawValue) source=\(source)"
            )
            logKimchiInitialState(for: exchange, now: Date())
            if hasReadyableRepresentativeRows(in: cachedKimchiPresentation(for: exchange)) {
                AppLogger.debug(
                    .network,
                    "[KimchiHeaderDebug] action=preserve_shell reason=exchange_switch_with_cache"
                )
                applyCachedKimchiPresentationIfAvailable(for: exchange, reason: "exchange_changed_cached_kimchi")
            } else {
                beginKimchiTransition(to: exchange, reason: "exchange_changed")
            }
        }

        cancelInFlightMarketRequests(excluding: exchange)
        updatePublicSubscriptions(reason: "exchange_changed")
        updatePrivateSubscriptions(reason: "exchange_changed")
        refreshPublicStatusViewStates()
        refreshPrivateStatusViewStates()

        let refreshContext = beginRouteRefresh(reason: "exchange_changed")

        if activeTab.accessRequirement == .authenticatedRequired, !isAuthenticated {
            return
        }

        Task {
            await runRouteRefreshIfCurrent(
                refreshContext,
                forceRefresh: activeTab == .market || activeTab == .kimchi,
                reason: "exchange_changed"
            )
        }

        if activeTab == .trade {
            logOrderHeaderPriceDebug(reason: "exchange_changed_\(source)", force: true)
        }
    }

    func updateSelectedDomesticKimchiExchange(_ exchange: Exchange, source: String = "user") {
        guard exchange.isDomestic, exchange.supportsKimchiPremium else {
            AppLogger.debug(.route, "[KimchiView] selectedDomesticExchange rejected -> \(exchange.rawValue) source=\(source)")
            return
        }
        guard selectedExchange != exchange || selectedDomesticKimchiExchange != exchange else {
            AppLogger.debug(.route, "[KimchiView] selectedDomesticExchange unchanged -> \(exchange.rawValue) source=\(source)")
            return
        }

        if activeTab == .kimchi {
            updateKimchiExchangeSelection(exchange, source: source)
            return
        }

        updateExchange(exchange, source: source)
    }

    func selectCoin(_ coin: CoinInfo) {
        selectedCoin = coin
        prefillOrderPriceIfPossible()
        setActiveTab(.chart)
    }

    func selectCoinForTrade(_ coin: CoinInfo) {
        selectedCoin = coin
        prefillOrderPriceIfPossible()
        setActiveTab(.trade)
        logOrderHeaderPriceDebug(reason: "select_coin_for_trade", force: true)
    }

    func setChartInterval(_ interval: String) {
        guard chartPeriod.lowercased() != interval.lowercased() else {
            AppLogger.debug(.route, "Chart interval unchanged -> \(interval)")
            return
        }
        chartPeriod = interval
        updatePublicSubscriptions(reason: "chart_interval_changed")

        Task {
            await loadChartData(forceRefresh: true, reason: "chart_interval_changed")
        }
    }

    func applyChartSettings(_ state: ChartSettingsState, source: String = "chart_settings_sheet") {
        let normalizedState = state.normalized
        let didPersistedStateChange = chartSettingsState != normalizedState
        let previousStyle = chartSettingsState.selectedChartStyle

        if didPersistedStateChange {
            chartSettingsState = normalizedState
            chartSettingsStorage.save(normalizedState)
        }

        syncChartSettingsToRenderer(normalizedState, source: source)

        guard didPersistedStateChange else {
            return
        }

        AppLogger.debug(
            .route,
            "[ChartSettings] source=\(source) style=\(normalizedState.selectedChartStyle.rawValue) top=\(normalizedState.selectedTopIndicators.map(\.rawValue).joined(separator: ",")) bottom=\(normalizedState.selectedBottomIndicators.map(\.rawValue).joined(separator: ",")) compared=\(normalizedState.comparedSymbols.joined(separator: ",")) viewOptions=bestBidAsk:\(normalizedState.showBestBidAskLine),globalColors:\(normalizedState.useGlobalExchangeColorScheme),utc:\(normalizedState.useUTC)"
        )

        if previousStyle != normalizedState.selectedChartStyle {
            AppLogger.debug(
                .route,
                "[ChartSettings] chart_style_changed previous=\(previousStyle.rawValue) next=\(normalizedState.selectedChartStyle.rawValue) dataReload=false"
            )
        }
    }

    private func syncChartSettingsToRenderer(_ state: ChartSettingsState, source: String) {
        let normalizedState = state.normalized
        guard appliedChartSettingsState != normalizedState else {
            scheduleComparedChartSeriesRefresh(reason: "\(source)_renderer_resync", context: lastChartSnapshotContext)
            return
        }

        appliedChartSettingsState = normalizedState
        assert(normalizedState.comparedSymbols.count <= ChartSettingsState.maximumComparedSymbolCount)
        AppLogger.debug(
            .route,
            "[ChartSettings] renderer_sync source=\(source) style=\(normalizedState.selectedChartStyle.rawValue) comparedCount=\(normalizedState.comparedSymbols.count)"
        )
        scheduleComparedChartSeriesRefresh(reason: source, context: lastChartSnapshotContext)
    }

    private func clearComparedChartSeries(reason: String) {
        chartComparisonTask?.cancel()
        chartComparisonTask = nil
        activeChartComparisonSignature = nil
        if comparedChartSeries.isEmpty == false {
            comparedChartSeries = []
        }
        AppLogger.debug(.route, "[ChartSettings] compare_series_cleared reason=\(reason)")
    }

    private func scheduleComparedChartSeriesRefresh(
        reason: String,
        context: ChartRequestContext? = nil
    ) {
        let effectiveContext = context ?? lastChartSnapshotContext
        guard let effectiveContext,
              effectiveContext.exchange == selectedExchange else {
            clearComparedChartSeries(reason: "\(reason)_missing_context")
            return
        }

        let currentSymbol = selectedCoin?.symbol ?? effectiveContext.symbol
        let comparedSymbols = appliedChartSettingsState.comparedSymbols.filter { $0 != currentSymbol }
        guard comparedSymbols.isEmpty == false else {
            clearComparedChartSeries(reason: "\(reason)_empty_selection")
            return
        }

        let signature = [
            effectiveContext.marketIdentity.cacheKey,
            effectiveContext.mappedInterval,
            comparedSymbols.joined(separator: ",")
        ].joined(separator: "|")

        guard activeChartComparisonSignature != signature else {
            return
        }

        activeChartComparisonSignature = signature
        chartComparisonTask?.cancel()

        chartComparisonTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let palette = ["#F59E0B", "#34D399", "#60A5FA", "#F472B6", "#A78BFA"]
            var nextSeries: [ChartComparisonSeries] = []

            for (index, symbol) in comparedSymbols.enumerated() {
                guard Task.isCancelled == false else { return }

                let key = self.chartRequestKey(
                    exchange: effectiveContext.exchange,
                    symbol: symbol,
                    interval: effectiveContext.mappedInterval
                )
                let response = await self.fetchCandleSnapshot(for: key)
                guard Task.isCancelled == false else { return }

                let candles: [CandleData]
                switch response {
                case .success(let snapshot):
                    let prepared = self.prepareCandlesForLive(
                        snapshot.candles,
                        interval: effectiveContext.mappedInterval,
                        seedPrice: self.pricesByMarketIdentity[key.marketIdentity]?.price
                    )
                    let fetchedAt = snapshot.meta.fetchedAt ?? Date()
                    self.storeChartDetailCandleEntry(
                        candles: prepared,
                        meta: snapshot.meta,
                        fetchedAt: fetchedAt,
                        keys: [key],
                        rememberSuccess: snapshot.meta.isChartAvailable != false
                    )
                    candles = prepared
                case .failure:
                    candles = self.lastSuccessfulCandles[key]?.candles
                        ?? self.candleCacheByKey[key]?.candles
                        ?? []
                }

                guard candles.isEmpty == false else {
                    AppLogger.debug(
                        .route,
                        "[ChartSettings] compare_series_skipped symbol=\(symbol) reason=no_candles interval=\(effectiveContext.mappedInterval)"
                    )
                    continue
                }

                nextSeries.append(
                    ChartComparisonSeries(
                        symbol: symbol,
                        name: self.chartComparisonDisplayName(for: symbol, exchange: effectiveContext.exchange),
                        candles: candles,
                        colorHex: palette[index % palette.count]
                    )
                )
            }

            guard self.activeChartComparisonSignature == signature,
                  self.selectedExchange == effectiveContext.exchange,
                  (self.selectedCoin?.symbol ?? effectiveContext.symbol) == currentSymbol else {
                return
            }

            self.comparedChartSeries = nextSeries
            AppLogger.debug(
                .route,
                "[ChartSettings] compare_series_synced reason=\(reason) interval=\(effectiveContext.mappedInterval) count=\(nextSeries.count)"
            )
        }
    }

    private func chartComparisonDisplayName(for symbol: String, exchange: Exchange) -> String {
        chartComparisonCandidates.first(where: { $0.symbol == symbol })?.name
            ?? resolvedMarketUniverse(for: exchange).first(where: { $0.symbol == symbol })?.name
            ?? CoinCatalog.coin(symbol: symbol, exchange: exchange).name
    }

    func refreshMarketData(forceRefresh: Bool = true, reason: String = "manual") async {
        if activeMarketPresentationSnapshot?.exchange == selectedExchange {
            beginSameExchangeMarketReuse(reason: reason)
        } else if activeMarketPresentationSnapshot?.exchange != selectedExchange || activeMarketPresentationSnapshot == nil {
            beginMarketTransition(to: selectedExchange, from: activeMarketPresentationSnapshot?.exchange, reason: reason)
        }
        async let marketTask = loadMarkets(for: selectedExchange, forceRefresh: forceRefresh, reason: reason)
        async let tickerTask = loadTickers(for: selectedExchange, forceRefresh: forceRefresh, reason: reason)
        _ = await (marketTask, tickerTask)
        refreshMarketStateForSelectedExchange(reason: reason)
    }

    func refreshKimchiPremium(forceRefresh: Bool = true, reason: String = "manual") async {
        if activeKimchiPresentationSnapshot?.exchange == currentKimchiDomesticExchange {
            beginSameExchangeKimchiReuse(reason: reason)
        } else if activeKimchiPresentationSnapshot?.exchange != currentKimchiDomesticExchange || activeKimchiPresentationSnapshot == nil {
            beginKimchiTransition(to: currentKimchiDomesticExchange, reason: reason)
        }
        await loadKimchiPremium(forceRefresh: forceRefresh, reason: reason)
    }

    func loadChartData(forceRefresh: Bool = false, reason: String = "manual") async {
        guard capabilityResolver.supportsChart(on: selectedExchange) else {
            clearComparedChartSeries(reason: "unsupported_chart")
            activeChartCandleMeta = .empty
            activeChartOrderbookMeta = .empty
            activeChartTradesMeta = .empty
            updateCandleState(
                .unavailable("이 거래소는 차트를 지원하지 않아요."),
                exchange: selectedExchange,
                symbol: selectedCoin?.symbol ?? "-",
                interval: chartPeriod,
                phase: "unsupported_chart"
            )
            updateOrderbookState(.unavailable("이 거래소는 호가를 지원하지 않아요."))
            updateTradesState(.unavailable("이 거래소는 최근 체결을 지원하지 않아요."))
            chartStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: .snapshotOnly,
                context: .chart,
                warningMessage: "지원하지 않는 기능입니다."
            )
            refreshChartSummaryStates(reason: "unsupported_chart")
            return
        }

        ensureSelectedCoinIfPossible(for: selectedExchange)
        guard let coin = selectedCoin else {
            clearComparedChartSeries(reason: "selected_coin_missing")
            activeChartCandleMeta = .empty
            activeChartOrderbookMeta = .empty
            activeChartTradesMeta = .empty
            updateCandleState(.idle, exchange: selectedExchange, symbol: "-", interval: chartPeriod, phase: "selected_coin_missing")
            updateOrderbookState(.idle)
            updateTradesState(.idle)
            refreshChartSummaryStates(reason: "selected_coin_missing")
            return
        }

        let requestedInterval = chartPeriod.lowercased()
        let mappedInterval = resolvedChartInterval(
            requestedInterval: requestedInterval,
            symbol: coin.symbol,
            exchange: exchange
        )
        updateChartIntervalIfNeeded(mappedInterval, reason: reason)

        let selectedMarketIdentity = coin.marketIdentity(exchange: exchange)
        let context = ChartRequestContext(
            marketIdentity: selectedMarketIdentity,
            requestedInterval: requestedInterval,
            mappedInterval: mappedInterval,
            window: chartWindow
        )
        scheduleComparedChartSeriesRefresh(reason: "\(reason)_request_start", context: context)
        let requestKey = chartRequestKey(marketIdentity: context.marketIdentity, interval: context.mappedInterval)
        let fallbackRequestKey = chartDetailFallbackRequestKey(coin: coin, context: context)
        let resourceKey = chartResourceKey(marketIdentity: context.marketIdentity)
        let endpoint = marketRepository.marketCandlesEndpointPath
        let retainedCandleEntry = chartDetailRetainedCandleEntry(
            primaryKey: requestKey,
            fallbackKey: fallbackRequestKey
        )
        refreshChartSummaryStates(reason: "\(reason)_chart_start")

        AppLogger.debug(
            .route,
            "Public chart path -> \(selectedMarketIdentity.logFields) interval=\(chartPeriod) mappedInterval=\(mappedInterval) endpoint=\(endpoint) reason=\(reason)"
        )
        AppLogger.debug(
            .network,
            "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.requestedInterval.uppercased()) phase=request_start mappedInterval=\(context.mappedInterval.uppercased()) endpoint=\(endpoint) key=\(requestKey.debugValue)"
        )
        AppLogger.debug(
            .network,
            "[ChartDetailScreenDebug] selectedExchange=\(context.exchange.rawValue) selectedSymbol=\(context.symbol) selectedMarketId=\(context.marketId ?? "-") candleRequestKey=\(requestKey.debugValue) fallbackKey=\(fallbackRequestKey?.debugValue ?? "-") reason=\(reason)"
        )

        activeChartRequestGeneration += 1
        let generation = activeChartRequestGeneration
        let previousKey = activeChartRequestKey
        activeChartRequestKey = requestKey
        if let previousKey, previousKey != requestKey {
            AppLogger.debug(
                .network,
                "[ChartPipeline] \(previousKey.marketIdentity.logFields) interval=\(previousKey.interval.uppercased()) phase=request_cancelled key=\(previousKey.debugValue) reason=new_request"
            )
        }
        cancelChartBootstrapTasks()
        cancelInFlightChartRequests(except: requestKey, resourceKey: resourceKey)
        updatePublicSubscriptions(reason: reason)

        if !forceRefresh, shouldSkipChartSnapshot(for: context) {
            AppLogger.debug(
                .network,
                "fetchChartSnapshot skipped -> \(context.marketIdentity.logFields) interval=\(context.mappedInterval) reason=\(reason)"
            )
            chartStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: chartMetaForStatus,
                streamingStatus: currentPublicStreamingStatus,
                context: .chart,
                warningMessage: currentPublicStreamingWarningMessage
            )
            logChartFirstUsableFrameIfNeeded(context: context, phase: "skip_fresh_cache")
            scheduleChartSecondarySubscriptions(reason: reason)
            return
        }

        if let retainedCandleEntry,
           retainedCandleEntry.entry.candles.isEmpty == false {
            let candleCache = retainedCandleEntry.entry
            updateCandleState(
                forceRefresh ? .refreshing(candleCache.candles) : .staleCache(candleCache.candles),
                exchange: context.exchange,
                symbol: context.symbol,
                interval: context.mappedInterval,
                phase: "show_stale_cache"
            )
            activeChartCandleMeta = candleCache.meta
            AppLogger.debug(
                .network,
                "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.mappedInterval.uppercased()) phase=show_stale_cache candles=\(candleCache.candles.count) key=\(retainedCandleEntry.key.debugValue)"
            )
            AppLogger.debug(
                .network,
                "[ChartDetailScreenDebug] action=apply_retained selectedExchange=\(context.exchange.rawValue) selectedSymbol=\(context.symbol) selectedMarketId=\(context.marketId ?? "-") candleRequestKey=\(requestKey.debugValue) fallbackKey=\(fallbackRequestKey?.debugValue ?? "-") sourceKey=\(retainedCandleEntry.key.debugValue)"
            )
            AppLogger.debug(
                .network,
                "[GraphApplyDebug] screen=detail renderVersion=\(chartDetailRenderVersion(for: candleCache.candles)) applied=true source=retained"
            )
            logChartFirstUsableFrameIfNeeded(context: context, phase: "show_stale_cache")
        } else {
            updateCandleState(.loading, exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "request_pending")
            activeChartCandleMeta = .empty
        }

        if let orderbookCache = lastSuccessfulOrderBook[resourceKey] ?? orderbookCacheByKey[resourceKey] {
            updateOrderbookState(forceRefresh ? .refreshing(orderbookCache.orderbook) : .loaded(orderbookCache.orderbook))
            activeChartOrderbookMeta = orderbookCache.meta
        } else {
            updateOrderbookState(.loading)
            activeChartOrderbookMeta = .empty
        }

        if let tradesCache = lastSuccessfulTrades[resourceKey] ?? tradesCacheByKey[resourceKey] {
            updateTradesState(forceRefresh ? .refreshing(tradesCache.trades) : .loaded(tradesCache.trades))
            activeChartTradesMeta = tradesCache.meta
        } else {
            updateTradesState(.loading)
            activeChartTradesMeta = .empty
        }

        var resolvedRequestKey = requestKey
        var candleResponse = await fetchCandleSnapshot(for: requestKey)
        if shouldRetryChartDetailWithFallback(candleResponse),
           let fallbackRequestKey {
            AppLogger.debug(
                .network,
                "[ChartDetailScreenDebug] action=fallback_retry selectedExchange=\(context.exchange.rawValue) selectedSymbol=\(context.symbol) selectedMarketId=\(context.marketId ?? "-") candleRequestKey=\(requestKey.debugValue) fallbackKey=\(fallbackRequestKey.debugValue)"
            )
            let fallbackResponse = await fetchCandleSnapshot(for: fallbackRequestKey)
            if case .success(let fallbackSnapshot) = fallbackResponse,
               isUsableChartDetailSnapshot(fallbackSnapshot) {
                candleResponse = fallbackResponse
                resolvedRequestKey = fallbackRequestKey
            }
        }
        if shouldApplyChartResult(generation: generation, key: requestKey) {
            switch candleResponse {
            case .success(let candleSnapshot):
                let preparedCandles = prepareCandlesForLive(
                    candleSnapshot.candles,
                    interval: context.mappedInterval,
                    seedPrice: currentTicker?.price
                )
                let fetchedAt = candleSnapshot.meta.fetchedAt ?? Date()
                storeChartDetailCandleEntry(
                    candles: preparedCandles,
                    meta: candleSnapshot.meta,
                    fetchedAt: fetchedAt,
                    keys: [requestKey, resolvedRequestKey],
                    rememberSuccess: candleSnapshot.meta.isChartAvailable != false
                )
                activeChartCandleMeta = candleSnapshot.meta
                if candleSnapshot.meta.isChartAvailable == false {
                    if let retainedCandleEntry,
                       retainedCandleEntry.entry.candles.isEmpty == false {
                        let userMessage = chartUnavailableMessage(kind: .candles, exchange: context.exchange)
                        activeChartCandleMeta = ResponseMeta(
                            fetchedAt: retainedCandleEntry.entry.meta.fetchedAt,
                            isStale: true,
                            warningMessage: staleWarningMessage(kind: .candles),
                            partialFailureMessage: userMessage
                        )
                        updateCandleState(
                            .staleCache(retainedCandleEntry.entry.candles),
                            exchange: context.exchange,
                            symbol: context.symbol,
                            interval: context.mappedInterval,
                            phase: "response_unavailable_keep_retained"
                        )
                        AppLogger.debug(
                            .network,
                            "[ChartDetailScreenDebug] action=apply_retained selectedExchange=\(context.exchange.rawValue) selectedSymbol=\(context.symbol) selectedMarketId=\(context.marketId ?? "-") candleRequestKey=\(requestKey.debugValue) fallbackKey=\(fallbackRequestKey?.debugValue ?? "-") sourceKey=\(retainedCandleEntry.key.debugValue)"
                        )
                        AppLogger.debug(
                            .network,
                            "[GraphApplyDebug] screen=detail renderVersion=\(chartDetailRenderVersion(for: retainedCandleEntry.entry.candles)) applied=true source=retained"
                        )
                        logChartFirstUsableFrameIfNeeded(context: context, phase: "response_unavailable_keep_retained")
                    } else {
                        updateCandleState(
                            .unavailable(chartUnavailableMessage(kind: .candles, exchange: context.exchange)),
                            exchange: context.exchange,
                            symbol: context.symbol,
                            interval: context.mappedInterval,
                            phase: "response_unavailable"
                        )
                        AppLogger.debug(
                            .network,
                            "[ChartDetailScreenDebug] action=unavailable_shown selectedExchange=\(context.exchange.rawValue) selectedSymbol=\(context.symbol) selectedMarketId=\(context.marketId ?? "-") candleRequestKey=\(requestKey.debugValue) fallbackKey=\(fallbackRequestKey?.debugValue ?? "-")"
                        )
                        AppLogger.debug(
                            .network,
                            "[GraphApplyDebug] screen=detail renderVersion=0 applied=false source=unavailable"
                        )
                        logChartFirstUsableFrameIfNeeded(context: context, phase: "response_unavailable")
                    }
                } else if preparedCandles.isEmpty {
                    if let retainedCandleEntry,
                       retainedCandleEntry.entry.candles.isEmpty == false {
                        activeChartCandleMeta = ResponseMeta(
                            fetchedAt: retainedCandleEntry.entry.meta.fetchedAt,
                            isStale: true,
                            warningMessage: staleWarningMessage(kind: .candles),
                            partialFailureMessage: nil
                        )
                        updateCandleState(
                            .staleCache(retainedCandleEntry.entry.candles),
                            exchange: context.exchange,
                            symbol: context.symbol,
                            interval: context.mappedInterval,
                            phase: "response_empty_keep_retained"
                        )
                        AppLogger.debug(
                            .network,
                            "[ChartDetailScreenDebug] action=apply_retained selectedExchange=\(context.exchange.rawValue) selectedSymbol=\(context.symbol) selectedMarketId=\(context.marketId ?? "-") candleRequestKey=\(requestKey.debugValue) fallbackKey=\(fallbackRequestKey?.debugValue ?? "-") sourceKey=\(retainedCandleEntry.key.debugValue)"
                        )
                        AppLogger.debug(
                            .network,
                            "[GraphApplyDebug] screen=detail renderVersion=\(chartDetailRenderVersion(for: retainedCandleEntry.entry.candles)) applied=true source=retained"
                        )
                        logChartFirstUsableFrameIfNeeded(context: context, phase: "response_empty_keep_retained")
                    } else {
                        updateCandleState(.empty, exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "response_empty")
                        AppLogger.debug(
                            .network,
                            "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.mappedInterval.uppercased()) phase=response_empty key=\(resolvedRequestKey.debugValue)"
                        )
                        AppLogger.debug(
                            .network,
                            "[GraphApplyDebug] screen=detail renderVersion=0 applied=false source=empty"
                        )
                        logChartFirstUsableFrameIfNeeded(context: context, phase: "response_empty")
                    }
                } else {
                    AppLogger.debug(
                        .network,
                        "[GraphPolicyDebug] screen=detail oldDetail=\(chartDetailStateDetailLabel(candlesState)) newDetail=liveDetailed accepted=true rejectReason=-"
                    )
                    updateCandleState(.loaded(preparedCandles), exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "response_success")
                    AppLogger.debug(
                        .network,
                        "[ChartDetailScreenDebug] action=apply_live_detailed selectedExchange=\(context.exchange.rawValue) selectedSymbol=\(context.symbol) selectedMarketId=\(context.marketId ?? "-") candleRequestKey=\(requestKey.debugValue) fallbackKey=\(fallbackRequestKey?.debugValue ?? "-") sourceKey=\(resolvedRequestKey.debugValue)"
                    )
                    AppLogger.debug(
                        .network,
                        "[GraphApplyDebug] screen=detail renderVersion=\(chartDetailRenderVersion(for: preparedCandles)) applied=true source=live_detailed"
                    )
                    logChartFirstUsableFrameIfNeeded(context: context, phase: "response_success")
                }
            case .failure(let error):
                let presentation = userFacingChartMessage(for: error, kind: .candles, exchange: context.exchange)
                let userMessage = presentation.message
                if let retainedCandleEntry,
                   retainedCandleEntry.entry.candles.isEmpty == false {
                    let cache = retainedCandleEntry.entry
                    AppLogger.debug(
                        .network,
                        "[GraphPolicyDebug] screen=detail oldDetail=\(chartDetailStateDetailLabel(candlesState)) newDetail=retainedDetailed accepted=true rejectReason=-"
                    )
                    activeChartCandleMeta = ResponseMeta(
                        fetchedAt: cache.meta.fetchedAt,
                        isStale: true,
                        warningMessage: staleWarningMessage(kind: .candles),
                        partialFailureMessage: userMessage
                    )
                    updateCandleState(.staleCache(cache.candles), exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "response_failure_keep_stale")
                    AppLogger.debug(
                        .network,
                        "[ChartDetailScreenDebug] action=apply_retained selectedExchange=\(context.exchange.rawValue) selectedSymbol=\(context.symbol) selectedMarketId=\(context.marketId ?? "-") candleRequestKey=\(requestKey.debugValue) fallbackKey=\(fallbackRequestKey?.debugValue ?? "-") sourceKey=\(retainedCandleEntry.key.debugValue)"
                    )
                    AppLogger.debug(
                        .network,
                        "[GraphApplyDebug] screen=detail renderVersion=\(chartDetailRenderVersion(for: cache.candles)) applied=true source=retained"
                    )
                    logChartFirstUsableFrameIfNeeded(context: context, phase: "response_failure_keep_stale")
                } else if presentation.isUnavailable {
                    activeChartCandleMeta = ResponseMeta(
                        fetchedAt: nil,
                        isStale: false,
                        warningMessage: userMessage,
                        partialFailureMessage: userMessage,
                        isChartAvailable: false,
                        unavailableReason: userMessage
                    )
                    updateCandleState(.unavailable(userMessage), exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "response_unavailable")
                    AppLogger.debug(
                        .network,
                        "[ChartDetailScreenDebug] action=unavailable_shown selectedExchange=\(context.exchange.rawValue) selectedSymbol=\(context.symbol) selectedMarketId=\(context.marketId ?? "-") candleRequestKey=\(requestKey.debugValue) fallbackKey=\(fallbackRequestKey?.debugValue ?? "-")"
                    )
                    AppLogger.debug(
                        .network,
                        "[GraphApplyDebug] screen=detail renderVersion=0 applied=false source=unavailable"
                    )
                    logChartFirstUsableFrameIfNeeded(context: context, phase: "response_unavailable")
                } else {
                    updateCandleState(.failed(userMessage), exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "response_failure")
                    AppLogger.debug(
                        .network,
                        "[GraphApplyDebug] screen=detail renderVersion=0 applied=false source=failure"
                    )
                    logChartFirstUsableFrameIfNeeded(context: context, phase: "response_failure")
                }
                AppLogger.debug(
                    .network,
                    "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.mappedInterval.uppercased()) phase=response_failure key=\(resolvedRequestKey.debugValue) message=\(userMessage)"
                )
            }
            scheduleChartSecondaryBootstrap(
                context: context,
                requestKey: requestKey,
                resourceKey: resourceKey,
                generation: generation,
                reason: reason
            )
        } else {
            AppLogger.debug(
                .network,
                "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.mappedInterval.uppercased()) phase=drop_stale_generation generation=\(generation) key=\(requestKey.debugValue)"
            )
        }

        lastChartSnapshotContext = context
        lastChartSnapshotFetchedAt = Date()
        refreshChartSummaryStates(reason: "\(reason)_chart_finished")
        refreshPublicStatusViewStates()
    }

    private func applyChartOrderbookResponse(
        _ response: Result<OrderbookSnapshot, Error>,
        resourceKey: ChartResourceKey,
        context: ChartRequestContext
    ) {
        switch response {
        case .success(let orderbookSnapshot):
            let entry = OrderbookCacheEntry(
                key: resourceKey,
                orderbook: orderbookSnapshot.orderbook,
                meta: orderbookSnapshot.meta,
                fetchedAt: orderbookSnapshot.meta.fetchedAt ?? Date()
            )
            orderbookCacheByKey[resourceKey] = entry
            activeChartOrderbookMeta = orderbookSnapshot.meta
            if orderbookSnapshot.meta.isOrderBookAvailable == false {
                updateOrderbookState(.unavailable(chartUnavailableMessage(kind: .orderbook, exchange: context.exchange)))
            } else if orderbookSnapshot.orderbook.asks.isEmpty && orderbookSnapshot.orderbook.bids.isEmpty {
                updateOrderbookState(.empty)
            } else {
                lastSuccessfulOrderBook[resourceKey] = entry
                updateOrderbookState(.loaded(orderbookSnapshot.orderbook))
            }
        case .failure(let error):
            let presentation = userFacingChartMessage(for: error, kind: .orderbook, exchange: context.exchange)
            if let cache = lastSuccessfulOrderBook[resourceKey] ?? orderbookCacheByKey[resourceKey] {
                let warningMessage = staleWarningMessage(kind: .orderbook)
                activeChartOrderbookMeta = ResponseMeta(
                    fetchedAt: cache.meta.fetchedAt,
                    isStale: true,
                    warningMessage: warningMessage,
                    partialFailureMessage: presentation.message
                )
                updateOrderbookState(.staleCache(cache.orderbook, warningMessage))
            } else if presentation.isUnavailable {
                activeChartOrderbookMeta = ResponseMeta(
                    fetchedAt: nil,
                    isStale: false,
                    warningMessage: presentation.message,
                    partialFailureMessage: presentation.message,
                    isOrderBookAvailable: false,
                    unavailableReason: presentation.message
                )
                updateOrderbookState(.unavailable(presentation.message))
            } else {
                updateOrderbookState(.failed(presentation.message))
            }
        }
    }

    private func applyChartTradesResponse(
        _ response: Result<PublicTradesSnapshot, Error>,
        resourceKey: ChartResourceKey,
        context: ChartRequestContext
    ) {
        switch response {
        case .success(let tradesSnapshot):
            let entry = TradesCacheEntry(
                key: resourceKey,
                trades: tradesSnapshot.trades,
                meta: tradesSnapshot.meta,
                fetchedAt: tradesSnapshot.meta.fetchedAt ?? Date()
            )
            tradesCacheByKey[resourceKey] = entry
            activeChartTradesMeta = tradesSnapshot.meta
            if tradesSnapshot.meta.isTradesAvailable == false {
                updateTradesState(.unavailable(chartUnavailableMessage(kind: .trades, exchange: context.exchange)))
            } else if tradesSnapshot.trades.isEmpty {
                updateTradesState(.empty)
            } else {
                lastSuccessfulTrades[resourceKey] = entry
                updateTradesState(.loaded(tradesSnapshot.trades))
            }
        case .failure(let error):
            let presentation = userFacingChartMessage(for: error, kind: .trades, exchange: context.exchange)
            if let cache = lastSuccessfulTrades[resourceKey] ?? tradesCacheByKey[resourceKey] {
                let warningMessage = staleWarningMessage(kind: .trades)
                activeChartTradesMeta = ResponseMeta(
                    fetchedAt: cache.meta.fetchedAt,
                    isStale: true,
                    warningMessage: warningMessage,
                    partialFailureMessage: presentation.message
                )
                updateTradesState(.staleCache(cache.trades, warningMessage))
            } else if presentation.isUnavailable {
                activeChartTradesMeta = ResponseMeta(
                    fetchedAt: nil,
                    isStale: false,
                    warningMessage: presentation.message,
                    partialFailureMessage: presentation.message,
                    isTradesAvailable: false,
                    unavailableReason: presentation.message
                )
                updateTradesState(.unavailable(presentation.message))
            } else {
                updateTradesState(.failed(presentation.message))
            }
        }
    }

    func toggleFavorite(_ symbol: String) {
        if favCoins.contains(symbol) {
            favCoins.remove(symbol)
        } else {
            favCoins.insert(symbol)
        }

        defaults.set(Array(favCoins).sorted(), forKey: favoritesKey)
        refreshMarketRowsForSelectedExchange(reason: "favorite_toggled")
        logMarketScreenCounts(reason: "favorite_toggled")
    }

    func presentLogin(for feature: ProtectedFeature) {
        pendingPostLoginFeature = feature
        loginErrorMessage = nil
        clearSignUpServerError()
        authFlowMode = .login
        isLoginPresented = true
        AppLogger.debug(.auth, "Present login for \(feature.rawValue)")
    }

    func configureExchangeConnectionsPresentation(
        onPresent: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        presentExchangeConnectionsSheet = onPresent
        dismissExchangeConnectionsSheet = onDismiss
    }

    func syncExchangeConnectionsPresentationState(_ isPresented: Bool, reason: String) {
        guard isExchangeConnectionsPresented != isPresented else {
            return
        }

        let previous = isExchangeConnectionsPresented
        isExchangeConnectionsPresented = isPresented
        AppLogger.debug(
            .lifecycle,
            "[ExchangeConnectionSheetDebug] presentation_reason=\(reason) state_transition=\(previous)->\(isPresented)"
        )
    }

    func switchAuthFlowMode(_ mode: AuthFlowMode) {
        guard authFlowMode != mode else { return }
        authFlowMode = mode
        loginErrorMessage = nil
        clearSignUpServerError()
    }

    func submitLogin() async {
        if let validationMessage = authInputValidator.loginValidationMessage(
            email: loginEmail,
            password: loginPassword
        ) {
            loginErrorMessage = validationMessage
            return
        }

        authState = .signingIn
        loginErrorMessage = nil
        AppLogger.debug(.auth, "[AuthFlowDebug] action=login_started method=email")

        do {
            let session = try await authService.signIn(email: loginEmail, password: loginPassword)
            AppLogger.debug(.auth, "[AuthFlowDebug] action=login_success method=email")
            await completeAuthentication(with: session, source: "login_success", method: "email")
        } catch {
            authState = .guest
            loginErrorMessage = friendlyAuthErrorMessage(error, mode: .login)
        }
    }

    func submitGoogleSignIn(presenting viewController: UIViewController?) async {
        guard !isAuthenticationBusy else { return }
        guard let viewController else {
            loginErrorMessage = "로그인 화면을 준비하지 못했어요. 잠시 후 다시 시도해주세요."
            return
        }

        authState = .signingIn
        activeSocialSignInMethod = .google
        loginErrorMessage = nil
        AppLogger.debug(.auth, "[AuthFlowDebug] action=login_started method=google")

        do {
            let credential = try await googleSignInProvider.signIn(presenting: viewController)
            let session = try await authService.signInWithGoogle(
                request: GoogleSocialLoginRequest(
                    idToken: credential.idToken,
                    email: credential.email,
                    displayName: credential.displayName,
                    deviceID: currentDeviceID
                )
            )
            AppLogger.debug(.auth, "[AuthFlowDebug] action=login_success method=google")
            await completeAuthentication(with: session, source: "google_login_success", method: "google")
        } catch {
            authState = .guest
            if !isUserCancelledAuthentication(error) {
                loginErrorMessage = friendlySocialAuthErrorMessage(error, method: .google)
            }
        }

        activeSocialSignInMethod = nil
    }

    func submitAppleSignIn(result: Result<ASAuthorization, Error>) async {
        guard !isAuthenticationBusy else { return }

        authState = .signingIn
        activeSocialSignInMethod = .apple
        loginErrorMessage = nil
        AppLogger.debug(.auth, "[AuthFlowDebug] action=login_started method=apple")

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw NetworkServiceError.parsingFailed("애플 인증 정보를 확인할 수 없어요.")
            }
            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  identityToken.isEmpty == false else {
                throw NetworkServiceError.parsingFailed("애플 identity token을 확인할 수 없어요.")
            }

            let authorizationCode = credential.authorizationCode.flatMap {
                String(data: $0, encoding: .utf8)
            }
            let fullName = credential.fullName.map {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .medium, options: [])
            }?.trimmedNonEmpty

            let session = try await authService.signInWithApple(
                request: AppleSocialLoginRequest(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    userIdentifier: credential.user,
                    email: credential.email,
                    fullName: fullName,
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName,
                    deviceID: currentDeviceID
                )
            )
            AppLogger.debug(.auth, "[AuthFlowDebug] action=login_success method=apple")
            await completeAuthentication(with: session, source: "apple_login_success", method: "apple")
        } catch {
            authState = .guest
            if !isUserCancelledAuthentication(error) {
                loginErrorMessage = friendlySocialAuthErrorMessage(error, method: .apple)
            }
        }

        activeSocialSignInMethod = nil
    }

    func submitSignUp() async {
        guard !isSigningUp else { return }

        let validation = signUpValidation
        guard let validationMessage = validation.primaryMessage else {
            clearSignUpServerError()
            isSigningUp = true
            defer { isSigningUp = false }

            do {
                let session = try await authService.signUp(
                    request: SignUpRequest(
                        email: signupEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: signupPassword,
                        passwordConfirm: signupPasswordConfirm,
                        nickname: signupNickname.trimmingCharacters(in: .whitespacesAndNewlines),
                        acceptedTerms: signupAcceptedTerms
                    )
                )
                showNotification("회원가입이 완료되었어요", type: .success)
                AppLogger.debug(.auth, "[AuthFlowDebug] action=login_success method=email_signup")
                await completeAuthentication(with: session, source: "signup_success", method: "email_signup")
                clearSignUpFields()
            } catch {
                presentSignUpServerError(error)
            }
            return
        }

        clearSignUpServerError()
        AppLogger.debug(.auth, "Sign up blocked by local validation -> \(validationMessage)")
    }

    func logout() {
        let sessionToRevoke = authState.session
        if let sessionToRevoke {
            let service = authService
            Task { @MainActor in
                try? await service.signOut(session: sessionToRevoke)
            }
        }
        googleSignInProvider.signOut()
        completeLocalSessionReset(reason: "logout")
        AppLogger.debug(.auth, "[AuthFlowDebug] action=logout_completed")
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard let session = authState.session else {
            presentLogin(for: .portfolio)
            return false
        }
        guard !isDeletingAccount else { return false }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await runAuthenticatedRequest(session: session) { [authService] refreshedSession in
                try await authService.deleteAccount(session: refreshedSession)
            }
            googleSignInProvider.signOut()
            completeLocalSessionReset(reason: "delete_account")
            showNotification("계정이 삭제되었어요.", type: .success)
            return true
        } catch {
            showNotification(friendlyAccountDeletionErrorMessage(error), type: .error)
            return false
        }
    }

    private func completeLocalSessionReset(reason: String) {
        authState = .guest
        activeSocialSignInMethod = nil
        pendingPostLoginFeature = nil
        loginPassword = ""
        clearSignUpFields()
        sessionRefreshTask?.cancel()
        sessionRefreshTask = nil
        acceptedStaleAccessTokens.removeAll()
        authSessionStore?.clearSession()
        dismissExchangeConnectionsPresentation(reason: reason)
        portfolioSummaryFetchTask?.cancel()
        portfolioSummaryFetchTask = nil
        portfolioSummaryFetchTaskContext = nil
        portfolioHistoryFetchTask?.cancel()
        portfolioHistoryFetchTask = nil
        portfolioHistoryFetchTaskContext = nil
        tradingChanceFetchTask?.cancel()
        tradingChanceFetchTask = nil
        tradingChanceFetchTaskContext = nil
        tradingOpenOrdersFetchTask?.cancel()
        tradingOpenOrdersFetchTask = nil
        tradingOpenOrdersFetchTaskContext = nil
        tradingFillsFetchTask?.cancel()
        tradingFillsFetchTask = nil
        tradingFillsFetchTaskContext = nil
        exchangeConnectionsFetchTask?.cancel()
        exchangeConnectionsFetchTask = nil
        exchangeConnectionsFetchTaskContext = nil
        assignPortfolioSummaryCardState(nil)
        portfolioSnapshotsByExchange.removeAll()
        refreshPortfolioOverviewViewState(reason: "logout")
        assignPortfolioState(.idle)
        assignPortfolioHistoryState(.idle)
        portfolioSummaryResponseMeta = .empty
        portfolioHistoryResponseMeta = .empty
        portfolioRefreshWarningMessage = nil
        lastResolvedPortfolioExchange = nil
        lastResolvedPortfolioHistoryExchange = nil
        selectedOrderRatioPercent = nil
        assignTradingChanceState(.idle, reason: "logout")
        assignOrderHistoryState(.idle, reason: "logout")
        assignFillsState(.idle, reason: "logout")
        assignSelectedOrderDetailState(.idle, reason: "logout")
        assignExchangeConnectionsState(.idle)
        exchangeConnectionsNoticeState = nil
        isExchangeConnectionsRetrying = false
        hasResolvedExchangeConnectionsState = false
        loadedExchangeConnections = []
        privateRequestFailureStates.removeAll()
        lastAutomaticPrivateRequestAtByKey.removeAll()
        privateWebSocketService.disconnect()
        updateAuthGate()
        updatePrivateSubscriptions(reason: reason)
        AppLogger.debug(.auth, "User session cleared reason=\(reason)")
    }

    func openStatusAction() {
        if isAuthenticated {
            requestExchangeConnectionsPresentation(reason: "status_action")
            Task {
                await loadExchangeConnections()
            }
        } else {
            presentLogin(for: activeTab.protectedFeature ?? .portfolio)
        }
    }

    func openExchangeConnections() {
        if isAuthenticated {
            requestExchangeConnectionsPresentation(reason: "user_request")
            Task {
                await loadExchangeConnections()
            }
        } else {
            presentLogin(for: .exchangeConnections)
        }
    }

    private func completeAuthentication(with session: AuthSession, source: String, method: String) async {
        authState = .authenticated(session)
        authSessionStore?.saveSession(session)
        AppLogger.debug(
            .auth,
            "[AuthFlowDebug] action=token_saved method=\(method) hasAccessToken=\(!session.accessToken.isEmpty) hasRefreshToken=\(session.hasRefreshToken)"
        )
        AppLogger.debug(.auth, "Authentication success -> \(session.email ?? session.userID ?? "user")")

        loginPassword = ""
        loginErrorMessage = nil
        activeSocialSignInMethod = nil
        clearSignUpServerError()
        isLoginPresented = false
        updateAuthGate()
        connectPrivateTradingFeedIfNeeded(reason: source)

        if pendingPostLoginFeature == .exchangeConnections {
            await loadExchangeConnections()
        }
        let refreshContext = beginRouteRefresh(reason: source)
        await runRouteRefreshIfCurrent(
            refreshContext,
            forceRefresh: true,
            reason: source
        )

        if pendingPostLoginFeature == .exchangeConnections {
            requestExchangeConnectionsPresentation(reason: "post_login_route")
        }
        pendingPostLoginFeature = nil
    }

    private func runAuthenticatedRequest<Value>(
        session: AuthSession,
        operation: @escaping (AuthSession) async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation(session)
        } catch {
            guard shouldAttemptRefresh(after: error) else {
                throw error
            }

            let refreshedSession = try await refreshAuthenticatedSession(
                matching: session,
                reason: "authenticated_request_401"
            )
            return try await operation(refreshedSession)
        }
    }

    private func refreshRestoredSessionIfPossible(_ session: AuthSession) async {
        guard session.hasRefreshToken else { return }

        do {
            _ = try await refreshAuthenticatedSession(matching: session, reason: "session_restore")
        } catch {
            if shouldClearSessionAfterRefreshFailure(error) {
                expireSessionAfterRefreshFailure(reason: "session_restore_failed")
            } else {
                AppLogger.debug(
                    .auth,
                    "[AuthFlowDebug] action=session_restore_failed reason=\(error.localizedDescription)"
                )
            }
        }
    }

    private func refreshAuthenticatedSession(matching session: AuthSession, reason: String) async throws -> AuthSession {
        guard let currentSession = authState.session else {
            AppLogger.debug(.auth, "[AuthFlowDebug] action=refresh_failed reason=no_current_session")
            throw NetworkServiceError.authenticationRequired
        }

        guard currentSession.accessToken == session.accessToken else {
            return currentSession
        }

        guard let refreshToken = currentSession.refreshToken?.trimmedNonEmpty else {
            AppLogger.debug(.auth, "[AuthFlowDebug] action=refresh_failed reason=missing_refresh_token")
            expireSessionAfterRefreshFailure(reason: "missing_refresh_token")
            throw NetworkServiceError.authenticationRequired
        }

        if let sessionRefreshTask {
            return try await sessionRefreshTask.value
        }

        AppLogger.debug(.auth, "[AuthFlowDebug] action=refresh_started reason=\(reason)")
        let service = authService
        let task = Task<AuthSession, Error> { @MainActor in
            try await service.refreshSession(refreshToken: refreshToken)
        }
        sessionRefreshTask = task

        do {
            let refreshedSession = try await task.value
                .replacingRefreshTokenIfMissing(with: currentSession.refreshToken)
            sessionRefreshTask = nil
            acceptedStaleAccessTokens.insert(currentSession.accessToken)
            authState = .authenticated(refreshedSession)
            authSessionStore?.saveSession(refreshedSession)
            updateAuthGate()
            connectPrivateTradingFeedIfNeeded(reason: "refresh_success")
            AppLogger.debug(.auth, "[AuthFlowDebug] action=refresh_success")
            AppLogger.debug(
                .auth,
                "[AuthFlowDebug] action=token_saved method=refresh hasAccessToken=\(!refreshedSession.accessToken.isEmpty) hasRefreshToken=\(refreshedSession.hasRefreshToken)"
            )
            return refreshedSession
        } catch {
            sessionRefreshTask = nil
            AppLogger.debug(.auth, "[AuthFlowDebug] action=refresh_failed reason=\(error.localizedDescription)")
            if shouldClearSessionAfterRefreshFailure(error) {
                expireSessionAfterRefreshFailure(reason: error.localizedDescription)
            }
            throw error
        }
    }

    private func shouldAttemptRefresh(after error: Error) -> Bool {
        guard let networkError = error as? NetworkServiceError else {
            return false
        }

        switch networkError {
        case .authenticationRequired:
            return true
        case .httpError(let statusCode, _, let category):
            return statusCode == 401 || category == .authenticationFailed
        case .transportError(_, let category):
            return category == .authenticationFailed
        case .invalidURL, .invalidResponse, .parsingFailed:
            return false
        }
    }

    private func shouldClearSessionAfterRefreshFailure(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkServiceError else {
            return false
        }

        switch networkError {
        case .authenticationRequired:
            return true
        case .httpError(let statusCode, _, let category):
            return statusCode == 400 || statusCode == 401 || statusCode == 403 || category == .authenticationFailed
        case .transportError, .invalidURL, .invalidResponse, .parsingFailed:
            return false
        }
    }

    private func expireSessionAfterRefreshFailure(reason: String) {
        completeLocalSessionReset(reason: "refresh_failed")
        AppLogger.debug(.auth, "[AuthFlowDebug] action=session_restore_failed reason=\(reason)")
        if let feature = activeTab.protectedFeature {
            presentLogin(for: feature)
        }
    }

    private func requestExchangeConnectionsPresentation(reason: String) {
        syncExchangeConnectionsPresentationState(true, reason: reason)
        presentExchangeConnectionsSheet?()
    }

    private func dismissExchangeConnectionsPresentation(reason: String) {
        syncExchangeConnectionsPresentationState(false, reason: reason)
        dismissExchangeConnectionsSheet?()
    }

    private func clearSignUpFields() {
        signupEmail = ""
        signupPassword = ""
        signupPasswordConfirm = ""
        signupNickname = ""
        signupAcceptedTerms = false
    }

    func clearSignUpServerError() {
        signupServerError = nil
    }

    private func presentSignUpServerError(_ error: Error) {
        let serverError = mapSignUpServerError(error)
        signupServerError = serverError

        let statusText = serverError.statusCode.map(String.init) ?? "none"
        AppLogger.debug(
            .auth,
            "Sign up failed -> status=\(statusText) mappedCode=\(serverError.code.rawValue) detail=\(error.localizedDescription)"
        )
    }

    private func mapSignUpServerError(_ error: Error) -> SignUpServerErrorState {
        if let networkError = error as? NetworkServiceError {
            switch networkError {
            case .httpError(let statusCode, _, _):
                switch statusCode {
                case 400:
                    return SignUpServerErrorState(
                        message: "입력값을 다시 확인해주세요.",
                        code: .invalidInput,
                        statusCode: statusCode
                    )
                case 409:
                    return SignUpServerErrorState(
                        message: "이미 존재하는 계정이에요.",
                        code: .duplicateAccount,
                        statusCode: statusCode
                    )
                case 500...599:
                    return SignUpServerErrorState(
                        message: "일시적인 오류예요. 잠시 후 다시 시도해주세요.",
                        code: .serverUnavailable,
                        statusCode: statusCode
                    )
                default:
                    break
                }
            case .parsingFailed:
                return SignUpServerErrorState(
                    message: "일시적인 오류예요. 잠시 후 다시 시도해주세요.",
                    code: .decodingFailure,
                    statusCode: nil
                )
            case .transportError(let message, _):
                return signUpTransportErrorState(message: message)
            case .invalidURL, .invalidResponse, .authenticationRequired:
                break
            }
        }

        let rawMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = rawMessage.lowercased()
        if lowercased.contains("already")
            || lowercased.contains("exists")
            || lowercased.contains("duplicate")
            || lowercased.contains("이미 가입")
            || lowercased.contains("이미 사용") {
            return SignUpServerErrorState(
                message: "이미 존재하는 계정이에요.",
                code: .duplicateAccount,
                statusCode: 409
            )
        }
        if lowercased.contains("invalid") || lowercased.contains("credential") {
            return SignUpServerErrorState(
                message: "입력값을 다시 확인해주세요.",
                code: .invalidInput,
                statusCode: 400
            )
        }
        if lowercased.contains("timed out") || lowercased.contains("timeout") {
            return SignUpServerErrorState(
                message: "일시적인 오류예요. 잠시 후 다시 시도해주세요.",
                code: .timeout,
                statusCode: nil
            )
        }
        if lowercased.contains("network") || lowercased.contains("connect") {
            return SignUpServerErrorState(
                message: "일시적인 오류예요. 잠시 후 다시 시도해주세요.",
                code: .transport,
                statusCode: nil
            )
        }

        return SignUpServerErrorState(
            message: "일시적인 오류예요. 잠시 후 다시 시도해주세요.",
            code: .unknown,
            statusCode: nil
        )
    }

    private func signUpTransportErrorState(message: String) -> SignUpServerErrorState {
        let normalized = message.lowercased()
        if normalized.contains("지연")
            || normalized.contains("timed out")
            || normalized.contains("timeout") {
            return SignUpServerErrorState(
                message: "일시적인 오류예요. 잠시 후 다시 시도해주세요.",
                code: .timeout,
                statusCode: nil
            )
        }

        return SignUpServerErrorState(
            message: "일시적인 오류예요. 잠시 후 다시 시도해주세요.",
            code: .transport,
            statusCode: nil
        )
    }

    private func friendlyAuthErrorMessage(_ error: Error, mode: AuthFlowMode) -> String {
        if let networkError = error as? NetworkServiceError,
           case let .httpError(statusCode, serverMessage, _) = networkError {
            return friendlyHTTPAuthErrorMessage(
                statusCode: statusCode,
                serverMessage: serverMessage,
                mode: mode
            )
        }

        let rawMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = rawMessage.lowercased()
        if lowercased.contains("already")
            || lowercased.contains("exists")
            || lowercased.contains("duplicate")
            || lowercased.contains("이미 가입")
            || lowercased.contains("이미 사용") {
            return mode == .signUp
                ? "이미 존재하는 계정이에요."
                : "이미 사용 중인 이메일이에요. 다른 이메일로 시도해주세요."
        }
        if lowercased.contains("invalid") || lowercased.contains("credential") || lowercased.contains("password") {
            return mode == .login
                ? "이메일 또는 비밀번호를 다시 확인해주세요."
                : "입력한 정보 또는 인증 상태를 다시 확인해주세요."
        }
        if lowercased.contains("network") || lowercased.contains("connect") || lowercased.contains("timed out") {
            return "서버 연결이 불안정해요. 잠시 후 다시 시도해주세요."
        }
        return rawMessage.isEmpty
            ? (mode == .login ? "로그인에 실패했어요." : "회원가입에 실패했어요.")
            : rawMessage
    }

    private func friendlySocialAuthErrorMessage(_ error: Error, method: SocialSignInMethod) -> String {
        if let networkError = error as? NetworkServiceError,
           case .httpError(let statusCode, _, _) = networkError {
            switch statusCode {
            case 400, 401, 403:
                return "\(method.title) 인증 정보를 확인하지 못했어요. 다시 시도해주세요."
            case 404:
                return "\(method.title) 로그인 API 경로를 찾지 못했어요. 앱과 서버 설정을 확인해주세요."
            case 500...599:
                return "일시적인 오류예요. 잠시 후 다시 시도해주세요."
            default:
                break
            }
        }

        let message = friendlyAuthErrorMessage(error, mode: .login)
        if message.isEmpty {
            return "\(method.title) 로그인에 실패했어요."
        }
        return message
    }

    private func friendlyAccountDeletionErrorMessage(_ error: Error) -> String {
        if let networkError = error as? NetworkServiceError,
           case .httpError(let statusCode, _, _) = networkError {
            switch statusCode {
            case 401, 403:
                return "로그인 상태를 다시 확인한 뒤 탈퇴를 진행해주세요."
            case 404, 501:
                return "앱 내 탈퇴 API가 아직 준비되지 않았어요. 계정삭제 안내 페이지를 확인해주세요."
            case 500...599:
                return "일시적인 오류예요. 잠시 후 다시 시도해주세요."
            default:
                break
            }
        }

        let rawMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawMessage.isEmpty ? "회원탈퇴를 완료하지 못했어요. 잠시 후 다시 시도해주세요." : rawMessage
    }

    private func isUserCancelledAuthentication(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return true
        }

        let message = nsError.localizedDescription.lowercased()
        return message.contains("cancel") || message.contains("취소")
    }

    private var currentDeviceID: String? {
        UIDevice.current.identifierForVendor?.uuidString
    }

    private func friendlyHTTPAuthErrorMessage(
        statusCode: Int,
        serverMessage: String,
        mode: AuthFlowMode
    ) -> String {
        if mode == .signUp {
            switch statusCode {
            case 400:
                return "입력한 회원가입 정보를 다시 확인해주세요."
            case 404:
                AppLogger.debug(.auth, "Sign up endpoint returned 404 -> \(serverMessage)")
                return "회원가입 API 경로를 찾지 못했어요. 앱과 서버 설정을 확인해주세요."
            case 409:
                return "이미 존재하는 계정이에요."
            case 500...599:
                return "일시적인 오류예요. 잠시 후 다시 시도해주세요."
            default:
                break
            }
        }

        switch statusCode {
        case 400:
            return mode == .login
                ? "이메일 또는 비밀번호를 다시 확인해주세요."
                : "입력한 정보를 다시 확인해주세요."
        case 401, 403:
            return mode == .login
                ? "이메일 또는 비밀번호를 다시 확인해주세요."
                : "인증 상태를 다시 확인해주세요."
        case 404:
            AppLogger.debug(.auth, "Auth endpoint returned 404 -> \(serverMessage)")
            return mode == .login
                ? "로그인 API 경로를 찾지 못했어요. 앱과 서버 설정을 확인해주세요."
                : "회원가입 API 경로를 찾지 못했어요. 앱과 서버 설정을 확인해주세요."
        case 409:
            return "이미 존재하는 계정이에요."
        case 500...599:
            return "일시적인 오류예요. 잠시 후 다시 시도해주세요."
        default:
            let trimmedMessage = serverMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedMessage.isEmpty
                ? (mode == .login ? "로그인에 실패했어요." : "회원가입에 실패했어요.")
                : trimmedMessage
        }
    }

    func makeExchangeConnectionFormViewState(
        exchange: Exchange,
        connection: ExchangeConnection? = nil
    ) -> ExchangeConnectionFormViewState {
        if let connection {
            return .edit(connection: connection)
        }
        return .create(exchange: exchange)
    }

    func validationMessageForExchangeConnectionForm(
        exchange: Exchange,
        nickname: String,
        credentials: [ExchangeCredentialFieldKey: String],
        mode: ExchangeConnectionFormViewState.Mode
    ) -> String? {
        exchangeConnectionFormValidator.validationMessage(
            exchange: exchange,
            nickname: nickname,
            credentials: credentials,
            mode: mode
        )
    }

    @discardableResult
    func createExchangeConnection(
        exchange: Exchange,
        nickname: String,
        permission: ExchangeConnectionPermission,
        credentials: [ExchangeCredentialFieldKey: String]
    ) async -> Bool {
        guard let session = authState.session else {
            presentLogin(for: .exchangeConnections)
            return false
        }

        let validationMessage = exchangeConnectionFormValidator.validationMessage(
            exchange: exchange,
            nickname: nickname,
            credentials: credentials,
            mode: .create
        )
        guard validationMessage == nil else {
            showNotification(validationMessage!, type: .error)
            return false
        }

        do {
            _ = try await runAuthenticatedRequest(session: session) { [exchangeConnectionsRepository] refreshedSession in
                try await exchangeConnectionsRepository.createConnection(
                    session: refreshedSession,
                    request: ExchangeConnectionUpsertRequest(
                        exchange: exchange,
                        permission: permission,
                        nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        credentials: credentials.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    )
                )
            }
            showNotification("거래소 연결을 추가했어요", type: .success)
            await loadExchangeConnections()
            return true
        } catch {
            showNotification(error.localizedDescription, type: .error)
            return false
        }
    }

    @discardableResult
    func updateExchangeConnection(
        connection: ExchangeConnection,
        nickname: String,
        permission: ExchangeConnectionPermission,
        credentials: [ExchangeCredentialFieldKey: String]
    ) async -> Bool {
        guard let session = authState.session else {
            presentLogin(for: .exchangeConnections)
            return false
        }

        let filteredCredentials = credentials.filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let validationMessage = exchangeConnectionFormValidator.validationMessage(
            exchange: connection.exchange,
            nickname: nickname,
            credentials: filteredCredentials,
            mode: .edit(connectionID: connection.id)
        )

        guard validationMessage == nil else {
            showNotification(validationMessage!, type: .error)
            return false
        }

        do {
            _ = try await runAuthenticatedRequest(session: session) { [exchangeConnectionsRepository] refreshedSession in
                try await exchangeConnectionsRepository.updateConnection(
                    session: refreshedSession,
                    request: ExchangeConnectionUpdateRequest(
                        id: connection.id,
                        permission: permission,
                        nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        credentials: filteredCredentials
                    )
                )
            }
            showNotification("거래소 연결을 수정했어요", type: .success)
            await loadExchangeConnections()
            return true
        } catch {
            showNotification(error.localizedDescription, type: .error)
            return false
        }
    }

    @discardableResult
    func deleteExchangeConnection(id: String) async -> Bool {
        guard let session = authState.session else {
            presentLogin(for: .exchangeConnections)
            return false
        }

        do {
            try await runAuthenticatedRequest(session: session) { [exchangeConnectionsRepository] refreshedSession in
                try await exchangeConnectionsRepository.deleteConnection(session: refreshedSession, connectionID: id)
            }
            showNotification("거래소 연결을 삭제했어요", type: .success)
            await loadExchangeConnections()
            return true
        } catch {
            showNotification(error.localizedDescription, type: .error)
            return false
        }
    }

    func loadPortfolio(reason: String = "manual") async {
        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip portfolio fetch in guest state")
            assignPortfolioSummaryCardState(nil)
            portfolioSnapshotsByExchange.removeAll()
            refreshPortfolioOverviewViewState(reason: "\(reason)_guest")
            assignPortfolioState(.idle)
            assignPortfolioHistoryState(.idle)
            portfolioSummaryResponseMeta = .empty
            portfolioHistoryResponseMeta = .empty
            portfolioRefreshWarningMessage = nil
            lastResolvedPortfolioExchange = nil
            lastResolvedPortfolioHistoryExchange = nil
            return
        }

        guard let requestExchange = portfolioPrimaryExchange() else {
            assignPortfolioSummaryCardState(nil)
            refreshPortfolioOverviewViewState(reason: "\(reason)_unsupported")
            assignPortfolioState(.failed("자산 조회를 지원하는 거래소 연결이 필요해요."))
            assignPortfolioHistoryState(.idle)
            portfolioSummaryResponseMeta = .empty
            portfolioHistoryResponseMeta = .empty
            portfolioRefreshWarningMessage = nil
            portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: currentPrivateStreamingStatus,
                context: .portfolio,
                warningMessage: "지원하지 않는 기능입니다."
            )
            return
        }

        if requestExchange != selectedExchange {
            AppLogger.debug(
                .lifecycle,
                "[PortfolioSectionDebug] asset_snapshot_retained selectedExchange=\(selectedExchange.rawValue) requestExchange=\(requestExchange.rawValue) reason=portfolio_aggregate_fallback"
            )
        }

        let context = PortfolioLoadContext(exchange: requestExchange, accessToken: session.accessToken)
        let retainsSummaryState = canRetainPortfolioSummary(for: requestExchange)
        let retainsHistoryState = canRetainPortfolioHistory(for: requestExchange)
        let summaryRequestKey = privateRequestKey(
            endpoint: .portfolioSummary,
            exchange: requestExchange,
            route: .portfolio
        )
        let historyRequestKey = privateRequestKey(
            endpoint: .portfolioHistory,
            exchange: requestExchange,
            route: .portfolio
        )
        let shouldSkipSummary = shouldSuppressPrivateRequest(
            summaryRequestKey,
            reason: reason
        )
        let shouldSkipHistory = shouldSuppressPrivateRequest(
            historyRequestKey,
            reason: reason
        )
        let shouldThrottleSummary = shouldThrottleAutomaticPrivateRefresh(
            summaryRequestKey,
            reason: reason
        )
        let shouldThrottleHistory = shouldThrottleAutomaticPrivateRefresh(
            historyRequestKey,
            reason: reason
        )

        if !retainsSummaryState, lastResolvedPortfolioExchange != requestExchange {
            assignPortfolioSummaryCardState(nil)
            portfolioSummaryResponseMeta = .empty
        }

        guard (!shouldSkipSummary && !shouldThrottleSummary) || (!shouldSkipHistory && !shouldThrottleHistory) else {
            refreshPrivateStatusViewStates()
            return
        }

        AppLogger.debug(.route, "Authenticated portfolio path -> \(requestExchange.rawValue) reason=\(reason)")

        if !isAutomaticPrivateRefreshReason(reason) {
            portfolioRefreshWarningMessage = nil
        }
        if !shouldSkipSummary,
           !retainsSummaryState,
           shouldEnterLoadingState(from: portfolioState, reason: reason) {
            assignPortfolioState(.loading)
        }
        if !shouldSkipHistory,
           !retainsHistoryState,
           shouldEnterLoadingState(from: portfolioHistoryState, reason: reason) {
            assignPortfolioHistoryState(.loading)
            portfolioHistoryResponseMeta = .empty
        }

        let summaryTask: Task<PortfolioSnapshot, Error>?
        if shouldSkipSummary || shouldThrottleSummary {
            summaryTask = nil
        } else {
            noteAutomaticPrivateRefresh(summaryRequestKey, reason: reason)
            summaryTask = makePortfolioSummaryTask(for: context, session: session)
        }

        let historyTask: Task<PortfolioHistorySnapshot, Error>?
        if shouldSkipHistory || shouldThrottleHistory {
            historyTask = nil
        } else {
            noteAutomaticPrivateRefresh(historyRequestKey, reason: reason)
            historyTask = makePortfolioHistoryTask(for: context, session: session)
        }

        if let summaryTask {
            do {
                let summary = try await summaryTask.value
                if portfolioSummaryFetchTaskContext == context {
                    portfolioSummaryFetchTask = nil
                    portfolioSummaryFetchTaskContext = nil
                }
                guard shouldApplyPortfolioLoad(for: context) else { return }

                clearPrivateRequestFailure(summaryRequestKey)
                lastResolvedPortfolioExchange = requestExchange
                portfolioSummaryResponseMeta = summary.meta
                assignPortfolioSummaryCardState(PortfolioSummaryCardState(snapshot: summary))
                portfolioSnapshotsByExchange[requestExchange] = summary
                assignPortfolioState(summary.holdings.isEmpty && summary.cash == 0 ? .empty : .loaded(summary))
                if let partialFailureMessage = summary.partialFailureMessage {
                    portfolioRefreshWarningMessage = partialFailureMessage
                }
                refreshPortfolioOverviewViewState(reason: "\(reason)_selected_summary_loaded")
            } catch {
                if portfolioSummaryFetchTaskContext == context {
                    portfolioSummaryFetchTask = nil
                    portfolioSummaryFetchTaskContext = nil
                }
                guard shouldApplyPortfolioLoad(for: context) else { return }
                if isCancellationLike(error) {
                    AppLogger.debug(
                        .lifecycle,
                        "[PortfolioSectionDebug] request_cancelled_ignored exchange=\(requestExchange.rawValue) section=summary reason=\(reason)"
                    )
                } else {
                    recordPrivateRequestFailure(summaryRequestKey, error: error, reason: reason)
                    let message = userFacingRefreshMessage(
                        for: error,
                        fallback: "자산 데이터를 불러오지 못했어요. 서버 상태를 확인한 뒤 다시 시도해주세요.",
                        cancellationFallback: "자산 현황을 다시 확인하고 있어요."
                    )

                    if retainsSummaryState || portfolioSnapshotsByExchange[requestExchange] != nil {
                        portfolioRefreshWarningMessage = message
                        AppLogger.debug(
                            .lifecycle,
                            "[PortfolioSectionDebug] asset_snapshot_retained exchange=\(requestExchange.rawValue) reason=\(reason)_selected_summary_failed"
                        )
                        refreshPortfolioOverviewViewState(reason: "\(reason)_selected_summary_failed_retained")
                    } else {
                        assignPortfolioSummaryCardState(nil)
                        portfolioSnapshotsByExchange.removeValue(forKey: requestExchange)
                        refreshPortfolioOverviewViewState(reason: "\(reason)_selected_summary_failed")
                        portfolioSummaryResponseMeta = .empty
                        assignPortfolioState(.failed(message))
                    }
                }
            }
        }

        if activeTab == .portfolio {
            await loadConnectedPortfolioSummaries(
                excluding: requestExchange,
                session: session,
                reason: reason
            )
        }

        if let historyTask {
            do {
                let historySnapshot = try await historyTask.value
                if portfolioHistoryFetchTaskContext == context {
                    portfolioHistoryFetchTask = nil
                    portfolioHistoryFetchTaskContext = nil
                }
                guard shouldApplyPortfolioLoad(for: context) else { return }

                clearPrivateRequestFailure(historyRequestKey)
                lastResolvedPortfolioHistoryExchange = requestExchange
                portfolioHistoryResponseMeta = historySnapshot.meta
                let filteredItems = filteredPortfolioHistoryItems(
                    historySnapshot.items,
                    exchange: requestExchange
                )
                assignPortfolioHistoryState(filteredItems.isEmpty ? .empty : .loaded(filteredItems))
            } catch {
                if portfolioHistoryFetchTaskContext == context {
                    portfolioHistoryFetchTask = nil
                    portfolioHistoryFetchTaskContext = nil
                }
                guard shouldApplyPortfolioLoad(for: context) else { return }

                if isCancellationLike(error) {
                    AppLogger.debug(
                        .lifecycle,
                        "[PortfolioSectionDebug] request_cancelled_ignored exchange=\(requestExchange.rawValue) section=history reason=\(reason)"
                    )
                } else {
                    recordPrivateRequestFailure(historyRequestKey, error: error, reason: reason)
                    let message = userFacingRefreshMessage(
                        for: error,
                        fallback: "최근 자산 히스토리를 불러오지 못했어요. 잠시 후 다시 시도해주세요.",
                        cancellationFallback: "최근 자산 히스토리를 다시 확인하고 있어요."
                    )

                    if retainsHistoryState {
                        portfolioRefreshWarningMessage = portfolioRefreshWarningMessage ?? message
                    } else if portfolioState.value != nil || retainsSummaryState || portfolioOverviewViewState != nil {
                        assignPortfolioHistoryState(.failed(message))
                        portfolioRefreshWarningMessage = portfolioRefreshWarningMessage ?? message
                    } else {
                        assignPortfolioHistoryState(.idle)
                    }
                }
            }
        }

        refreshPrivateStatusViewStates()
    }

    func loadOrders(reason: String = "manual") async {
        guard capabilityResolver.supportsTrading(on: selectedExchange) else {
            assignOrderHistoryState(.failed("이 거래소는 주문 기능을 지원하지 않아요."), reason: "\(reason)_unsupported")
            assignFillsState(.idle, reason: "\(reason)_unsupported")
            assignTradingChanceState(.idle, reason: "\(reason)_unsupported")
            tradingStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: currentPrivateStreamingStatus,
                context: .trade,
                warningMessage: "지원하지 않는 기능입니다."
            )
            return
        }

        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip orders fetch in guest state")
            assignOrderHistoryState(.idle, reason: "\(reason)_guest")
            assignFillsState(.idle, reason: "\(reason)_guest")
            assignTradingChanceState(.idle, reason: "\(reason)_guest")
            return
        }

        guard let coin = selectedCoin else {
            assignTradingChanceState(.idle, reason: "\(reason)_missing_symbol")
            assignOrderHistoryState(.idle, reason: "\(reason)_missing_symbol")
            assignFillsState(.idle, reason: "\(reason)_missing_symbol")
            assignSelectedOrderDetailState(.idle, reason: "\(reason)_missing_symbol")
            return
        }

        let context = TradingLoadContext(
            exchange: selectedExchange,
            symbol: coin.symbol,
            accessToken: session.accessToken
        )
        let previousChanceState = tradingChanceState
        let previousOrderHistoryState = orderHistoryState
        let previousFillsState = fillsState
        let chanceRequestKey = privateRequestKey(
            endpoint: .tradingChance,
            exchange: context.exchange,
            route: .trade
        )
        let openOrdersRequestKey = privateRequestKey(
            endpoint: .openOrders,
            exchange: context.exchange,
            route: .trade
        )
        let fillsRequestKey = privateRequestKey(
            endpoint: .fills,
            exchange: context.exchange,
            route: .trade
        )

        let shouldSkipChance = shouldSuppressPrivateRequest(chanceRequestKey, reason: reason)
            || shouldThrottleAutomaticPrivateRefresh(chanceRequestKey, reason: reason)
        let shouldSkipOpenOrders = shouldSuppressPrivateRequest(openOrdersRequestKey, reason: reason)
            || shouldThrottleAutomaticPrivateRefresh(openOrdersRequestKey, reason: reason)
        let shouldSkipFills = shouldSuppressPrivateRequest(fillsRequestKey, reason: reason)
            || shouldThrottleAutomaticPrivateRefresh(fillsRequestKey, reason: reason)

        guard !shouldSkipChance || !shouldSkipOpenOrders || !shouldSkipFills else {
            refreshPrivateStatusViewStates()
            return
        }

        if !shouldSkipChance, shouldShowTradingLoading(tradingChanceState, reason: reason) {
            assignTradingChanceState(.loading, reason: "\(reason)_start")
        }
        if !shouldSkipOpenOrders, shouldShowTradingLoading(orderHistoryState, reason: reason) {
            assignOrderHistoryState(.loading, reason: "\(reason)_start")
        }
        if !shouldSkipFills, shouldShowTradingLoading(fillsState, reason: reason) {
            assignFillsState(.loading, reason: "\(reason)_start")
        }

        var metas: [ResponseMeta] = []
        var warningMessages: [String] = []

        let chanceTask: Task<TradingChance, Error>?
        if shouldSkipChance {
            chanceTask = nil
        } else {
            noteAutomaticPrivateRefresh(chanceRequestKey, reason: reason)
            chanceTask = makeTradingChanceTask(for: context, session: session)
        }

        let openOrdersTask: Task<OrderRecordsSnapshot, Error>?
        if shouldSkipOpenOrders {
            openOrdersTask = nil
        } else {
            noteAutomaticPrivateRefresh(openOrdersRequestKey, reason: reason)
            openOrdersTask = makeTradingOpenOrdersTask(for: context, session: session)
        }

        let fillsTask: Task<TradeFillsSnapshot, Error>?
        if shouldSkipFills {
            fillsTask = nil
        } else {
            noteAutomaticPrivateRefresh(fillsRequestKey, reason: reason)
            fillsTask = makeTradingFillsTask(for: context, session: session)
        }

        if let chanceTask {
            do {
                let chance = try await chanceTask.value
                if tradingChanceFetchTaskContext == context {
                    tradingChanceFetchTask = nil
                    tradingChanceFetchTaskContext = nil
                }
                guard shouldApplyTradingLoad(for: context) else { return }
                clearPrivateRequestFailure(chanceRequestKey)
                assignTradingChanceState(.loaded(chance), reason: "\(reason)_chance_loaded")
                if !chance.supportedOrderTypes.contains(orderType) {
                    setOrderType(chance.supportedOrderTypes.first ?? .limit)
                }
                if let warningMessage = chance.warningMessage {
                    warningMessages.append(warningMessage)
                }
            } catch {
                if tradingChanceFetchTaskContext == context {
                    tradingChanceFetchTask = nil
                    tradingChanceFetchTaskContext = nil
                }
                guard shouldApplyTradingLoad(for: context) else { return }
                recordPrivateRequestFailure(chanceRequestKey, error: error, reason: reason)
                let message = tradingSectionFailureMessage(for: error, endpoint: .tradingChance)
                let nextState = stableTradingFallback(
                    previous: previousChanceState,
                    current: tradingChanceState,
                    error: error,
                    message: message,
                    section: "chance"
                )
                assignTradingChanceState(nextState, reason: "\(reason)_chance_failed")
                if !isCancellationLike(error), previousChanceState.value != nil {
                    warningMessages.append(message)
                }
            }
        }

        if let openOrdersTask {
            do {
                let openOrdersSnapshot = try await openOrdersTask.value
                if tradingOpenOrdersFetchTaskContext == context {
                    tradingOpenOrdersFetchTask = nil
                    tradingOpenOrdersFetchTaskContext = nil
                }
                guard shouldApplyTradingLoad(for: context) else { return }
                clearPrivateRequestFailure(openOrdersRequestKey)
                metas.append(openOrdersSnapshot.meta)
                if let warningMessage = openOrdersSnapshot.meta.warningMessage {
                    warningMessages.append(warningMessage)
                }
                assignOrderHistoryState(
                    openOrdersSnapshot.orders.isEmpty ? .empty : .loaded(openOrdersSnapshot.orders),
                    reason: "\(reason)_open_orders_loaded"
                )
            } catch {
                if tradingOpenOrdersFetchTaskContext == context {
                    tradingOpenOrdersFetchTask = nil
                    tradingOpenOrdersFetchTaskContext = nil
                }
                guard shouldApplyTradingLoad(for: context) else { return }
                recordPrivateRequestFailure(openOrdersRequestKey, error: error, reason: reason)
                let message = tradingSectionFailureMessage(for: error, endpoint: .openOrders)
                let nextState = stableTradingFallback(
                    previous: previousOrderHistoryState,
                    current: orderHistoryState,
                    error: error,
                    message: message,
                    section: "open_orders"
                )
                assignOrderHistoryState(nextState, reason: "\(reason)_open_orders_failed")
                if !isCancellationLike(error), previousOrderHistoryState.value != nil {
                    warningMessages.append(message)
                }
            }
        }

        if let fillsTask {
            do {
                let fillsSnapshot = try await fillsTask.value
                if tradingFillsFetchTaskContext == context {
                    tradingFillsFetchTask = nil
                    tradingFillsFetchTaskContext = nil
                }
                guard shouldApplyTradingLoad(for: context) else { return }
                clearPrivateRequestFailure(fillsRequestKey)
                metas.append(fillsSnapshot.meta)
                if let warningMessage = fillsSnapshot.meta.warningMessage {
                    warningMessages.append(warningMessage)
                }
                assignFillsState(fillsSnapshot.fills.isEmpty ? .empty : .loaded(fillsSnapshot.fills), reason: "\(reason)_fills_loaded")
            } catch {
                if tradingFillsFetchTaskContext == context {
                    tradingFillsFetchTask = nil
                    tradingFillsFetchTaskContext = nil
                }
                guard shouldApplyTradingLoad(for: context) else { return }
                recordPrivateRequestFailure(fillsRequestKey, error: error, reason: reason)
                let message = tradingSectionFailureMessage(for: error, endpoint: .fills)
                let nextState = stableTradingFallback(
                    previous: previousFillsState,
                    current: fillsState,
                    error: error,
                    message: message,
                    section: "fills"
                )
                assignFillsState(nextState, reason: "\(reason)_fills_failed")
                if !isCancellationLike(error), previousFillsState.value != nil {
                    warningMessages.append(message)
                }
            }
        }

        tradingStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: combineMetas(metas),
            streamingStatus: currentPrivateStreamingStatus,
            context: .trade,
            warningMessage: resolvedWarningMessage(
                primary: warningMessages.first,
                fallback: currentPrivateStreamingWarningMessage
            )
        )
    }

    func loadOrderDetail(orderID: String) async {
        guard let session = authState.session else {
            presentLogin(for: .trade)
            return
        }

        selectedOrderDetailState = .loading

        do {
            let detail = try await runAuthenticatedRequest(session: session) { [tradingRepository, selectedExchange] refreshedSession in
                try await tradingRepository.fetchOrderDetail(session: refreshedSession, exchange: selectedExchange, orderID: orderID)
            }
            selectedOrderDetailState = .loaded(detail)
        } catch {
            selectedOrderDetailState = .failed(error.localizedDescription)
        }
    }

    func cancelOrder(_ order: OrderRecord) async {
        guard let session = authState.session else {
            presentLogin(for: .trade)
            return
        }

        do {
            try await runAuthenticatedRequest(session: session) { [tradingRepository, selectedExchange] refreshedSession in
                try await tradingRepository.cancelOrder(session: refreshedSession, exchange: selectedExchange, orderID: order.id)
            }
            showNotification("주문을 취소했어요", type: .success)
            await loadOrders(reason: "order_cancel_refresh")
            await loadPortfolio()
        } catch {
            showNotification(error.localizedDescription, type: .error)
        }
    }

    func loadExchangeConnections(reason: String = "manual") async {
        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip exchange connections fetch in guest state")
            assignExchangeConnectionsState(.idle)
            exchangeConnectionsNoticeState = nil
            hasResolvedExchangeConnectionsState = false
            loadedExchangeConnections = []
            return
        }

        let context = ExchangeConnectionsLoadContext(accessToken: session.accessToken)
        let requestKey = privateRequestKey(
            endpoint: .exchangeConnections,
            exchange: nil,
            route: activeTab
        )
        let isUserRetry = isUserInitiatedPrivateRetryReason(reason)

        if isUserRetry, isExchangeConnectionsRetrying {
            AppLogger.debug(.network, "[ExchangeConnections] retry ignored while request is in flight")
            return
        }

        guard !shouldSuppressPrivateRequest(requestKey, reason: reason),
              !shouldThrottleAutomaticPrivateRefresh(requestKey, reason: reason) else {
            return
        }

        if isUserRetry {
            isExchangeConnectionsRetrying = true
        }
        defer {
            if isUserRetry {
                isExchangeConnectionsRetrying = false
            }
        }

        if !hasResolvedExchangeConnectionsState,
           shouldEnterLoadingState(from: exchangeConnectionsState, reason: reason) {
            assignExchangeConnectionsState(.loading)
            if !isAutomaticPrivateRefreshReason(reason) {
                exchangeConnectionsNoticeState = nil
            }
        }

        do {
            noteAutomaticPrivateRefresh(requestKey, reason: reason)
            let task = makeExchangeConnectionsTask(for: context, session: session)
            let snapshot = try await task.value
            if exchangeConnectionsFetchTaskContext == context {
                exchangeConnectionsFetchTask = nil
                exchangeConnectionsFetchTaskContext = nil
            }
            guard shouldApplyExchangeConnectionsLoad(for: context) else { return }

            clearPrivateRequestFailure(requestKey)
            loadedExchangeConnections = snapshot.connections
            let cards = exchangeConnectionsUseCase.makeCardViewStates(
                connections: snapshot.connections,
                crudCapability: exchangeConnectionCRUDCapability
            )
            hasResolvedExchangeConnectionsState = true
            exchangeConnectionsNoticeState = makeExchangeConnectionsNotice(from: snapshot)
            assignExchangeConnectionsState(cards.isEmpty ? .empty : .loaded(cards))
            prunePortfolioSnapshotsToConnectedAssetExchanges(reason: "\(reason)_connections_loaded")
            updatePrivateSubscriptions(reason: "exchange_connections_loaded")
        } catch {
            if exchangeConnectionsFetchTaskContext == context {
                exchangeConnectionsFetchTask = nil
                exchangeConnectionsFetchTaskContext = nil
            }
            guard shouldApplyExchangeConnectionsLoad(for: context) else { return }

            recordPrivateRequestFailure(requestKey, error: error, reason: reason)
            let message = userFacingRefreshMessage(
                for: error,
                fallback: "거래소 연결 상태를 불러오지 못했어요. 잠시 후 다시 시도해주세요.",
                cancellationFallback: "거래소 연결 상태를 다시 확인하고 있어요."
            )

            if hasResolvedExchangeConnectionsState {
                exchangeConnectionsNoticeState = ExchangeConnectionsNoticeState(
                    title: isCancellationLike(error) ? "연결 상태를 다시 확인하고 있어요" : "마지막으로 확인한 연결 정보를 표시하고 있어요",
                    message: message,
                    tone: .warning
                )
            } else {
                exchangeConnectionsNoticeState = nil
                assignExchangeConnectionsState(.failed(message))
            }
        }
    }

    func loadKimchiPremium(forceRefresh: Bool = false, reason: String = "unknown") async {
        await loadKimchiPremium(
            forceRefresh: forceRefresh,
            reason: reason,
            requestedSymbolsOverride: nil
        )
    }

    private func emptyKimchiSnapshot() -> KimchiPremiumSnapshot {
        KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [],
            fetchedAt: nil,
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil,
            failedSymbols: []
        )
    }

    private func beginKimchiGeneration(for exchange: Exchange) -> Int {
        let previousGeneration = kimchiPremiumRequestVersion
        kimchiPremiumRequestVersion += 1
        let generation = kimchiPremiumRequestVersion
        kimchiPremiumSettleTask?.cancel()
        kimchiPremiumDebugMessage = nil
        if previousGeneration > 0 {
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=drop_stale_generation previousGeneration=\(previousGeneration)"
            )
        }
        for (_, task) in kimchiPremiumFetchTasksByContext {
            task.cancel()
        }
        kimchiPremiumFetchTasksByContext.removeAll()
        kimchiPremiumFetchContext = nil
        return generation
    }

    private func shouldApplyKimchiGeneration(_ generation: Int, exchange: Exchange) -> Bool {
        generation == kimchiPremiumRequestVersion
            && currentKimchiDomesticExchange == exchange
    }

    private func fetchKimchiSnapshot(
        context: KimchiPremiumRequestContext
    ) async -> Result<KimchiPremiumSnapshot, Error> {
        if let task = kimchiPremiumFetchTasksByContext[context] {
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(context.exchange.rawValue) generation=\(context.generation) phase=request_deduped count=\(context.requestedSymbols.count)"
            )
            do {
                return .success(try await task.value)
            } catch {
                return .failure(error)
            }
        }

        let task = Task<KimchiPremiumSnapshot, Error> { [kimchiPremiumRepository] in
            try await kimchiPremiumRepository.fetchSnapshot(
                exchange: context.exchange,
                symbols: context.requestedSymbols
            )
        }
        kimchiPremiumFetchTasksByContext[context] = task
        kimchiPremiumFetchContext = context

        let result: Result<KimchiPremiumSnapshot, Error>
        do {
            result = .success(try await task.value)
        } catch {
            result = .failure(error)
        }
        kimchiPremiumFetchTasksByContext[context] = nil
        if kimchiPremiumFetchContext == context {
            kimchiPremiumFetchContext = nil
        }
        return result
    }

    private func mergeKimchiSnapshots(
        existing: KimchiPremiumSnapshot?,
        incoming: KimchiPremiumSnapshot
    ) -> KimchiPremiumSnapshot {
        func rowKey(_ row: KimchiPremiumRow) -> String {
            "\(row.exchange.rawValue):\(row.sourceExchange.rawValue):\(row.symbol)"
        }

        var rowsByIdentity = Dictionary(
            uniqueKeysWithValues: (existing?.rows ?? []).map { (rowKey($0), $0) }
        )
        incoming.rows.forEach { rowsByIdentity[rowKey($0)] = $0 }

        var failedSymbols = Set(existing?.failedSymbols ?? [])
        incoming.rows.forEach { failedSymbols.remove($0.symbol) }
        incoming.failedSymbols.forEach { failedSymbols.insert($0) }

        let fetchedAt = [incoming.fetchedAt, existing?.fetchedAt].compactMap { $0 }.max()
        return KimchiPremiumSnapshot(
            referenceExchange: incoming.referenceExchange,
            rows: rowsByIdentity.values.sorted {
                if $0.symbol == $1.symbol {
                    return $0.exchange.rawValue < $1.exchange.rawValue
                }
                return $0.symbol < $1.symbol
            },
            fetchedAt: fetchedAt,
            isStale: incoming.isStale || (existing?.isStale ?? false),
            warningMessage: incoming.warningMessage ?? existing?.warningMessage,
            partialFailureMessage: incoming.partialFailureMessage ?? existing?.partialFailureMessage,
            failedSymbols: Array(failedSymbols).sorted()
        )
    }

    private func mergedKimchiFailureSnapshot(
        existing: KimchiPremiumSnapshot?,
        failedSymbols: [String],
        message: String
    ) -> KimchiPremiumSnapshot {
        var failures = Set(existing?.failedSymbols ?? [])
        failedSymbols.forEach { failures.insert($0) }
        return KimchiPremiumSnapshot(
            referenceExchange: existing?.referenceExchange ?? .binance,
            rows: existing?.rows ?? [],
            fetchedAt: existing?.fetchedAt,
            isStale: existing?.rows.isEmpty == false ? true : (existing?.isStale ?? false),
            warningMessage: existing?.warningMessage,
            partialFailureMessage: message,
            failedSymbols: Array(failures).sorted()
        )
    }

    private func cacheKimchiPresentation(
        _ presentation: KimchiPresentationSnapshot,
        tier: KimchiCacheTier
    ) {
        let entry = KimchiCacheEntry(
            exchange: presentation.exchange,
            symbolsHash: presentation.symbolsHash,
            presentation: presentation,
            fetchedAt: presentation.meta.fetchedAt ?? Date()
        )
        switch tier {
        case .representative:
            representativeKimchiCacheByExchange[presentation.exchange] = entry
        case .visible:
            visibleKimchiCacheByExchange[presentation.exchange] = entry
        case .full:
            fullKimchiCacheByExchange[presentation.exchange] = entry
        }
    }

    private func applyKimchiPresentationIfChanged(
        _ presentation: KimchiPresentationSnapshot,
        generation: Int,
        phase: String,
        clearTransition: Bool,
        reason: String
    ) {
        let requiresTransitionMutation = clearTransition
            && kimchiPresentationState.selectedExchange == presentation.exchange
            && (kimchiPresentationState.transitionState.isLoading || kimchiTransitionMessage != nil)
        if activeKimchiPresentationSnapshot?.exchange == presentation.exchange,
           activeKimchiPresentationSnapshot == presentation,
           requiresTransitionMutation == false {
            AppLogger.debug(
                .network,
                "[KimchiSwitchPerf] exchange=\(presentation.exchange.rawValue) dropPatch reason=duplicate_exchange_state phase=\(phase)"
            )
            return
        }

        let previousRows = activeKimchiPresentationSnapshot?.exchange == presentation.exchange
            ? activeKimchiPresentationSnapshot?.rows ?? []
            : []
        swapKimchiPresentation(
            presentation,
            reason: reason,
            clearTransition: clearTransition
        )

        let previousByID = Dictionary(uniqueKeysWithValues: previousRows.map { ($0.id, $0) })
        for row in presentation.rows {
            let previousRow = previousByID[row.id]
            guard previousRow != row else { continue }
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(presentation.exchange.rawValue) generation=\(generation) phase=row_patch symbol=\(row.symbol) state=\(describe(row.status))"
            )
        }

        AppLogger.debug(
            .network,
            "[KimchiPipeline] exchange=\(presentation.exchange.rawValue) generation=\(generation) phase=\(phase) count=\(presentation.rows.count) reason=\(reason)"
        )
    }

    private func applyKimchiShell(
        exchange: Exchange,
        comparableSymbols: [String],
        symbolsHash: String,
        generation: Int,
        reason: String
    ) {
        let shellPresentation = makeKimchiPresentationSnapshot(
            from: emptyKimchiSnapshot(),
            exchange: exchange,
            comparableSymbols: comparableSymbols,
            symbolsHash: symbolsHash,
            phase: .responsePending
        )
        kimchiBasePhaseByExchange[exchange] = .initialLoading
        AppLogger.debug(
            .network,
            "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=switch_shell"
        )
        applyKimchiPresentationIfChanged(
            shellPresentation,
            generation: generation,
            phase: "switch_shell",
            clearTransition: false,
            reason: reason
        )
    }

    private func applyCachedKimchiLayers(
        exchange: Exchange,
        generation: Int,
        reason: String
    ) {
        if let representativeCache = representativeKimchiCacheByExchange[exchange] {
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=show_representative_cache count=\(Array(representativeCache.presentation.rows.prefix(kimchiRepresentativeRowLimit)).count)"
            )
            applyKimchiPresentationIfChanged(
                representativeCache.presentation,
                generation: generation,
                phase: "show_representative_cache",
                clearTransition: false,
                reason: reason
            )
        }

        if let visibleCache = visibleKimchiCacheByExchange[exchange] {
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=show_visible_cache count=\(visibleCache.presentation.rows.count)"
            )
            applyKimchiPresentationIfChanged(
                visibleCache.presentation,
                generation: generation,
                phase: "show_visible_cache",
                clearTransition: false,
                reason: reason
            )
        }

        if let fullCache = fullKimchiCacheByExchange[exchange] {
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=show_full_cache count=\(fullCache.presentation.rows.count)"
            )
            applyKimchiPresentationIfChanged(
                fullCache.presentation,
                generation: generation,
                phase: "show_full_cache",
                clearTransition: false,
                reason: reason
            )
        }
    }

    private func representativeKimchiSymbols(
        for exchange: Exchange,
        comparableSymbols: [String]
    ) -> [String] {
        Array(prioritizedSymbols(from: comparableSymbols, exchange: exchange).prefix(kimchiFirstPaintSymbolLimit))
    }

    private func visibleKimchiSymbols(
        for exchange: Exchange,
        comparableSymbols: [String],
        excluding excludedSymbols: [String]
    ) -> [String] {
        let excluded = Set(excludedSymbols)
        let visibleSymbols = visibleKimchiSymbolsByExchange[exchange] ?? []
        let firstScreenSymbols = Array(comparableSymbols.prefix(kimchiVisibleBatchSize))
        return Array(
            deduplicatedSymbols(visibleSymbols + firstScreenSymbols + comparableSymbols)
                .filter { excluded.contains($0) == false }
                .prefix(kimchiVisibleBatchSize)
        )
    }

    private func cacheTier(
        for requestedSymbols: [String],
        representativeSymbols: [String],
        fullComparableSymbols: [String]
    ) -> KimchiCacheTier {
        if Set(requestedSymbols) == Set(representativeSymbols) {
            return .representative
        }
        if Set(requestedSymbols) == Set(fullComparableSymbols) {
            return .full
        }
        return .visible
    }

    private func hydrateVisibleKimchiRowsIfNeeded(
        for exchange: Exchange,
        reason: String
    ) async {
        guard activeTab == .kimchi, currentKimchiDomesticExchange == exchange else {
            return
        }
        try? await Task.sleep(nanoseconds: kimchiVisibleHydrationDebounceNanoseconds)
        guard activeTab == .kimchi, currentKimchiDomesticExchange == exchange else {
            return
        }
        guard let symbols = visibleKimchiSymbolsByExchange[exchange], symbols.isEmpty == false else {
            return
        }
        await loadKimchiPremium(forceRefresh: true, reason: reason, requestedSymbolsOverride: symbols)
    }

    private func scheduleVisibleKimchiHydration(
        for exchange: Exchange,
        reason: String
    ) {
        guard activeTab == .kimchi, currentKimchiDomesticExchange == exchange else {
            return
        }

        let generation = kimchiPremiumRequestVersion
        kimchiVisibleHydrationTask?.cancel()
        kimchiVisibleHydrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.kimchiVisibleHydrationDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard self.activeTab == .kimchi, self.currentKimchiDomesticExchange == exchange else {
                return
            }
            guard generation == self.kimchiPremiumRequestVersion else {
                AppLogger.debug(
                    .network,
                    "[KimchiSwitchPerf] exchange=\(exchange.rawValue) dropPatch reason=stale_visible_hydration_generation"
                )
                return
            }
            guard let symbols = self.visibleKimchiSymbolsByExchange[exchange], symbols.isEmpty == false else {
                return
            }

            AppLogger.debug(
                .network,
                "[KimchiSwitchPerf] exchange=\(exchange.rawValue) phase=visible_hydration count=\(symbols.count)"
            )
            await self.loadKimchiPremium(
                forceRefresh: true,
                reason: reason,
                requestedSymbolsOverride: symbols
            )
        }
    }

    private func updateKimchiExchangeSelection(_ exchange: Exchange, source: String) {
        let previousExchange = selectedExchange
        selectedDomesticKimchiExchange = exchange
        selectedExchange = exchange
        setExchangeMenuVisible(false)
        kimchiVisibleHydrationTask?.cancel()
        kimchiSwitchStartedAtByExchange[exchange] = Date()
        kimchiFirstVisibleLoggedExchanges.remove(exchange)

        AppLogger.debug(
            .network,
            "[KimchiSwitchPerf] exchange=\(exchange.rawValue) phase=select previous=\(previousExchange.rawValue) source=\(source)"
        )
        AppLogger.debug(
            .route,
            "[KimchiView] selectedDomesticExchange changed \(previousExchange.rawValue) -> \(exchange.rawValue)"
        )

        if hasReadyableRepresentativeRows(in: cachedKimchiPresentation(for: exchange)) {
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=preserve_shell reason=exchange_switch_with_cache"
            )
            applyCachedKimchiPresentationIfAvailable(for: exchange, reason: "\(source)_cached")
        } else {
            beginKimchiTransition(to: exchange, reason: source)
        }

        let refreshContext = beginRouteRefresh(reason: "kimchi_exchange_changed")
        Task {
            await runRouteRefreshIfCurrent(
                refreshContext,
                forceRefresh: true,
                reason: "kimchi_exchange_changed"
            )
        }
    }

    private func fetchKimchiBatchAndPatch(
        exchange: Exchange,
        generation: Int,
        requestedSymbols: [String],
        representativeSymbols: [String],
        fullComparableSymbols: [String],
        fullComparableSymbolsHash: String,
        phase: String,
        batchIndex: Int?,
        reason: String
    ) async {
        let batchSymbols = deduplicatedSymbols(requestedSymbols)
        guard batchSymbols.isEmpty == false else {
            return
        }
        guard shouldApplyKimchiGeneration(generation, exchange: exchange) else {
            return
        }

        let requestContext = KimchiPremiumRequestContext(
            exchange: exchange,
            route: .kimchi,
            requestedSymbols: batchSymbols,
            symbolsHash: stableSymbolHash(from: batchSymbols),
            generation: generation
        )
        if let batchIndex {
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=\(phase)_start batchIndex=\(batchIndex) batchSize=\(batchSymbols.count)"
            )
        } else {
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=\(phase)_start count=\(batchSymbols.count)"
            )
        }

        let startedAt = Date()
        let result = await fetchKimchiSnapshot(context: requestContext)
        guard shouldApplyKimchiGeneration(generation, exchange: exchange) else {
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=drop_stale_generation previousGeneration=\(generation)"
            )
            return
        }

        switch result {
        case .success(let snapshot):
            let mergedSnapshot = mergeKimchiSnapshots(
                existing: kimchiSnapshotsByExchange[exchange],
                incoming: snapshot
            )
            kimchiSnapshotsByExchange[exchange] = mergedSnapshot
            lastGoodKimchiSnapshotsByExchange[exchange] = mergedSnapshot
            let presentationBuildStartedAt = Date()
            let presentation = await prepareKimchiPresentationSnapshot(
                from: mergedSnapshot,
                exchange: exchange,
                comparableSymbols: fullComparableSymbols,
                symbolsHash: fullComparableSymbolsHash,
                phase: .responsePending
            )
            let presentationBuildElapsedMs = Int(Date().timeIntervalSince(presentationBuildStartedAt) * 1000)
            AppLogger.debug(
                .network,
                "[KimchiSwitchPerf] exchange=\(exchange.rawValue) phase=prepare_\(phase) elapsedMs=\(presentationBuildElapsedMs)"
            )
            kimchiBasePhaseByExchange[exchange] = .showingSnapshot
            let publishStartedAt = Date()
            applyKimchiPresentationIfChanged(
                presentation,
                generation: generation,
                phase: phase,
                clearTransition: true,
                reason: reason
            )
            let publishElapsedMs = Int(Date().timeIntervalSince(publishStartedAt) * 1000)
            AppLogger.debug(
                .network,
                "[KimchiSwitchPerf] exchange=\(exchange.rawValue) phase=publish_\(phase) elapsedMs=\(publishElapsedMs)"
            )
            cacheKimchiPresentation(
                presentation,
                tier: cacheTier(
                    for: batchSymbols,
                    representativeSymbols: representativeSymbols,
                    fullComparableSymbols: fullComparableSymbols
                )
            )
            lastKimchiPremiumFetchedAtByExchange[exchange] = Date()
            lastSuccessfulKimchiPremiumRequestContext = requestContext
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            if let batchIndex {
                AppLogger.debug(
                    .network,
                    "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=\(phase)_success batchIndex=\(batchIndex) patched=\(batchSymbols.count) elapsedMs=\(elapsedMs)"
                )
            } else {
                AppLogger.debug(
                    .network,
                    "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=\(phase)_success count=\(batchSymbols.count) elapsedMs=\(elapsedMs)"
                )
            }
            scheduleKimchiPremiumSettlementIfNeeded(
                snapshot: mergedSnapshot,
                exchange: exchange,
                comparableSymbols: fullComparableSymbols,
                symbolsHash: fullComparableSymbolsHash,
                requestVersion: generation
            )
        case .failure(let error):
            let userFacingMessage = kimchiPremiumUserFacingMessage(for: error)
            kimchiPremiumDebugMessage = kimchiPremiumDebugDetail(for: error)
            let retainedSnapshot = kimchiSnapshotsByExchange[exchange]
                ?? lastGoodKimchiSnapshotsByExchange[exchange]
            let hadExistingRows = retainedSnapshot?.rows.isEmpty == false
            let mergedSnapshot = mergedKimchiFailureSnapshot(
                existing: retainedSnapshot,
                failedSymbols: batchSymbols,
                message: userFacingMessage
            )
            kimchiSnapshotsByExchange[exchange] = mergedSnapshot
            kimchiBasePhaseByExchange[exchange] = hadExistingRows ? .partialFailure : .hardFailure

            if hadExistingRows {
                AppLogger.debug(
                    .network,
                    "[KimchiStateDebug] action=retain_last_good_data reason=refresh_failure"
                )
            } else if let cachedPresentation = cachedKimchiPresentation(for: exchange),
                      hasReadyableRepresentativeRows(in: cachedPresentation) {
                kimchiBasePhaseByExchange[exchange] = .partialFailure
                AppLogger.debug(
                    .network,
                    "[KimchiStateDebug] action=retain_last_good_data reason=refresh_failure_cached_presentation"
                )
                applyKimchiPresentationIfChanged(
                    cachedPresentation,
                    generation: generation,
                    phase: "\(phase)_failure_retain_cache",
                    clearTransition: true,
                    reason: reason
                )
                return
            }

            let presentation = makeKimchiPresentationSnapshot(
                from: mergedSnapshot,
                exchange: exchange,
                comparableSymbols: fullComparableSymbols,
                symbolsHash: fullComparableSymbolsHash,
                phase: .settled
            )
            let publishStartedAt = Date()
            applyKimchiPresentationIfChanged(
                presentation,
                generation: generation,
                phase: "\(phase)_failure",
                clearTransition: true,
                reason: reason
            )
            let publishElapsedMs = Int(Date().timeIntervalSince(publishStartedAt) * 1000)
            AppLogger.debug(
                .network,
                "[KimchiSwitchPerf] exchange=\(exchange.rawValue) phase=publish_\(phase)_failure elapsedMs=\(publishElapsedMs)"
            )
            AppLogger.debug(
                .network,
                "[KimchiPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=\(phase)_failure message=\(error.localizedDescription)"
            )
        }
    }

    private func loadKimchiPremium(
        forceRefresh: Bool,
        reason: String,
        requestedSymbolsOverride: [String]?
    ) async {
        let domesticExchange = currentKimchiDomesticExchange

        if marketsByExchange[domesticExchange]?.isEmpty != false {
            await loadMarkets(for: domesticExchange, forceRefresh: false, reason: "\(reason)_kimchi_symbols")
        }

        let allComparableSymbols = await resolvedComparableKimchiSymbols(for: domesticExchange)
        guard !allComparableSymbols.isEmpty else {
            let userFacingMessage = "데이터를 불러오지 못했어요. 잠시 후 다시 시도해주세요."
            kimchiPremiumDebugMessage = BuildConfiguration.current == .debug
                ? "Kimchi supported symbols are empty for \(domesticExchange.rawValue)"
                : nil
            kimchiBasePhaseByExchange[domesticExchange] = .hardFailure
            refreshKimchiLoadState(reason: "kimchi_supported_symbols_empty")
            updateKimchiPremiumState(.failed(userFacingMessage))
            kimchiStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: kimchiStreamingStatus,
                context: .kimchi,
                warningMessage: userFacingMessage,
                loadState: kimchiLoadState
            )
            return
        }

        let fullComparableSymbolsHash = stableSymbolHash(from: allComparableSymbols)
        let representativeSymbols = representativeKimchiSymbols(
            for: domesticExchange,
            comparableSymbols: allComparableSymbols
        )

        if let requestedSymbolsOverride {
            let currentGeneration = kimchiPremiumRequestVersion
            guard currentGeneration > 0 else {
                return
            }
            await fetchKimchiBatchAndPatch(
                exchange: domesticExchange,
                generation: currentGeneration,
                requestedSymbols: requestedSymbolsOverride,
                representativeSymbols: representativeSymbols,
                fullComparableSymbols: allComparableSymbols,
                fullComparableSymbolsHash: fullComparableSymbolsHash,
                phase: "visible_rows",
                batchIndex: nil,
                reason: reason
            )
            return
        }

        let requestVersion = beginKimchiGeneration(for: domesticExchange)
        selectedDomesticKimchiExchange = domesticExchange
        let hasStableVisiblePresentation = hasVisibleRepresentativeKimchiData(for: domesticExchange)
            || hasReadyableRepresentativeRows(in: cachedKimchiPresentation(for: domesticExchange))
        if hasStableVisiblePresentation == false {
            applyKimchiShell(
                exchange: domesticExchange,
                comparableSymbols: allComparableSymbols,
                symbolsHash: fullComparableSymbolsHash,
                generation: requestVersion,
                reason: reason
            )
            applyCachedKimchiLayers(
                exchange: domesticExchange,
                generation: requestVersion,
                reason: reason
            )
        } else {
            if hasVisibleRepresentativeKimchiData(for: domesticExchange) == false,
               hasReadyableRepresentativeRows(in: cachedKimchiPresentation(for: domesticExchange)) {
                AppLogger.debug(
                    .network,
                    "[KimchiHeaderDebug] action=preserve_shell reason=exchange_switch_with_cache"
                )
                applyCachedKimchiPresentationIfAvailable(for: domesticExchange, reason: "\(reason)_cached_ready")
            }
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=keep_copy copy=\(kimchiHeaderState.copyState) reason=background_batch_only"
            )
            refreshKimchiHeaderState(reason: "background_batch_only")
        }

        await fetchKimchiBatchAndPatch(
            exchange: domesticExchange,
            generation: requestVersion,
            requestedSymbols: representativeSymbols,
            representativeSymbols: representativeSymbols,
            fullComparableSymbols: allComparableSymbols,
            fullComparableSymbolsHash: fullComparableSymbolsHash,
            phase: "representative_live",
            batchIndex: nil,
            reason: reason
        )

        guard shouldApplyKimchiGeneration(requestVersion, exchange: domesticExchange) else {
            return
        }

        let visibleSymbols = visibleKimchiSymbols(
            for: domesticExchange,
            comparableSymbols: allComparableSymbols,
            excluding: representativeSymbols
        )
        await fetchKimchiBatchAndPatch(
            exchange: domesticExchange,
            generation: requestVersion,
            requestedSymbols: visibleSymbols,
            representativeSymbols: representativeSymbols,
            fullComparableSymbols: allComparableSymbols,
            fullComparableSymbolsHash: fullComparableSymbolsHash,
            phase: "visible_rows",
            batchIndex: nil,
            reason: reason
        )

        guard shouldApplyKimchiGeneration(requestVersion, exchange: domesticExchange) else {
            return
        }

        let requestedSet = Set(representativeSymbols + visibleSymbols)
        let backgroundSymbols = allComparableSymbols.filter { requestedSet.contains($0) == false }
        for (index, batch) in backgroundSymbols.chunked(into: kimchiBackgroundBatchSize).enumerated() {
            guard shouldApplyKimchiGeneration(requestVersion, exchange: domesticExchange) else {
                return
            }
            if forceRefresh == false,
               let lastVisibleAt = lastVisibleKimchiRowAtByExchange[domesticExchange],
               Date().timeIntervalSince(lastVisibleAt) < kimchiRecentVisibleThrottleInterval {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 140 : 220))
            }
            await fetchKimchiBatchAndPatch(
                exchange: domesticExchange,
                generation: requestVersion,
                requestedSymbols: batch,
                representativeSymbols: representativeSymbols,
                fullComparableSymbols: allComparableSymbols,
                fullComparableSymbolsHash: fullComparableSymbolsHash,
                phase: "background_batch",
                batchIndex: index + 1,
                reason: reason
            )
        }

        guard shouldApplyKimchiGeneration(requestVersion, exchange: domesticExchange) else {
            return
        }

        fullyHydratedKimchiSymbolsHashByExchange[domesticExchange] = fullComparableSymbolsHash
        if let presentation = activeKimchiPresentationSnapshot, presentation.exchange == domesticExchange {
            cacheKimchiPresentation(presentation, tier: .full)
        }
        if let startedAt = kimchiSwitchStartedAtByExchange[domesticExchange] {
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            AppLogger.debug(
                .network,
                "[KimchiSwitch] completed exchange=\(domesticExchange.rawValue) hydratedRows=\(activeKimchiPresentationSnapshot?.rows.count ?? 0) elapsedMs=\(elapsedMs) reason=\(reason)"
            )
            kimchiSwitchStartedAtByExchange.removeValue(forKey: domesticExchange)
        }
        refreshKimchiLoadState(reason: reason)
    }

    func submitOrder() async {
        guard let session = authState.session else {
            presentLogin(for: .trade)
            return
        }

        guard capabilityResolver.supportsTrading(on: selectedExchange) else {
            showNotification("선택한 거래소는 주문을 지원하지 않아요.", type: .error)
            return
        }

        guard let coin = selectedCoin else {
            showNotification("시세 탭에서 코인을 먼저 선택해주세요", type: .error)
            return
        }

        guard hasTradeEnabledConnection else {
            showNotification("선택한 거래소에 주문 가능 권한 연결이 필요해요", type: .error)
            return
        }

        guard currentSupportedOrderTypes.contains(orderType) else {
            showNotification("서버에서 지원하는 주문 타입만 사용할 수 있어요", type: .error)
            return
        }

        let quantity = Double(orderQty.replacingOccurrences(of: ",", with: "")) ?? 0
        guard quantity > 0 else {
            showNotification("수량을 입력해주세요", type: .error)
            return
        }

        let price: Double?
        switch orderType {
        case .market:
            price = nil
        case .limit:
            let parsedPrice = Double(orderPrice.replacingOccurrences(of: ",", with: "")) ?? 0
            guard parsedPrice > 0 else {
                showNotification("주문 가격을 확인해주세요", type: .error)
                return
            }
            price = parsedPrice
        }

        if let minimumOrderAmount = tradingChanceState.value?.minimumOrderAmount {
            let notional = (price ?? currentPrice) * quantity
            guard notional >= minimumOrderAmount else {
                showNotification("최소 주문금액 \(PriceFormatter.formatInteger(minimumOrderAmount)) KRW 이상이어야 해요", type: .error)
                return
            }
        }

        isSubmittingOrder = true

        do {
            _ = try await runAuthenticatedRequest(session: session) { [tradingRepository, selectedExchange, orderSide, orderType] refreshedSession in
                try await tradingRepository.createOrder(
                    session: refreshedSession,
                    request: TradingOrderCreateRequest(
                        symbol: coin.symbol,
                        exchange: selectedExchange,
                        side: orderSide,
                        type: orderType,
                        price: price,
                        quantity: quantity
                    )
                )
            }

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            showNotification("\(coin.name) 주문 요청을 전송했어요", type: .success)
            orderQty = ""
            selectedOrderRatioPercent = nil
            await loadOrders(reason: "order_submit_refresh")
            await loadPortfolio()
        } catch {
            showNotification(error.localizedDescription, type: .error)
        }

        isSubmittingOrder = false
    }

    func setOrderSide(_ side: OrderSide, source: String = "unspecified") {
        let previousMode = orderSide
        AppLogger.debug(
            .lifecycle,
            "[OrderModeDebug] tap_received previousMode=\(previousMode.rawValue) newMode=\(side.rawValue) source=\(source)"
        )
        if source == "trade_toggle_button" {
            lastOrderModeTapAt = Date()
            lastOrderModeTappedSide = side
        } else if let lastOrderModeTapAt,
                  let lastOrderModeTappedSide,
                  Date().timeIntervalSince(lastOrderModeTapAt) < 0.75,
                  side != lastOrderModeTappedSide {
            AppLogger.debug(
                .lifecycle,
                "[OrderModeDebug] overwrite_detected source=\(source) expectedMode=\(lastOrderModeTappedSide.rawValue) overwrittenMode=\(side.rawValue)"
            )
        }
        guard previousMode != side else {
            AppLogger.debug(
                .lifecycle,
                "[OrderModeDebug] ui_applied selectedMode=\(orderSide.rawValue) source=\(source) changed=false"
            )
            return
        }
        orderSide = side
        selectedOrderRatioPercent = nil
        AppLogger.debug(
            .lifecycle,
            "[OrderModeDebug] ui_applied selectedMode=\(orderSide.rawValue) source=\(source) changed=true"
        )
    }

    func setOrderType(_ type: OrderType) {
        guard orderType != type else { return }
        orderType = type
        selectedOrderRatioPercent = nil
    }

    func updateOrderPriceManually(_ price: String) {
        guard orderPrice != price else { return }
        orderPrice = price
        selectedOrderRatioPercent = nil
    }

    func updateOrderQuantityManually(_ quantity: String) {
        guard orderQty != quantity else { return }
        orderQty = quantity
        selectedOrderRatioPercent = nil
    }

    func isOrderRatioButtonEnabled(_ percent: Double) -> Bool {
        guard percent > 0,
              let chance = tradingChanceState.value else {
            return false
        }

        switch orderSide {
        case .buy:
            return chance.bidBalance > 0 && resolvedOrderPriceForRatio() > 0
        case .sell:
            return chance.askBalance > 0
        }
    }

    func applyPercent(_ percent: Double) {
        AppLogger.debug(
            .lifecycle,
            "[OrderRatio] ratio_button_tapped percent=\(Int(percent)) exchange=\(selectedExchange.rawValue) side=\(orderSide.rawValue)"
        )

        guard selectedCoin != nil else { return }
        guard let chance = tradingChanceState.value else {
            selectedOrderRatioPercent = nil
            showNotification("주문 가능 정보가 없어 비율 수량을 계산할 수 없어요.", type: .error)
            return
        }

        let quantity: Double
        let price = resolvedOrderPriceForRatio()
        if orderSide == .buy {
            guard price > 0 else {
                selectedOrderRatioPercent = nil
                showNotification("주문 가격을 먼저 확인해주세요.", type: .error)
                return
            }
            let availableQuoteAmount = chance.bidBalance
            guard availableQuoteAmount > 0 else {
                selectedOrderRatioPercent = nil
                showNotification("매수 가능 KRW가 확인되지 않았어요.", type: .error)
                return
            }
            quantity = (availableQuoteAmount * percent / 100.0) / price
        } else {
            let availableBaseQuantity = chance.askBalance
            guard availableBaseQuantity > 0 else {
                selectedOrderRatioPercent = nil
                showNotification("매도 가능 수량이 확인되지 않았어요.", type: .error)
                return
            }
            quantity = availableBaseQuantity * percent / 100.0
        }

        orderQty = formattedOrderQuantity(quantity, precision: chance.quantityPrecision)
        selectedOrderRatioPercent = percent
        AppLogger.debug(
            .lifecycle,
            "[OrderRatio] ratio_applied_success percent=\(Int(percent)) exchange=\(selectedExchange.rawValue) side=\(orderSide.rawValue) price=\(price) quantity=\(orderQty)"
        )
    }

    func adjustPrice(up: Bool) {
        let baseValue = Double(orderPrice.replacingOccurrences(of: ",", with: "")) ?? currentPrice
        let priceUnit = tradingChanceState.value?.priceUnit ?? max(baseValue * 0.001, 1)
        let newPrice = up ? baseValue + priceUnit : max(baseValue - priceUnit, 0)
        orderPrice = PriceFormatter.formatPrice(newPrice)
        selectedOrderRatioPercent = nil
    }

    private func resolvedOrderPriceForRatio() -> Double {
        switch orderType {
        case .market:
            return currentPrice
        case .limit:
            return Double(orderPrice.replacingOccurrences(of: ",", with: "")) ?? 0
        }
    }

    private func formattedOrderQuantity(_ quantity: Double, precision: Int?) -> String {
        let boundedPrecision = min(max(precision ?? 6, 0), 8)
        return String(format: "%.\(boundedPrecision)f", quantity)
    }

    func showNotification(_ message: String, type: NotifType) {
        notification = (msg: message, type: type)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.notification = nil
        }
    }

    private func connectPublicMarketFeed(reason: String) {
        guard requiresPublicStreaming else {
            AppLogger.debug(.websocket, "connectPublicMarketFeed skipped -> reason=\(reason) route=\(activeTab.rawValue) mode=snapshot")
            updatePublicSubscriptions(reason: reason)
            return
        }

        AppLogger.debug(.websocket, "connectPublicMarketFeed -> reason=\(reason)")
        updatePublicSubscriptions(reason: reason)
    }

    private func connectPrivateTradingFeedIfNeeded(reason: String) {
        guard authState.session != nil else {
            lastAppliedPrivateSubscriptions = nil
            privateWebSocketService.disconnect()
            return
        }

        AppLogger.debug(.websocket, "connectPrivateTradingFeedIfNeeded -> reason=\(reason)")
        updatePrivateSubscriptions(reason: reason)
    }

    private func bindPublicWebSocket() {
        publicWebSocketService.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.publicWebSocketState = state
                switch state {
                case .connecting:
                    AppLogger.debug(.websocket, "[PublicWS] connect start route=\(self.activeTab.rawValue) exchange=\(self.selectedExchange.rawValue)")
                case .connected:
                    AppLogger.debug(.websocket, "[PublicWS] connect success route=\(self.activeTab.rawValue) exchange=\(self.selectedExchange.rawValue)")
                case .failed(let message):
                    AppLogger.debug(.websocket, "[PublicWS] connect failure route=\(self.activeTab.rawValue) exchange=\(self.selectedExchange.rawValue) message=\(message)")
                case .disconnected:
                    break
                }
                self.updatePublicPollingIfNeeded()
                self.refreshMarketLoadState(reason: "public_ws_state_changed")
                self.refreshKimchiLoadState(reason: "public_ws_state_changed")
                self.refreshPublicStatusViewStates()
            }
        }

        publicWebSocketService.onTickerReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                self.applyTickerUpdate(payload)
                if self.activeTab == .chart,
                   self.selectedCoin?.symbol == payload.symbol,
                   self.exchange.rawValue == payload.exchange {
                    self.refreshChartSummaryStates(reason: "ticker_stream_update")
                    self.applyLiveChartPriceUpdate(
                        price: payload.ticker.price,
                        quantity: 0,
                        timestamp: payload.ticker.timestamp ?? Date()
                    )
                }
            }
        }

        publicWebSocketService.onOrderbookReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard self.selectedCoin?.symbol == payload.symbol, self.exchange.rawValue == payload.exchange else { return }
                let key = self.chartResourceKey(exchange: self.exchange, symbol: payload.symbol)
                let entry = OrderbookCacheEntry(
                    key: key,
                    orderbook: payload.orderbook,
                    meta: ResponseMeta(
                        fetchedAt: payload.orderbook.timestamp,
                        isStale: payload.orderbook.isStale,
                        warningMessage: nil,
                        partialFailureMessage: nil
                    ),
                    fetchedAt: payload.orderbook.timestamp ?? Date()
                )
                self.orderbookCacheByKey[key] = entry
                self.lastSuccessfulOrderBook[key] = entry
                self.updateOrderbookState(
                    payload.orderbook.asks.isEmpty && payload.orderbook.bids.isEmpty
                        ? .empty
                        : .loaded(payload.orderbook)
                )
                self.refreshPublicStatusViewStates()
            }
        }

        publicWebSocketService.onTradesReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard self.selectedCoin?.symbol == payload.symbol, self.exchange.rawValue == payload.exchange else { return }
                let key = self.chartResourceKey(exchange: self.exchange, symbol: payload.symbol)
                let entry = TradesCacheEntry(
                    key: key,
                    trades: payload.trades,
                    meta: ResponseMeta(
                        fetchedAt: payload.trades.first?.executedDate,
                        isStale: false,
                        warningMessage: nil,
                        partialFailureMessage: nil
                    ),
                    fetchedAt: payload.trades.first?.executedDate ?? Date()
                )
                self.tradesCacheByKey[key] = entry
                if payload.trades.isEmpty == false {
                    self.lastSuccessfulTrades[key] = entry
                }
                self.updateTradesState(payload.trades.isEmpty ? .empty : .loaded(payload.trades))
                if self.activeTab == .chart {
                    self.applyLiveChartTrades(payload.trades)
                }
                self.refreshPublicStatusViewStates()
            }
        }

        publicWebSocketService.onCandlesReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard self.selectedCoin?.symbol == payload.symbol, self.exchange.rawValue == payload.exchange else { return }
                let mappedInterval = self.resolvedChartInterval(
                    requestedInterval: self.chartPeriod,
                    symbol: payload.symbol,
                    exchange: self.exchange
                )
                guard mappedInterval == payload.interval.lowercased() else { return }
                self.mergeCandleUpdate(payload)
                self.refreshPublicStatusViewStates()
            }
        }
    }

    private func bindPrivateWebSocket() {
        privateWebSocketService.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.privateWebSocketState = state
                if case .failed(let message) = state {
                    AppLogger.debug(
                        .websocket,
                        "[PrivateWS] websocket_handshake_failed exchange=\(self.selectedExchange.rawValue) route=\(self.activeTab.rawValue) message=\(message)"
                    )
                }
                self.updatePrivatePollingIfNeeded()
                self.refreshPrivateStatusViewStates()
            }
        }

        privateWebSocketService.onOrderReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard payload.exchange == self.selectedExchange else { return }
                self.applyOrderStreamUpdate(payload.order)
                self.refreshPrivateStatusViewStates()
            }
        }

        privateWebSocketService.onFillReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard payload.exchange == self.selectedExchange else { return }
                self.applyFillStreamUpdate(payload.fill)
                self.refreshPrivateStatusViewStates()
            }
        }
    }

    private func bootstrapPublicData(reason: String) async {
        if marketPresentationSnapshotsByExchange[selectedExchange] == nil {
            beginMarketTransition(to: selectedExchange, from: activeMarketPresentationSnapshot?.exchange, reason: reason)
        }
        async let marketTask = loadMarkets(for: selectedExchange, forceRefresh: true, reason: "\(reason)_bootstrap_markets")
        async let tickerTask = loadTickers(for: selectedExchange, forceRefresh: true, reason: "\(reason)_bootstrap_tickers")
        _ = await (marketTask, tickerTask)
        ensureSelectedCoinForCurrentExchange()
        refreshMarketStateForSelectedExchange(reason: "\(reason)_bootstrap_refresh")
    }

    private func loadMarkets(for exchange: Exchange, forceRefresh: Bool = false, reason: String) async {
        let requestContext = makeMarketRequestContext(for: exchange)
        if !forceRefresh,
           let lastFetchedAt = lastMarketCatalogFetchedAtByExchange[exchange],
           Date().timeIntervalSince(lastFetchedAt) < marketCatalogStaleInterval,
           marketsByExchange[exchange]?.isEmpty == false {
            AppLogger.debug(.network, "fetchMarkets skipped -> exchange=\(exchange.rawValue) reason=\(reason)")
            return
        }

        if let existingTask = marketCatalogFetchTasks[exchange] {
            AppLogger.debug(.network, "fetchMarkets deduped -> exchange=\(exchange.rawValue) reason=\(reason)")
            do {
                _ = try await existingTask.value
            } catch {}
            return
        }

        AppLogger.debug(.network, "fetchMarkets start -> exchange=\(exchange.rawValue) reason=\(reason)")
        AppLogger.debug(.network, "[MarketSnapshot] request start kind=markets exchange=\(exchange.rawValue) reason=\(reason)")
        let requestTask = Task {
            try await marketRepository.fetchMarkets(exchange: exchange)
        }
        marketCatalogFetchTasks[exchange] = requestTask

        do {
            let catalogSnapshot = try await requestTask.value
            marketCatalogFetchTasks[exchange] = nil
            lastMarketCatalogFetchedAtByExchange[exchange] = Date()
            marketCatalogResponseCountsByExchange[exchange] = catalogSnapshot.markets.count
            marketCatalogMetaByExchange[exchange] = catalogSnapshot.meta
            marketsByExchange[exchange] = catalogSnapshot.markets
            supportedIntervalsByExchangeAndMarketIdentity[exchange] = catalogSupportedIntervalsByMarketIdentity(
                from: catalogSnapshot
            )
            filteredMarketIdentitiesByExchange[exchange] = resolvedMarketIdentities(
                exchange: exchange,
                symbols: catalogSnapshot.filteredSymbols
            )
            promoteResolvedMarketIdentityState(for: exchange)
            marketSnapshotCacheStore?.saveCatalogSnapshot(catalogSnapshot)
            if let partialFailureMessage = catalogSnapshot.meta.partialFailureMessage {
                AppLogger.debug(.network, "[MarketSnapshot] partial symbol failure exchange=\(exchange.rawValue) message=\(partialFailureMessage)")
            }
            AppLogger.debug(
                .network,
                "[MarketSnapshot] received item count exchange=\(exchange.rawValue) kind=markets count=\(catalogSnapshot.markets.count)"
            )
            AppLogger.debug(
                .network,
                "[MarketSnapshot] filtered unsupported or unlisted exchange=\(exchange.rawValue) count=\(catalogSnapshot.filteredSymbols.count)"
            )
            AppLogger.debug(.lifecycle, "[MarketScreen] server universe count exchange=\(exchange.rawValue) count=\(catalogSnapshot.markets.count)")
            ensureSelectedCoinIfPossible(for: exchange)
            stageAndSwapMarketPresentationIfPossible(
                for: exchange,
                requestContext: requestContext,
                reason: "\(reason)_markets_loaded"
            )
            AppLogger.debug(.network, "[MarketSnapshot] request success kind=markets exchange=\(exchange.rawValue) count=\(catalogSnapshot.markets.count)")
            AppLogger.debug(.network, "[MarketScreen] response items count=\(catalogSnapshot.markets.count) exchange=\(exchange.rawValue)")
            AppLogger.debug(.network, "fetchMarkets end -> exchange=\(exchange.rawValue) count=\(catalogSnapshot.markets.count) reason=\(reason)")
        } catch {
            marketCatalogFetchTasks[exchange] = nil
            lastMarketCatalogFetchedAtByExchange[exchange] = Date()
            AppLogger.debug(.network, "[MarketSnapshot] request failure kind=markets exchange=\(exchange.rawValue) message=\(error.localizedDescription)")
            AppLogger.debug(.network, "Failed market catalog for \(exchange.rawValue): \(error.localizedDescription)")
            if selectedExchange == exchange, marketState.value == nil {
                refreshMarketStateForSelectedExchange()
            }
        }
    }

    private func loadTickers(for exchange: Exchange, forceRefresh: Bool = false, reason: String) async {
        let requestContext = makeMarketRequestContext(for: exchange)
        if !forceRefresh,
           let lastFetchedAt = lastTickerFetchedAtByExchange[exchange],
           Date().timeIntervalSince(lastFetchedAt) < tickerStaleInterval,
           hasAnyTickerData(for: exchange) {
            AppLogger.debug(.network, "fetchTickers skipped -> exchange=\(exchange.rawValue) reason=\(reason)")
            return
        }

        if let existingTask = tickerFetchTasks[exchange] {
            AppLogger.debug(.network, "fetchTickers deduped -> exchange=\(exchange.rawValue) reason=\(reason)")
            do {
                _ = try await existingTask.value
            } catch {}
            return
        }

        AppLogger.debug(.network, "fetchTickers start -> exchange=\(exchange.rawValue) reason=\(reason)")
        AppLogger.debug(.network, "[MarketSnapshot] request start kind=tickers exchange=\(exchange.rawValue) reason=\(reason)")
        AppLogger.debug(
            .network,
            "[MarketPipeline] exchange=\(exchange.rawValue) generation=\(requestContext.generation) phase=base_refresh_start symbols=\(resolvedSymbols(for: exchange).count)"
        )
        let requestStartedAt = Date()
        let requestTask = Task {
            try await marketRepository.fetchTickers(exchange: exchange)
        }
        tickerFetchTasks[exchange] = requestTask

        do {
            let tickerSnapshot = try await requestTask.value
            tickerFetchTasks[exchange] = nil
            lastTickerFetchedAtByExchange[exchange] = Date()
            marketTickerResponseCountsByExchange[exchange] = tickerSnapshot.tickers.count
            marketTickerMetaByExchange[exchange] = tickerSnapshot.meta
            hasLoadedTickerSnapshotByExchange[exchange] = true
            tickerSnapshotCoinsByExchange[exchange] = tickerSnapshot.coins
            filteredTickerIdentitiesByExchange[exchange] = resolvedMarketIdentities(
                exchange: exchange,
                symbols: tickerSnapshot.filteredSymbols
            )
            promoteResolvedMarketIdentityState(for: exchange)
            marketSnapshotCacheStore?.saveTickerSnapshot(tickerSnapshot)
            for (symbol, ticker) in tickerSnapshot.tickers {
                if let responseSourceExchange = ticker.sourceExchange, responseSourceExchange != exchange {
                    AppLogger.debug(
                        .network,
                        "[MarketSnapshot] sourceExchange mismatch ignored \(marketLogFields(exchange: exchange, symbol: symbol)) responseSourceExchange=\(responseSourceExchange.rawValue)"
                    )
                    continue
                }
                mergeTicker(symbol: symbol, exchange: exchange.rawValue, incoming: ticker, seedHistoryIfNeeded: true)
                seedSparklineSnapshotIfAvailable(
                    marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol),
                    ticker: ticker,
                    source: .tickerSnapshot,
                    fetchedAt: ticker.timestamp ?? tickerSnapshot.meta.fetchedAt ?? Date()
                )
            }
            if let partialFailureMessage = tickerSnapshot.meta.partialFailureMessage {
                AppLogger.debug(.network, "[MarketSnapshot] partial symbol failure exchange=\(exchange.rawValue) message=\(partialFailureMessage)")
            }
            AppLogger.debug(
                .network,
                "[MarketSnapshot] received item count exchange=\(exchange.rawValue) kind=tickers count=\(tickerSnapshot.tickers.count)"
            )
            AppLogger.debug(
                .network,
                "[MarketSnapshot] filtered unsupported or unlisted exchange=\(exchange.rawValue) count=\(tickerSnapshot.filteredSymbols.count)"
            )

            if exchange == .coinone {
                let missingSymbols = coinoneMissingTickerSymbols(parsedSymbols: Set(tickerSnapshot.tickers.keys))
                if !missingSymbols.isEmpty {
                    AppLogger.debug(.network, "Coinone ticker missing symbols -> \(missingSymbols.joined(separator: ","))")
                    AppLogger.debug(.network, "[MarketSnapshot] partial symbol failure exchange=\(exchange.rawValue) symbols=\(missingSymbols.joined(separator: ","))")
                }
            }

            stageAndSwapMarketPresentationIfPossible(
                for: exchange,
                requestContext: requestContext,
                reason: "\(reason)_tickers_loaded"
            )
            AppLogger.debug(
                .network,
                "[MarketPipeline] exchange=\(exchange.rawValue) generation=\(requestContext.generation) phase=base_refresh_success rows=\(tickerSnapshot.tickers.count) elapsedMs=\(Int(Date().timeIntervalSince(requestStartedAt) * 1000))"
            )
            AppLogger.debug(.network, "[MarketSnapshot] request success kind=tickers exchange=\(exchange.rawValue) count=\(tickerSnapshot.tickers.count)")
            AppLogger.debug(.network, "[MarketScreen] response items count=\(tickerSnapshot.tickers.count) exchange=\(exchange.rawValue)")
            AppLogger.debug(.network, "fetchTickers end -> exchange=\(exchange.rawValue) count=\(tickerSnapshot.tickers.count) reason=\(reason)")
        } catch {
            tickerFetchTasks[exchange] = nil
            lastTickerFetchedAtByExchange[exchange] = Date()
            AppLogger.debug(.network, "[MarketSnapshot] request failure kind=tickers exchange=\(exchange.rawValue) message=\(error.localizedDescription)")
            AppLogger.debug(.network, "Failed public ticker snapshot for \(exchange.rawValue): \(error.localizedDescription)")
            if selectedExchange == exchange {
                refreshMarketStateForSelectedExchange()
            }
        }
    }

    private func refreshDataForCurrentRoute(forceRefresh: Bool, reason: String) async {
        updateAuthGate()

        switch activeTab {
        case .market:
            if activeMarketPresentationSnapshot?.exchange != selectedExchange || activeMarketPresentationSnapshot == nil {
                beginMarketTransition(to: selectedExchange, from: activeMarketPresentationSnapshot?.exchange, reason: reason)
            }
            async let marketTask = loadMarkets(for: selectedExchange, forceRefresh: forceRefresh, reason: "\(reason)_market_markets")
            async let tickerTask = loadTickers(for: selectedExchange, forceRefresh: forceRefresh, reason: "\(reason)_market_tickers")
            _ = await (marketTask, tickerTask)
            refreshMarketStateForSelectedExchange(reason: "\(reason)_market_refresh")
        case .kimchi:
            if activeKimchiPresentationSnapshot?.exchange != currentKimchiDomesticExchange || activeKimchiPresentationSnapshot == nil {
                beginKimchiTransition(to: currentKimchiDomesticExchange, reason: reason)
            }
            await loadKimchiPremium(forceRefresh: forceRefresh, reason: "\(reason)_kimchi")
        case .chart:
            await loadMarkets(for: selectedExchange, forceRefresh: false, reason: "\(reason)_chart_markets")
            ensureSelectedCoinIfPossible(for: selectedExchange)
            if forceRefresh {
                await loadTickers(for: selectedExchange, forceRefresh: true, reason: "\(reason)_chart_tickers")
            }
            await loadChartData(forceRefresh: forceRefresh, reason: "\(reason)_chart")
        case .portfolio:
            await loadExchangeConnections(reason: "\(reason)_portfolio_connections")
            await loadPortfolio(reason: "\(reason)_portfolio")
        case .trade:
            await loadMarkets(for: selectedExchange, forceRefresh: false, reason: "\(reason)_trade_markets")
            ensureSelectedCoinIfPossible(for: selectedExchange)
            await loadExchangeConnections(reason: "\(reason)_trade_connections")
            await loadOrders(reason: "\(reason)_trade_orders")
            if portfolioState.value == nil || forceRefresh {
                await loadPortfolio(reason: "\(reason)_trade_portfolio")
            }
        }
    }

    private func beginRouteRefresh(reason: String) -> RouteRefreshContext {
        routeRefreshGeneration += 1
        let context = RouteRefreshContext(
            tab: activeTab,
            exchange: selectedExchange,
            isAuthenticated: isAuthenticated,
            generation: routeRefreshGeneration
        )
        AppLogger.debug(
            .route,
            "[RouteRefresh] begin reason=\(reason) tab=\(context.tab.rawValue) exchange=\(context.exchange.rawValue) auth=\(context.isAuthenticated) generation=\(context.generation)"
        )
        return context
    }

    private func shouldRunRouteRefresh(_ context: RouteRefreshContext, reason: String) -> Bool {
        guard context.generation == routeRefreshGeneration,
              context.tab == activeTab,
              context.exchange == selectedExchange,
              context.isAuthenticated == isAuthenticated else {
            AppLogger.debug(
                .route,
                "[RouteRefresh] stale refresh ignored reason=\(reason) tab=\(context.tab.rawValue) exchange=\(context.exchange.rawValue) auth=\(context.isAuthenticated) generation=\(context.generation) currentTab=\(activeTab.rawValue) currentExchange=\(selectedExchange.rawValue) currentAuth=\(isAuthenticated) currentGeneration=\(routeRefreshGeneration)"
            )
            return false
        }
        return true
    }

    private func runRouteRefreshIfCurrent(_ context: RouteRefreshContext, forceRefresh: Bool, reason: String) async {
        guard shouldRunRouteRefresh(context, reason: reason) else { return }
        await refreshDataForCurrentRoute(forceRefresh: forceRefresh, reason: reason)
    }

    private func updateAuthGate() {
        if let feature = activeTab.protectedFeature, !isAuthenticated {
            activeAuthGate = feature
        } else {
            activeAuthGate = nil
        }
    }

    private func updatePublicSubscriptions(reason: String = "unspecified") {
        let subscriptions = desiredPublicSubscriptions
        let isConnectionStable = publicWebSocketState == .connected || publicWebSocketState == .connecting
        if lastAppliedPublicSubscriptions == subscriptions, (subscriptions.isEmpty || isConnectionStable) {
            AppLogger.debug(.websocket, "Public subscriptions skip -> reason=\(reason) route=\(activeTab.rawValue) total=\(subscriptions.count)")
            return
        }

        lastAppliedPublicSubscriptions = subscriptions
        AppLogger.debug(.websocket, "Public subscriptions request -> reason=\(reason) route=\(activeTab.rawValue) total=\(subscriptions.count)")
        if !subscriptions.isEmpty, publicWebSocketState == .disconnected {
            publicWebSocketState = .connecting
        }
        publicWebSocketService.updateSubscriptions(subscriptions)
    }

    private func updatePrivateSubscriptions(reason: String = "unspecified") {
        guard let session = authState.session else {
            lastAppliedPrivateSubscriptions = nil
            privateWebSocketService.disconnect()
            return
        }

        guard activeTab == .trade || activeTab == .portfolio else {
            if lastAppliedPrivateSubscriptions == [] {
                AppLogger.debug(.websocket, "Private subscriptions skip -> reason=\(reason) route=\(activeTab.rawValue) total=0")
                return
            }
            lastAppliedPrivateSubscriptions = []
            privateWebSocketService.updateSubscriptions([])
            return
        }

        var subscriptions = Set<PrivateTradingSubscription>()

        if activeTab == .trade, selectedExchange.supportsOrder {
            subscriptions.insert(
                PrivateTradingSubscription(
                    channel: .orders,
                    exchange: selectedExchange.rawValue,
                    symbol: selectedCoin?.symbol
                )
            )
            subscriptions.insert(
                PrivateTradingSubscription(
                    channel: .fills,
                    exchange: selectedExchange.rawValue,
                    symbol: selectedCoin?.symbol
                )
            )
        }

        if (activeTab == .trade || activeTab == .portfolio), selectedExchange.supportsAsset {
            subscriptions.insert(
                PrivateTradingSubscription(
                    channel: .portfolio,
                    exchange: selectedExchange.rawValue,
                    symbol: nil
                )
            )
        }

        let isConnectionStable = privateWebSocketState == .connected || privateWebSocketState == .connecting
        if lastAppliedPrivateSubscriptions == subscriptions, isConnectionStable {
            AppLogger.debug(.websocket, "Private subscriptions skip -> reason=\(reason) route=\(activeTab.rawValue) total=\(subscriptions.count)")
            return
        }
        if lastAppliedPrivateSubscriptions == subscriptions,
           case .failed = privateWebSocketState {
            AppLogger.debug(
                .websocket,
                "Private subscriptions skip -> reason=\(reason) route=\(activeTab.rawValue) total=\(subscriptions.count) state=failed_reconnect_backoff"
            )
            return
        }

        lastAppliedPrivateSubscriptions = subscriptions
        privateWebSocketService.connect(accessToken: session.accessToken)
        privateWebSocketService.updateSubscriptions(subscriptions)
    }

    private func updatePublicPollingIfNeeded() {
        publicPollingTask?.cancel()

        let shouldUsePolling = currentPublicStreamingStatus == .pollingFallback || activeTab == .kimchi

        guard shouldUsePolling else {
            if isPublicPollingFallbackActive {
                AppLogger.debug(.network, "Public polling fallback -> inactive")
            }
            isPublicPollingFallbackActive = false
            return
        }

        if !isPublicPollingFallbackActive {
            AppLogger.debug(
                .network,
                "Public polling fallback -> active (state=\(describe(publicWebSocketState)), exchange=\(selectedExchange.rawValue), route=\(activeTab.rawValue))"
            )
            AppLogger.debug(
                .network,
                activeTab == .kimchi
                    ? "[KimchiPolling] fallback polling started exchange=\(currentKimchiDomesticExchange.rawValue)"
                    : "[MarketPolling] fallback polling started exchange=\(selectedExchange.rawValue)"
            )
        }
        isPublicPollingFallbackActive = true

        publicPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let intervalNanoseconds: UInt64 = self?.activeTab == .kimchi ? 8_000_000_000 : 5_000_000_000
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                await self?.pollPublicFallback()
            }
        }
    }

    private func updatePrivatePollingIfNeeded() {
        privatePollingTask?.cancel()

        guard isAuthenticated, currentPrivateStreamingStatus == .pollingFallback else {
            if isPrivatePollingFallbackActive {
                AppLogger.debug(.network, "Private polling fallback -> inactive")
                AppLogger.debug(
                    .network,
                    "[PrivatePolling] polling_fallback_stopped exchange=\(selectedExchange.rawValue) route=\(activeTab.rawValue) state=\(describe(privateWebSocketState))"
                )
            }
            isPrivatePollingFallbackActive = false
            return
        }

        if !isPrivatePollingFallbackActive {
            AppLogger.debug(
                .network,
                "Private polling fallback -> active (state=\(describe(privateWebSocketState)), exchange=\(selectedExchange.rawValue), route=\(activeTab.rawValue))"
            )
            AppLogger.debug(
                .network,
                "[PrivatePolling] polling_fallback_started exchange=\(selectedExchange.rawValue) route=\(activeTab.rawValue) state=\(describe(privateWebSocketState))"
            )
        }
        isPrivatePollingFallbackActive = true

        privatePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                await self?.pollPrivateFallback()
            }
        }
    }

    private func pollPublicFallback() async {
        switch activeTab {
        case .market:
            await loadTickers(for: selectedExchange, reason: "polling_fallback_market")
        case .chart:
            await loadTickers(for: selectedExchange, reason: "polling_fallback_chart")
            await loadChartData(reason: "polling_fallback_chart")
        case .kimchi:
            await loadKimchiPremium(reason: "polling_fallback_kimchi")
        case .trade, .portfolio:
            break
        }
    }

    private func pollPrivateFallback() async {
        guard isAuthenticated else { return }

        switch activeTab {
        case .portfolio:
            if !hasResolvedExchangeConnectionsState || isExchangeConnectionsPresented {
                await loadExchangeConnections(reason: "polling_fallback_portfolio")
            }
            await loadPortfolio(reason: "polling_fallback_portfolio")
        case .trade:
            if !hasResolvedExchangeConnectionsState || isExchangeConnectionsPresented {
                await loadExchangeConnections(reason: "polling_fallback_trade")
            }
            await loadOrders(reason: "polling_fallback_trade")
        case .market, .chart, .kimchi:
            break
        }
    }

    private func applyTickerUpdate(_ payload: TickerStreamPayload) {
        guard shouldApplyVisibleTickerUpdate(for: payload.exchange) else {
            if selectedExchange.rawValue != payload.exchange {
                AppLogger.debug(
                    .network,
                    "[MarketScreen] visible ticker patch skipped exchange=\(payload.exchange) route=\(activeTab.rawValue) generation=\(marketPresentationGeneration) reason=route_or_exchange_mismatch source=websocket"
                )
            }
            mergeTicker(symbol: payload.symbol, exchange: payload.exchange, incoming: payload.ticker)
            return
        }
        if let exchange = Exchange(rawValue: payload.exchange), firstTickerStreamEventsByExchange.insert(exchange).inserted {
            let marketIdentity = resolvedMarketIdentity(exchange: exchange, symbol: payload.symbol)
            AppLogger.debug(.websocket, "[PublicWS] first stream event received \(marketIdentity.logFields)")
        }
        mergeTicker(symbol: payload.symbol, exchange: payload.exchange, incoming: payload.ticker)
        let affectedRowCount: Int
        let marketLogFields: String
        if let exchange = Exchange(rawValue: payload.exchange) {
            let marketIdentity = resolvedMarketIdentity(exchange: exchange, symbol: payload.symbol)
            marketLogFields = marketIdentity.logFields
            affectedRowCount = applyTargetedMarketRowUpdate(
                marketIdentity: marketIdentity,
                reason: "ticker_stream_update"
            )
        } else {
            marketLogFields = "exchange=\(payload.exchange) marketId=- symbol=\(payload.symbol)"
            affectedRowCount = 0
        }
        AppLogger.debug(
            .websocket,
            "[MarketLive] merge applied \(marketLogFields) rows=\(affectedRowCount)"
        )
        if affectedRowCount == 0 {
            refreshMarketStateForSelectedExchange(reason: "ticker_stream_update_fallback")
        }
        refreshMarketLoadState(reason: "ticker_stream_update")
        refreshPublicStatusViewStates()
    }

    @discardableResult
    private func applyTargetedMarketRowUpdate(
        marketIdentity: MarketIdentity,
        reason: String
    ) -> Int {
        let exchange = marketIdentity.exchange
        guard let snapshot = marketPresentationSnapshotsByExchange[exchange] else {
            return 0
        }
        guard snapshot.rows.contains(where: { $0.marketIdentity == marketIdentity }) else {
            return 0
        }

        guard let tickerDisplayPatch = makeTickerDisplayPatch(
            marketIdentity: marketIdentity,
            exchange: exchange,
            generation: snapshot.generation,
            reason: reason
        ) else {
            return 0
        }

        let didEnqueue = enqueueMarketRowPatch(
            marketIdentity: marketIdentity,
            exchange: exchange,
            generation: snapshot.generation,
            sparklinePatch: nil,
            symbolImagePatch: nil,
            tickerDisplayPatch: tickerDisplayPatch,
            rebuildReason: nil
        )
        if didEnqueue {
            AppLogger.debug(
                .lifecycle,
                "[MarketRows] reconfigure_queued count=1 \(marketIdentity.logFields) reason=\(reason) scope=\(reason == "ticker_flash_reset" ? "price_subview_flash" : "ticker_display_patch")"
            )
        }
        return didEnqueue ? 1 : 0
    }

    private func mergeTicker(symbol: String, exchange: String, incoming: TickerData, seedHistoryIfNeeded: Bool = false) {
        guard let parsedExchange = Exchange(rawValue: exchange) else {
            return
        }
        let marketIdentity = resolvedMarketIdentity(exchange: parsedExchange, symbol: symbol)
        let previous = pricesByMarketIdentity[marketIdentity]
        var ticker = incoming
        if ticker.sourceExchange == nil {
            ticker.sourceExchange = parsedExchange
        }

        let previousPrice = previous?.price ?? incoming.price
        let previousSparkline = previous?.sparkline ?? []
        var sparkline = incoming.sparkline.count >= 2 ? incoming.sparkline : previousSparkline
        if !seedHistoryIfNeeded, sparkline.isEmpty, let previous, previous.price != incoming.price {
            sparkline = [previous.price, incoming.price]
        } else if !seedHistoryIfNeeded, previous?.price != incoming.price, sparkline.isEmpty == false {
            sparkline.append(incoming.price)
        } else if !seedHistoryIfNeeded, sparkline.count == 1 {
            sparkline.append(incoming.price)
        }
        if sparkline.count > 20 {
            sparkline = Array(sparkline.suffix(20))
        }
        let mergedPointsCount = incoming.sparklinePointCount ?? sparkline.count

        ticker.sparkline = sparkline
        ticker.sparklinePointCount = mergedPointsCount
        ticker.hasServerSparkline = incoming.hasServerSparkline || previous?.hasServerSparkline == true
        if seedHistoryIfNeeded {
            ticker.flash = nil
        } else {
            ticker.flash = incoming.price > previousPrice ? .up : (incoming.price < previousPrice ? .down : nil)
        }

        pricesByMarketIdentity[marketIdentity] = ticker
        if ticker.sparkline.count >= 2 {
            seedSparklineSnapshotIfAvailable(
                marketIdentity: marketIdentity,
                ticker: ticker,
                source: ticker.delivery == .live ? .stream : .tickerSnapshot,
                fetchedAt: ticker.timestamp ?? Date()
            )
        }
        AppLogger.debug(
            .websocket,
            "[TrendChart] sparkline points merged count \(marketIdentity.logFields) count=\(mergedPointsCount)"
        )
        AppLogger.debug(
            .websocket,
            "[TrendChart] sparkline pointCount=\(mergedPointsCount) displayedPoints=\(sparkline.count) usable=\(MarketSparklineRenderPolicy.hasRenderableGraph(points: sparkline, pointCount: mergedPointsCount)) hydrated=\(MarketSparklineRenderPolicy.hasHydratedGraph(points: sparkline, pointCount: mergedPointsCount)) staleSnapshotReused=\(incoming.sparkline.count < 2 && previousSparkline.count >= 2) \(marketIdentity.logFields)"
        )

        if ticker.sparkline.count >= 2 {
            if seedHistoryIfNeeded {
                AppLogger.debug(.lifecycle, "[TrendChart] snapshot applied \(marketIdentity.logFields)")
            } else {
                AppLogger.debug(
                    .lifecycle,
                    "[TrendChart] stream update applied \(marketIdentity.logFields) points=\(ticker.sparkline.count)"
                )
            }
        }

        if let selectedCoin,
           selectedExchange == parsedExchange,
           selectedCoin.marketIdentity(exchange: parsedExchange) == marketIdentity {
            rememberOrderHeaderLastKnownGoodPrice(
                ticker: ticker,
                exchange: parsedExchange,
                symbol: selectedCoin.symbol
            )
            prefillOrderPriceIfPossible()
            refreshChartSummaryStates(reason: "ticker_merge")
            if activeTab == .trade {
                logOrderHeaderPriceDebug(reason: "ticker_merge")
            }
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            guard var ticker = self.pricesByMarketIdentity[marketIdentity], ticker.flash != nil else {
                return
            }
            ticker.flash = nil
            self.pricesByMarketIdentity[marketIdentity] = ticker
            if self.selectedExchange == parsedExchange {
                _ = self.applyTargetedMarketRowUpdate(
                    marketIdentity: marketIdentity,
                    reason: "ticker_flash_reset"
                )
            }
        }
    }

    private func makeTickerDisplayPatch(
        marketIdentity: MarketIdentity,
        exchange: Exchange,
        generation: Int,
        reason: String
    ) -> MarketTickerDisplayPatch? {
        guard marketIdentity.exchange == exchange,
              let ticker = pricesByMarketIdentity[marketIdentity]
                ?? pricesByMarketIdentity[resolvedMarketIdentity(exchange: exchange, symbol: marketIdentity.symbol)] else {
            return nil
        }

        let freshnessState: MarketRowFreshnessState
        if ticker.delivery == .live {
            freshnessState = .live
        } else {
            freshnessState = ticker.isStale ? .stale : .refreshing
        }

        return MarketTickerDisplayPatch(
            marketIdentity: marketIdentity,
            exchange: exchange,
            generation: generation,
            sourceExchange: ticker.sourceExchange ?? exchange,
            priceText: PriceFormatter.formatPrice(ticker.price),
            changeText: Self.formatMarketChange(ticker.change),
            volumeText: PriceFormatter.formatVolume(ticker.volume),
            isPricePlaceholder: false,
            isChangePlaceholder: false,
            isVolumePlaceholder: false,
            isUp: ticker.change >= 0,
            flash: ticker.flash,
            dataState: ticker.delivery == .live ? .live : .snapshot,
            baseFreshnessState: freshnessState,
            reason: reason
        )
    }

    private func seedSparklineSnapshotIfAvailable(
        marketIdentity: MarketIdentity,
        ticker: TickerData,
        source: SparklineLayerSource,
        fetchedAt: Date
    ) {
        guard ticker.sparkline.count >= 2 else {
            return
        }

        let pointCount = ticker.sparklinePointCount ?? ticker.sparkline.count
        let interval = sparklineInterval(for: marketIdentity)
        let key = SparklineCacheKey(marketIdentity: marketIdentity, interval: interval)
        let existingSnapshot = sparklineSnapshotsByKey[key]
        let points = sparklinePointsForSnapshotSeed(
            tickerPoints: ticker.sparkline,
            pointCount: pointCount,
            source: source,
            existingSnapshot: existingSnapshot
        )
        let snapshot = SparklineLayerSnapshot(
            interval: interval,
            points: points,
            pointCount: max(pointCount, points.count),
            fetchedAt: fetchedAt,
            source: source
        )
        guard shouldReplaceSparklineSnapshot(
            existing: existingSnapshot,
            incoming: snapshot,
            marketIdentity: marketIdentity
        ) else {
            return
        }
        sparklineSnapshotsByKey[key] = snapshot
    }

    private func sparklinePointsForSnapshotSeed(
        tickerPoints: [Double],
        pointCount: Int,
        source: SparklineLayerSource,
        existingSnapshot: SparklineLayerSnapshot?
    ) -> [Double] {
        var points = Array(tickerPoints.suffix(24))
        guard source == .stream,
              let existingSnapshot,
              existingSnapshot.points.count > points.count,
              let latestPrice = points.last else {
            return points
        }

        var mergedPoints = existingSnapshot.points
        if mergedPoints.last != latestPrice {
            mergedPoints.append(latestPrice)
        }
        let retainedWindow = max(existingSnapshot.points.count, min(24, max(pointCount, points.count)))
        points = Array(mergedPoints.suffix(retainedWindow))
        return points
    }

    private func shouldReplaceSparklineSnapshot(
        existing: SparklineLayerSnapshot?,
        incoming: SparklineLayerSnapshot,
        marketIdentity: MarketIdentity
    ) -> Bool {
        guard let existing else {
            let incomingQuality = Self.sparklineQuality(
                for: incoming,
                staleInterval: sparklineCacheStaleInterval,
                now: Date()
            )
            Self.logGraphQualityDecision(
                marketIdentity: marketIdentity,
                existing: nil,
                incoming: incomingQuality,
                decision: .accept("quality_upgrade")
            )
            if incoming.source == .tickerSnapshot && incomingQuality.isVeryLowCoarse {
                AppLogger.debug(
                    .network,
                    "[GraphDetailDebug] \(marketIdentity.logFields) action=coarse_snapshot_retained_as_fallback pointCount=\(incoming.pointCount)"
                )
            }
            return true
        }

        let now = Date()
        let existingQuality = Self.sparklineQuality(
            for: existing,
            staleInterval: sparklineCacheStaleInterval,
            now: now
        )
        let incomingQuality = Self.sparklineQuality(
            for: incoming,
            staleInterval: sparklineCacheStaleInterval,
            now: now
        )
        let decision = incomingQuality.promotionDecision(over: existingQuality)
        Self.logGraphQualityDecision(
            marketIdentity: marketIdentity,
            existing: existingQuality,
            incoming: incomingQuality,
            decision: decision
        )
        guard decision.accepted else {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(marketIdentity.logFields) action=redraw_skipped reason=\(decision.reason == "same_quality_skip" ? "same_quality_snapshot_skipped" : "coarse_snapshot_rejected") oldDetail=\(existingQuality.detailLevel.cacheComponent) newDetail=\(incomingQuality.detailLevel.cacheComponent)"
            )
            noteSparklineNoImprovement(for: marketIdentity, now: now)
            return false
        }
        if incoming.source == .tickerSnapshot && incomingQuality.isVeryLowCoarse {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(marketIdentity.logFields) action=coarse_snapshot_retained_as_fallback pointCount=\(incoming.pointCount)"
            )
        }
        if (incoming.source == .candleSnapshot || incoming.source == .stream) && incomingQuality.detailLevel == .liveDetailed {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(marketIdentity.logFields) action=live_detail_locked pointCount=\(incoming.pointCount)"
            )
        }
        clearSparklineNoImprovement(for: marketIdentity)
        return true
    }

    private func sparklineCacheKey(symbol: String, exchange: Exchange) -> SparklineCacheKey {
        let marketIdentity = resolvedMarketIdentity(exchange: exchange, symbol: symbol)
        return sparklineCacheKey(marketIdentity: marketIdentity)
    }

    private func sparklineCacheKey(marketIdentity: MarketIdentity) -> SparklineCacheKey {
        SparklineCacheKey(
            marketIdentity: marketIdentity,
            interval: sparklineInterval(for: marketIdentity)
        )
    }

    private func sparklineSnapshot(symbol: String, exchange: Exchange) -> SparklineLayerSnapshot? {
        sparklineSnapshot(marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol))
    }

    private func sparklineSnapshot(marketIdentity: MarketIdentity) -> SparklineLayerSnapshot? {
        sparklineSnapshotsByKey[sparklineCacheKey(marketIdentity: marketIdentity)]
    }

    private func setSparklineSnapshot(
        _ snapshot: SparklineLayerSnapshot,
        symbol: String,
        exchange: Exchange
    ) {
        let marketIdentity = resolvedMarketIdentity(exchange: exchange, symbol: symbol)
        setSparklineSnapshot(snapshot, marketIdentity: marketIdentity)
    }

    private func setSparklineSnapshot(
        _ snapshot: SparklineLayerSnapshot,
        marketIdentity: MarketIdentity
    ) {
        sparklineSnapshotsByKey[SparklineCacheKey(
            marketIdentity: marketIdentity,
            interval: snapshot.interval
        )] = snapshot
    }

    private func stableSparklineDisplayKey(symbol: String, exchange: Exchange) -> MarketGraphBindingKey {
        stableSparklineDisplayKey(marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol))
    }

    private func stableSparklineDisplayKey(marketIdentity: MarketIdentity) -> MarketGraphBindingKey {
        MarketGraphBindingKey(
            marketIdentity: marketIdentity,
            interval: sparklineInterval(for: marketIdentity)
        )
    }

    private func stableSparklineDisplay(symbol: String, exchange: Exchange) -> StableSparklineDisplay? {
        stableSparklineDisplay(marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol))
    }

    private func stableSparklineDisplay(marketIdentity: MarketIdentity) -> StableSparklineDisplay? {
        stableSparklineDisplaysByKey[stableSparklineDisplayKey(marketIdentity: marketIdentity)]
    }

    private func stableSparklineDisplaysByMarketIdentity(for exchange: Exchange) -> [MarketIdentity: StableSparklineDisplay] {
        var displays = [MarketIdentity: StableSparklineDisplay]()
        for (key, value) in stableSparklineDisplaysByKey where key.exchange == exchange {
            guard key.interval == sparklineInterval(for: key.marketIdentity) else {
                continue
            }
            if let existing = displays[key.marketIdentity] {
                displays[key.marketIdentity] = Self.preferredStableSparklineDisplay(existing, value)
            } else {
                displays[key.marketIdentity] = value
            }
        }
        return displays
    }

    private func persistStableSparklineDisplays(
        from rows: [MarketRowViewState],
        exchange: Exchange,
        generation: Int,
        now: Date = Date()
    ) {
        for row in rows {
            guard row.exchange == exchange,
                  row.graphState.keepsVisibleGraph,
                  MarketSparklineRenderPolicy.hasRenderableGraph(
                    points: row.sparkline,
                    pointCount: row.sparklinePointCount
                  ) else {
                continue
            }

            stableSparklineDisplaysByKey[stableSparklineDisplayKey(marketIdentity: row.marketIdentity)] = StableSparklineDisplay(
                key: stableSparklineDisplayKey(marketIdentity: row.marketIdentity),
                points: row.sparkline,
                pointCount: row.sparklinePointCount,
                graphState: row.graphState,
                generation: generation,
                updatedAt: now,
                sourceVersion: row.sparklinePayload.sourceVersion == 0
                    ? Self.sparklineSourceVersion(from: now)
                    : row.sparklinePayload.sourceVersion
            )
        }
    }

    private func sparklineSnapshotsByMarketIdentity(
        for exchange: Exchange,
        additionalMarketIdentities: [MarketIdentity] = []
    ) -> [MarketIdentity: SparklineLayerSnapshot] {
        var snapshots = [MarketIdentity: SparklineLayerSnapshot]()
        let marketIdentities = Self.deduplicatedMarketIdentities(
            additionalMarketIdentities
                + (marketPresentationSnapshotsByExchange[exchange]?.rows.map(\.marketIdentity) ?? [])
                + (tickerSnapshotCoinsByExchange[exchange]?.map { $0.marketIdentity(exchange: exchange) } ?? [])
        )
        for marketIdentity in marketIdentities {
            if let snapshot = sparklineSnapshot(marketIdentity: marketIdentity) {
                snapshots[marketIdentity] = snapshot
            }
        }
        return snapshots
    }

    private func reserveScheduledSparklineRequests(
        marketIdentities: [MarketIdentity],
        exchange: Exchange,
        generation: Int,
        priority: SparklineQueuePriority,
        phase: String
    ) -> [MarketIdentity] {
        var enqueued = [MarketIdentity]()
        var skippedCount = 0
        var upgradedCount = 0

        for marketIdentity in Self.deduplicatedMarketIdentities(marketIdentities) where marketIdentity.exchange == exchange {
            let key = sparklineCacheKey(marketIdentity: marketIdentity)
            if let existing = scheduledSparklineRequestsByKey[key], existing.generation == generation {
                if existing.priority.rawValue >= priority.rawValue {
                    skippedCount += 1
                    AppLogger.debug(
                        .network,
                        "[GraphEnqueueDebug] \(marketIdentity.logFields) action=skip reason=queued_duplicate"
                    )
                    AppLogger.debug(
                        .network,
                        "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_queue_skipped_duplicate phase=\(phase) priority=\(priority.logValue)"
                    )
                    AppLogger.debug(
                        .network,
                        "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_request_suppressed reason=already_scheduled_same_generation phase=\(phase)"
                    )
                    continue
                }

                scheduledSparklineRequestsByKey[key] = ScheduledSparklineRequestState(
                    generation: generation,
                    priority: priority,
                    phase: phase
                )
                enqueued.append(marketIdentity)
                upgradedCount += 1
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_queue_upgraded_priority old=\(existing.priority.logValue) new=\(priority.logValue) phase=\(phase)"
                )
                continue
            }

            scheduledSparklineRequestsByKey[key] = ScheduledSparklineRequestState(
                generation: generation,
                priority: priority,
                phase: phase
            )
            enqueued.append(marketIdentity)
            AppLogger.debug(
                .network,
                "[GraphEnqueueDebug] \(marketIdentity.logFields) action=enqueue reason=\(priority == .visibleMissing || priority == .visibleCoarse ? "visible_priority" : priority.logValue)"
            )
            AppLogger.debug(
                .network,
                "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_queue_enqueued phase=\(phase) priority=\(priority.logValue)"
            )
        }

        let coalescedCount = skippedCount + upgradedCount
        if coalescedCount > 0 {
            AppLogger.debug(
                .network,
                "[GraphRequestDebug] exchange=\(exchange.rawValue) action=graph_scheduler_coalesced count=\(coalescedCount) phase=\(phase)"
            )
        }
        return enqueued
    }

    private func releaseScheduledSparklineRequests(
        marketIdentities: [MarketIdentity],
        generation: Int
    ) {
        for marketIdentity in Self.deduplicatedMarketIdentities(marketIdentities) {
            let key = sparklineCacheKey(marketIdentity: marketIdentity)
            guard let existing = scheduledSparklineRequestsByKey[key],
                  existing.generation == generation else {
                continue
            }
            scheduledSparklineRequestsByKey.removeValue(forKey: key)
        }
    }

    private func scheduleVisibleSparklineHydration(
        for exchange: Exchange,
        reason: String
    ) {
        guard activeTab == .market, selectedExchange == exchange else {
            return
        }

        if runningSparklineHydrationExchanges.contains(exchange) {
            pendingSparklineHydrationReasonsByExchange[exchange] = reason
            let scheduledPriorityRefresh = schedulePriorityVisibleSparklineRefresh(
                for: exchange,
                reason: "\(reason)_inflight_priority"
            )
            if scheduledPriorityRefresh {
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] exchange=\(exchange.rawValue) action=priority_visible_refresh reason=hydration_inflight"
                )
            }
            return
        }

        let generation = marketPresentationGeneration
        let context = ScheduledHydrationContext(exchange: exchange, generation: generation)
        if scheduledSparklineHydrationContext == context, sparklineHydrationTask != nil {
            return
        }

        sparklineHydrationTask?.cancel()
        scheduledSparklineHydrationContext = context
        sparklineHydrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.scheduledSparklineHydrationContext == context {
                    self.scheduledSparklineHydrationContext = nil
                    self.sparklineHydrationTask = nil
                }
            }
            try? await Task.sleep(nanoseconds: self.sparklineSchedulerDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard self.scheduledSparklineHydrationContext == context else {
                return
            }
            await self.runSparklineHydrationLoop(
                for: exchange,
                generation: generation,
                reason: reason
            )
        }
    }

    @discardableResult
    private func schedulePriorityVisibleSparklineRefresh(
        for exchange: Exchange,
        reason: String
    ) -> Bool {
        guard activeTab == .market, selectedExchange == exchange else {
            return false
        }

        let generation = marketPresentationGeneration
        let context = ScheduledHydrationContext(exchange: exchange, generation: generation)
        if scheduledPriorityVisibleSparklineContext == context, priorityVisibleSparklineTask != nil {
            return false
        }

        priorityVisibleSparklineTask?.cancel()
        scheduledPriorityVisibleSparklineContext = context
        priorityVisibleSparklineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.scheduledPriorityVisibleSparklineContext == context {
                    self.scheduledPriorityVisibleSparklineContext = nil
                    self.priorityVisibleSparklineTask = nil
                }
            }
            try? await Task.sleep(for: .milliseconds(5))
            guard !Task.isCancelled else { return }
            guard self.scheduledPriorityVisibleSparklineContext == context else {
                return
            }
            await self.runPriorityVisibleSparklineRefresh(
                for: exchange,
                generation: generation,
                reason: reason
            )
        }
        return true
    }

    private func runPriorityVisibleSparklineRefresh(
        for exchange: Exchange,
        generation: Int,
        reason: String
    ) async {
        guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
            return
        }
        guard let snapshot = marketPresentationSnapshotsByExchange[exchange], snapshot.rows.isEmpty == false else {
            return
        }

        let rowsByMarketIdentity = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.marketIdentity, $0) })
        let now = Date()
        let priorityCandidates = Array(
            priorityVisibleSparklineMarketIdentities(
                for: exchange,
                rows: snapshot.rows
            )
            .filter { marketIdentity in
                guard let row = rowsByMarketIdentity[marketIdentity] else {
                    return true
                }
                return shouldPrioritizeVisibleSparklineHydration(marketIdentity: marketIdentity)
                    && hasPotentialSparklineQualityGain(for: marketIdentity, now: now)
                    && row.sparklinePayload.detailLevel.isDetailed == false
            }
            .prefix(sparklineVisibleBatchSize)
        )
        let priorityBatch = reserveScheduledSparklineRequests(
            marketIdentities: priorityCandidates.filter {
                shouldFetchSparkline(marketIdentity: $0, now: now, allowVisibleBypass: true)
            },
            exchange: exchange,
            generation: generation,
            priority: .visibleMissing,
            phase: "priority_visible_batch"
        )

        guard priorityBatch.isEmpty == false else {
            return
        }

        let startedAt = Date()
        AppLogger.debug(
            .network,
            "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=priority_visible_batch_start reason=\(reason) markets=\(priorityBatch.prefix(8).map(\.cacheKey).joined(separator: ","))"
        )

        let results = await fetchSparklineBatch(
            marketIdentities: priorityBatch,
            exchange: exchange
        )
        releaseScheduledSparklineRequests(
            marketIdentities: priorityBatch,
            generation: generation
        )
        guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
            return
        }

        var patches = [MarketSparklinePatch]()
        var failedMarketIdentities = [MarketIdentity]()
        for result in results {
            switch result.result {
            case .success(let sparklineSnapshot):
                setSparklineSnapshot(sparklineSnapshot, marketIdentity: result.marketIdentity)
                unavailableSparklineMarketIdentitiesByExchange[exchange, default: []].remove(result.marketIdentity)
                patches.append(
                    MarketSparklinePatch(
                        marketIdentity: result.marketIdentity,
                        snapshot: sparklineSnapshot,
                        graphState: sparklineSnapshot.graphState(staleInterval: sparklineCacheStaleInterval, now: Date()),
                        reason: "priority_visible_batch"
                    )
                )
            case .failure:
                failedMarketIdentities.append(result.marketIdentity)
            }
        }

        let updatedRows = applySparklinePatches(patches, exchange: exchange, generation: generation)
        marketVisibleGraphPatchCountByExchange[exchange, default: 0] += updatedRows
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        AppLogger.debug(
            .network,
            "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=priority_visible_batch_success updatedRows=\(updatedRows) failedRows=\(failedMarketIdentities.count) elapsedMs=\(elapsedMs)"
        )
    }

    private func runSparklineHydrationLoop(
        for exchange: Exchange,
        generation: Int,
        reason: String
    ) async {
        guard runningSparklineHydrationExchanges.contains(exchange) == false else {
            pendingSparklineHydrationReasonsByExchange[exchange] = reason
            return
        }

        runningSparklineHydrationExchanges.insert(exchange)
        await runSparklineHydration(
            for: exchange,
            generation: generation,
            reason: reason
        )
        runningSparklineHydrationExchanges.remove(exchange)

        guard let pendingReason = pendingSparklineHydrationReasonsByExchange.removeValue(forKey: exchange) else {
            return
        }
        guard activeTab == .market, selectedExchange == exchange else {
            return
        }
        scheduleVisibleSparklineHydration(
            for: exchange,
            reason: pendingReason
        )
    }

    private func runSparklineHydration(
        for exchange: Exchange,
        generation: Int,
        reason: String
    ) async {
        guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
            return
        }
        guard let snapshot = marketPresentationSnapshotsByExchange[exchange], snapshot.rows.isEmpty == false else {
            return
        }

        let allMarketIdentities = snapshot.rows.map(\.marketIdentity)
        let rowsByMarketIdentity = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.marketIdentity, $0) })
        let visibleMarketIdentities = visibleMarketIdentitiesByExchange[exchange] ?? []
        let selectedMarketIdentities = selectedExchange == exchange ? [selectedCoin?.marketIdentity(exchange: exchange)].compactMap { $0 } : []
        let firstScreenMarketIdentities = snapshot.rows.prefix(sparklineRepresentativeLimit).map(\.marketIdentity)
        let nearVisibleMarketIdentities = nearVisibleSparklineMarketIdentities(
            rows: snapshot.rows,
            visibleMarketIdentities: visibleMarketIdentities,
            radius: 2
        )
        let prioritizedMarketIdentities = Self.deduplicatedMarketIdentities(
            selectedMarketIdentities
                + visibleMarketIdentities
                + nearVisibleMarketIdentities
                + firstScreenMarketIdentities
                + allMarketIdentities
        )
        let candidates = prioritizedMarketIdentities.filter {
            shouldFetchSparkline(
                marketIdentity: $0,
                now: Date(),
                allowVisibleBypass: visibleMarketIdentities.contains($0)
                    || firstScreenMarketIdentities.contains($0)
                    || nearVisibleMarketIdentities.contains($0)
            )
        }

        guard candidates.isEmpty == false else {
            return
        }

        let cacheHits = Self.deduplicatedMarketIdentities(
            selectedMarketIdentities
                + visibleMarketIdentities
                + nearVisibleMarketIdentities
                + firstScreenMarketIdentities
        ).filter {
            sparklineSnapshot(marketIdentity: $0) != nil
        }
        if cacheHits.isEmpty == false {
            let signature = cacheHits.prefix(12).map(\.cacheKey).joined(separator: ",")
            if lastLoggedGraphCacheHitSignatureByExchange[exchange] != signature {
                lastLoggedGraphCacheHitSignatureByExchange[exchange] = signature
                AppLogger.debug(
                    .network,
                    "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=cache_hit markets=\(cacheHits.prefix(8).map(\.cacheKey).joined(separator: ",")) count=\(cacheHits.count)"
                )
            }
        }

        let visibleSet = Set(
            Self.deduplicatedMarketIdentities(
                selectedMarketIdentities
                    + visibleMarketIdentities
                    + nearVisibleMarketIdentities
                    + firstScreenMarketIdentities
            )
            .prefix(sparklineRepresentativeLimit * 2)
        )
        let visiblePrioritySet = Set(
            visibleSet.filter { marketIdentity in
                guard let row = rowsByMarketIdentity[marketIdentity] else {
                    return true
                }
                return row.graphState != .liveVisible || row.sparklinePayload.detailLevel.isDetailed == false
            }
        )
        let isActivelyScrolling = isActivelyScrollingMarketRows(for: exchange, now: Date())
        let orderedVisibleCandidates = candidates.filter { visiblePrioritySet.contains($0) }
        let immediateVisibleCandidates = orderedVisibleCandidates.filter { marketIdentity in
            guard let row = rowsByMarketIdentity[marketIdentity] else {
                return true
            }
            let quality = Self.sparklineQuality(for: row)
            return quality.isUsableGraph == false
                || quality.detailLevel.isDetailed == false
                || quality.isVeryLowCoarse
        }
        let deferredVisibleCandidates = orderedVisibleCandidates.filter { marketIdentity in
            immediateVisibleCandidates.contains(marketIdentity) == false
                && hasPotentialSparklineQualityGain(for: marketIdentity, now: Date())
        }
        let visibleBatch = reserveScheduledSparklineRequests(
            marketIdentities: Array(orderedVisibleCandidates.prefix(sparklineVisibleBatchSize)),
            exchange: exchange,
            generation: generation,
            priority: .visibleCoarse,
            phase: "visible_batch"
        )
        if visibleBatch.isEmpty == false {
            await hydrateSparklineBatch(
                marketIdentities: visibleBatch,
                exchange: exchange,
                generation: generation,
                phase: "visible_batch",
                batchIndex: nil,
                reason: reason
            )
        }

        var settledVisibleBatch = [MarketIdentity]()
        if isActivelyScrolling,
           deferredVisibleCandidates.isEmpty == false {
            try? await Task.sleep(nanoseconds: sparklineScrollSettleDelayNanoseconds)
            guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
                return
            }
            if isActivelyScrollingMarketRows(for: exchange, now: Date()) {
                pendingSparklineHydrationReasonsByExchange[exchange] = "\(reason)_scroll_settling"
                return
            }
            settledVisibleBatch = reserveScheduledSparklineRequests(
                marketIdentities: Array(deferredVisibleCandidates.prefix(sparklineVisibleBatchSize)),
                exchange: exchange,
                generation: generation,
                priority: .visibleCoarse,
                phase: "visible_refine_batch"
            )
            if settledVisibleBatch.isEmpty == false {
                await hydrateSparklineBatch(
                    marketIdentities: settledVisibleBatch,
                    exchange: exchange,
                    generation: generation,
                    phase: "visible_refine_batch",
                    batchIndex: nil,
                    reason: reason
                )
            }
        }

        guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
            return
        }

        let alreadyRequested = Set(visibleBatch + settledVisibleBatch)
        let backgroundCandidates = candidates.filter { alreadyRequested.contains($0) == false }
        guard backgroundCandidates.isEmpty == false else {
            return
        }
        if visibleBatch.isEmpty == false {
            try? await Task.sleep(for: .milliseconds(180))
        }
        if let lastVisibleAt = lastVisibleMarketRowAtByExchange[exchange],
           Date().timeIntervalSince(lastVisibleAt) < 0.45 {
            marketOffscreenDeferredGraphCountByExchange[exchange, default: 0] += backgroundCandidates.count
            let signature = backgroundCandidates.prefix(12).map(\.cacheKey).joined(separator: ",")
            if lastLoggedGraphDeferredSignatureByExchange[exchange] != signature {
                lastLoggedGraphDeferredSignatureByExchange[exchange] = signature
                AppLogger.debug(
                    .network,
                    "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=deferred_offscreen markets=\(backgroundCandidates.prefix(10).map(\.cacheKey).joined(separator: ","))"
                )
            }
            return
        }

        for (index, batch) in backgroundCandidates.chunked(into: sparklineBackgroundBatchSize).enumerated() {
            guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
                return
            }
            try? await Task.sleep(for: .milliseconds(index == 0 ? 120 : 220))
            guard !Task.isCancelled else {
                return
            }
            if let lastVisibleAt = lastVisibleMarketRowAtByExchange[exchange],
               Date().timeIntervalSince(lastVisibleAt) < 0.45 {
                marketOffscreenDeferredGraphCountByExchange[exchange, default: 0] += backgroundCandidates.count
                pendingSparklineHydrationReasonsByExchange[exchange] = "\(reason)_visible_preempted"
                AppLogger.debug(
                    .network,
                    "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=deferred_offscreen_preempted markets=\(backgroundCandidates.prefix(10).map(\.cacheKey).joined(separator: ","))"
                )
                return
            }
            MarketPerformanceDebugClient.shared.increment(.offscreenBatch)
            let reservedBatch = reserveScheduledSparklineRequests(
                marketIdentities: batch,
                exchange: exchange,
                generation: generation,
                priority: .offscreen,
                phase: "offscreen_batch"
            )
            guard reservedBatch.isEmpty == false else {
                continue
            }
            await hydrateSparklineBatch(
                marketIdentities: reservedBatch,
                exchange: exchange,
                generation: generation,
                phase: "offscreen_batch",
                batchIndex: index + 1,
                reason: reason
            )
        }
    }

    private func primeFirstPaintDetailedSparklinesIfPossible(
        for snapshot: MarketPresentationSnapshot,
        requestContext: MarketRequestContext
    ) async -> MarketPresentationSnapshot {
        guard activeTab == .market,
              selectedExchange == snapshot.exchange,
              snapshot.rows.isEmpty == false,
              shouldAcceptMarketPresentation(requestContext, responseUniverseVersion: snapshot.universe.symbolsHash) else {
            return snapshot
        }

        let candidates = reserveScheduledSparklineRequests(
            marketIdentities: firstPaintSparklinePrimeCandidates(from: snapshot),
            exchange: snapshot.exchange,
            generation: snapshot.generation,
            priority: .visibleMissing,
            phase: "first_paint_prime"
        )
        guard candidates.isEmpty == false else {
            return snapshot
        }

        AppLogger.debug(
            .network,
            "[GraphPipeline] exchange=\(snapshot.exchange.rawValue) generation=\(snapshot.generation) phase=first_paint_prime_start markets=\(candidates.prefix(8).map(\.cacheKey).joined(separator: ","))"
        )

        let startedAt = Date()
        let results = await fetchSparklineBatch(
            marketIdentities: candidates,
            exchange: snapshot.exchange
        )
        releaseScheduledSparklineRequests(
            marketIdentities: candidates,
            generation: snapshot.generation
        )
        guard shouldAcceptMarketPresentation(requestContext, responseUniverseVersion: snapshot.universe.symbolsHash) else {
            return snapshot
        }

        var appliedCount = 0
        var failedCount = 0
        for result in results {
            switch result.result {
            case .success(let sparklineSnapshot):
                setSparklineSnapshot(sparklineSnapshot, marketIdentity: result.marketIdentity)
                unavailableSparklineMarketIdentitiesByExchange[snapshot.exchange, default: []].remove(result.marketIdentity)
                unsupportedSparklineMarketIdentitiesByExchange[snapshot.exchange, default: []].remove(result.marketIdentity)
                appliedCount += 1
            case .failure:
                failedCount += 1
            }
        }

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        AppLogger.debug(
            .network,
            "[GraphPipeline] exchange=\(snapshot.exchange.rawValue) generation=\(snapshot.generation) phase=first_paint_prime_finish appliedRows=\(appliedCount) failedRows=\(failedCount) elapsedMs=\(elapsedMs)"
        )

        guard appliedCount > 0 else {
            return snapshot
        }

        let rebuiltInput = makeMarketPresentationBuildInput(
            for: snapshot.exchange,
            overrideMeta: snapshot.meta,
            referenceRows: snapshot.rows
        )
        return await prepareMarketPresentationSnapshot(from: rebuiltInput)
    }

    private func firstPaintSparklinePrimeCandidates(
        from snapshot: MarketPresentationSnapshot
    ) -> [MarketIdentity] {
        let rowsByMarketIdentity = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.marketIdentity, $0) })
        let selectedMarketIdentities = selectedExchange == snapshot.exchange
            ? [selectedCoin?.marketIdentity(exchange: snapshot.exchange)].compactMap { $0 }
            : []
        let visibleMarketIdentities = visibleMarketIdentitiesByExchange[snapshot.exchange] ?? []
        let representativeMarketIdentities = snapshot.rows.prefix(marketRepresentativeRowLimit).map(\.marketIdentity)
        let firstScreenMarketIdentities = snapshot.rows.prefix(sparklineRepresentativeLimit).map(\.marketIdentity)
        let orderedMarketIdentities = Self.deduplicatedMarketIdentities(
            selectedMarketIdentities + representativeMarketIdentities + visibleMarketIdentities + firstScreenMarketIdentities
        )

        let now = Date()
        return Array(
            orderedMarketIdentities.compactMap { marketIdentity -> MarketIdentity? in
                guard let row = rowsByMarketIdentity[marketIdentity] else {
                    return nil
                }
                guard row.sparklinePayload.detailLevel.isDetailed == false else {
                    return nil
                }
                guard shouldFetchSparkline(marketIdentity: marketIdentity, now: now) else {
                    return nil
                }
                return marketIdentity
            }
            .prefix(sparklineVisibleBatchSize)
        )
    }

    private func nearVisibleSparklineMarketIdentities(
        rows: [MarketRowViewState],
        visibleMarketIdentities: [MarketIdentity],
        radius: Int
    ) -> [MarketIdentity] {
        guard visibleMarketIdentities.isEmpty == false else {
            return []
        }

        let indexByMarketIdentity = rows.enumerated().reduce(into: [MarketIdentity: Int]()) { partialResult, element in
            let (offset, row) = element
            if partialResult[row.marketIdentity] == nil {
                partialResult[row.marketIdentity] = offset
            }
        }
        var marketIdentities = [MarketIdentity]()
        for visibleMarketIdentity in visibleMarketIdentities {
            guard let index = indexByMarketIdentity[visibleMarketIdentity] else { continue }
            let lowerBound = max(index - radius, 0)
            let upperBound = min(index + radius, rows.count - 1)
            for rowIndex in lowerBound...upperBound {
                marketIdentities.append(rows[rowIndex].marketIdentity)
            }
        }
        return Self.deduplicatedMarketIdentities(marketIdentities)
    }

    private func shouldRunSparklineHydration(exchange: Exchange, generation: Int) -> Bool {
        activeTab == .market
            && selectedExchange == exchange
            && marketPresentationGeneration == generation
            && Task.isCancelled == false
    }

    private func recordStaleGraphPatchDrop(
        for marketIdentity: MarketIdentity,
        reason: String = "identity_mismatch"
    ) {
        marketStaleCallbackDropCountByExchange[marketIdentity.exchange, default: 0] += 1
        AppLogger.debug(
            .network,
            "[GraphPatchDropDebug] \(marketIdentity.logFields) reason=\(reason)"
        )
        AppLogger.debug(
            .network,
            "[GraphScrollDebug] \(marketIdentity.logFields) action=drop_patch reason=\(reason)"
        )
    }

    private func isVisibleSparklinePatchLane(_ reason: String) -> Bool {
        reason == "priority_visible_batch"
            || reason == "visible_refine_batch"
            || reason == "visible_batch"
            || reason == "hold_timeout_fallback"
    }

    private func isCurrentlyVisibleSparklineIdentity(
        _ marketIdentity: MarketIdentity,
        exchange: Exchange,
        rows: [MarketRowViewState]
    ) -> Bool {
        if visibleMarketIdentitiesByExchange[exchange]?.contains(marketIdentity) == true {
            return true
        }
        return priorityVisibleSparklineMarketIdentities(for: exchange, rows: rows)
            .contains(marketIdentity)
    }

    private func shouldDropSparklinePatchBeforeUIPromotion(
        _ patch: MarketSparklinePatch,
        exchange: Exchange,
        generation: Int,
        rows: [MarketRowViewState]
    ) -> Bool {
        guard isVisibleSparklinePatchLane(patch.reason) == false,
              isCurrentlyVisibleSparklineIdentity(patch.marketIdentity, exchange: exchange, rows: rows) else {
            return false
        }

        AppLogger.debug(
            .network,
            "[GraphPatchDropDebug] \(patch.marketIdentity.logFields) reason=visible_lower_lane_allowed lane=\(patch.reason) generation=\(generation)"
        )
        return false
    }

    private func shouldFetchSparkline(symbol: String, exchange: Exchange, now: Date) -> Bool {
        shouldFetchSparkline(
            marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol),
            now: now
        )
    }

    private func shouldFetchSparkline(
        marketIdentity: MarketIdentity,
        now: Date,
        allowVisibleBypass: Bool = false
    ) -> Bool {
        let key = sparklineCacheKey(marketIdentity: marketIdentity)
        let isVisibleTarget = allowVisibleBypass
            && isVisibleSparklineRedrawTarget(marketIdentity, exchange: marketIdentity.exchange)
        if unsupportedSparklineMarketIdentitiesByExchange[marketIdentity.exchange]?.contains(marketIdentity) == true {
            AppLogger.debug(
                .network,
                "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_capability_cached supported=false"
            )
            AppLogger.debug(
                .network,
                "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_request_skipped reason=runtime_unsupported_cached"
            )
            return false
        }
        if let supportedIntervals = supportedIntervalsByExchangeAndMarketIdentity[marketIdentity.exchange]?[marketIdentity] {
            let isSupported = supportedIntervals.isEmpty == false
            if isSupported == false {
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_capability_cached supported=false"
                )
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_request_skipped reason=server_declared_unsupported"
                )
                return false
            }
        }
        if sparklineFetchTasksByKey[key] != nil {
            AppLogger.debug(
                .network,
                "[GraphEnqueueDebug] \(marketIdentity.logFields) action=skip reason=inflight_duplicate"
            )
            AppLogger.debug(
                .network,
                "[GraphRequestDebug] \(marketIdentity.logFields) action=deduped_existing_inflight"
            )
            return false
        }

        if loadingSparklineMarketIdentitiesByExchange[marketIdentity.exchange]?.contains(marketIdentity) == true {
            return false
        }

        if let cooldownUntil = sparklineFailureCooldownUntilByKey[key],
           cooldownUntil > now,
           hasUsableSparklineGraph(marketIdentity: marketIdentity) {
            AppLogger.debug(
                .network,
                "[GraphRequestDebug] \(marketIdentity.logFields) action=skip_refresh reason=stale_usable_within_cooldown"
            )
            return false
        }

        if let noImprovementUntil = sparklineNoImprovementUntilByKey[key],
           noImprovementUntil > now,
           hasUsableSparklineGraph(marketIdentity: marketIdentity),
           hasPotentialSparklineQualityGain(for: marketIdentity, now: now) == false {
            if isVisibleTarget {
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_request_allowed reason=visible_no_quality_gain_bypass"
                )
            } else {
                AppLogger.debug(
                    .network,
                    "[GraphEnqueueDebug] \(marketIdentity.logFields) action=skip reason=no_quality_gain"
                )
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_request_skipped reason=no_quality_gain_backoff"
                )
                return false
            }
        }

        if let lastAttemptAt = lastSparklineRefreshAttemptAtByKey[key],
           now.timeIntervalSince(lastAttemptAt) < sparklineRefreshThrottleInterval,
           hasUsableSparklineGraph(marketIdentity: marketIdentity) {
            if isVisibleTarget,
               hasPotentialSparklineQualityGain(for: marketIdentity, now: now) {
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] \(marketIdentity.logFields) action=graph_request_allowed reason=visible_refresh_throttle_bypass"
                )
            } else {
                AppLogger.debug(
                    .network,
                    "[GraphEnqueueDebug] \(marketIdentity.logFields) action=skip reason=throttled"
                )
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] \(marketIdentity.logFields) action=skip_refresh reason=stale_usable_within_cooldown"
                )
                return false
            }
        }

        guard let snapshot = sparklineSnapshot(marketIdentity: marketIdentity) else {
            return true
        }

        guard MarketSparklineRenderPolicy.hasHydratedGraph(points: snapshot.points, pointCount: snapshot.pointCount) else {
            return true
        }

        return now.timeIntervalSince(snapshot.fetchedAt) > sparklineCacheStaleInterval
    }

    private func hasUsableSparklineGraph(symbol: String, exchange: Exchange) -> Bool {
        hasUsableSparklineGraph(marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol))
    }

    private func hasUsableSparklineGraph(marketIdentity: MarketIdentity) -> Bool {
        if let stableDisplay = stableSparklineDisplay(marketIdentity: marketIdentity),
           stableDisplay.hasRenderableGraph {
            return true
        }
        if let snapshot = sparklineSnapshot(marketIdentity: marketIdentity),
           MarketSparklineRenderPolicy.hasRenderableGraph(
            points: snapshot.points,
            pointCount: snapshot.pointCount
           ) {
            return true
        }
        if let row = marketPresentationSnapshotsByExchange[marketIdentity.exchange]?.rows.first(where: { $0.marketIdentity == marketIdentity }),
           row.graphState.keepsVisibleGraph,
           MarketSparklineRenderPolicy.hasRenderableGraph(
            points: row.sparkline,
            pointCount: row.sparklinePointCount
           ) {
            return true
        }
        return false
    }

    private func hydrateSparklineBatch(
        marketIdentities: [MarketIdentity],
        exchange: Exchange,
        generation: Int,
        phase: String,
        batchIndex: Int?,
        reason: String
    ) async {
        let allowVisibleBypass = phase == "visible_batch"
            || phase == "visible_refine_batch"
            || phase == "priority_visible_batch"
        let batchMarketIdentities = Self.deduplicatedMarketIdentities(
            marketIdentities.filter {
                $0.exchange == exchange && shouldFetchSparkline(
                    marketIdentity: $0,
                    now: Date(),
                    allowVisibleBypass: allowVisibleBypass
                )
            }
        )
        guard batchMarketIdentities.isEmpty == false else {
            releaseScheduledSparklineRequests(
                marketIdentities: marketIdentities,
                generation: generation
            )
            return
        }
        let batchSet = Set(batchMarketIdentities)
        guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
            releaseScheduledSparklineRequests(
                marketIdentities: batchMarketIdentities,
                generation: generation
            )
            return
        }

        loadingSparklineMarketIdentitiesByExchange[exchange, default: []].formUnion(batchSet)
        applySparklineLoadingPatch(
            marketIdentities: batchMarketIdentities,
            exchange: exchange,
            generation: generation,
            reason: reason
        )

        let startedAt = Date()
        let marketPreview = batchMarketIdentities.prefix(8).map(\.cacheKey).joined(separator: ",")
        if let batchIndex {
            AppLogger.debug(
                .network,
                "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=\(phase)_start batchIndex=\(batchIndex) batchSize=\(batchMarketIdentities.count)"
            )
        } else {
            AppLogger.debug(
                .network,
                "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=\(phase)_start markets=\(marketPreview)"
            )
        }

        let results = await fetchSparklineBatch(marketIdentities: batchMarketIdentities, exchange: exchange)
        releaseScheduledSparklineRequests(
            marketIdentities: batchMarketIdentities,
            generation: generation
        )

        loadingSparklineMarketIdentitiesByExchange[exchange, default: []].subtract(batchSet)
        guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
            marketStaleCallbackDropCountByExchange[exchange, default: 0] += batchMarketIdentities.count
            AppLogger.debug(
                .network,
                "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=stale_response_ignored batchSize=\(batchMarketIdentities.count)"
            )
            return
        }

        var patches = [MarketSparklinePatch]()
        var failedMarketIdentities = [MarketIdentity]()
        for result in results {
            switch result.result {
            case .success(let snapshot):
                setSparklineSnapshot(snapshot, marketIdentity: result.marketIdentity)
                unavailableSparklineMarketIdentitiesByExchange[exchange, default: []].remove(result.marketIdentity)
                patches.append(
                    MarketSparklinePatch(
                        marketIdentity: result.marketIdentity,
                        snapshot: snapshot,
                        graphState: snapshot.graphState(staleInterval: sparklineCacheStaleInterval, now: Date()),
                        reason: phase
                    )
                )
            case .failure:
                failedMarketIdentities.append(result.marketIdentity)
                unavailableSparklineMarketIdentitiesByExchange[exchange, default: []].insert(result.marketIdentity)
                let cachedSnapshot = sparklineSnapshot(marketIdentity: result.marketIdentity)
                patches.append(
                    MarketSparklinePatch(
                        marketIdentity: result.marketIdentity,
                        snapshot: cachedSnapshot,
                        graphState: cachedSnapshot == nil ? .unavailable : .staleVisible,
                        reason: "\(phase)_failure"
                    )
                )
            }
        }
        let updatedRows = applySparklinePatches(patches, exchange: exchange, generation: generation)
        if phase == "offscreen_batch",
           activeTab == .market,
           selectedExchange == exchange,
           patches.contains(where: { isVisibleSparklineRedrawTarget($0.marketIdentity, exchange: exchange) }) {
            reconcileVisibleSparklines(
                exchange: exchange,
                reason: "offscreen_batch_immediate_apply"
            )
        }
        if phase == "offscreen_batch" {
            marketOffscreenDeferredGraphCountByExchange[exchange, default: 0] += updatedRows
        } else if phase == "visible_batch" {
            marketVisibleGraphPatchCountByExchange[exchange, default: 0] += updatedRows
        }

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        if let batchIndex {
            AppLogger.debug(
                .network,
                "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=\(phase)_success batchIndex=\(batchIndex) updatedRows=\(updatedRows) failedRows=\(failedMarketIdentities.count) elapsedMs=\(elapsedMs)"
            )
        } else {
            AppLogger.debug(
                .network,
                "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=\(phase)_success updatedRows=\(updatedRows) failedRows=\(failedMarketIdentities.count) elapsedMs=\(elapsedMs)"
            )
        }
    }

    private func fetchSparklineBatch(
        marketIdentities: [MarketIdentity],
        exchange: Exchange
    ) async -> [(marketIdentity: MarketIdentity, result: Result<SparklineLayerSnapshot, Error>)] {
        var tasks = [(marketIdentity: MarketIdentity, key: SparklineCacheKey, task: Task<SparklineLayerSnapshot, Error>)]()
        let now = Date()

        for marketIdentity in Self.deduplicatedMarketIdentities(marketIdentities) where marketIdentity.exchange == exchange {
            let interval = sparklineInterval(for: marketIdentity)
            let key = SparklineCacheKey(marketIdentity: marketIdentity, interval: interval)

            if let cooldownUntil = sparklineFailureCooldownUntilByKey[key],
               cooldownUntil > now,
               hasUsableSparklineGraph(marketIdentity: marketIdentity) {
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] \(marketIdentity.logFields) action=skip_refresh reason=stale_usable_within_cooldown"
                )
                continue
            }

            if let existingTask = sparklineFetchTasksByKey[key] {
                AppLogger.debug(
                    .network,
                    "[GraphRequestDebug] \(marketIdentity.logFields) action=deduped_existing_inflight"
                )
                tasks.append((marketIdentity, key, existingTask))
                continue
            }

            lastSparklineRefreshAttemptAtByKey[key] = now
            let task = Task<SparklineLayerSnapshot, Error> { [marketRepository] in
                let snapshot = try await marketRepository.fetchCandles(
                    symbol: marketIdentity.marketId ?? marketIdentity.symbol,
                    exchange: exchange,
                    interval: interval
                )
                let points = Self.sparklinePoints(from: snapshot.candles)
                guard points.count >= 2 else {
                    throw NetworkServiceError.parsingFailed("sparkline candle data is empty")
                }
                return SparklineLayerSnapshot(
                    interval: interval,
                    points: points,
                    pointCount: points.count,
                    fetchedAt: snapshot.meta.fetchedAt ?? Date(),
                    source: .candleSnapshot
                )
            }
            sparklineFetchTasksByKey[key] = task
            tasks.append((marketIdentity, key, task))
        }

        var results: [(marketIdentity: MarketIdentity, result: Result<SparklineLayerSnapshot, Error>)] = []
        for taskChunk in tasks.chunked(into: sparklineMaxConcurrentFetchCount) {
            guard Task.isCancelled == false else {
                break
            }
            let chunkResults = await withTaskGroup(
                of: (MarketIdentity, SparklineCacheKey, Result<SparklineLayerSnapshot, Error>).self,
                returning: [(MarketIdentity, SparklineCacheKey, Result<SparklineLayerSnapshot, Error>)].self
            ) { group in
                for request in taskChunk {
                    group.addTask {
                        do {
                            let snapshot = try await request.task.value
                            return (request.marketIdentity, request.key, .success(snapshot))
                        } catch {
                            return (request.marketIdentity, request.key, .failure(error))
                        }
                    }
                }

                var collected = [(MarketIdentity, SparklineCacheKey, Result<SparklineLayerSnapshot, Error>)]()
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for (marketIdentity, key, result) in chunkResults {
                switch result {
                case .success(let snapshot):
                    sparklineFetchTasksByKey[key] = nil
                    sparklineFailureCooldownUntilByKey[key] = nil
                    unsupportedSparklineMarketIdentitiesByExchange[marketIdentity.exchange, default: []].remove(marketIdentity)
                    results.append((marketIdentity, .success(snapshot)))
                case .failure(let error):
                    sparklineFetchTasksByKey[key] = nil
                    sparklineFailureCooldownUntilByKey[key] = Date().addingTimeInterval(sparklineFailureCooldownInterval)
                    if isUnsupportedSparklineError(error) {
                        unsupportedSparklineMarketIdentitiesByExchange[marketIdentity.exchange, default: []].insert(marketIdentity)
                    }
                    results.append((marketIdentity, .failure(error)))
                }
            }
        }
        return results
    }

    private func sparklineInterval(for symbol: String, exchange: Exchange) -> String {
        sparklineInterval(for: resolvedMarketIdentity(exchange: exchange, symbol: symbol))
    }

    private func sparklineInterval(for marketIdentity: MarketIdentity) -> String {
        let supported = supportedIntervalsByExchangeAndMarketIdentity[marketIdentity.exchange]?[marketIdentity]?.map { $0.lowercased() } ?? []
        for preferred in ["1h", "15m", "5m", "1m", "1d"] where supported.contains(preferred) {
            return preferred
        }
        return supported.first ?? "1h"
    }

    private nonisolated static func sparklinePoints(from candles: [CandleData]) -> [Double] {
        Array(candles.sorted { $0.time < $1.time }.map(\.close).filter { $0 > 0 }.suffix(24))
    }

    private func applySparklineLoadingPatch(
        marketIdentities: [MarketIdentity],
        exchange: Exchange,
        generation: Int,
        reason: String
    ) {
        guard let presentation = marketPresentationSnapshotsByExchange[exchange] else {
            return
        }
        guard presentation.generation == generation else {
            for marketIdentity in marketIdentities {
                recordStaleGraphPatchDrop(for: marketIdentity, reason: "older_epoch")
            }
            return
        }

        for marketIdentity in marketIdentities {
            guard let row = presentation.rows.first(where: { $0.marketIdentity == marketIdentity }) else {
                recordStaleGraphPatchDrop(for: marketIdentity)
                continue
            }

            if row.graphState.keepsVisibleGraph {
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(marketIdentity.logFields) action=preserve_graph reason=cell_rebind existingState=\(row.graphState)"
                )
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(marketIdentity.logFields) action=drop_reset reason=usable_graph_exists"
                )
            } else {
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(marketIdentity.logFields) action=preserve_graph reason=loading_patch existingState=\(row.graphState)"
                )
            }
        }
        _ = reason
    }

    @discardableResult
    private func applySparklinePatch(
        marketIdentity: MarketIdentity,
        exchange: Exchange,
        snapshot sparklineSnapshot: SparklineLayerSnapshot?,
        graphState: MarketRowGraphState,
        generation: Int,
        reason: String
    ) -> Bool {
        applySparklinePatches(
            [MarketSparklinePatch(
                marketIdentity: marketIdentity,
                snapshot: sparklineSnapshot,
                graphState: graphState,
                reason: reason
            )],
            exchange: exchange,
            generation: generation
        ) > 0
    }

#if DEBUG
    struct SparklineResolutionDebugState: Equatable {
        let source: String
        let detailLevel: MarketSparklineDetailLevel
        let pointCount: Int
        let sourceVersion: Int
        let graphState: MarketRowGraphState
    }

    func seedStableSparklineDisplayForTesting(
        marketIdentity: MarketIdentity,
        interval: String,
        points: [Double],
        graphState: MarketRowGraphState,
        sourceVersion: Int,
        updatedAt: Date = Date()
    ) {
        stableSparklineDisplaysByKey[MarketGraphBindingKey(
            marketIdentity: marketIdentity,
            interval: interval
        )] = StableSparklineDisplay(
            key: MarketGraphBindingKey(
                marketIdentity: marketIdentity,
                interval: interval
            ),
            points: points,
            pointCount: points.count,
            graphState: graphState,
            generation: marketPresentationGeneration,
            updatedAt: updatedAt,
            sourceVersion: sourceVersion
        )
    }

    func seedSparklineSnapshotForTesting(
        marketIdentity: MarketIdentity,
        interval: String,
        points: [Double],
        fetchedAt: Date = Date()
    ) {
        sparklineSnapshotsByKey[SparklineCacheKey(
            marketIdentity: marketIdentity,
            interval: interval
        )] = SparklineLayerSnapshot(
            interval: interval,
            points: points,
            pointCount: points.count,
            fetchedAt: fetchedAt,
            source: .candleSnapshot
        )
    }

    func clearSparklineSnapshotForTesting(
        marketIdentity: MarketIdentity,
        interval: String
    ) {
        sparklineSnapshotsByKey.removeValue(
            forKey: SparklineCacheKey(
                marketIdentity: marketIdentity,
                interval: interval
            )
        )
    }

    func visibleSparklineResolutionForTesting(
        marketIdentity: MarketIdentity
    ) -> SparklineResolutionDebugState? {
        let exchange = marketIdentity.exchange
        let cachedRow = marketPresentationSnapshotsByExchange[exchange]?.rows.first(where: {
            $0.marketIdentity == marketIdentity
        })
        let coin = cachedRow?.coin
            ?? marketsByExchange[exchange]?.first(where: { $0.marketIdentity(exchange: exchange) == marketIdentity })
            ?? tickerSnapshotCoinsByExchange[exchange]?.first(where: { $0.marketIdentity(exchange: exchange) == marketIdentity })
        guard let coin else {
            return nil
        }

        let resolution = Self.resolvedSparkline(
            snapshot: sparklineSnapshot(marketIdentity: marketIdentity),
            cachedRow: cachedRow,
            stableSparklineDisplay: stableSparklineDisplay(marketIdentity: marketIdentity),
            isLoading: loadingSparklineMarketIdentitiesByExchange[exchange]?.contains(marketIdentity) == true,
            isUnavailable: unavailableSparklineMarketIdentitiesByExchange[exchange]?.contains(marketIdentity) == true,
            preferDetailedVisibleGraph: true,
            staleInterval: sparklineCacheStaleInterval,
            now: Date(),
            hasResolvedBaseData: pricesByMarketIdentity[marketIdentity] != nil || cachedRow != nil
        )
        let quality = MarketSparklineQuality(
            graphState: resolution.graphState,
            points: resolution.points,
            pointCount: resolution.pointCount,
            sourceVersion: resolution.sourceVersion
        )
        return SparklineResolutionDebugState(
            source: resolution.source.logComponent,
            detailLevel: quality.detailLevel,
            pointCount: resolution.pointCount,
            sourceVersion: resolution.sourceVersion,
            graphState: resolution.graphState
        )
    }

    @discardableResult
    func applySparklinePatchForTesting(
        marketIdentity: MarketIdentity,
        exchange: Exchange,
        interval: String,
        points: [Double],
        graphState: MarketRowGraphState,
        reason: String
    ) -> Bool {
        let sparklineSnapshot = SparklineLayerSnapshot(
            interval: interval,
            points: points,
            pointCount: points.count,
            fetchedAt: Date(),
            source: .candleSnapshot
        )
        return applySparklinePatch(
            marketIdentity: marketIdentity,
            exchange: exchange,
            snapshot: sparklineSnapshot,
            graphState: graphState,
            generation: marketPresentationGeneration,
            reason: reason
        )
    }
#endif

    private func preferredSparklinePatch(
        existing: MarketSparklinePatch,
        incoming: MarketSparklinePatch
    ) -> MarketSparklinePatch {
        if let incomingSnapshot = incoming.snapshot, let existingSnapshot = existing.snapshot {
            let shouldReplace = shouldReplaceSparklineSnapshot(
                existing: existingSnapshot,
                incoming: incomingSnapshot,
                marketIdentity: incoming.marketIdentity
            )
            if shouldReplace {
                return incoming
            }
            return existing
        }
        if incoming.snapshot != nil {
            return incoming
        }
        if existing.snapshot != nil {
            return existing
        }

        let existingLiveScore = existing.graphState == .liveVisible ? 2 : (existing.graphState.keepsVisibleGraph ? 1 : 0)
        let incomingLiveScore = incoming.graphState == .liveVisible ? 2 : (incoming.graphState.keepsVisibleGraph ? 1 : 0)
        if existingLiveScore != incomingLiveScore {
            return incomingLiveScore > existingLiveScore ? incoming : existing
        }
        return incoming
    }

    private func preferredSymbolImagePatch(
        existing: MarketSymbolImagePatch,
        incoming: MarketSymbolImagePatch
    ) -> MarketSymbolImagePatch {
        if incoming.nextState.renderRank != existing.nextState.renderRank {
            return incoming.nextState.renderRank > existing.nextState.renderRank ? incoming : existing
        }
        return incoming
    }

    @discardableResult
    private func applySparklinePatches(
        _ patches: [MarketSparklinePatch],
        exchange: Exchange,
        generation: Int
    ) -> Int {
        guard patches.isEmpty == false,
              let presentation = marketPresentationSnapshotsByExchange[exchange] else {
            return 0
        }
        guard presentation.generation == generation else {
            for patch in patches {
                recordStaleGraphPatchDrop(for: patch.marketIdentity, reason: "older_epoch")
            }
            return 0
        }

        var coalescedPatches = [MarketIdentity: MarketSparklinePatch]()
        for patch in patches {
            if let current = coalescedPatches[patch.marketIdentity] {
                coalescedPatches[patch.marketIdentity] = preferredSparklinePatch(
                    existing: current,
                    incoming: patch
                )
            } else {
                coalescedPatches[patch.marketIdentity] = patch
            }
        }

        var enqueuedCount = 0
        for patch in coalescedPatches.values {
            guard presentation.rows.contains(where: { $0.marketIdentity == patch.marketIdentity }) else {
                recordStaleGraphPatchDrop(for: patch.marketIdentity)
                continue
            }
            if shouldDropSparklinePatchBeforeUIPromotion(
                patch,
                exchange: exchange,
                generation: generation,
                rows: presentation.rows
            ) {
                continue
            }
            if enqueueMarketRowPatch(
                marketIdentity: patch.marketIdentity,
                exchange: exchange,
                generation: generation,
                sparklinePatch: patch,
                symbolImagePatch: nil,
                tickerDisplayPatch: nil,
                rebuildReason: nil
            ) {
                enqueuedCount += 1
            }
        }
        return enqueuedCount
    }

    private func mergeCandleUpdate(_ payload: CandleStreamPayload) {
        var currentCandles = candlesState.value ?? []
        for incomingCandle in payload.candles {
            if let existingIndex = currentCandles.firstIndex(where: { $0.time == incomingCandle.time }) {
                currentCandles[existingIndex] = incomingCandle
            } else {
                currentCandles.append(incomingCandle)
            }
        }

        currentCandles.sort { $0.time < $1.time }
        let mappedInterval = resolvedChartInterval(
            requestedInterval: chartPeriod,
            symbol: payload.symbol,
            exchange: exchange
        )
        let key = chartRequestKey(exchange: exchange, symbol: payload.symbol, interval: mappedInterval)
        let entry = CandleCacheEntry(
            key: key,
            candles: currentCandles,
            meta: ResponseMeta(fetchedAt: Date(), isStale: false, warningMessage: nil, partialFailureMessage: nil),
            fetchedAt: Date()
        )
        candleCacheByKey[key] = entry
        if currentCandles.isEmpty == false {
            lastSuccessfulCandles[key] = entry
        }
        updateCandleState(
            currentCandles.isEmpty ? .empty : .loaded(currentCandles),
            exchange: exchange,
            symbol: payload.symbol,
            interval: mappedInterval,
            phase: "stream_patch"
        )
    }

    private func prepareCandlesForLive(
        _ candles: [CandleData],
        interval: String,
        seedPrice: Double?
    ) -> [CandleData] {
        let sortedCandles = candles.sorted { $0.time < $1.time }
        guard let liveSeedPrice = seedPrice ?? sortedCandles.last?.close else {
            return sortedCandles
        }

        let currentBucketStart = candleBucketStart(for: Date(), interval: interval)
        guard let lastCandle = sortedCandles.last else {
            return [
                CandleData(
                    time: currentBucketStart,
                    open: liveSeedPrice,
                    high: liveSeedPrice,
                    low: liveSeedPrice,
                    close: liveSeedPrice,
                    volume: 0
                )
            ]
        }

        let lastBucketStart = candleBucketStart(
            for: Date(timeIntervalSince1970: TimeInterval(lastCandle.time)),
            interval: interval
        )
        guard lastBucketStart < currentBucketStart else {
            return sortedCandles
        }

        var liveReadyCandles = sortedCandles
        liveReadyCandles.append(
            CandleData(
                time: currentBucketStart,
                open: lastCandle.close,
                high: max(lastCandle.close, liveSeedPrice),
                low: min(lastCandle.close, liveSeedPrice),
                close: liveSeedPrice,
                volume: 0
            )
        )
        return liveReadyCandles
    }

    private func applyLiveChartTrades(_ trades: [PublicTrade]) {
        let sortedTrades = trades.sorted {
            ($0.executedDate ?? Date.distantPast) < ($1.executedDate ?? Date.distantPast)
        }

        for trade in sortedTrades {
            applyLiveChartPriceUpdate(
                price: trade.price,
                quantity: trade.quantity,
                timestamp: trade.executedDate ?? Date()
            )
        }
    }

    private func applyLiveChartPriceUpdate(
        price: Double,
        quantity: Double,
        timestamp: Date
    ) {
        guard !price.isNaN, price > 0 else {
            return
        }

        let interval = chartPeriod.lowercased()
        var currentCandles = candlesState.value ?? []
        let bucketStart = candleBucketStart(for: timestamp, interval: interval)
        let volumeDelta = quantity > 0 ? max(Int(quantity.rounded()), 1) : 0

        if let lastIndex = currentCandles.indices.last {
            let lastCandle = currentCandles[lastIndex]
            let lastBucketStart = candleBucketStart(
                for: Date(timeIntervalSince1970: TimeInterval(lastCandle.time)),
                interval: interval
            )

            if lastBucketStart == bucketStart {
                currentCandles[lastIndex] = CandleData(
                    time: bucketStart,
                    open: lastCandle.open,
                    high: max(lastCandle.high, price),
                    low: min(lastCandle.low, price),
                    close: price,
                    volume: lastCandle.volume + volumeDelta
                )
            } else if lastBucketStart < bucketStart {
                currentCandles.append(
                    CandleData(
                        time: bucketStart,
                        open: lastCandle.close,
                        high: max(lastCandle.close, price),
                        low: min(lastCandle.close, price),
                        close: price,
                        volume: volumeDelta
                    )
                )
            } else if let existingIndex = currentCandles.firstIndex(where: { $0.time == bucketStart }) {
                let existingCandle = currentCandles[existingIndex]
                currentCandles[existingIndex] = CandleData(
                    time: bucketStart,
                    open: existingCandle.open,
                    high: max(existingCandle.high, price),
                    low: min(existingCandle.low, price),
                    close: price,
                    volume: existingCandle.volume + volumeDelta
                )
            }
        } else {
            currentCandles = [
                CandleData(
                    time: bucketStart,
                    open: price,
                    high: price,
                    low: price,
                    close: price,
                    volume: volumeDelta
                )
            ]
        }

        currentCandles.sort { $0.time < $1.time }
        let key = chartRequestKey(exchange: exchange, symbol: selectedCoin?.symbol ?? "-", interval: interval)
        let entry = CandleCacheEntry(
            key: key,
            candles: currentCandles,
            meta: ResponseMeta(fetchedAt: timestamp, isStale: false, warningMessage: nil, partialFailureMessage: nil),
            fetchedAt: timestamp
        )
        candleCacheByKey[key] = entry
        if currentCandles.isEmpty == false {
            lastSuccessfulCandles[key] = entry
        }
        updateCandleState(
            currentCandles.isEmpty ? .empty : .loaded(currentCandles),
            exchange: exchange,
            symbol: selectedCoin?.symbol ?? "-",
            interval: interval,
            phase: "trade_patch"
        )
    }

    private func candleBucketStart(for date: Date, interval: String) -> Int {
        let normalizedInterval = interval.lowercased()
        let calendar = Calendar(identifier: .gregorian)

        if normalizedInterval.hasSuffix("m"),
           let minutes = Int(normalizedInterval.dropLast()) {
            let seconds = max(minutes, 1) * 60
            return Int(date.timeIntervalSince1970) / seconds * seconds
        }

        if normalizedInterval.hasSuffix("h"),
           let hours = Int(normalizedInterval.dropLast()) {
            let seconds = max(hours, 1) * 60 * 60
            return Int(date.timeIntervalSince1970) / seconds * seconds
        }

        if normalizedInterval == "1d" {
            return Int(calendar.startOfDay(for: date).timeIntervalSince1970)
        }

        if normalizedInterval == "1w" {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let startOfWeek = calendar.date(from: components) ?? calendar.startOfDay(for: date)
            return Int(startOfWeek.timeIntervalSince1970)
        }

        return Int(date.timeIntervalSince1970)
    }

    private func applyOrderStreamUpdate(_ order: OrderRecord) {
        var orders = orderHistoryState.value ?? []
        if let existingIndex = orders.firstIndex(where: { $0.id == order.id }) {
            orders[existingIndex] = order
        } else {
            orders.insert(order, at: 0)
        }

        orderHistoryState = orders.isEmpty ? .empty : .loaded(orders)

        if case .loaded(let detail) = selectedOrderDetailState, detail.id == order.id {
            selectedOrderDetailState = .loaded(order)
        }
    }

    private func applyFillStreamUpdate(_ fill: TradeFill) {
        var fills = fillsState.value ?? []
        if fills.contains(where: { $0.id == fill.id }) == false {
            fills.insert(fill, at: 0)
        }
        fillsState = fills.isEmpty ? .empty : .loaded(Array(fills.prefix(20)))
    }

    private func prefillOrderPriceIfPossible() {
        guard orderHeaderPricePresentation.price != nil else {
            return
        }
        orderPrice = PriceFormatter.formatPrice(currentPrice)
    }

    private func refreshMarketStateForSelectedExchange(
        meta: ResponseMeta = ResponseMeta(
            fetchedAt: nil,
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil
        ),
        reason: String = "refresh_market_state"
    ) {
        if let activeSnapshot = activeMarketPresentationSnapshot,
           activeSnapshot.exchange == selectedExchange {
            _ = stageAndSwapMarketPresentationIfPossible(
                for: selectedExchange,
                requestContext: makeMarketRequestContext(for: selectedExchange),
                reason: reason,
                overrideMeta: meta
            )
        } else if activeMarketPresentationSnapshot == nil,
                  marketPresentationSnapshotsByExchange[selectedExchange] == nil {
            let hasAttemptedSnapshot = lastMarketCatalogFetchedAtByExchange[selectedExchange] != nil
                || lastTickerFetchedAtByExchange[selectedExchange] != nil
            if hasAttemptedSnapshot,
               marketsByExchange[selectedExchange] == nil,
               hasAnyTickerData(for: selectedExchange) == false {
                assignMarketState(.failed("데이터를 불러오지 못했어요. 잠시 후 다시 시도해주세요."))
                marketLoadState = .hardFailure
            } else {
                assignMarketState(.loading)
                marketLoadState = .initialLoading
            }
        }
        refreshMarketLoadState(reason: reason)
        refreshPublicStatusViewStates()
    }

    private func marketUniverseSnapshot(for exchange: Exchange) -> MarketUniverseSnapshot {
        let catalogCoins = marketsByExchange[exchange] ?? []
        let tickerSnapshotCoins = tickerSnapshotCoinsByExchange[exchange] ?? []
        let cachedCoins = provisionalCoins(for: exchange)
        let baseCoins: [CoinInfo]
        let source: MarketUniverseSource

        if !catalogCoins.isEmpty {
            baseCoins = catalogCoins
            source = .catalog
        } else if !tickerSnapshotCoins.isEmpty {
            baseCoins = tickerSnapshotCoins
            source = .tickerSnapshot
        } else {
            baseCoins = cachedCoins
            source = .cachedSnapshot
        }

        let tradableCoins = baseCoins.filter(\.isTradable)
        let isProvisional = source != .catalog
        let sortedTradableCoins = tradableCoins.sorted { leftCoin, rightCoin in
            let leftIdentity = leftCoin.marketIdentity(exchange: exchange)
            let rightIdentity = rightCoin.marketIdentity(exchange: exchange)
            let leftVolume = pricesByMarketIdentity[leftIdentity]?.volume ?? 0
            let rightVolume = pricesByMarketIdentity[rightIdentity]?.volume ?? 0
            if leftVolume == rightVolume {
                return leftIdentity.cacheKey < rightIdentity.cacheKey
            }
            return leftVolume > rightVolume
        }
        let tradableMarketIdentities = Set(sortedTradableCoins.map { $0.marketIdentity(exchange: exchange) })
        let droppedSymbols = baseCoins
            .map { $0.marketIdentity(exchange: exchange) }
            .filter { tradableMarketIdentities.contains($0) == false }
            .map(\.cacheKey)
        let filteredSymbols = Self.deduplicatedMarketIdentities(
            (filteredMarketIdentitiesByExchange[exchange] ?? [])
                + (filteredTickerIdentitiesByExchange[exchange] ?? [])
        )
        .map(\.cacheKey)
        let pendingSymbols = sortedTradableCoins.compactMap { coin in
            let marketIdentity = coin.marketIdentity(exchange: exchange)
            return pricesByMarketIdentity[marketIdentity] == nil ? marketIdentity.cacheKey : nil
        }
        let symbolsHash = stableSymbolHash(
            from: baseCoins.map {
                let marketIdentity = $0.marketIdentity(exchange: exchange)
                return "\(marketIdentity.cacheKey)|\($0.isTradable ? 1 : 0)|\($0.isKimchiComparable ? 1 : 0)"
            }
        )

        let signature = "\(source.rawValue)|\(baseCoins.count)|\(sortedTradableCoins.count)|\(symbolsHash)"
        if lastLoggedMarketUniverseSignatureByExchange[exchange] != signature {
            lastLoggedMarketUniverseSignatureByExchange[exchange] = signature
            AppLogger.debug(
                .lifecycle,
                "[MarketView] resolved market universe exchange=\(exchange.rawValue) source=\(source.rawValue) count=\(sortedTradableCoins.count)"
            )
        }

        return MarketUniverseSnapshot(
            exchange: exchange,
            source: source,
            serverCoins: baseCoins,
            tradableCoins: sortedTradableCoins,
            serverUniverseCount: baseCoins.count,
            tradableCount: sortedTradableCoins.count,
            droppedSymbols: droppedSymbols,
            filteredSymbols: filteredSymbols,
            pendingSymbols: pendingSymbols,
            symbolsHash: symbolsHash,
            isProvisional: isProvisional
        )
    }

    private func provisionalCoins(for exchange: Exchange) -> [CoinInfo] {
        let cachedRows = marketPresentationSnapshotsByExchange[exchange]?.rows ?? []
        let cachedRowsByMarketIdentity = cachedRows.reduce(into: [MarketIdentity: MarketRowViewState]()) { partialResult, row in
            if let existing = partialResult[row.marketIdentity] {
                partialResult[row.marketIdentity] = Self.preferredMarketRow(existing: existing, incoming: row)
            } else {
                partialResult[row.marketIdentity] = row
            }
        }

        return cachedRowsByMarketIdentity.values
            .sorted { $0.marketIdentity.cacheKey < $1.marketIdentity.cacheKey }
            .map { cachedRow in
            return CoinCatalog.coin(
                symbol: cachedRow.symbol,
                exchange: cachedRow.exchange,
                marketId: cachedRow.marketId,
                displayName: cachedRow.displayName,
                englishName: cachedRow.displayNameEn,
                imageURL: cachedRow.imageURL
            )
        }
    }

    private func resolvedMarketUniverse(for exchange: Exchange) -> [CoinInfo] {
        marketUniverseSnapshot(for: exchange).tradableCoins
    }

    private func resolvedSymbols(for exchange: Exchange) -> [String] {
        resolvedMarketUniverse(for: exchange).map(\.symbol)
    }

    private func resolvedComparableKimchiSymbols(for exchange: Exchange) async -> [String] {
        let buildInput = makeMarketPresentationBuildInput(for: exchange, overrideMeta: .empty)
        let supportedSymbols = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let comparableSymbols = Self.buildMarketPresentationSnapshot(from: buildInput)
                    .universe
                    .tradableCoins
                    .filter(\.isKimchiComparable)
                    .map(\.symbol)
                let prioritized = Self.prioritizedSymbols(
                    from: comparableSymbols,
                    selectedCoinSymbol: buildInput.selectedCoinIdentity?.symbol,
                    favoriteSymbols: buildInput.favoriteSymbols
                )
                continuation.resume(returning: prioritized)
            }
        }

        AppLogger.debug(
            .network,
            "[KimchiView] comparable canonical symbols count exchange=\(exchange.rawValue) count=\(supportedSymbols.count)"
        )

        return supportedSymbols
    }

    private func prioritizedSymbols(
        from symbols: [String],
        exchange: Exchange
    ) -> [String] {
        let availableSymbols = Set(symbols)
        var orderedSymbols = [String]()

        func append(_ symbol: String?) {
            guard let symbol, availableSymbols.contains(symbol), orderedSymbols.contains(symbol) == false else {
                return
            }
            orderedSymbols.append(symbol)
        }

        if selectedExchange == exchange {
            append(selectedCoin?.symbol)
        }

        favCoins.sorted().forEach { append($0) }
        CoinCatalog.fallbackTopSymbols.forEach { append($0) }
        symbols.forEach { append($0) }

        return orderedSymbols
    }

    private func makeMarketPresentationBuildInput(
        for exchange: Exchange,
        overrideMeta: ResponseMeta,
        referenceRows: [MarketRowViewState]? = nil
    ) -> MarketPresentationBuildInput {
        let normalizedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceRows = referenceRows ?? marketPresentationSnapshotsByExchange[exchange]?.rows ?? []
        return MarketPresentationBuildInput(
            exchange: exchange,
            generation: marketPresentationGeneration,
            assetImageClient: assetImageClient,
            catalogCoins: marketsByExchange[exchange] ?? [],
            tickerSnapshotCoins: tickerSnapshotCoinsByExchange[exchange] ?? [],
            cachedRows: referenceRows,
            pricesByMarketIdentity: pricesByMarketIdentity.filter { $0.key.exchange == exchange },
            sparklineSnapshotsByMarketIdentity: sparklineSnapshotsByMarketIdentity(
                for: exchange,
                additionalMarketIdentities: referenceRows.map(\.marketIdentity)
            ),
            stableSparklineDisplaysByMarketIdentity: stableSparklineDisplaysByMarketIdentity(for: exchange),
            loadingSparklineMarketIdentities: loadingSparklineMarketIdentitiesByExchange[exchange] ?? [],
            unavailableSparklineMarketIdentities: unavailableSparklineMarketIdentitiesByExchange[exchange] ?? [],
            filteredMarketIdentities: filteredMarketIdentitiesByExchange[exchange] ?? [],
            filteredTickerIdentities: filteredTickerIdentitiesByExchange[exchange] ?? [],
            visiblePriorityMarketIdentities: priorityVisibleSparklineMarketIdentities(
                for: exchange,
                rows: referenceRows
            ),
            selectedCoinIdentity: selectedExchange == exchange ? selectedCoin?.marketIdentity(exchange: exchange) : nil,
            favoriteSymbols: favCoins,
            shouldLimitFirstPaint: fullyHydratedMarketExchanges.contains(exchange) == false
                && marketFilter == .all
                && normalizedSearch.isEmpty,
            preservesVisibleOrderDuringHydration: marketFullHydrationPendingExchanges.contains(exchange),
            marketFirstPaintRowLimit: marketFirstPaintRowLimit,
            sparklineStaleInterval: sparklineCacheStaleInterval,
            now: Date(),
            catalogMeta: marketCatalogMetaByExchange[exchange] ?? .empty,
            tickerMeta: marketTickerMetaByExchange[exchange] ?? .empty,
            overrideMeta: overrideMeta
        )
    }

    private func prepareMarketPresentationSnapshot(
        from input: MarketPresentationBuildInput
    ) async -> MarketPresentationSnapshot {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.buildMarketPresentationSnapshot(from: input))
            }
        }
    }

    private nonisolated static func buildMarketPresentationSnapshot(
        from input: MarketPresentationBuildInput
    ) -> MarketPresentationSnapshot {
        let cachedRowsByMarketIdentity = input.cachedRows.reduce(into: [MarketIdentity: MarketRowViewState]()) { partialResult, row in
            if let existing = partialResult[row.marketIdentity] {
                partialResult[row.marketIdentity] = preferredMarketRow(existing: existing, incoming: row)
            } else {
                partialResult[row.marketIdentity] = row
            }
        }
        let cachedCoins = input.cachedRows.map { row in
            CoinCatalog.coin(
                symbol: row.symbol,
                exchange: row.exchange,
                marketId: row.marketId,
                displayName: row.displayName,
                englishName: row.displayNameEn,
                imageURL: row.imageURL,
                hasImage: row.hasImage,
                localAssetName: row.localAssetName
            )
        }
        let cachedCoinsByMarketIdentity = coinsByMarketIdentity(cachedCoins, exchange: input.exchange)
        let tickerSnapshotCoinsByMarketIdentity = coinsByMarketIdentity(
            input.tickerSnapshotCoins,
            exchange: input.exchange
        )

        let baseCoins: [CoinInfo]
        let source: MarketUniverseSource
        if !input.catalogCoins.isEmpty {
            baseCoins = input.catalogCoins.map { coin in
                let marketIdentity = coin.marketIdentity(exchange: input.exchange)
                let tickerMergedCoin = mergeCoinInfoPreservingImage(
                    primary: coin,
                    supplementary: tickerSnapshotCoinsByMarketIdentity[marketIdentity],
                    exchange: input.exchange
                )
                return mergeCoinInfoPreservingImage(
                    primary: tickerMergedCoin,
                    supplementary: cachedCoinsByMarketIdentity[marketIdentity],
                    exchange: input.exchange
                )
            }
            source = .catalog
        } else if !input.tickerSnapshotCoins.isEmpty {
            baseCoins = input.tickerSnapshotCoins.map { coin in
                let marketIdentity = coin.marketIdentity(exchange: input.exchange)
                return mergeCoinInfoPreservingImage(
                    primary: coin,
                    supplementary: cachedCoinsByMarketIdentity[marketIdentity],
                    exchange: input.exchange
                )
            }
            source = .tickerSnapshot
        } else {
            baseCoins = cachedCoins
            source = .cachedSnapshot
        }

        let tradableCoins = baseCoins.filter(\.isTradable)
        let sortedTradableCoins = tradableCoins.sorted { leftCoin, rightCoin in
            let leftIdentity = leftCoin.marketIdentity(exchange: input.exchange)
            let rightIdentity = rightCoin.marketIdentity(exchange: input.exchange)
            let leftVolume = input.pricesByMarketIdentity[leftIdentity]?.volume ?? 0
            let rightVolume = input.pricesByMarketIdentity[rightIdentity]?.volume ?? 0
            if leftVolume == rightVolume {
                return leftIdentity.cacheKey < rightIdentity.cacheKey
            }
            return leftVolume > rightVolume
        }
        let tradableMarketIdentities = Set(sortedTradableCoins.map { $0.marketIdentity(exchange: input.exchange) })
        let droppedSymbols = baseCoins
            .map { $0.marketIdentity(exchange: input.exchange) }
            .filter { tradableMarketIdentities.contains($0) == false }
            .map(\.cacheKey)
        let filteredSymbols = Self.deduplicatedMarketIdentities(
            input.filteredMarketIdentities + input.filteredTickerIdentities
        )
        .map(\.cacheKey)
        let pendingSymbols = sortedTradableCoins.compactMap { coin in
            let marketIdentity = coin.marketIdentity(exchange: input.exchange)
            return input.pricesByMarketIdentity[marketIdentity] == nil ? marketIdentity.cacheKey : nil
        }
        let symbolsHash = Self.stableSymbolHash(
            from: baseCoins.map {
                let marketIdentity = $0.marketIdentity(exchange: input.exchange)
                return "\(marketIdentity.cacheKey)|\($0.isTradable ? 1 : 0)|\($0.isKimchiComparable ? 1 : 0)"
            }
        )
        let universe = MarketUniverseSnapshot(
            exchange: input.exchange,
            source: source,
            serverCoins: baseCoins,
            tradableCoins: sortedTradableCoins,
            serverUniverseCount: baseCoins.count,
            tradableCount: sortedTradableCoins.count,
            droppedSymbols: droppedSymbols,
            filteredSymbols: filteredSymbols,
            pendingSymbols: pendingSymbols,
            symbolsHash: symbolsHash,
            isProvisional: source != .catalog
        )

        let presentationCoinIdentities: [MarketIdentity]
        if input.shouldLimitFirstPaint, sortedTradableCoins.count > input.marketFirstPaintRowLimit {
            presentationCoinIdentities = Array(
                sortedTradableCoins
                    .prefix(input.marketFirstPaintRowLimit)
                    .map { $0.marketIdentity(exchange: input.exchange) }
            )
        } else if input.preservesVisibleOrderDuringHydration, input.cachedRows.isEmpty == false {
            let existingPrefix = input.cachedRows
                .map(\.marketIdentity)
                .filter { tradableMarketIdentities.contains($0) }
            let existingPrefixSet = Set(existingPrefix)
            let remainingIdentities = sortedTradableCoins
                .map { $0.marketIdentity(exchange: input.exchange) }
                .filter { existingPrefixSet.contains($0) == false }
            presentationCoinIdentities = Self.deduplicatedMarketIdentities(
                existingPrefix + remainingIdentities
            )
        } else {
            presentationCoinIdentities = sortedTradableCoins.map { $0.marketIdentity(exchange: input.exchange) }
        }

        let coinsByMarketIdentity = coinsByMarketIdentity(sortedTradableCoins, exchange: input.exchange)
        let priorityDetailedMarketIdentities = Set(
            Self.deduplicatedMarketIdentities(
                input.visiblePriorityMarketIdentities
                    + Array(presentationCoinIdentities.prefix(input.marketFirstPaintRowLimit))
            )
        )
        let rows = presentationCoinIdentities.compactMap { marketIdentity -> MarketRowViewState? in
            guard let coin = coinsByMarketIdentity[marketIdentity] else { return nil }
            return Self.makeMarketRowViewState(
                for: coin,
                exchange: input.exchange,
                assetImageClient: input.assetImageClient,
                ticker: input.pricesByMarketIdentity[marketIdentity],
                cachedRow: cachedRowsByMarketIdentity[marketIdentity],
                favoriteSymbols: input.favoriteSymbols,
                sparklineSnapshot: input.sparklineSnapshotsByMarketIdentity[marketIdentity],
                stableSparklineDisplay: input.stableSparklineDisplaysByMarketIdentity[marketIdentity],
                isSparklineLoading: input.loadingSparklineMarketIdentities.contains(marketIdentity),
                isSparklineUnavailable: input.unavailableSparklineMarketIdentities.contains(marketIdentity),
                preferDetailedVisibleGraph: priorityDetailedMarketIdentities.contains(marketIdentity),
                sparklineStaleInterval: input.sparklineStaleInterval,
                now: input.now
            )
        }
        let meta = Self.combineMetas(
            input.catalogMeta,
            input.tickerMeta,
            input.overrideMeta
        )

        return MarketPresentationSnapshot(
            exchange: input.exchange,
            generation: input.generation,
            universe: universe,
            rows: rows,
            meta: meta
        )
    }

    private nonisolated static func coinsByMarketIdentity(
        _ coins: [CoinInfo],
        exchange: Exchange
    ) -> [MarketIdentity: CoinInfo] {
        coins.reduce(into: [MarketIdentity: CoinInfo]()) { partialResult, coin in
            let marketIdentity = coin.marketIdentity(exchange: exchange)
            if let existing = partialResult[marketIdentity] {
                partialResult[marketIdentity] = mergeCoinInfoPreservingImage(
                    primary: existing,
                    supplementary: coin,
                    exchange: exchange
                )
            } else {
                partialResult[marketIdentity] = coin
            }
        }
    }

    private nonisolated static func shouldCarryForwardGraph(
        existing: MarketRowViewState,
        over incoming: MarketRowViewState
    ) -> Bool {
        guard existing.marketIdentity == incoming.marketIdentity,
              existing.sparklineTimeframe == incoming.sparklineTimeframe else {
            return false
        }

        let existingQuality = sparklineQuality(for: existing)
        guard existingQuality.isUsableGraph else {
            return false
        }

        let incomingQuality = sparklineQuality(for: incoming)
        if incomingQuality.isUsableGraph == false {
            return true
        }
        if existingQuality.detailLevel == .retainedDetailed,
           incomingQuality.detailLevel == .liveDetailed {
            return false
        }
        if existing.graphState != .liveVisible,
           incoming.graphState == .liveVisible,
           incomingQuality.detailLevel.pathDetailRank >= existingQuality.detailLevel.pathDetailRank {
            return false
        }
        if incomingQuality.detailLevel == existingQuality.detailLevel,
           incomingQuality.sourceVersion > existingQuality.sourceVersion {
            return false
        }
        if incoming.sparklinePointCount == existing.sparklinePointCount,
           incoming.sparkline != existing.sparkline,
           incomingQuality.detailLevel.pathDetailRank >= existingQuality.detailLevel.pathDetailRank {
            return false
        }
        if incomingQuality.graphPathVersion != existingQuality.graphPathVersion,
           incomingQuality.detailLevel.pathDetailRank >= existingQuality.detailLevel.pathDetailRank,
           incoming.sparklinePointCount >= existing.sparklinePointCount {
            return false
        }

        return incomingQuality.promotionDecision(over: existingQuality).accepted == false
    }

    private nonisolated static func rowByCarryingForwardGraph(
        existing: MarketRowViewState,
        into incoming: MarketRowViewState
    ) -> MarketRowViewState {
        guard shouldCarryForwardGraph(existing: existing, over: incoming) else {
            return incoming
        }
        return incoming.replacingSparkline(
            points: existing.sparkline,
            pointCount: existing.sparklinePointCount,
            graphState: existing.graphState,
            sourceVersion: existing.sparklinePayload.sourceVersion
        )
    }

    private nonisolated static func preferredMarketRow(
        existing: MarketRowViewState,
        incoming: MarketRowViewState
    ) -> MarketRowViewState {
        if shouldCarryForwardGraph(existing: existing, over: incoming) {
            return rowByCarryingForwardGraph(existing: existing, into: incoming)
        }
        if shouldCarryForwardGraph(existing: incoming, over: existing) {
            return incoming
        }

        let existingDetail = existing.sparklinePayload.detailLevel
        let incomingDetail = incoming.sparklinePayload.detailLevel
        if incomingDetail.pathDetailRank != existingDetail.pathDetailRank {
            return incomingDetail.pathDetailRank > existingDetail.pathDetailRank ? incoming : existing
        }
        if incoming.graphState.preservationRank != existing.graphState.preservationRank {
            return incoming.graphState.preservationRank > existing.graphState.preservationRank ? incoming : existing
        }
        if incoming.sparklinePointCount != existing.sparklinePointCount {
            return incoming.sparklinePointCount > existing.sparklinePointCount ? incoming : existing
        }
        if incoming.hasPrice != existing.hasPrice {
            return incoming.hasPrice ? incoming : existing
        }
        if incoming.hasVolume != existing.hasVolume {
            return incoming.hasVolume ? incoming : existing
        }
        if incoming.symbolImageState.renderRank != existing.symbolImageState.renderRank {
            return incoming.symbolImageState.renderRank > existing.symbolImageState.renderRank ? incoming : existing
        }
        return incoming
    }

    private nonisolated static func mergeCoinInfoPreservingImage(
        primary: CoinInfo,
        supplementary: CoinInfo?,
        exchange: Exchange
    ) -> CoinInfo {
        guard let supplementary else {
            return primary
        }

        let mergedCoin = primary.merged(with: supplementary)
        if let previousImageURL = primary.imageURL,
           supplementary.imageURL == nil,
           mergedCoin.imageURL == previousImageURL {
            let marketIdentity = primary.marketIdentity(exchange: exchange)
            AppLogger.debug(
                .network,
                "[ImageDebug] \(marketIdentity.logFields) action=merge_preserved previous=\(previousImageURL) incoming=<nil>"
            )
        }
        return mergedCoin
    }

    private nonisolated static func makeMarketRowViewState(
        for coin: CoinInfo,
        exchange: Exchange,
        assetImageClient: AssetImageClient,
        ticker: TickerData?,
        cachedRow: MarketRowViewState?,
        favoriteSymbols: Set<String>,
        sparklineSnapshot: SparklineLayerSnapshot?,
        stableSparklineDisplay: StableSparklineDisplay?,
        isSparklineLoading: Bool,
        isSparklineUnavailable: Bool,
        preferDetailedVisibleGraph: Bool,
        sparklineStaleInterval: TimeInterval,
        now: Date
    ) -> MarketRowViewState {
        let marketIdentity = coin.marketIdentity(exchange: exchange)
        let cachedPriceText = cachedRow?.priceText ?? "—"
        let cachedChangeText = cachedRow?.changeText ?? "—"
        let cachedVolumeText = cachedRow?.volumeText ?? "—"
        let priceText = ticker.map { PriceFormatter.formatPrice($0.price) } ?? cachedPriceText
        let changeText = ticker.map { formatMarketChange($0.change) } ?? cachedChangeText
        let volumeText = ticker.map { PriceFormatter.formatVolume($0.volume) } ?? cachedVolumeText
        let hasResolvedTicker = ticker != nil || cachedRow != nil

        let graphResolution = resolvedSparkline(
            snapshot: sparklineSnapshot,
            cachedRow: cachedRow,
            stableSparklineDisplay: stableSparklineDisplay,
            isLoading: isSparklineLoading,
            isUnavailable: isSparklineUnavailable,
            preferDetailedVisibleGraph: preferDetailedVisibleGraph,
            staleInterval: sparklineStaleInterval,
            now: now,
            hasResolvedBaseData: hasResolvedTicker
        )
        let sparkline = graphResolution.points
        let sparklinePointCount = graphResolution.pointCount
        let sparklineTimeframe = sparklineSnapshot?.interval
            ?? stableSparklineDisplay?.key.interval
            ?? cachedRow?.sparklineTimeframe
            ?? "1h"
        let hasEnoughSparklineData = MarketSparklineRenderPolicy.hasHydratedGraph(
            points: sparkline,
            pointCount: sparklinePointCount
        )
        let sourceExchange = ticker?.sourceExchange ?? exchange
        let dataState: MarketRowDataState
        if ticker?.delivery == .live {
            dataState = .live
        } else if ticker != nil || cachedRow != nil {
            dataState = .snapshot
        } else {
            dataState = .pending
        }
        let baseFreshnessState = resolvedBaseFreshnessState(ticker: ticker, cachedRow: cachedRow)
        let graphState = graphResolution.graphState
        let chartPresentation = graphState.chartPresentation
        let symbolImageState = assetImageClient.renderState(
            for: AssetImageRequestDescriptor(
                marketIdentity: marketIdentity,
                symbol: coin.symbol,
                canonicalSymbol: coin.canonicalSymbol,
                imageURL: coin.iconURL,
                hasImage: coin.resolvedHasImage,
                localAssetName: coin.localAssetName
            )
        )
        if graphState.keepsVisibleGraph {
            switch graphResolution.source {
            case .displayCache:
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(marketIdentity.logFields) action=restore_visible_graph source=display_cache"
                )
            case .rowState:
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(marketIdentity.logFields) action=restore_visible_graph source=row_state"
                )
            case .snapshot, .unavailable, .placeholder, .none:
                break
            }
        }

        let isUp = ticker.map { $0.change >= 0 } ?? cachedRow?.isUp ?? true

        return MarketRowViewState(
            selectedExchange: exchange,
            exchange: exchange,
            sourceExchange: sourceExchange,
            coin: coin,
            priceText: priceText,
            changeText: changeText,
            volumeText: volumeText,
            sparkline: sparkline,
            sparklinePointCount: sparklinePointCount,
            sparklineTimeframe: sparklineTimeframe,
            hasEnoughSparklineData: hasEnoughSparklineData,
            chartPresentation: chartPresentation,
            baseFreshnessState: baseFreshnessState,
            graphState: graphState,
            symbolImageState: symbolImageState,
            isPricePlaceholder: hasResolvedTicker == false,
            isChangePlaceholder: hasResolvedTicker == false,
            isVolumePlaceholder: hasResolvedTicker == false,
            isUp: isUp,
            flash: ticker?.flash,
            isFavorite: favoriteSymbols.contains(coin.symbol),
            dataState: dataState,
            suppressesCoarseRetainedReuse: preferDetailedVisibleGraph,
            sparklineSourceVersion: graphResolution.sourceVersion
        )
    }

    private nonisolated static func resolvedBaseFreshnessState(
        ticker: TickerData?,
        cachedRow: MarketRowViewState?
    ) -> MarketRowFreshnessState {
        if let ticker {
            if ticker.delivery == .live {
                return .live
            }
            return ticker.isStale ? .stale : .refreshing
        }
        if cachedRow != nil {
            return .cached
        }
        return .pending
    }

    private nonisolated static func resolvedSparkline(
        snapshot: SparklineLayerSnapshot?,
        cachedRow: MarketRowViewState?,
        stableSparklineDisplay: StableSparklineDisplay?,
        isLoading: Bool,
        isUnavailable: Bool,
        preferDetailedVisibleGraph: Bool,
        staleInterval: TimeInterval,
        now: Date,
        hasResolvedBaseData: Bool
    ) -> (points: [Double], pointCount: Int, graphState: MarketRowGraphState, source: SparklineDisplayResolutionSource, sourceVersion: Int) {
        let snapshotCandidate: SparklineResolutionCandidate?

        if let snapshot {
            snapshotCandidate = SparklineResolutionCandidate(
                points: snapshot.points,
                pointCount: snapshot.pointCount,
                graphState: snapshot.graphState(staleInterval: staleInterval, now: now),
                source: .snapshot,
                sourceVersion: sparklineSourceVersion(from: snapshot.fetchedAt)
            )
        } else {
            snapshotCandidate = nil
        }

        let displayCacheCandidate: SparklineResolutionCandidate?
        if let stableSparklineDisplay, stableSparklineDisplay.hasRenderableGraph {
            let retainedState: MarketRowGraphState
            if isUnavailable {
                retainedState = .staleVisible
            } else if isLoading {
                retainedState = stableSparklineDisplay.graphState
            } else if now.timeIntervalSince(stableSparklineDisplay.updatedAt) > staleInterval {
                retainedState = .staleVisible
            } else {
                retainedState = stableSparklineDisplay.graphState
            }

            displayCacheCandidate = SparklineResolutionCandidate(
                points: stableSparklineDisplay.points,
                pointCount: stableSparklineDisplay.pointCount,
                graphState: retainedState,
                source: .displayCache,
                sourceVersion: stableSparklineDisplay.sourceVersion
            )
        } else {
            displayCacheCandidate = nil
        }

        let rowStateCandidate: SparklineResolutionCandidate?
        if let cachedRow,
           MarketSparklineRenderPolicy.hasRenderableGraph(
            points: cachedRow.sparkline,
            pointCount: cachedRow.sparklinePointCount
           ),
           cachedRow.graphState.keepsVisibleGraph {
            let retainedState: MarketRowGraphState
            switch cachedRow.graphState {
            case .liveVisible:
                if preferDetailedVisibleGraph {
                    retainedState = isUnavailable ? .staleVisible : .liveVisible
                } else {
                    retainedState = isUnavailable ? .staleVisible : (isLoading ? .liveVisible : .staleVisible)
                }
            case .cachedVisible:
                retainedState = .cachedVisible
            case .staleVisible:
                retainedState = .staleVisible
            case .none, .placeholder, .unavailable:
                retainedState = .cachedVisible
            }

            rowStateCandidate = SparklineResolutionCandidate(
                points: cachedRow.sparkline,
                pointCount: cachedRow.sparklinePointCount,
                graphState: retainedState,
                source: .rowState,
                sourceVersion: cachedRow.sparklinePayload.sourceVersion
            )
        } else {
            rowStateCandidate = nil
        }

        let hasRetainedUsableGraph = stableSparklineDisplay?.hasRenderableGraph == true
            || (cachedRow.map {
                MarketSparklineRenderPolicy.hasRenderableGraph(
                    points: $0.sparkline,
                    pointCount: $0.sparklinePointCount
                ) && $0.graphState.keepsVisibleGraph
            } ?? false)
        let graphLogFields = cachedRow?.marketLogFields
            ?? stableSparklineDisplay?.key.marketIdentity.logFields
            ?? "exchange=- marketId=- symbol=-"

        let resolutionSelection: SparklineResolutionSelection
        if preferDetailedVisibleGraph {
            resolutionSelection = preferredVisibleSparklineResolutionCandidate(
                snapshot: snapshotCandidate,
                rowState: rowStateCandidate,
                displayCache: displayCacheCandidate
            )
        } else {
            var preferredCandidate: SparklineResolutionCandidate?
            for candidate in [snapshotCandidate, displayCacheCandidate, rowStateCandidate].compactMap({ $0 }) {
                preferredCandidate = preferredSparklineResolutionCandidate(
                    existing: preferredCandidate,
                    incoming: candidate
                )
            }
            resolutionSelection = SparklineResolutionSelection(
                candidate: preferredCandidate,
                skippedDisplayCacheForNewerCandidate: false
            )
        }

        if let preferredCandidate = resolutionSelection.candidate {
            let preferredQuality = MarketSparklineQuality(
                graphState: preferredCandidate.graphState,
                points: preferredCandidate.points,
                pointCount: preferredCandidate.pointCount,
                sourceVersion: preferredCandidate.sourceVersion
            )
            if preferDetailedVisibleGraph {
                AppLogger.debug(
                    .network,
                    "[GraphVisibleDebug] \(graphLogFields) action=visible_candidate_selected source=\(preferredCandidate.source.logComponent) detailLevel=\(preferredQuality.detailLevel.cacheComponent) pointCount=\(preferredCandidate.pointCount)"
                )
                if resolutionSelection.skippedDisplayCacheForNewerCandidate {
                    AppLogger.debug(
                        .network,
                        "[GraphVisibleDebug] \(graphLogFields) action=restore_skipped_due_to_newer_candidate selectedSource=\(preferredCandidate.source.logComponent) detailLevel=\(preferredQuality.detailLevel.cacheComponent)"
                    )
                }
                if preferredCandidate.graphState.keepsVisibleGraph,
                   preferredCandidate.source != .displayCache {
                    AppLogger.debug(
                        .network,
                        "[GraphVisibleDebug] \(graphLogFields) action=visible_fast_lane_applied source=\(preferredCandidate.source.logComponent) detailLevel=\(preferredQuality.detailLevel.cacheComponent)"
                    )
                    if preferredQuality.isMinimumVisualQualityForFirstPaint {
                        AppLogger.debug(
                            .network,
                            "[GraphVisibleDebug] \(graphLogFields) action=visible_first_paint_promoted source=\(preferredCandidate.source.logComponent) detailLevel=\(preferredQuality.detailLevel.cacheComponent)"
                        )
                    }
                }
            }
            if preferDetailedVisibleGraph,
               preferredCandidate.source == .snapshot,
               preferredQuality.isLowInformationFirstPaintCandidate,
               hasRetainedUsableGraph == false {
                let holdReason = preferredQuality.isFlatLookingLowInformation
                    ? "flat_looking_low_information"
                    : "awaiting_visible_refine"
                AppLogger.debug(
                    .network,
                    "[GraphHoldDebug] \(graphLogFields) action=first_paint_low_information_allowed detailLevel=\(preferredQuality.detailLevel.cacheComponent) pointCount=\(preferredCandidate.pointCount)"
                )
                AppLogger.debug(
                    .network,
                    "[GraphEligibilityDebug] \(graphLogFields) action=allow reason=\(holdReason) detailLevel=\(preferredQuality.detailLevel.cacheComponent) pointCount=\(preferredCandidate.pointCount)"
                )
            }
            let preferredDetail = preferredQuality.detailLevel
            if preferredCandidate.graphState.keepsVisibleGraph,
               preferredCandidate.source == .displayCache || preferredCandidate.source == .rowState {
                let source = preferredCandidate.source == .displayCache ? "display_cache" : "row_state"
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] action=graph_state_rehydrated_from_cache source=\(source) detailLevel=\(preferredDetail.cacheComponent) pointCount=\(preferredCandidate.pointCount)"
                )
            }
            if preferDetailedVisibleGraph,
               preferredCandidate.graphState.keepsVisibleGraph,
               preferredDetail.isDetailed == false {
                AppLogger.debug(
                    .network,
                    "[GraphDetailDebug] action=placeholder_first_paint_blocked reason=usable_graph_exists detailLevel=\(preferredDetail.cacheComponent) pointCount=\(preferredCandidate.pointCount)"
                )
            }
            return (
                preferredCandidate.points,
                preferredCandidate.pointCount,
                preferredCandidate.graphState,
                preferredCandidate.source,
                preferredCandidate.sourceVersion
            )
        }

        switch cachedRow?.graphState {
        case .some(.unavailable):
            return ([], 0, .unavailable, .unavailable, 0)
        case .some(.none), .some(.placeholder), .some(.cachedVisible), .some(.liveVisible), .some(.staleVisible), nil:
            break
        }

        if isUnavailable {
            return ([], 0, .unavailable, .unavailable, 0)
        }

        if preferDetailedVisibleGraph,
           hasRetainedUsableGraph == false,
           hasResolvedBaseData {
            AppLogger.debug(
                .network,
                "[GraphVisibleDebug] \(graphLogFields) action=visible_first_paint_deferred_reason reason=awaiting_visible_refine"
            )
            AppLogger.debug(
                .network,
                "[GraphHoldDebug] \(graphLogFields) action=first_paint_held detailLevel=none pointCount=0"
            )
            AppLogger.debug(
                .network,
                "[GraphEligibilityDebug] \(graphLogFields) action=skip reason=awaiting_visible_refine detailLevel=none pointCount=0"
            )
            return ([], 0, .placeholder, .placeholder, 0)
        }

        return (
            [],
            0,
            hasResolvedBaseData ? .placeholder : .none,
            hasResolvedBaseData ? .placeholder : .none,
            0
        )
    }

    private nonisolated static func preferredSparklineResolutionCandidate(
        existing: SparklineResolutionCandidate?,
        incoming: SparklineResolutionCandidate
    ) -> SparklineResolutionCandidate {
        guard let existing else {
            return incoming
        }

        let existingQuality = MarketSparklineQuality(
            graphState: existing.graphState,
            points: existing.points,
            pointCount: existing.pointCount,
            sourceVersion: existing.sourceVersion
        )
        let incomingQuality = MarketSparklineQuality(
            graphState: incoming.graphState,
            points: incoming.points,
            pointCount: incoming.pointCount,
            sourceVersion: incoming.sourceVersion
        )
        let decision = incomingQuality.promotionDecision(over: existingQuality)
        let displayCacheFallbackOverrideBlocked = incoming.source == .displayCache
            && existing.source != .displayCache
            && existingQuality.isUsableGraph
            && incomingQuality.detailLevel.pathDetailRank <= existingQuality.detailLevel.pathDetailRank
        if decision.accepted,
           displayCacheFallbackOverrideBlocked == false {
            return incoming
        }
        guard decision.reason == "same_quality_skip" else {
            return existing
        }

        let existingSourceRank = sparklineResolutionSourceRank(existing.source)
        let incomingSourceRank = sparklineResolutionSourceRank(incoming.source)
        if incomingSourceRank != existingSourceRank {
            return incomingSourceRank > existingSourceRank ? incoming : existing
        }
        if incoming.sourceVersion != existing.sourceVersion {
            return incoming.sourceVersion > existing.sourceVersion ? incoming : existing
        }

        return existing
    }

    private nonisolated static func preferredVisibleSparklineResolutionCandidate(
        snapshot: SparklineResolutionCandidate?,
        rowState: SparklineResolutionCandidate?,
        displayCache: SparklineResolutionCandidate?
    ) -> SparklineResolutionSelection {
        var preferredCandidate: SparklineResolutionCandidate?
        for candidate in [snapshot, rowState].compactMap({ $0 }) {
            preferredCandidate = preferredVisibleSparklineResolutionCandidate(
                existing: preferredCandidate,
                incoming: candidate
            )
        }

        let preferredWithoutDisplayCache = preferredCandidate
        if let displayCache {
            if let preferredWithoutDisplayCache {
                let preferredQuality = MarketSparklineQuality(
                    graphState: preferredWithoutDisplayCache.graphState,
                    points: preferredWithoutDisplayCache.points,
                    pointCount: preferredWithoutDisplayCache.pointCount,
                    sourceVersion: preferredWithoutDisplayCache.sourceVersion
                )
                let displayQuality = MarketSparklineQuality(
                    graphState: displayCache.graphState,
                    points: displayCache.points,
                    pointCount: displayCache.pointCount,
                    sourceVersion: displayCache.sourceVersion
                )
                if preferredQuality.isUsableGraph,
                   preferredQuality.detailLevel.pathDetailRank >= displayQuality.detailLevel.pathDetailRank {
                    return SparklineResolutionSelection(
                        candidate: preferredWithoutDisplayCache,
                        skippedDisplayCacheForNewerCandidate: true
                    )
                }
            }
            preferredCandidate = preferredVisibleSparklineResolutionCandidate(
                existing: preferredCandidate,
                incoming: displayCache
            )
        }

        return SparklineResolutionSelection(
            candidate: preferredCandidate ?? displayCache,
            skippedDisplayCacheForNewerCandidate: displayCache != nil
                && preferredWithoutDisplayCache != nil
                && preferredCandidate?.source != .displayCache
        )
    }

    private nonisolated static func preferredVisibleSparklineResolutionCandidate(
        existing: SparklineResolutionCandidate?,
        incoming: SparklineResolutionCandidate
    ) -> SparklineResolutionCandidate {
        guard let existing else {
            return incoming
        }

        let existingQuality = MarketSparklineQuality(
            graphState: existing.graphState,
            points: existing.points,
            pointCount: existing.pointCount,
            sourceVersion: existing.sourceVersion
        )
        let incomingQuality = MarketSparklineQuality(
            graphState: incoming.graphState,
            points: incoming.points,
            pointCount: incoming.pointCount,
            sourceVersion: incoming.sourceVersion
        )
        let decision = incomingQuality.promotionDecision(over: existingQuality)
        if decision.accepted {
            return incoming
        }

        let incomingVisibleReason = incomingQuality.visibleBindableChangeReason(over: existingQuality)
        let existingVisibleReason = existingQuality.visibleBindableChangeReason(over: incomingQuality)
        let incomingSourceRank = visibleSparklineResolutionSourceRank(incoming.source)
        let existingSourceRank = visibleSparklineResolutionSourceRank(existing.source)

        if incomingVisibleReason != nil,
           existingVisibleReason == nil,
           incomingSourceRank >= existingSourceRank || existing.source == .displayCache {
            return incoming
        }
        if existingVisibleReason != nil,
           incomingVisibleReason == nil,
           existingSourceRank >= incomingSourceRank || incoming.source == .displayCache {
            return existing
        }

        if incomingQuality.visibleFirstPaintPriority != existingQuality.visibleFirstPaintPriority {
            return incomingQuality.visibleFirstPaintPriority > existingQuality.visibleFirstPaintPriority
                ? incoming
                : existing
        }

        if incoming.sourceVersion != existing.sourceVersion {
            return incoming.sourceVersion > existing.sourceVersion ? incoming : existing
        }
        if incomingSourceRank != existingSourceRank {
            return incomingSourceRank > existingSourceRank ? incoming : existing
        }
        if incomingQuality.graphState.preservationRank != existingQuality.graphState.preservationRank {
            return incomingQuality.graphState.preservationRank > existingQuality.graphState.preservationRank
                ? incoming
                : existing
        }
        if incoming.pointCount != existing.pointCount {
            return incoming.pointCount > existing.pointCount ? incoming : existing
        }

        return existing
    }

    private nonisolated static func sparklineResolutionSourceRank(
        _ source: SparklineDisplayResolutionSource
    ) -> Int {
        switch source {
        case .displayCache:
            return 3
        case .rowState:
            return 2
        case .snapshot:
            return 1
        case .unavailable, .placeholder, .none:
            return 0
        }
    }

    private nonisolated static func visibleSparklineResolutionSourceRank(
        _ source: SparklineDisplayResolutionSource
    ) -> Int {
        switch source {
        case .snapshot:
            return 3
        case .rowState:
            return 2
        case .displayCache:
            return 1
        case .unavailable, .placeholder, .none:
            return 0
        }
    }

    private nonisolated static func prioritizedSymbols(
        from symbols: [String],
        selectedCoinSymbol: String?,
        favoriteSymbols: Set<String>
    ) -> [String] {
        let availableSymbols = Set(symbols)
        var orderedSymbols = [String]()

        func append(_ symbol: String?) {
            guard let symbol, availableSymbols.contains(symbol), orderedSymbols.contains(symbol) == false else {
                return
            }
            orderedSymbols.append(symbol)
        }

        append(selectedCoinSymbol)
        favoriteSymbols.sorted().forEach { append($0) }
        CoinCatalog.fallbackTopSymbols.forEach { append($0) }
        symbols.forEach { append($0) }

        return orderedSymbols
    }

    private nonisolated static func prioritizedMarketIdentities(
        from coins: [CoinInfo],
        exchange: Exchange,
        selectedCoinIdentity: MarketIdentity?,
        favoriteSymbols: Set<String>
    ) -> [MarketIdentity] {
        let availableMarketIdentities = coins.map { $0.marketIdentity(exchange: exchange) }
        let coinByMarketIdentity = zip(availableMarketIdentities, coins).reduce(into: [MarketIdentity: CoinInfo]()) { partialResult, element in
            let (marketIdentity, coin) = element
            if let existing = partialResult[marketIdentity] {
                partialResult[marketIdentity] = mergeCoinInfoPreservingImage(
                    primary: existing,
                    supplementary: coin,
                    exchange: exchange
                )
            } else {
                partialResult[marketIdentity] = coin
            }
        }
        var orderedMarketIdentities = [MarketIdentity]()

        func append(_ marketIdentity: MarketIdentity?) {
            guard let marketIdentity,
                  coinByMarketIdentity[marketIdentity] != nil,
                  orderedMarketIdentities.contains(marketIdentity) == false else {
                return
            }
            orderedMarketIdentities.append(marketIdentity)
        }

        append(selectedCoinIdentity)

        for favoriteSymbol in favoriteSymbols.sorted() {
            for marketIdentity in availableMarketIdentities where marketIdentity.symbol == favoriteSymbol {
                append(marketIdentity)
            }
        }

        for fallbackSymbol in CoinCatalog.fallbackTopSymbols {
            for marketIdentity in availableMarketIdentities where marketIdentity.symbol == fallbackSymbol {
                append(marketIdentity)
            }
        }

        availableMarketIdentities.forEach { append($0) }
        return orderedMarketIdentities
    }

    private nonisolated static func stableSymbolHash(from items: [String]) -> String {
        items.sorted().joined(separator: ",")
    }

    private nonisolated static func deduplicatedSymbols(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        return symbols.filter { symbol in
            seen.insert(symbol).inserted
        }
    }

    private nonisolated static func formatMarketChange(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }

    private nonisolated static func combineMetas(
        _ catalogMeta: ResponseMeta,
        _ tickerMeta: ResponseMeta,
        _ overrideMeta: ResponseMeta
    ) -> ResponseMeta {
        let metas = [catalogMeta, tickerMeta, overrideMeta]
        let fetchedAt = metas.compactMap(\.fetchedAt).sorted(by: >).first
        let isStale = metas.contains(where: \.isStale)
        let warningMessage = metas.compactMap(\.warningMessage).first
        let partialFailureMessage = metas.compactMap(\.partialFailureMessage).first

        return ResponseMeta(
            fetchedAt: fetchedAt,
            isStale: isStale,
            warningMessage: warningMessage,
            partialFailureMessage: partialFailureMessage
        )
    }

    private func marketPresentationCoins(
        for universe: MarketUniverseSnapshot,
        exchange: Exchange
    ) -> [CoinInfo] {
        guard shouldUseLimitedMarketFirstPaint(for: exchange, totalCount: universe.tradableCount) else {
            return universe.tradableCoins
        }
        let limitedCoins = Array(universe.tradableCoins.prefix(marketFirstPaintRowLimit))

        AppLogger.debug(
            .lifecycle,
            "[MarketFirstPaint] exchange=\(exchange.rawValue) source=\(universe.source.rawValue) count=\(limitedCoins.count) total=\(universe.tradableCount)"
        )

        return limitedCoins
    }

    private func shouldUseLimitedMarketFirstPaint(for exchange: Exchange, totalCount: Int) -> Bool {
        guard totalCount > marketFirstPaintRowLimit else {
            return false
        }
        guard fullyHydratedMarketExchanges.contains(exchange) == false else {
            return false
        }
        guard marketFilter == .all else {
            return false
        }

        let normalizedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedSearch.isEmpty
    }

    private func requestedKimchiSymbols(
        for exchange: Exchange,
        comparableSymbols: [String],
        fullComparableSymbolsHash: String,
        forceRefresh: Bool
    ) -> [String] {
        guard comparableSymbols.count > kimchiFirstPaintSymbolLimit else {
            return comparableSymbols
        }
        guard fullyHydratedKimchiSymbolsHashByExchange[exchange] != fullComparableSymbolsHash else {
            return comparableSymbols
        }
        guard forceRefresh == false else {
            return comparableSymbols
        }

        let firstPaintSymbols = Array(comparableSymbols.prefix(kimchiFirstPaintSymbolLimit))
        AppLogger.debug(
            .network,
            "[KimchiRepresentative] selected exchange=\(exchange.rawValue) count=\(firstPaintSymbols.count) total=\(comparableSymbols.count)"
        )
        return firstPaintSymbols
    }

    private func scheduleKimchiHydrationIfNeeded(
        for exchange: Exchange,
        requestedSymbols: [String],
        fullComparableSymbols: [String],
        fullComparableSymbolsHash: String,
        reason: String
    ) {
        kimchiHydrationTask?.cancel()

        guard activeTab == .kimchi, currentKimchiDomesticExchange == exchange else {
            return
        }
        guard requestedSymbols.count < fullComparableSymbols.count else {
            fullyHydratedKimchiSymbolsHashByExchange[exchange] = fullComparableSymbolsHash
            return
        }

        kimchiHydrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.kimchiHydrationDelayNanoseconds)
            guard self.activeTab == .kimchi, self.currentKimchiDomesticExchange == exchange else { return }

            AppLogger.debug(
                .network,
                "[KimchiHydration] exchange=\(exchange.rawValue) firstPaint=\(requestedSymbols.count) total=\(fullComparableSymbols.count)"
            )
            await self.loadKimchiPremium(
                forceRefresh: true,
                reason: "\(reason)_hydrate_all",
                requestedSymbolsOverride: fullComparableSymbols
            )
        }
    }

    private func refreshMarketRowsForSelectedExchange(reason: String) {
        _ = stageAndSwapMarketPresentationIfPossible(
            for: selectedExchange,
            requestContext: makeMarketRequestContext(for: selectedExchange),
            reason: reason
        )
    }

    private func enqueueSymbolImagePatch(
        marketIdentity: MarketIdentity,
        exchange: Exchange,
        generation: Int,
        expectedImageURL: String?,
        nextState: MarketRowSymbolImageState,
        reason: String
    ) {
        guard marketIdentity.exchange == exchange,
              let presentation = marketPresentationSnapshotsByExchange[exchange],
              presentation.generation == generation,
              let row = presentation.rows.first(where: { $0.marketIdentity == marketIdentity }),
              row.imageURL == expectedImageURL,
              row.symbolImageState != nextState else {
            return
        }

        let patch = MarketSymbolImagePatch(
            marketIdentity: marketIdentity,
            exchange: exchange,
            generation: generation,
            expectedImageURL: expectedImageURL,
            nextState: nextState,
            reason: reason
        )
        _ = enqueueMarketRowPatch(
            marketIdentity: marketIdentity,
            exchange: exchange,
            generation: generation,
            sparklinePatch: nil,
            symbolImagePatch: patch,
            tickerDisplayPatch: nil,
            rebuildReason: nil
        )
    }

    @discardableResult
    private func enqueueMarketRowRebuildPatch(
        marketIdentity: MarketIdentity,
        exchange: Exchange,
        reason: String
    ) -> Bool {
        guard let presentation = marketPresentationSnapshotsByExchange[exchange],
              presentation.rows.contains(where: { $0.marketIdentity == marketIdentity }) else {
            return false
        }

        return enqueueMarketRowPatch(
            marketIdentity: marketIdentity,
            exchange: exchange,
            generation: presentation.generation,
            sparklinePatch: nil,
            symbolImagePatch: nil,
            tickerDisplayPatch: nil,
            rebuildReason: reason
        )
    }

    @discardableResult
    private func enqueueMarketRowPatch(
        marketIdentity: MarketIdentity,
        exchange: Exchange,
        generation: Int,
        sparklinePatch: MarketSparklinePatch?,
        symbolImagePatch: MarketSymbolImagePatch?,
        tickerDisplayPatch: MarketTickerDisplayPatch?,
        rebuildReason: String?
    ) -> Bool {
        guard marketIdentity.exchange == exchange,
              let presentation = marketPresentationSnapshotsByExchange[exchange],
              presentation.generation == generation,
              presentation.rows.contains(where: { $0.marketIdentity == marketIdentity }) else {
            if let sparklinePatch {
                recordStaleGraphPatchDrop(for: sparklinePatch.marketIdentity)
            }
            return false
        }

        var patches = pendingMarketRowPatchesByExchange[exchange] ?? [:]
        if var existingPatch = patches[marketIdentity] {
            let hadGraph = existingPatch.sparklinePatch != nil
            let hadImage = existingPatch.symbolImagePatch != nil
            let hadDisplay = existingPatch.tickerDisplayPatch != nil
            existingPatch.merge(
                sparklinePatch: sparklinePatch,
                symbolImagePatch: symbolImagePatch,
                tickerDisplayPatch: tickerDisplayPatch,
                rebuildReason: rebuildReason,
                preferredSparklinePatch: { [self] existing, incoming in
                    preferredSparklinePatch(existing: existing, incoming: incoming)
                },
                preferredImagePatch: { [self] existing, incoming in
                    preferredSymbolImagePatch(existing: existing, incoming: incoming)
                },
                preferredTickerDisplayPatch: { existing, incoming in
                    incoming
                }
            )
            if (existingPatch.sparklinePatch != nil || hadGraph),
               (existingPatch.symbolImagePatch != nil || hadImage || existingPatch.tickerDisplayPatch != nil || hadDisplay) {
                AppLogger.debug(
                    .network,
                    "[MarketRows] row_patch_coalesced graph=\(existingPatch.sparklinePatch != nil) image=\(existingPatch.symbolImagePatch != nil) display=\(existingPatch.tickerDisplayPatch != nil)"
                )
            }
            patches[marketIdentity] = existingPatch
        } else {
            var patch = PendingMarketRowPatch(
                marketIdentity: marketIdentity,
                exchange: exchange,
                generation: generation
            )
            patch.merge(
                sparklinePatch: sparklinePatch,
                symbolImagePatch: symbolImagePatch,
                tickerDisplayPatch: tickerDisplayPatch,
                rebuildReason: rebuildReason,
                preferredSparklinePatch: { [self] existing, incoming in
                    preferredSparklinePatch(existing: existing, incoming: incoming)
                },
                preferredImagePatch: { [self] existing, incoming in
                    preferredSymbolImagePatch(existing: existing, incoming: incoming)
                },
                preferredTickerDisplayPatch: { existing, incoming in
                    incoming
                }
            )
            patches[marketIdentity] = patch
        }
        pendingMarketRowPatchesByExchange[exchange] = patches

        guard marketRowPatchTask == nil else {
            return true
        }

        marketRowPatchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.marketRowPatchCoalesceNanoseconds)
            guard Task.isCancelled == false else {
                return
            }
            self.flushMarketRowPatches()
        }
        return true
    }

    private func flushMarketRowPatches() {
        marketRowPatchTask = nil
        let pendingPatches = pendingMarketRowPatchesByExchange
        pendingMarketRowPatchesByExchange.removeAll(keepingCapacity: true)

        var appliedCount = 0
        for (exchange, patchesByMarketIdentity) in pendingPatches {
            guard var presentation = marketPresentationSnapshotsByExchange[exchange] else {
                continue
            }

            var updatedRows = presentation.rows
            var reconfigureTraces = [MarketRowReconfigureTrace]()
            let rawPatchCount = patchesByMarketIdentity.values.reduce(0) { $0 + max($1.sourcePatchCount, 1) }
            for (index, row) in updatedRows.enumerated() {
                guard let patch = patchesByMarketIdentity[row.marketIdentity],
                      patch.exchange == exchange,
                      patch.generation == presentation.generation else {
                    continue
                }
                let result = applyPendingMarketRowPatch(
                    patch,
                    to: row,
                    exchange: exchange,
                    generation: presentation.generation
                )
                guard result.row != row else {
                    AppLogger.debug(
                        .network,
                        "[MarketRows] apply_suppressed reason=no_meaningful_visual_change exchange=\(exchange.rawValue) marketId=\(row.marketId ?? "-") symbol=\(row.symbol)"
                    )
                    continue
                }
                updatedRows[index] = result.row
                reconfigureTraces.append(result.trace)
            }

            guard reconfigureTraces.isEmpty == false else {
                continue
            }

            presentation = MarketPresentationSnapshot(
                exchange: presentation.exchange,
                generation: presentation.generation,
                universe: presentation.universe,
                rows: updatedRows,
                meta: presentation.meta
            )
            marketPresentationSnapshotsByExchange[exchange] = presentation
            persistStableSparklineDisplays(
                from: updatedRows,
                exchange: exchange,
                generation: presentation.generation
            )
            if activeMarketPresentationSnapshot?.exchange == exchange {
                activeMarketPresentationSnapshot = presentation
                applyMarketRowsDiff(
                    updatedRows,
                    reason: "coalesced_row_patch",
                    reconfigureTraces: reconfigureTraces
                )
                marketPresentationState = makeMarketPresentationState(
                    from: presentation,
                    previousExchange: nil,
                    sameExchangeStaleReuse: marketPresentationState.sameExchangeStaleReuse,
                    transitionPhase: marketPresentationState.transitionState.phase
                )
            }

            appliedCount += reconfigureTraces.count
            let savedCount = max(rawPatchCount - reconfigureTraces.count, 0)
            if savedCount > 0 {
                AppLogger.debug(
                    .network,
                    "[MarketRows] row_patch_batch_saved count=\(savedCount) exchange=\(exchange.rawValue)"
                )
            }
            let patchKinds: String
            if reconfigureTraces.allSatisfy({ $0.patchKind == "image_only" }) {
                patchKinds = "image_only"
            } else if reconfigureTraces.allSatisfy({ $0.patchKind == "graph_only" }) {
                patchKinds = "graph_only"
            } else {
                patchKinds = "mixed"
            }
            AppLogger.debug(
                .network,
                "[MarketRowsPatchDebug] exchange=\(exchange.rawValue) batchedCount=\(rawPatchCount) debounceWindowMs=\(marketRowPatchCoalesceNanoseconds / 1_000_000) patchKinds=\(patchKinds)"
            )
            recordMarketRowPatchMetrics(reconfigureTraces, exchange: exchange)
        }

        guard appliedCount > 0 else {
            return
        }

        AssetImageDebugClient.shared.log(
            .batchedVisiblePatch,
            marketIdentity: nil,
            category: .network,
            details: ["count": "\(appliedCount)"]
        )
        logAssetImageCoverageSummary(reason: "batched_visible_patch")
    }

    private func applyPendingMarketRowPatch(
        _ patch: PendingMarketRowPatch,
        to row: MarketRowViewState,
        exchange: Exchange,
        generation: Int
    ) -> (row: MarketRowViewState, trace: MarketRowReconfigureTrace) {
        var currentRow = row
        var reasons = [String]()

        if let tickerDisplayPatch = patch.tickerDisplayPatch {
            let updatedRow = currentRow.replacingTickerDisplay(
                sourceExchange: tickerDisplayPatch.sourceExchange,
                priceText: tickerDisplayPatch.priceText,
                changeText: tickerDisplayPatch.changeText,
                volumeText: tickerDisplayPatch.volumeText,
                isPricePlaceholder: tickerDisplayPatch.isPricePlaceholder,
                isChangePlaceholder: tickerDisplayPatch.isChangePlaceholder,
                isVolumePlaceholder: tickerDisplayPatch.isVolumePlaceholder,
                isUp: tickerDisplayPatch.isUp,
                flash: tickerDisplayPatch.flash,
                dataState: tickerDisplayPatch.dataState,
                baseFreshnessState: tickerDisplayPatch.baseFreshnessState
            )
            if updatedRow != currentRow {
                currentRow = updatedRow
                reasons.append(tickerDisplayPatch.reason)
            }
        }

        for rebuildReason in patch.rebuildReasons {
            let rebuiltRow = makeMarketRowViewState(
                for: currentRow.coin,
                exchange: exchange,
                cachedRow: currentRow
            )
            if rebuiltRow != currentRow {
                currentRow = rebuiltRow
                reasons.append(rebuildReason)
            }
        }

        if let sparklinePatch = patch.sparklinePatch,
           let patchedRow = applySparklinePatchToRow(
            sparklinePatch,
            row: currentRow,
            exchange: exchange,
            generation: generation
           ) {
            currentRow = patchedRow
            reasons.append("graph_refined_patch:\(sparklinePatch.reason)")
        }

        if let imagePatch = patch.symbolImagePatch,
           imagePatch.expectedImageURL == currentRow.imageURL,
           imagePatch.nextState != currentRow.symbolImageState {
            let previousImageState = currentRow.symbolImageState
            currentRow = currentRow.replacingSymbolImage(state: imagePatch.nextState)
            reasons.append("image_visible_patch:\(imagePatch.reason)")
            AssetImageDebugClient.shared.log(
                .visibleRowPatch,
                marketIdentity: imagePatch.marketIdentity,
                category: .network,
                details: [
                    "anchorMarketId": row.marketId ?? "-",
                    "from": previousImageState.rawValue,
                    "reason": imagePatch.reason,
                    "scope": "image_subview_state",
                    "symbol": row.canonicalSymbol,
                    "targetMarketId": imagePatch.marketIdentity.marketId ?? "-",
                    "to": imagePatch.nextState.rawValue
                ]
            )
        }

        let trace = MarketRowReconfigureTrace(
            marketIdentity: patch.marketIdentity,
            patchKind: patch.patchKind,
            reasons: reasons.isEmpty ? patch.reasons : reasons,
            previousGraphState: row.graphState,
            nextGraphState: currentRow.graphState,
            previousImageState: row.symbolImageState,
            nextImageState: currentRow.symbolImageState
        )
        return (currentRow, trace)
    }

    private func hasVisibleSparklineRefineIntent(
        for marketIdentity: MarketIdentity,
        generation: Int
    ) -> Bool {
        let key = sparklineCacheKey(marketIdentity: marketIdentity)
        if let scheduled = scheduledSparklineRequestsByKey[key],
           scheduled.generation == generation,
           scheduled.priority.rawValue >= SparklineQueuePriority.visibleCoarse.rawValue {
            return true
        }
        if sparklineFetchTasksByKey[key] != nil,
           visibleMarketIdentitiesByExchange[marketIdentity.exchange]?.contains(marketIdentity) == true {
            return true
        }
        return visibleMarketIdentitiesByExchange[marketIdentity.exchange]?.contains(marketIdentity) == true
    }

    private func shouldBypassFirstPaintHold(reason: String) -> Bool {
        reason.contains("failure")
            || reason == "hold_timeout_fallback"
    }

    private func scheduleFirstPaintHoldFallback(
        marketIdentity: MarketIdentity,
        exchange: Exchange,
        generation: Int,
        delay: TimeInterval
    ) {
        let key = stableSparklineDisplayKey(marketIdentity: marketIdentity)
        guard sparklineFirstPaintHoldFallbackTasksByKey[key] == nil else {
            return
        }

        sparklineFirstPaintHoldFallbackTasksByKey[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard Task.isCancelled == false else { return }
            self.sparklineFirstPaintHoldFallbackTasksByKey.removeValue(forKey: key)
            guard self.marketPresentationGeneration == generation,
                  self.selectedExchange == exchange,
                  let snapshot = self.sparklineSnapshot(marketIdentity: marketIdentity) else {
                return
            }
            _ = self.applySparklinePatch(
                marketIdentity: marketIdentity,
                exchange: exchange,
                snapshot: snapshot,
                graphState: snapshot.graphState(staleInterval: self.sparklineCacheStaleInterval, now: Date()),
                generation: generation,
                reason: "hold_timeout_fallback"
            )
        }
    }

    private func shouldHoldLowInformationFirstPaintPatch(
        marketIdentity: MarketIdentity,
        previousQuality: MarketSparklineQuality,
        nextQuality: MarketSparklineQuality,
        hasRetainedVisibleGraph: Bool,
        patchReason: String,
        exchange: Exchange,
        generation: Int
    ) -> Bool {
        guard shouldBypassFirstPaintHold(reason: patchReason) == false,
              previousQuality.isUsableGraph == false,
              hasRetainedVisibleGraph == false,
              nextQuality.isUsableGraph,
              nextQuality.isMinimumVisualQualityForFirstPaint == false,
              nextQuality.isLowInformationFirstPaintCandidate,
              isVisibleSparklineRedrawTarget(marketIdentity, exchange: exchange) == false,
              hasVisibleSparklineRefineIntent(for: marketIdentity, generation: generation) else {
            return false
        }

        let key = stableSparklineDisplayKey(marketIdentity: marketIdentity)
        let now = Date()
        let startedAt = sparklineFirstPaintHoldStartedAtByKey[key] ?? now
        sparklineFirstPaintHoldStartedAtByKey[key] = startedAt
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed < sparklineFirstPaintHoldInterval else {
            sparklineFirstPaintHoldStartedAtByKey.removeValue(forKey: key)
            sparklineFirstPaintHoldFallbackTasksByKey[key]?.cancel()
            sparklineFirstPaintHoldFallbackTasksByKey.removeValue(forKey: key)
            AppLogger.debug(
                .network,
                "[GraphHoldDebug] \(marketIdentity.logFields) action=hold_timeout_fallback_painted detailLevel=\(nextQuality.detailLevel.cacheComponent) pointCount=\(nextQuality.pointCount)"
            )
            return false
        }

        scheduleFirstPaintHoldFallback(
            marketIdentity: marketIdentity,
            exchange: exchange,
            generation: generation,
            delay: sparklineFirstPaintHoldInterval - elapsed
        )
        AppLogger.debug(
            .network,
            "[GraphHoldDebug] \(marketIdentity.logFields) action=first_paint_held detailLevel=\(nextQuality.detailLevel.cacheComponent) pointCount=\(nextQuality.pointCount)"
        )
        AppLogger.debug(
            .network,
            "[GraphEligibilityDebug] \(marketIdentity.logFields) action=skip reason=\(nextQuality.isFlatLookingLowInformation ? "flat_looking_low_information" : "awaiting_visible_refine") detailLevel=\(nextQuality.detailLevel.cacheComponent) pointCount=\(nextQuality.pointCount)"
        )
        return true
    }

    private func visibleSparklineRedrawReason(
        previousRow: MarketRowViewState,
        nextRow: MarketRowViewState,
        patchReason: String
    ) -> String? {
        guard isVisibleSparklinePatchLane(patchReason)
            || isVisibleSparklineRedrawTarget(previousRow.marketIdentity, exchange: previousRow.exchange) else {
            return nil
        }

        let previousQuality = Self.sparklineQuality(for: previousRow)
        let nextQuality = Self.sparklineQuality(for: nextRow)
        guard nextQuality.isUsableGraph else {
            return nil
        }

        if previousQuality.isUsableGraph == false
            || previousRow.sparklinePayload.hasRenderableGraph == false {
            return "blank_or_placeholder_to_live"
        }
        if previousQuality.detailLevel == .retainedDetailed,
           nextQuality.detailLevel == .liveDetailed {
            return "retained_to_live"
        }
        if previousRow.graphState != .liveVisible,
           nextRow.graphState == .liveVisible,
           nextQuality.detailLevel.isDetailed {
            return "retained_to_live"
        }
        if previousRow.sparklinePointCount == nextRow.sparklinePointCount,
           previousRow.sparkline != nextRow.sparkline,
           nextQuality.detailLevel.pathDetailRank >= previousQuality.detailLevel.pathDetailRank {
            return "points_changed_same_count"
        }
        if previousRow.sparkline != nextRow.sparkline,
           nextQuality.detailLevel.pathDetailRank >= previousQuality.detailLevel.pathDetailRank,
           nextRow.sparklinePointCount >= previousRow.sparklinePointCount {
            return "points_changed"
        }
        if nextQuality.detailLevel == previousQuality.detailLevel,
           (
               nextQuality.graphPathVersion != previousQuality.graphPathVersion
                   || nextQuality.renderVersion != previousQuality.renderVersion
                   || nextQuality.sourceVersion > previousQuality.sourceVersion
           ) {
            return "newer_render_signature"
        }
        if nextRow.graphState == .liveVisible,
           previousRow.graphState != .liveVisible,
           nextQuality.detailLevel.pathDetailRank >= previousQuality.detailLevel.pathDetailRank {
            return "live_path_arrived"
        }
        return nil
    }

    private func reconcileVisibleSparklines(
        exchange: Exchange,
        reason: String
    ) {
        guard activeTab == .market,
              selectedExchange == exchange,
              var presentation = marketPresentationSnapshotsByExchange[exchange],
              presentation.rows.isEmpty == false else {
            return
        }

        let visibleIdentities = visibleSparklineReconcileIdentities(
            for: exchange,
            rows: presentation.rows
        )
        guard visibleIdentities.isEmpty == false else {
            return
        }

        AppLogger.debug(
            .network,
            "[GraphVisibleDebug] exchange=\(exchange.rawValue) action=visible_reconcile_started reason=\(reason) count=\(visibleIdentities.count)"
        )

        let visibleSet = Set(visibleIdentities)
        var updatedRows = presentation.rows
        var traces = [MarketRowReconfigureTrace]()

        for (index, row) in presentation.rows.enumerated() where visibleSet.contains(row.marketIdentity) {
            let rebuiltRow = makeMarketRowViewState(
                for: row.coin,
                exchange: exchange,
                cachedRow: row
            )
            let previousQuality = Self.sparklineQuality(for: row)
            let rebuiltQuality = Self.sparklineQuality(for: rebuiltRow)
            guard let redrawReason = visibleSparklineRedrawReason(
                previousRow: row,
                nextRow: rebuiltRow,
                patchReason: "visible_reconcile"
            ) else {
                continue
            }
            guard rebuiltRow != row else {
                continue
            }

            AppLogger.debug(
                .network,
                "[GraphPolicyDebug] screen=list oldDetail=\(previousQuality.detailLevel.cacheComponent) newDetail=\(rebuiltQuality.detailLevel.cacheComponent) accepted=true rejectReason=- reason=visible_reconcile:\(redrawReason)"
            )
            updatedRows[index] = rebuiltRow
            traces.append(
                MarketRowReconfigureTrace(
                    marketIdentity: row.marketIdentity,
                    patchKind: "graph_only",
                    reasons: ["visible_reconcile:\(redrawReason)"],
                    previousGraphState: row.graphState,
                    nextGraphState: rebuiltRow.graphState,
                    previousImageState: row.symbolImageState,
                    nextImageState: rebuiltRow.symbolImageState
                )
            )
            if redrawReason == "retained_to_live" {
                AppLogger.debug(
                    .network,
                    "[GraphVisibleDebug] \(row.marketLogFields) action=retained_to_live_visible_upgrade reason=\(reason)"
                )
            }
            AppLogger.debug(
                .network,
                "[GraphApplyDebug] screen=list renderVersion=\(rebuiltRow.graphRenderVersion) applied=true reason=visible_reconcile:\(redrawReason)"
            )
        }

        guard traces.isEmpty == false else {
            return
        }

        presentation = MarketPresentationSnapshot(
            exchange: presentation.exchange,
            generation: presentation.generation,
            universe: presentation.universe,
            rows: updatedRows,
            meta: presentation.meta
        )
        marketPresentationSnapshotsByExchange[exchange] = presentation
        persistStableSparklineDisplays(
            from: updatedRows,
            exchange: exchange,
            generation: presentation.generation
        )
        if activeMarketPresentationSnapshot?.exchange == exchange {
            activeMarketPresentationSnapshot = presentation
        }
        marketVisibleGraphPatchCountByExchange[exchange, default: 0] += traces.count
        AppLogger.debug(
            .network,
            "[GraphVisibleDebug] exchange=\(exchange.rawValue) action=visible_reconcile_applied reason=\(reason) count=\(traces.count)"
        )
        applyMarketRowsDiff(
            updatedRows,
            reason: "visible_reconcile:\(reason)",
            reconfigureTraces: traces
        )
    }

    private func applySparklinePatchToRow(
        _ patch: MarketSparklinePatch,
        row previousRow: MarketRowViewState,
        exchange: Exchange,
        generation: Int
    ) -> MarketRowViewState? {
        if previousRow.exchange != exchange || previousRow.sparklineTimeframe != sparklineInterval(for: patch.marketIdentity) {
            recordStaleGraphPatchDrop(for: patch.marketIdentity)
            return nil
        }
        if let snapshot = patch.snapshot,
           snapshot.interval != previousRow.sparklineTimeframe {
            recordStaleGraphPatchDrop(for: patch.marketIdentity)
            return nil
        }

        let retainedDisplay = stableSparklineDisplay(marketIdentity: patch.marketIdentity)
        let hasRetainedVisibleGraph = retainedDisplay?.hasRenderableGraph == true
            || (previousRow.graphState.keepsVisibleGraph
                && MarketSparklineRenderPolicy.hasRenderableGraph(
                    points: previousRow.sparkline,
                    pointCount: previousRow.sparklinePointCount
                ))

        let retainedPoints = retainedDisplay?.points ?? previousRow.sparkline
        let retainedPointCount = retainedDisplay?.pointCount ?? previousRow.sparklinePointCount
        if patch.reason.contains("failure"), hasRetainedVisibleGraph {
            AppLogger.debug(
                .network,
                "[GraphEligibilityDebug] \(patch.marketIdentity.logFields) action=keep_stale_visible reason=refresh_failed existingDetail=\(previousRow.sparklinePayload.detailLevel.cacheComponent) pointCount=\(previousRow.sparklinePointCount)"
            )
        }

        let nextGraphState: MarketRowGraphState
        let nextPoints: [Double]
        let nextPointCount: Int
        let nextSourceVersion: Int

        if let snapshot = patch.snapshot {
            let snapshotHasRenderableGraph = MarketSparklineRenderPolicy.hasRenderableGraph(
                points: snapshot.points,
                pointCount: snapshot.pointCount
            )
            let snapshotState = snapshot.graphState(staleInterval: sparklineCacheStaleInterval, now: Date())
            if snapshotHasRenderableGraph {
                switch patch.graphState {
                case .liveVisible, .cachedVisible:
                    nextGraphState = patch.graphState
                case .staleVisible, .unavailable:
                    nextGraphState = .staleVisible
                case .none, .placeholder:
                    nextGraphState = snapshotState
                }
            } else {
                nextGraphState = previousRow.hasPrice || previousRow.hasVolume ? .placeholder : .none
            }
            nextPoints = snapshot.points
            nextPointCount = snapshot.pointCount
            nextSourceVersion = Self.sparklineSourceVersion(from: snapshot.fetchedAt)
        } else if hasRetainedVisibleGraph {
            switch patch.graphState {
            case .liveVisible:
                nextGraphState = .liveVisible
            case .cachedVisible:
                nextGraphState = .cachedVisible
            case .staleVisible, .unavailable:
                nextGraphState = .staleVisible
            case .none, .placeholder:
                nextGraphState = retainedDisplay?.graphState ?? previousRow.graphState
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(patch.marketIdentity.logFields) action=preserve_graph reason=cell_rebind existingState=\(previousRow.graphState)"
                )
            }
            nextPoints = retainedPoints
            nextPointCount = retainedPointCount
            nextSourceVersion = retainedDisplay?.sourceVersion ?? previousRow.sparklinePayload.sourceVersion
        } else {
            switch patch.graphState {
            case .unavailable:
                nextGraphState = .unavailable
                nextPoints = []
                nextPointCount = 0
                nextSourceVersion = 0
            case .cachedVisible, .liveVisible, .staleVisible:
                nextGraphState = patch.graphState
                nextPoints = patch.snapshot?.points ?? previousRow.sparkline
                nextPointCount = patch.snapshot?.pointCount ?? previousRow.sparklinePointCount
                nextSourceVersion = patch.snapshot.map { Self.sparklineSourceVersion(from: $0.fetchedAt) }
                    ?? previousRow.sparklinePayload.sourceVersion
            case .none, .placeholder:
                nextGraphState = previousRow.hasPrice || previousRow.hasVolume ? .placeholder : .none
                nextPoints = []
                nextPointCount = 0
                nextSourceVersion = 0
            }
        }

        let previousQuality = Self.sparklineQuality(for: previousRow)
        let nextQuality = MarketSparklineQuality(
            graphState: nextGraphState,
            points: nextPoints,
            pointCount: nextPointCount,
            sourceVersion: nextSourceVersion
        )
        if shouldHoldLowInformationFirstPaintPatch(
            marketIdentity: patch.marketIdentity,
            previousQuality: previousQuality,
            nextQuality: nextQuality,
            hasRetainedVisibleGraph: hasRetainedVisibleGraph,
            patchReason: patch.reason,
            exchange: exchange,
            generation: generation
        ) {
            return nil
        }
        let decision = nextQuality.promotionDecision(over: previousQuality)
        Self.logGraphQualityDecision(
            marketIdentity: patch.marketIdentity,
            existing: previousQuality,
            incoming: nextQuality,
            decision: decision
        )
        let candidateRow = previousRow.replacingSparkline(
            points: nextPoints,
            pointCount: nextPointCount,
            graphState: nextGraphState,
            sourceVersion: nextSourceVersion
        )
        let visibleRedrawReason = visibleSparklineRedrawReason(
            previousRow: previousRow,
            nextRow: candidateRow,
            patchReason: patch.reason
        )
        let acceptedByPolicy = decision.accepted || visibleRedrawReason != nil
        AppLogger.debug(
            .network,
            "[GraphPolicyDebug] screen=list oldDetail=\(previousQuality.detailLevel.cacheComponent) newDetail=\(nextQuality.detailLevel.cacheComponent) accepted=\(acceptedByPolicy) rejectReason=\(decision.accepted ? "-" : decision.reason) reason=\(patch.reason)"
        )
        if decision.accepted == false,
           let visibleRedrawReason {
            AppLogger.debug(
                .network,
                "[GraphVisibleDebug] \(patch.marketIdentity.logFields) action=redraw_allowed_despite_state_skip stateReason=\(decision.reason) redrawReason=\(visibleRedrawReason)"
            )
            if visibleRedrawReason == "retained_to_live" {
                AppLogger.debug(
                    .network,
                    "[GraphVisibleDebug] \(patch.marketIdentity.logFields) action=retained_to_live_visible_upgrade reason=\(patch.reason)"
                )
            }
        }
        guard decision.accepted || visibleRedrawReason != nil else {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(patch.marketIdentity.logFields) action=redraw_skipped reason=\(decision.reason == "same_quality_skip" ? "same_quality_patch_skipped" : "quality_downgrade_blocked") oldDetail=\(previousQuality.detailLevel.cacheComponent) newDetail=\(nextQuality.detailLevel.cacheComponent)"
            )
            AppLogger.debug(
                .network,
                "[GraphApplyDebug] screen=list renderVersion=\(candidateRow.graphRenderVersion) applied=false reason=\(decision.reason)"
            )
            noteSparklineNoImprovement(for: patch.marketIdentity)
            return nil
        }

        AppLogger.debug(
            .network,
            "[GraphDetailDebug] \(patch.marketIdentity.logFields) action=refined_patch_received oldDetail=\(previousQuality.detailLevel.cacheComponent) newDetail=\(nextQuality.detailLevel.cacheComponent) oldPointCount=\(previousRow.sparklinePointCount) newPointCount=\(nextPointCount)"
        )

        let isFreshnessOnlyVisiblePatch = previousRow.graphState.keepsVisibleGraph
            && nextGraphState.keepsVisibleGraph
            && previousRow.sparkline == nextPoints
            && previousRow.sparklinePointCount == nextPointCount
            && previousQuality.detailLevel == nextQuality.detailLevel
            && previousRow.graphState == nextGraphState
            && previousRow.sparklinePayload.sourceVersion == nextSourceVersion
        if isFreshnessOnlyVisiblePatch {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(patch.marketIdentity.logFields) action=redraw_skipped reason=freshness_only_visible_patch_suppressed oldState=\(previousRow.graphState) newState=\(nextGraphState)"
            )
            AppLogger.debug(
                .network,
                "[GraphApplyDebug] screen=list renderVersion=\(candidateRow.graphRenderVersion) applied=false reason=freshness_only_visible_patch_suppressed"
            )
            noteSparklineNoImprovement(for: patch.marketIdentity)
            return nil
        }

        let updatedRow = candidateRow
        guard updatedRow != previousRow else {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(patch.marketIdentity.logFields) action=redraw_skipped reason=detailed_same_signature detailLevel=\(previousQuality.detailLevel.cacheComponent) pointCount=\(previousRow.sparklinePointCount)"
            )
            AppLogger.debug(
                .network,
                "[GraphApplyDebug] screen=list renderVersion=\(candidateRow.graphRenderVersion) applied=false reason=detailed_same_signature"
            )
            noteSparklineNoImprovement(for: patch.marketIdentity)
            return nil
        }

        AppLogger.debug(
            .network,
            "[GraphScrollDebug] \(patch.marketIdentity.logFields) action=apply_patch from=\(previousRow.graphState) to=\(nextGraphState)"
        )
        AppLogger.debug(
            .network,
            "[GraphDetailDebug] \(patch.marketIdentity.logFields) action=refined_patch_applied renderVersion=\(updatedRow.graphRenderVersion) pathVersion=\(updatedRow.graphPathVersion)"
        )
        AppLogger.debug(
            .network,
            "[GraphApplyDebug] screen=list renderVersion=\(updatedRow.graphRenderVersion) applied=true reason=\(patch.reason)"
        )
        AppLogger.debug(
            .network,
            "[GraphPipeline] \(patch.marketIdentity.logFields) generation=\(generation) phase=row_patch state=\(nextGraphState) reason=\(patch.reason) scope=graph_subview_payload"
        )
        clearSparklineNoImprovement(for: patch.marketIdentity)
        if sparklineFirstPaintHoldStartedAtByKey[stableSparklineDisplayKey(marketIdentity: patch.marketIdentity)] != nil,
           nextQuality.isMinimumVisualQualityForFirstPaint {
            AppLogger.debug(
                .network,
                "[GraphHoldDebug] \(patch.marketIdentity.logFields) action=held_paint_promoted_to_live detailLevel=\(nextQuality.detailLevel.cacheComponent) pointCount=\(nextQuality.pointCount)"
            )
        }
        clearSparklineFirstPaintHold(for: patch.marketIdentity)
        return updatedRow
    }

    private func recordMarketRowPatchMetrics(
        _ traces: [MarketRowReconfigureTrace],
        exchange: Exchange
    ) {
        guard traces.isEmpty == false else {
            return
        }

        var countsByKind = [String: Int]()
        for trace in traces {
            countsByKind[trace.patchKind, default: 0] += 1
            switch trace.patchKind {
            case "graph_only":
                MarketPerformanceDebugClient.shared.increment(.graphOnlyPatch)
            case "image_only":
                MarketPerformanceDebugClient.shared.increment(.imageOnlyPatch)
            case "flash_only":
                MarketPerformanceDebugClient.shared.increment(.flashOnlyPatch)
            case "ticker_display_only":
                break
            case "base_ticker_refresh":
                MarketPerformanceDebugClient.shared.increment(.baseTickerRefresh)
            default:
                MarketPerformanceDebugClient.shared.increment(.coalescedPatch)
            }
            AppLogger.debug(
                .lifecycle,
                "[MarketRows] reconfigure_reason \(trace.marketIdentity.logFields) scope=\(trace.patchKind) reason=\(trace.reasonSummary) graph=\(trace.previousGraphState)->\(trace.nextGraphState) image=\(trace.previousImageState.rawValue)->\(trace.nextImageState.rawValue)"
            )
        }

        let summary = countsByKind
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        AppLogger.debug(
            .lifecycle,
            "[MarketRows] coalesced_patch_summary exchange=\(exchange.rawValue) count=\(traces.count) \(summary)"
        )
    }

    private func filteredMarketRows(from rows: [MarketRowViewState]) -> [MarketRowViewState] {
        let filteredByFavorite = marketFilter == .fav
            ? rows.filter(\.isFavorite)
            : rows

        guard !searchQuery.isEmpty else {
            return filteredByFavorite
        }

        let query = searchQuery.lowercased()
        return filteredByFavorite.filter { row in
            row.symbol.lowercased().contains(query)
            || row.displayName.lowercased().contains(query)
            || row.displayNameEn.lowercased().contains(query)
        }
    }

    private func makeMarketRowViewState(
        for coin: CoinInfo,
        exchange: Exchange,
        cachedRow: MarketRowViewState?
    ) -> MarketRowViewState {
        let marketIdentity = coin.marketIdentity(exchange: exchange)
        let priorityVisibleMarketIdentities = Set(
            priorityVisibleSparklineMarketIdentities(
                for: exchange,
                rows: marketPresentationSnapshotsByExchange[exchange]?.rows ?? []
            )
        )
        return Self.makeMarketRowViewState(
            for: coin,
            exchange: exchange,
            assetImageClient: assetImageClient,
            ticker: pricesByMarketIdentity[marketIdentity]
                ?? pricesByMarketIdentity[resolvedMarketIdentity(exchange: exchange, symbol: coin.symbol)],
            cachedRow: cachedRow,
            favoriteSymbols: favCoins,
            sparklineSnapshot: sparklineSnapshot(marketIdentity: marketIdentity),
            stableSparklineDisplay: stableSparklineDisplay(marketIdentity: marketIdentity),
            isSparklineLoading: loadingSparklineMarketIdentitiesByExchange[exchange]?.contains(marketIdentity) == true,
            isSparklineUnavailable: unavailableSparklineMarketIdentitiesByExchange[exchange]?.contains(marketIdentity) == true,
            preferDetailedVisibleGraph: priorityVisibleMarketIdentities.contains(marketIdentity),
            sparklineStaleInterval: sparklineCacheStaleInterval,
            now: Date()
        )
    }

    private func makeMarketPresentationSnapshot(
        for exchange: Exchange,
        universe: MarketUniverseSnapshot,
        overrideMeta: ResponseMeta = ResponseMeta(
            fetchedAt: nil,
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil
        )
    ) -> MarketPresentationSnapshot {
        let cachedRowsByMarketIdentity = (marketPresentationSnapshotsByExchange[exchange]?.rows ?? [])
            .reduce(into: [MarketIdentity: MarketRowViewState]()) { partialResult, row in
                if let existing = partialResult[row.marketIdentity] {
                    partialResult[row.marketIdentity] = Self.preferredMarketRow(existing: existing, incoming: row)
                } else {
                    partialResult[row.marketIdentity] = row
                }
            }
        let presentationCoins = marketPresentationCoins(for: universe, exchange: exchange)
        let priorityDetailedMarketIdentities = Set(
            presentationCoins
                .prefix(marketFirstPaintRowLimit)
                .map { $0.marketIdentity(exchange: exchange) }
        )
        let rows = presentationCoins.map { coin in
            let marketIdentity = coin.marketIdentity(exchange: exchange)
            return Self.makeMarketRowViewState(
                for: coin,
                exchange: exchange,
                assetImageClient: assetImageClient,
                ticker: pricesByMarketIdentity[marketIdentity]
                    ?? pricesByMarketIdentity[resolvedMarketIdentity(exchange: exchange, symbol: coin.symbol)],
                cachedRow: cachedRowsByMarketIdentity[marketIdentity],
                favoriteSymbols: favCoins,
                sparklineSnapshot: sparklineSnapshot(marketIdentity: marketIdentity),
                stableSparklineDisplay: stableSparklineDisplay(marketIdentity: marketIdentity),
                isSparklineLoading: loadingSparklineMarketIdentitiesByExchange[exchange]?.contains(marketIdentity) == true,
                isSparklineUnavailable: unavailableSparklineMarketIdentitiesByExchange[exchange]?.contains(marketIdentity) == true,
                preferDetailedVisibleGraph: priorityDetailedMarketIdentities.contains(marketIdentity),
                sparklineStaleInterval: sparklineCacheStaleInterval,
                now: Date()
            )
        }
        let meta = combineMetas([
            marketCatalogMetaByExchange[exchange] ?? .empty,
            marketTickerMetaByExchange[exchange] ?? .empty,
            overrideMeta
        ])

        return MarketPresentationSnapshot(
            exchange: exchange,
            generation: marketPresentationGeneration,
            universe: universe,
            rows: rows,
            meta: meta
        )
    }

    @discardableResult
    private func stageAndSwapMarketPresentationIfPossible(
        for exchange: Exchange,
        requestContext: MarketRequestContext,
        reason: String,
        overrideMeta: ResponseMeta = ResponseMeta(
            fetchedAt: nil,
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil
        )
    ) -> Bool {
        let hasCatalog = marketsByExchange[exchange] != nil
        let hasTickerSnapshot = hasLoadedTickerSnapshotByExchange[exchange] == true
        let hasTickerData = hasAnyTickerData(for: exchange)
        let hasCachedPresentation = marketPresentationSnapshotsByExchange[exchange] != nil

        guard hasCatalog || hasTickerSnapshot || hasTickerData || hasCachedPresentation else {
            if activeMarketPresentationSnapshot == nil, selectedExchange == exchange {
                assignMarketState(.loading)
            }
            return false
        }

        let provisionalRows = marketPresentationSnapshotsByExchange[exchange]?.rows ?? []
        let baseCoins = marketsByExchange[exchange]
            ?? tickerSnapshotCoinsByExchange[exchange]
            ?? provisionalRows.map {
                CoinCatalog.coin(
                    symbol: $0.symbol,
                    displayName: $0.displayName,
                    englishName: $0.displayNameEn,
                    imageURL: $0.imageURL
                )
            }
        let hasTradableCoins = baseCoins.contains(where: \.isTradable)
        guard hasTradableCoins || hasCatalog else {
            if activeMarketPresentationSnapshot == nil, selectedExchange == exchange {
                assignMarketState(.loading)
            }
            return false
        }
        let responseUniverseVersion = stableSymbolHash(
            from: baseCoins.map {
                "\($0.symbol)|\($0.isTradable ? 1 : 0)|\($0.isKimchiComparable ? 1 : 0)"
            }
        )
        guard shouldAcceptMarketPresentation(requestContext, responseUniverseVersion: responseUniverseVersion) else {
            AppLogger.debug(
                .network,
                "[MarketScreen] stale response ignored exchange=\(exchange.rawValue) route=\(requestContext.route.rawValue) universe=\(responseUniverseVersion) generation=\(requestContext.generation)"
            )
            return false
        }

        if shouldDeferCatalogOnlyMarketPresentation(
            for: exchange,
            hasCatalog: hasCatalog,
            hasTickerSnapshot: hasTickerSnapshot,
            hasTickerData: hasTickerData
        ) {
            AppLogger.debug(
                .lifecycle,
                "[ExchangeSwitch] deferred placeholder rows exchange=\(exchange.rawValue) reason=\(reason)"
            )
            return false
        }

        if hasCatalog == false {
            AppLogger.debug(
                .network,
                "[MarketSnapshot] provisional render exchange=\(exchange.rawValue) reason=\(reason) symbols=\(baseCoins.count)"
            )
        }
        AppLogger.debug(
            .lifecycle,
            "[MarketScreen] tradable rows count exchange=\(exchange.rawValue) count=\(baseCoins.count)"
        )
        let buildInput = makeMarketPresentationBuildInput(for: exchange, overrideMeta: overrideMeta)
        let buildStartedAt = Date()
        Task { [weak self] in
            guard let self else { return }
            var snapshot = await self.prepareMarketPresentationSnapshot(from: buildInput)
            guard self.shouldAcceptMarketPresentation(requestContext, responseUniverseVersion: snapshot.universe.symbolsHash) else {
                AppLogger.debug(
                    .network,
                    "[MarketScreen] stale response ignored exchange=\(exchange.rawValue) route=\(requestContext.route.rawValue) universe=\(snapshot.universe.symbolsHash) generation=\(requestContext.generation)"
                )
                return
            }
            snapshot = await self.primeFirstPaintDetailedSparklinesIfPossible(
                for: snapshot,
                requestContext: requestContext
            )
            guard self.shouldAcceptMarketPresentation(requestContext, responseUniverseVersion: snapshot.universe.symbolsHash) else {
                AppLogger.debug(
                    .network,
                    "[MarketScreen] stale response ignored exchange=\(exchange.rawValue) route=\(requestContext.route.rawValue) universe=\(snapshot.universe.symbolsHash) generation=\(requestContext.generation)"
                )
                return
            }
            let buildElapsed = Int(Date().timeIntervalSince(buildStartedAt) * 1000)
            AppLogger.debug(
                .lifecycle,
                "[MarketScreen] staged rows prepared count exchange=\(exchange.rawValue) count=\(snapshot.rows.count) buildMs=\(buildElapsed)"
            )
            guard self.activeTab == .market, self.selectedExchange == exchange else {
                self.marketPresentationSnapshotsByExchange[exchange] = snapshot
                self.persistStableSparklineDisplays(
                    from: snapshot.rows,
                    exchange: exchange,
                    generation: snapshot.generation
                )
                AppLogger.debug(
                    .network,
                    "[MarketPipeline] exchange=\(exchange.rawValue) generation=\(snapshot.generation) phase=cache_prepared_only route=\(self.activeTab.rawValue) rows=\(snapshot.rows.count)"
                )
                return
            }
            self.swapMarketPresentation(snapshot, reason: reason, clearTransition: true)
        }
        return true
    }

    private func shouldDeferCatalogOnlyMarketPresentation(
        for exchange: Exchange,
        hasCatalog: Bool,
        hasTickerSnapshot: Bool,
        hasTickerData: Bool
    ) -> Bool {
        if marketFullHydrationPendingExchanges.contains(exchange), hasTickerSnapshot == false {
            return true
        }

        return hasCatalog
            && hasTickerSnapshot == false
            && hasTickerData == false
    }

    private func representativeMarketRows(from rows: [MarketRowViewState]) -> [MarketRowViewState] {
        Array(rows.prefix(marketRepresentativeRowLimit))
    }

    private func makeMarketSparklineAvailabilityState(
        exchange: Exchange,
        rows: [MarketRowViewState]
    ) -> SparklineAvailabilityState {
        var available = Set<String>()
        var placeholders = Set<String>()
        var hidden = Set<String>()

        for row in rows {
            if row.graphState.keepsVisibleGraph {
                available.insert(row.symbol)
            } else if row.graphState == .placeholder || row.graphState == .unavailable {
                placeholders.insert(row.symbol)
            } else {
                hidden.insert(row.symbol)
            }
        }

        return SparklineAvailabilityState(
            exchange: exchange,
            availableSymbols: available,
            placeholderSymbols: placeholders,
            hiddenSymbols: hidden
        )
    }

    private func marketRowsPhase(for snapshot: MarketPresentationSnapshot) -> ExchangeRowsPhase {
        if snapshot.rows.isEmpty {
            return .loading
        }
        if snapshot.rows.count < snapshot.universe.tradableCount
            || snapshot.universe.pendingSymbols.isEmpty == false
            || snapshot.meta.partialFailureMessage != nil {
            return .partial
        }
        return .hydrated
    }

    private func makeMarketPresentationState(
        from snapshot: MarketPresentationSnapshot,
        previousExchange: Exchange?,
        sameExchangeStaleReuse: Bool,
        transitionPhase: ExchangeTransitionPhase? = nil
    ) -> MarketScreenPresentationState {
        let representativeRows = representativeMarketRows(from: snapshot.rows)
        let listPhase = marketRowsPhase(for: snapshot)
        let representativePhase: ExchangeRowsPhase
        if representativeRows.isEmpty {
            representativePhase = .loading
        } else if listPhase == .hydrated {
            representativePhase = .hydrated
        } else {
            representativePhase = .partial
        }

        return MarketScreenPresentationState(
            selectedExchange: snapshot.exchange,
            representativeRowsState: ExchangeRowsState(
                exchange: snapshot.exchange,
                rows: representativeRows,
                phase: representativePhase,
                showsPlaceholder: representativeRows.isEmpty
            ),
            listRowsState: ExchangeRowsState(
                exchange: snapshot.exchange,
                rows: snapshot.rows,
                phase: listPhase,
                showsPlaceholder: snapshot.rows.isEmpty
            ),
            sparklineAvailabilityState: makeMarketSparklineAvailabilityState(
                exchange: snapshot.exchange,
                rows: snapshot.rows
            ),
            transitionState: ExchangeTransitionState(
                exchange: snapshot.exchange,
                previousExchange: previousExchange,
                phase: transitionPhase
                    ?? (listPhase == .hydrated ? .hydrated : (snapshot.rows.isEmpty ? .loading : .partial))
            ),
            sameExchangeStaleReuse: sameExchangeStaleReuse,
            crossExchangeStaleReuseAllowed: false
        )
    }

    private func swapMarketPresentation(
        _ incomingSnapshot: MarketPresentationSnapshot,
        reason: String,
        clearTransition: Bool
    ) {
        var snapshot = incomingSnapshot
        if activeTab == .market, selectedExchange == snapshot.exchange {
            snapshot = warmMarketImages(
                for: snapshot,
                reason: "\(reason)_pre_swap",
                visibleMode: .warmup,
                applyImmediateToSnapshot: true
            )
        }

        let requiresTransitionMutation = clearTransition
            && marketPresentationState.selectedExchange == snapshot.exchange
            && (marketPresentationState.transitionState.isLoading || marketTransitionMessage != nil)
        if activeMarketPresentationSnapshot?.exchange == snapshot.exchange,
           activeMarketPresentationSnapshot == snapshot,
           requiresTransitionMutation == false {
            AppLogger.debug(
                .network,
                "[MarketPipeline] exchange=\(snapshot.exchange.rawValue) generation=\(snapshot.generation) phase=publish_skipped reason=duplicate_snapshot"
            )
            return
        }

        marketStagedSwapCountByExchange[snapshot.exchange, default: 0] += 1

        marketPresentationSnapshotsByExchange[snapshot.exchange] = snapshot
        activeMarketPresentationSnapshot = snapshot
        persistStableSparklineDisplays(from: snapshot.rows, exchange: snapshot.exchange, generation: snapshot.generation)
        if clearTransition == false {
            marketBasePhaseByExchange[snapshot.exchange] = .showingCache
        } else {
            marketBasePhaseByExchange[snapshot.exchange] = .showingSnapshot
        }

        applyMarketRowsDiff(snapshot.rows, reason: "exchange_switch_staged_swap:\(reason)")
        let transitionPhase: ExchangeTransitionPhase?
        if clearTransition {
            transitionPhase = nil
        } else if marketFullHydrationPendingExchanges.contains(snapshot.exchange) {
            transitionPhase = snapshot.rows.isEmpty ? .loading : .partial
        } else {
            transitionPhase = .hydrated
        }
        marketPresentationState = makeMarketPresentationState(
            from: snapshot,
            previousExchange: marketPresentationState.selectedExchange == snapshot.exchange ? nil : marketPresentationState.selectedExchange,
            sameExchangeStaleReuse: false,
            transitionPhase: transitionPhase
        )
        reconcileVisibleSparklines(
            exchange: snapshot.exchange,
            reason: "staged_rows_swap"
        )
        logMarketSwitchProgressIfNeeded(snapshot: snapshot, reason: reason)

        if snapshot.rows.isEmpty {
            assignMarketState(.empty)
        } else {
            assignMarketState(.loaded(snapshot.universe.tradableCoins))
        }

        if activeTab == .market, snapshot.exchange == selectedExchange {
            updatePublicSubscriptions(reason: "\(reason)_visible_rows")
            scheduleMarketHydrationIfNeeded(
                for: snapshot.exchange,
                totalCount: snapshot.universe.tradableCount,
                reason: reason
            )
            scheduleMarketImageHydration(
                for: snapshot.exchange,
                reason: "\(reason)_symbol_image"
            )
            schedulePriorityVisibleSparklineRefresh(
                for: snapshot.exchange,
                reason: "\(reason)_priority_visible"
            )
            scheduleVisibleSparklineHydration(
                for: snapshot.exchange,
                reason: "\(reason)_sparkline"
            )
        }

        refreshMarketLoadState(reason: reason)
        marketStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: snapshot.meta,
            streamingStatus: currentPublicStreamingStatus,
            context: .market,
            warningMessage: currentPublicStreamingWarningMessage,
            loadState: marketLoadState
        )
        ensureSelectedCoinIfPossible(for: snapshot.exchange)
        logMarketScreenCounts(reason: reason, rows: snapshot.rows)
        logAssetImageCoverageSummary(reason: reason)
        logRepresentativeGraphSummary(snapshot: snapshot, reason: reason)
        AppLogger.debug(
            .lifecycle,
            "[MarketScreen] swapped staged rows exchange=\(snapshot.exchange.rawValue) count=\(snapshot.rows.count) swapCount=\(marketStagedSwapCountByExchange[snapshot.exchange] ?? 0)"
        )

        if clearTransition, snapshot.exchange == selectedExchange {
            marketTransitionMessage = nil
        }
    }

    private func logMarketSwitchProgressIfNeeded(
        snapshot: MarketPresentationSnapshot,
        reason: String
    ) {
        guard let startedAt = marketSwitchStartedAtByExchange[snapshot.exchange] else {
            return
        }

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let stagedSwapCount = marketStagedSwapCountByExchange[snapshot.exchange] ?? 0
        let visibleGraphPatchCount = marketVisibleGraphPatchCountByExchange[snapshot.exchange] ?? 0
        let offscreenDeferredGraphCount = marketOffscreenDeferredGraphCountByExchange[snapshot.exchange] ?? 0
        let staleDropCount = marketStaleCallbackDropCountByExchange[snapshot.exchange] ?? 0
        let placeholderBaseline = marketPlaceholderFinalBaselineByExchange[snapshot.exchange] ?? 0
        let placeholderAppliedCount = max(currentPlaceholderFinalTotal() - placeholderBaseline, 0)
        if marketFirstVisibleLoggedExchanges.contains(snapshot.exchange) == false,
           snapshot.rows.isEmpty == false {
            marketFirstVisibleLoggedExchanges.insert(snapshot.exchange)
            let applyCount = marketSwitchApplyCountByExchange[snapshot.exchange] ?? 0
            AppLogger.debug(
                .lifecycle,
                "[ExchangeSwitch] visible ready exchange=\(snapshot.exchange.rawValue) rows=\(snapshot.rows.count) elapsedMs=\(elapsedMs) applyCount=\(applyCount) stagedSwaps=\(stagedSwapCount) visibleGraphPatches=\(visibleGraphPatchCount) offscreenDeferredGraphs=\(offscreenDeferredGraphCount) staleDrops=\(staleDropCount) placeholderFinalApplied=\(placeholderAppliedCount) reason=\(reason)"
            )
            MarketPerformanceDebugClient.shared.log(
                .initialVisibleFirstPaintElapsed,
                exchange: snapshot.exchange,
                details: [
                    "applyCount": "\(applyCount)",
                    "elapsedMs": "\(elapsedMs)",
                    "offscreenDeferredGraphs": "\(offscreenDeferredGraphCount)",
                    "reason": reason,
                    "rows": "\(snapshot.rows.count)",
                    "stagedSwaps": "\(stagedSwapCount)",
                    "staleDrops": "\(staleDropCount)",
                    "visibleGraphPatches": "\(visibleGraphPatchCount)"
                ]
            )
            MarketPerformanceDebugClient.shared.log(
                .skeletonHidden,
                exchange: snapshot.exchange,
                details: [
                    "elapsedMs": "\(elapsedMs)",
                    "generation": "\(snapshot.generation)",
                    "rows": "\(snapshot.rows.count)"
                ]
            )
        }

        if marketFullHydrationPendingExchanges.contains(snapshot.exchange),
           snapshot.universe.tradableCount == snapshot.rows.count {
            marketFullHydrationPendingExchanges.remove(snapshot.exchange)
            marketSwitchStartedAtByExchange.removeValue(forKey: snapshot.exchange)
            AppLogger.debug(
                .lifecycle,
                "[ExchangeSwitch] completed exchange=\(snapshot.exchange.rawValue) hydratedRows=\(snapshot.rows.count) elapsedMs=\(elapsedMs) applyCount=\(marketSwitchApplyCountByExchange[snapshot.exchange] ?? 0) stagedSwaps=\(stagedSwapCount) fullReloads=\(marketFullReloadCountByExchange[snapshot.exchange] ?? 0) visibleGraphPatches=\(visibleGraphPatchCount) offscreenDeferredGraphs=\(offscreenDeferredGraphCount) staleDrops=\(staleDropCount) placeholderFinalApplied=\(placeholderAppliedCount) reason=\(reason)"
            )
            MarketPerformanceDebugClient.shared.log(
                .exchangeSwitchElapsed,
                exchange: snapshot.exchange,
                details: [
                    "elapsedMs": "\(elapsedMs)",
                    "fullReloads": "\(marketFullReloadCountByExchange[snapshot.exchange] ?? 0)",
                    "offscreenDeferredGraphs": "\(offscreenDeferredGraphCount)",
                    "reason": reason,
                    "rows": "\(snapshot.rows.count)",
                    "stagedSwaps": "\(stagedSwapCount)",
                    "staleDrops": "\(staleDropCount)",
                    "visibleGraphPatches": "\(visibleGraphPatchCount)"
                ]
            )
        }
    }

    private func logRepresentativeGraphSummary(
        snapshot: MarketPresentationSnapshot,
        reason: String
    ) {
        for row in representativeMarketRows(from: snapshot.rows) {
            AppLogger.debug(
                .lifecycle,
                "[RepresentativeGraph] exchange=\(snapshot.exchange.rawValue) symbol=\(row.symbol) reason=\(reason) detailLevel=\(row.sparklinePayload.detailLevel.cacheComponent) pointCount=\(row.sparklinePointCount) graphState=\(row.graphState)"
            )
        }
    }

    private func rowsByPreservingVisibleGraphs(
        previousRows: [MarketRowViewState],
        incomingRows: [MarketRowViewState],
        reason: String
    ) -> ([MarketRowViewState], Int) {
        guard previousRows.isEmpty == false else {
            return (incomingRows, 0)
        }

        let previousRowsByID = Dictionary(uniqueKeysWithValues: previousRows.map { ($0.id, $0) })
        let isStagedSwap = reason.contains("staged_swap")
        var preservedCount = 0
        let rows = incomingRows.map { incomingRow -> MarketRowViewState in
            guard let previousRow = previousRowsByID[incomingRow.id] else {
                return incomingRow
            }
            let preservedRow = Self.rowByCarryingForwardGraph(existing: previousRow, into: incomingRow)
            guard preservedRow != incomingRow else {
                return incomingRow
            }
            preservedCount += 1
            AppLogger.debug(
                .network,
                "[GraphScrollDebug] \(incomingRow.marketLogFields) action=\(isStagedSwap ? "graph_preserved_on_staged_swap" : "graph_preserved_on_rebind") oldDetail=\(previousRow.sparklinePayload.detailLevel.cacheComponent) newDetail=\(incomingRow.sparklinePayload.detailLevel.cacheComponent)"
            )
            if isStagedSwap {
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(incomingRow.marketLogFields) action=graph_state_carried_forward phase=staged_swap oldState=\(previousRow.graphState) newState=\(preservedRow.graphState)"
                )
            }
            return preservedRow
        }

        if preservedCount > 0 {
            AppLogger.debug(
                .lifecycle,
                "[MarketRows] \(isStagedSwap ? "staged_swap_preserved_visible_graph" : "row_reload_preserved_graph") count=\(preservedCount) reason=\(reason)"
            )
        }
        return (rows, preservedCount)
    }

    private func applyMarketRowsDiff(
        _ newRows: [MarketRowViewState],
        reason: String = "unspecified",
        reconfigureTraces: [MarketRowReconfigureTrace] = []
    ) {
        let applyStartedAt = Date()
        let previousIDs = marketRowStates.map(\.id)
        let previousRows = marketRowStates
        let preservationResult = rowsByPreservingVisibleGraphs(
            previousRows: previousRows,
            incomingRows: newRows,
            reason: reason
        )
        let effectiveNewRows = preservationResult.0
        let nextIDs = effectiveNewRows.map(\.id)
        let applyExchange = effectiveNewRows.first?.exchange ?? selectedExchange
        let shouldRunPostApplyVisibleReconcile = reason.hasPrefix("visible_reconcile") == false

        func logApply(
            mode: String,
            rowCount: Int,
            changedCount: Int,
            graphSubviewPatchCount: Int = 0,
            displaySubviewPatchCount: Int = 0,
            imageSubviewPatchCount: Int = 0
        ) {
            marketSwitchApplyCountByExchange[applyExchange, default: 0] += 1
            let applyCount = marketSwitchApplyCountByExchange[applyExchange] ?? 0
            let elapsedMs = Int(Date().timeIntervalSince(applyStartedAt) * 1000)
            AppLogger.debug(
                .lifecycle,
                "[MarketRows] apply_elapsed exchange=\(applyExchange.rawValue) mode=\(mode) rows=\(rowCount) changed=\(changedCount) graphSubviewPatch=\(graphSubviewPatchCount) displaySubviewPatch=\(displaySubviewPatchCount) imageSubviewPatch=\(imageSubviewPatchCount) elapsedMs=\(elapsedMs) applyCount=\(applyCount) reason=\(reason)"
            )
            MarketPerformanceDebugClient.shared.log(
                .marketRowsApply,
                exchange: applyExchange,
                details: [
                    "applyCount": "\(applyCount)",
                    "changed": "\(changedCount)",
                    "elapsedMs": "\(elapsedMs)",
                    "mode": mode,
                    "reason": reason,
                    "rows": "\(rowCount)"
                ]
            )
        }

        let isAppendOnlyHydration = previousIDs.isEmpty == false
            && nextIDs.count > previousIDs.count
            && Array(nextIDs.prefix(previousIDs.count)) == previousIDs

        if previousIDs.isEmpty {
            logGraphDisplayTransitions(from: previousRows, to: effectiveNewRows)
            marketRowStates = effectiveNewRows
            logApply(
                mode: "initial_visible",
                rowCount: effectiveNewRows.count,
                changedCount: effectiveNewRows.count
            )
            if shouldRunPostApplyVisibleReconcile {
                reconcileVisibleSparklines(
                    exchange: applyExchange,
                    reason: "reload_reconfigure_initial_visible"
                )
            }
            return
        }

        if isAppendOnlyHydration {
            var mergedRows = previousRows
            var changedIndices = [Int]()
            for index in previousRows.indices where previousRows[index] != effectiveNewRows[index] {
                mergedRows[index] = effectiveNewRows[index]
                changedIndices.append(index)
            }
            mergedRows.append(contentsOf: effectiveNewRows.dropFirst(previousRows.count))

            let normalizedTraces = normalizedMarketRowReconfigureTraces(
                previousRows: previousRows,
                nextRows: mergedRows,
                changedIndices: changedIndices,
                reason: reason,
                traces: reconfigureTraces
            )
            let graphSubviewPatchCount = normalizedTraces.filter { $0.patchKind == "graph_only" }.count
            let imageSubviewPatchCount = normalizedTraces.filter { $0.patchKind == "image_only" }.count
            let displaySubviewPatchCount = normalizedTraces.filter {
                $0.patchKind == "ticker_display_only" || $0.patchKind == "flash_only"
            }.count
            let rowReconfigureCount = normalizedTraces.filter {
                $0.patchKind != "graph_only"
                    && $0.patchKind != "image_only"
                    && $0.patchKind != "ticker_display_only"
                    && $0.patchKind != "flash_only"
            }.count

            AppLogger.debug(
                .lifecycle,
                "[MarketRows] append count=\(effectiveNewRows.count - previousRows.count) visibleReconfigure=\(rowReconfigureCount) graphSubviewPatch=\(graphSubviewPatchCount) displaySubviewPatch=\(displaySubviewPatchCount) imageSubviewPatch=\(imageSubviewPatchCount) exchange=\(applyExchange.rawValue) reason=\(reason) causes=\(marketRowsReconfigureCauseSummary(normalizedTraces))"
            )
            if rowReconfigureCount > 0 {
                MarketPerformanceDebugClient.shared.increment(.visibleRowReconfigure, by: rowReconfigureCount)
            }
            logGraphDisplayTransitions(from: previousRows, to: mergedRows)
            marketRowStates = mergedRows
            logApply(
                mode: "append_offscreen",
                rowCount: mergedRows.count,
                changedCount: changedIndices.count + (effectiveNewRows.count - previousRows.count),
                graphSubviewPatchCount: graphSubviewPatchCount,
                displaySubviewPatchCount: displaySubviewPatchCount,
                imageSubviewPatchCount: imageSubviewPatchCount
            )
            if shouldRunPostApplyVisibleReconcile {
                reconcileVisibleSparklines(
                    exchange: applyExchange,
                    reason: "reload_reconfigure_append"
                )
            }
            return
        }

        guard previousIDs == nextIDs else {
            logGraphDisplayTransitions(from: previousRows, to: effectiveNewRows)
            marketFullReloadCountByExchange[applyExchange, default: 0] += 1
            AppLogger.debug(
                .lifecycle,
                "[MarketRows] reload count=\(effectiveNewRows.count) exchange=\(effectiveNewRows.first?.exchange.rawValue ?? selectedExchange.rawValue) reason=\(reason) scope=exchange_switch_staged_swap"
            )
            marketRowStates = effectiveNewRows
            logApply(mode: "reload", rowCount: effectiveNewRows.count, changedCount: effectiveNewRows.count)
            if shouldRunPostApplyVisibleReconcile {
                reconcileVisibleSparklines(
                    exchange: applyExchange,
                    reason: "reload_reconfigure_reload"
                )
            }
            return
        }

        var mergedRows = marketRowStates
        var changedIndices = [Int]()

        for index in effectiveNewRows.indices where mergedRows[index] != effectiveNewRows[index] {
            mergedRows[index] = effectiveNewRows[index]
            changedIndices.append(index)
        }

        guard changedIndices.isEmpty == false else {
            if shouldRunPostApplyVisibleReconcile {
                reconcileVisibleSparklines(
                    exchange: applyExchange,
                    reason: "reload_reconfigure_noop"
                )
            }
            return
        }

        let normalizedTraces = normalizedMarketRowReconfigureTraces(
            previousRows: previousRows,
            nextRows: mergedRows,
            changedIndices: changedIndices,
            reason: reason,
            traces: reconfigureTraces
        )
        let graphSubviewPatchCount = normalizedTraces.filter { $0.patchKind == "graph_only" }.count
        let imageSubviewPatchCount = normalizedTraces.filter { $0.patchKind == "image_only" }.count
        let displaySubviewPatchCount = normalizedTraces.filter {
            $0.patchKind == "ticker_display_only" || $0.patchKind == "flash_only"
        }.count
        let rowReconfigureCount = normalizedTraces.filter {
            $0.patchKind != "graph_only"
                && $0.patchKind != "image_only"
                && $0.patchKind != "ticker_display_only"
                && $0.patchKind != "flash_only"
        }.count
        AppLogger.debug(
            .lifecycle,
            "[MarketRows] reconfigure count=\(rowReconfigureCount) graphSubviewPatch=\(graphSubviewPatchCount) displaySubviewPatch=\(displaySubviewPatchCount) imageSubviewPatch=\(imageSubviewPatchCount) exchange=\(newRows.first?.exchange.rawValue ?? selectedExchange.rawValue) reason=\(reason) causes=\(marketRowsReconfigureCauseSummary(normalizedTraces))"
        )
        if rowReconfigureCount > 0 {
            MarketPerformanceDebugClient.shared.increment(.visibleRowReconfigure, by: rowReconfigureCount)
        }
        logGraphDisplayTransitions(from: previousRows, to: mergedRows)
        marketRowStates = mergedRows
        logApply(
            mode: "patch",
            rowCount: mergedRows.count,
            changedCount: changedIndices.count,
            graphSubviewPatchCount: graphSubviewPatchCount,
            displaySubviewPatchCount: displaySubviewPatchCount,
            imageSubviewPatchCount: imageSubviewPatchCount
        )
        if shouldRunPostApplyVisibleReconcile {
            reconcileVisibleSparklines(
                exchange: applyExchange,
                reason: "reload_reconfigure_patch"
            )
        }
    }

    private func normalizedMarketRowReconfigureTraces(
        previousRows: [MarketRowViewState],
        nextRows: [MarketRowViewState],
        changedIndices: [Int],
        reason: String,
        traces: [MarketRowReconfigureTrace]
    ) -> [MarketRowReconfigureTrace] {
        guard traces.count == changedIndices.count else {
            return changedIndices.map { index in
                derivedMarketRowReconfigureTrace(
                    previousRow: previousRows[index],
                    nextRow: nextRows[index],
                    reason: reason
                )
            }
        }
        return traces
    }

    private func derivedMarketRowReconfigureTrace(
        previousRow: MarketRowViewState,
        nextRow: MarketRowViewState,
        reason: String
    ) -> MarketRowReconfigureTrace {
        let graphChanged = previousRow.sparklinePayload != nextRow.sparklinePayload
            || previousRow.graphState != nextRow.graphState
            || previousRow.chartPresentation != nextRow.chartPresentation
            || previousRow.hasEnoughSparklineData != nextRow.hasEnoughSparklineData
        let imageChanged = previousRow.symbolImageState != nextRow.symbolImageState
        let displayChanged = previousRow.priceText != nextRow.priceText
            || previousRow.changeText != nextRow.changeText
            || previousRow.volumeText != nextRow.volumeText
            || previousRow.isPricePlaceholder != nextRow.isPricePlaceholder
            || previousRow.isChangePlaceholder != nextRow.isChangePlaceholder
            || previousRow.isVolumePlaceholder != nextRow.isVolumePlaceholder
            || previousRow.isUp != nextRow.isUp
            || previousRow.flash != nextRow.flash
            || previousRow.dataState != nextRow.dataState
            || previousRow.baseFreshnessState != nextRow.baseFreshnessState
            || previousRow.sourceExchange != nextRow.sourceExchange
        let flashOnly = previousRow.flash != nextRow.flash
            && previousRow.priceText == nextRow.priceText
            && previousRow.changeText == nextRow.changeText
            && previousRow.volumeText == nextRow.volumeText
            && previousRow.isPricePlaceholder == nextRow.isPricePlaceholder
            && previousRow.isChangePlaceholder == nextRow.isChangePlaceholder
            && previousRow.isVolumePlaceholder == nextRow.isVolumePlaceholder
            && previousRow.isUp == nextRow.isUp
            && previousRow.dataState == nextRow.dataState
            && previousRow.baseFreshnessState == nextRow.baseFreshnessState
            && previousRow.sourceExchange == nextRow.sourceExchange
        let layoutChanged = previousRow.marketIdentity != nextRow.marketIdentity
            || previousRow.coin != nextRow.coin
            || previousRow.isFavorite != nextRow.isFavorite
            || previousRow.selectedExchange != nextRow.selectedExchange

        let patchKind: String
        switch (graphChanged, imageChanged, displayChanged, layoutChanged, flashOnly) {
        case (true, false, false, false, _):
            patchKind = "graph_only"
        case (false, true, false, false, _):
            patchKind = "image_only"
        case (false, false, true, false, true):
            patchKind = "flash_only"
        case (false, false, true, false, false):
            patchKind = "ticker_display_only"
        case (false, false, false, true, _):
            patchKind = "layout_affecting"
        default:
            patchKind = "coalesced"
        }

        return MarketRowReconfigureTrace(
            marketIdentity: nextRow.marketIdentity,
            patchKind: patchKind,
            reasons: [reason],
            previousGraphState: previousRow.graphState,
            nextGraphState: nextRow.graphState,
            previousImageState: previousRow.symbolImageState,
            nextImageState: nextRow.symbolImageState
        )
    }

    private func marketRowsReconfigureCauseSummary(_ traces: [MarketRowReconfigureTrace]) -> String {
        guard traces.isEmpty == false else {
            return "unspecified"
        }
        var countsByReason = [String: Int]()
        for trace in traces {
            if trace.patchKind == "ticker_display_only" {
                countsByReason["ticker_display_only", default: 0] += 1
                continue
            }
            if trace.patchKind == "flash_only" {
                countsByReason["ticker_flash_reset", default: 0] += 1
                continue
            }
            if trace.patchKind == "graph_only" {
                countsByReason["graph_refined_patch", default: 0] += 1
                continue
            }
            if trace.patchKind == "image_only" {
                countsByReason["image_visible_patch", default: 0] += 1
                continue
            }
            for reason in trace.reasons {
                let category = if reason.hasPrefix("graph_refined_patch") {
                    "graph_refined_patch"
                } else if reason.hasPrefix("image_visible_patch") {
                    "image_visible_patch"
                } else if reason == "ticker_flash_reset" {
                    "ticker_flash_reset"
                } else if reason == "ticker_stream_update" || reason == "ticker_snapshot_update" {
                    "base_ticker_refresh"
                } else {
                    reason
                }
                countsByReason[category, default: 0] += 1
            }
        }
        return countsByReason
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    private func logGraphDisplayTransitions(
        from oldRows: [MarketRowViewState],
        to newRows: [MarketRowViewState]
    ) {
        let oldRowsByID = Dictionary(uniqueKeysWithValues: oldRows.map { ($0.id, $0) })
        for row in newRows.prefix(32) {
            let signature = "\(row.graphState)|\(row.graphRenderVersion)|\(row.graphPathVersion)|\(row.sparklinePointCount)|\(row.sparklinePayload.sourceVersion)"
            guard lastLoggedGraphDisplaySignaturesByBindingKey[row.graphBindingKey] != signature else {
                continue
            }
            lastLoggedGraphDisplaySignaturesByBindingKey[row.graphBindingKey] = signature

            guard let previousRow = oldRowsByID[row.id] else {
                let firstPaintReason = row.sparklinePayload.hasRenderableGraph
                    ? "usable_graph_ready"
                    : "no_usable_graph"
                AppLogger.debug(
                    .network,
                    "[GraphFirstPaintDebug] \(row.marketLogFields) action=paint reason=\(firstPaintReason) source=\(graphLogSource(for: row)) graphState=\(row.graphState)"
                )
                AppLogger.debug(
                    .network,
                    "[GraphDetailDebug] \(row.marketLogFields) action=first_paint detailLevel=\(row.sparklinePayload.detailLevel.cacheComponent) pointCount=\(row.sparklinePointCount) source=\(graphLogSource(for: row))"
                )
                continue
            }

            guard previousRow.graphState != row.graphState
                || previousRow.graphRenderVersion != row.graphRenderVersion
                || previousRow.graphPathVersion != row.graphPathVersion
                || previousRow.sparklinePointCount != row.sparklinePointCount
                || previousRow.sparklinePayload.sourceVersion != row.sparklinePayload.sourceVersion else {
                continue
            }

            AppLogger.debug(
                .network,
                "[GraphPatchDebug] \(row.marketLogFields) from=\(previousRow.graphState) to=\(row.graphState) renderVersion=\(row.graphRenderVersion) pathVersion=\(row.graphPathVersion)"
            )
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(row.marketLogFields) action=refined_patch_received oldDetail=\(previousRow.sparklinePayload.detailLevel.cacheComponent) newDetail=\(row.sparklinePayload.detailLevel.cacheComponent) oldPointCount=\(previousRow.sparklinePointCount) newPointCount=\(row.sparklinePointCount)"
            )
        }
    }

    private func graphLogSource(for row: MarketRowViewState) -> String {
        switch row.graphState {
        case .liveVisible:
            return "live"
        case .cachedVisible, .staleVisible:
            return "retained"
        case .none, .placeholder, .unavailable:
            return "placeholder"
        }
    }

    private func scheduleMarketHydrationIfNeeded(
        for exchange: Exchange,
        totalCount: Int,
        reason: String
    ) {
        marketHydrationTask?.cancel()

        guard activeTab == .market, selectedExchange == exchange else {
            return
        }
        guard shouldUseLimitedMarketFirstPaint(for: exchange, totalCount: totalCount) else {
            fullyHydratedMarketExchanges.insert(exchange)
            if let startedAt = marketSwitchStartedAtByExchange[exchange],
               marketFullHydrationPendingExchanges.contains(exchange) {
                marketFullHydrationPendingExchanges.remove(exchange)
                marketSwitchStartedAtByExchange.removeValue(forKey: exchange)
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                AppLogger.debug(
                    .lifecycle,
                    "[ExchangeSwitch] completed exchange=\(exchange.rawValue) hydratedRows=\(totalCount) elapsedMs=\(elapsedMs) reason=\(reason)"
                )
            }
            return
        }

        marketHydrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.marketHydrationDelayNanoseconds)
            guard self.activeTab == .market, self.selectedExchange == exchange else { return }

            self.fullyHydratedMarketExchanges.insert(exchange)
            AppLogger.debug(
                .lifecycle,
                "[MarketHydration] exchange=\(exchange.rawValue) total=\(totalCount) reason=\(reason)"
            )
            self.refreshMarketRowsForSelectedExchange(reason: "\(reason)_hydrated")
        }
    }

    private func applyCachedMarketPresentationIfAvailable(for exchange: Exchange, reason: String) {
        guard let snapshot = marketPresentationSnapshotsByExchange[exchange] else {
            AppLogger.debug(.network, "[MarketCache] miss exchange=\(exchange.rawValue) reason=\(reason)")
            AppLogger.debug(.lifecycle, "[ExchangeSwitch] cache miss exchange=\(exchange.rawValue) reason=\(reason)")
            if activeMarketPresentationSnapshot == nil, selectedExchange == exchange {
                assignMarketState(.loading)
            }
            return
        }

        AppLogger.debug(.network, "[MarketCache] hit exchange=\(exchange.rawValue) rows=\(snapshot.rows.count) reason=\(reason)")
        AppLogger.debug(.lifecycle, "[ExchangeSwitch] cache hit exchange=\(exchange.rawValue) rows=\(snapshot.rows.count) reason=\(reason)")
        AppLogger.debug(
            .network,
            "[MarketPipeline] exchange=\(exchange.rawValue) generation=\(marketPresentationGeneration) phase=show_cache baseRows=\(snapshot.rows.count)"
        )
        marketLoadState = SourceAwareLoadState(
            phase: .showingCache,
            hasPartialFailure: snapshot.meta.partialFailureMessage != nil
        )
        marketTransitionMessage = nil
        swapMarketPresentation(snapshot, reason: reason, clearTransition: false)
    }

    private func beginSameExchangeMarketReuse(reason: String) {
        guard let activeSnapshot = activeMarketPresentationSnapshot,
              activeSnapshot.exchange == selectedExchange else {
            return
        }

        marketPresentationState = MarketScreenPresentationState(
            selectedExchange: selectedExchange,
            representativeRowsState: marketPresentationState.representativeRowsState,
            listRowsState: marketPresentationState.listRowsState,
            sparklineAvailabilityState: marketPresentationState.sparklineAvailabilityState,
            transitionState: ExchangeTransitionState(
                exchange: selectedExchange,
                previousExchange: selectedExchange,
                phase: .loading
            ),
            sameExchangeStaleReuse: true,
            crossExchangeStaleReuseAllowed: false
        )
        assignMarketState(activeSnapshot.rows.isEmpty ? .loading : .loaded(activeSnapshot.universe.tradableCoins))
        marketTransitionMessage = "\(selectedExchange.displayName) 시세 업데이트 중"
        AppLogger.debug(.lifecycle, "[MarketScreen] same exchange reuse exchange=\(selectedExchange.rawValue) reason=\(reason)")
    }

    private func beginMarketTransition(to exchange: Exchange, from previousExchange: Exchange?, reason: String) {
        activeMarketPresentationSnapshot = nil
        marketBasePhaseByExchange[exchange] = .initialLoading
        marketPresentationState = MarketScreenPresentationState(
            selectedExchange: exchange,
            representativeRowsState: .empty(for: exchange, phase: .loading, showsPlaceholder: true),
            listRowsState: .empty(for: exchange, phase: .loading, showsPlaceholder: true),
            sparklineAvailabilityState: .empty(for: exchange),
            transitionState: ExchangeTransitionState(
                exchange: exchange,
                previousExchange: previousExchange,
                phase: previousExchange == nil ? .loading : .exchangeChanged
            ),
            sameExchangeStaleReuse: false,
            crossExchangeStaleReuseAllowed: false
        )
        marketRowStates = []
        assignMarketState(.loading)
        marketLoadState = .initialLoading
        marketTransitionMessage = "\(exchange.displayName) 시세 준비 중"
        AppLogger.debug(.lifecycle, "[MarketScreen] transition start exchange=\(exchange.rawValue) reason=\(reason)")
        MarketPerformanceDebugClient.shared.log(
            .skeletonShown,
            exchange: exchange,
            details: [
                "generation": "\(marketPresentationGeneration)",
                "previousExchange": previousExchange?.rawValue ?? "-",
                "reason": reason
            ]
        )
        AppLogger.debug(
            .network,
            "[MarketPipeline] exchange=\(exchange.rawValue) generation=\(marketPresentationGeneration) phase=show_skeleton baseRows=0"
        )
    }

    private func makeMarketRequestContext(for exchange: Exchange) -> MarketRequestContext {
        MarketRequestContext(
            exchange: exchange,
            route: activeTab,
            universeVersion: marketUniverseVersion(for: exchange),
            generation: marketPresentationGeneration
        )
    }

    private func marketUniverseVersion(for exchange: Exchange) -> String {
        let universe = marketUniverseSnapshot(for: exchange)
        if universe.serverUniverseCount == 0 && universe.tradableCount == 0 {
            return "pending"
        }

        return universe.symbolsHash
    }

    private func shouldAcceptMarketPresentation(
        _ requestContext: MarketRequestContext,
        responseUniverseVersion: String
    ) -> Bool {
        guard requestContext.exchange == selectedExchange else { return false }
        guard requestContext.generation == marketPresentationGeneration else { return false }
        guard requestContext.route == activeTab else { return false }
        return responseUniverseVersion.isEmpty == false || requestContext.universeVersion == responseUniverseVersion
    }

    private func shouldApplyVisibleTickerUpdate(for exchange: String) -> Bool {
        activeTab == .market && selectedExchange.rawValue == exchange
    }

    private func stableSymbolHash(from items: [String]) -> String {
        items.sorted().joined(separator: ",")
    }

    private func deduplicatedSymbols(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        return symbols.filter { symbol in
            seen.insert(symbol).inserted
        }
    }

    private func formatDroppedSymbols(_ symbols: [String]) -> String {
        guard !symbols.isEmpty else { return "-" }
        let preview = symbols.prefix(24)
        let suffix = symbols.count > preview.count ? "...(+\(symbols.count - preview.count))" : ""
        return preview.joined(separator: ",") + suffix
    }

    private func formatMarketChange(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }

    private func scheduleMarketSearchRefresh() {
        marketSearchDebounceTask?.cancel()
        marketSearchDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.refreshMarketRowsForSelectedExchange(reason: "market_search_debounced")
            if self.activeTab == .market {
                self.updatePublicSubscriptions(reason: "market_search_debounced")
            }
        }
    }

    private func derivedMarketBasePhase(
        for snapshot: MarketPresentationSnapshot,
        exchange: Exchange
    ) -> DataLoadPhase {
        let hasResolvedValues = snapshot.rows.contains(where: { $0.hasPrice || $0.hasVolume || $0.isChangePlaceholder == false })
        if hasResolvedValues {
            return .showingSnapshot
        }

        if marketBasePhaseByExchange[exchange] == .showingCache {
            return .showingCache
        }

        return .initialLoading
    }

    private func refreshMarketLoadState(reason: String) {
        let nextState: SourceAwareLoadState

        if let snapshot = activeMarketPresentationSnapshot,
           snapshot.exchange == selectedExchange {
            let exchange = snapshot.exchange
            let hasResolvedValues = snapshot.rows.contains(where: { $0.hasPrice || $0.hasVolume || $0.isChangePlaceholder == false })
            let hasPartialFailure = snapshot.meta.partialFailureMessage != nil
            let basePhase = marketBasePhaseByExchange[exchange] ?? derivedMarketBasePhase(for: snapshot, exchange: exchange)
            let phase: DataLoadPhase

            if currentPublicStreamingStatus == .pollingFallback, hasResolvedValues {
                phase = .degradedPolling
            } else if currentPublicStreamingStatus == .live,
                      firstTickerStreamEventsByExchange.contains(exchange),
                      hasResolvedValues {
                phase = .streaming
            } else if basePhase == .showingCache {
                phase = .showingCache
            } else if hasResolvedValues {
                phase = .showingSnapshot
            } else {
                phase = .initialLoading
            }

            nextState = SourceAwareLoadState(
                phase: phase,
                hasPartialFailure: hasPartialFailure
            )
        } else {
            switch marketState {
            case .failed:
                nextState = .hardFailure
            case .idle, .loading:
                nextState = .initialLoading
            case .loaded, .empty:
                nextState = SourceAwareLoadState(
                    phase: .showingSnapshot,
                    hasPartialFailure: false
                )
            }
        }

        if marketLoadState != nextState {
            AppLogger.debug(
                .lifecycle,
                "[MarketLoadState] \(marketLoadState.phase) -> \(nextState.phase) reason=\(reason) partial=\(nextState.hasPartialFailure)"
            )
            marketLoadState = nextState
        }
    }

    private func refreshKimchiLoadState(reason: String) {
        let nextState: SourceAwareLoadState

        if let presentation = activeKimchiPresentationSnapshot,
           presentation.exchange == currentKimchiDomesticExchange {
            let hasRows = presentation.rows.isEmpty == false
            let hasPartialFailure = presentation.meta.partialFailureMessage != nil
                || !(kimchiSnapshotsByExchange[presentation.exchange]?.failedSymbols.isEmpty ?? true)
            let basePhase = kimchiBasePhaseByExchange[presentation.exchange]
                ?? (hasPartialFailure ? .partialFailure : .showingSnapshot)
            let phase: DataLoadPhase

            switch basePhase {
            case .showingCache:
                phase = .showingCache
            case .degradedPolling:
                phase = .degradedPolling
            case .hardFailure:
                phase = .hardFailure
            case .initialLoading, .partialFailure:
                phase = hasRows ? .showingSnapshot : .initialLoading
            case .showingSnapshot, .streaming:
                phase = hasRows ? .showingSnapshot : .initialLoading
            }

            nextState = SourceAwareLoadState(
                phase: phase,
                hasPartialFailure: hasPartialFailure
            )
        } else {
            switch kimchiPremiumState {
            case .failed:
                nextState = .hardFailure
            case .idle, .loading:
                nextState = .initialLoading
            case .loaded, .empty:
                nextState = SourceAwareLoadState(
                    phase: .showingSnapshot,
                    hasPartialFailure: false
                )
            }
        }

        if kimchiLoadState != nextState {
            AppLogger.debug(
                .network,
                "[KimchiLoadState] \(kimchiLoadState.phase) -> \(nextState.phase) reason=\(reason) partial=\(nextState.hasPartialFailure)"
            )
            AppLogger.debug(
                .network,
                "[KimchiStateDebug] action=state_transition from=\(kimchiLoadState.phase) to=\(nextState.phase) reason=\(reason)"
            )
            kimchiLoadState = nextState
        }
        refreshKimchiHeaderState(reason: reason)
    }

    private func kimchiHeaderFreshnessThresholdExceeded(
        for exchange: Exchange,
        now: Date
    ) -> Bool {
        guard let fetchedAt = lastKimchiPremiumFetchedAtByExchange[exchange]
            ?? activeKimchiPresentationSnapshot?.meta.fetchedAt else {
            return false
        }
        return now.timeIntervalSince(fetchedAt) > (kimchiPremiumStaleInterval * 1.5)
    }

    private func hasVisibleRepresentativeKimchiData(for exchange: Exchange) -> Bool {
        guard kimchiPresentationState.selectedExchange == exchange else {
            return false
        }
        return kimchiPresentationState.representativeRowsState.rows.contains { $0.status != .loading }
    }

    private func cachedKimchiPresentation(for exchange: Exchange) -> KimchiPresentationSnapshot? {
        fullKimchiCacheByExchange[exchange]?.presentation
            ?? visibleKimchiCacheByExchange[exchange]?.presentation
            ?? representativeKimchiCacheByExchange[exchange]?.presentation
            ?? kimchiPresentationSnapshotsByExchange[exchange]
    }

    private func cachedKimchiEntry(for exchange: Exchange) -> KimchiCacheEntry? {
        fullKimchiCacheByExchange[exchange]
            ?? visibleKimchiCacheByExchange[exchange]
            ?? representativeKimchiCacheByExchange[exchange]
    }

    private func hasReadyableRepresentativeRows(in presentation: KimchiPresentationSnapshot?) -> Bool {
        guard let presentation else {
            return false
        }
        return representativeKimchiRows(from: presentation.rows).contains { $0.status != .loading }
    }

    private func isKimchiPresentationStaleEnoughToDelay(
        _ presentation: KimchiPresentationSnapshot,
        fetchedAt: Date?,
        now: Date
    ) -> Bool {
        if presentation.meta.isStale {
            return true
        }
        if presentation.rows.contains(where: { $0.freshnessState == .stale || $0.status == .stale }) {
            return true
        }
        guard let fetchedAt = fetchedAt ?? presentation.meta.fetchedAt else {
            return false
        }
        return now.timeIntervalSince(fetchedAt) > kimchiPremiumStaleInterval
    }

    private func representativeState(for exchange: Exchange, now: Date) -> KimchiRepresentativeState {
        if kimchiPresentationState.selectedExchange == exchange,
           hasVisibleRepresentativeKimchiData(for: exchange),
           let activePresentation = activeKimchiPresentationSnapshot,
           activePresentation.exchange == exchange {
            return isKimchiPresentationStaleEnoughToDelay(
                activePresentation,
                fetchedAt: lastKimchiPremiumFetchedAtByExchange[exchange],
                now: now
            ) ? .staleReady : .liveReady
        }

        if let cachedPresentation = cachedKimchiPresentation(for: exchange),
           hasReadyableRepresentativeRows(in: cachedPresentation) {
            let cacheEntry = cachedKimchiEntry(for: exchange)
            return isKimchiPresentationStaleEnoughToDelay(
                cachedPresentation,
                fetchedAt: cacheEntry?.fetchedAt,
                now: now
            ) ? .staleReady : .cachedReady
        }

        if isKimchiFetchInFlight(for: exchange) {
            return .loading
        }

        return .none
    }

    private func fullHydrationState(for exchange: Exchange) -> KimchiFullHydrationState {
        if kimchiLoadState.phase == .hardFailure {
            return .degraded
        }
        if isKimchiFullyHydrated(for: exchange) {
            return .complete
        }
        if isKimchiFetchInFlight(for: exchange) {
            return .batching
        }
        if activeKimchiPresentationSnapshot?.exchange == exchange,
           activeKimchiPresentationSnapshot?.rows.isEmpty == false {
            return .partial
        }
        return .idle
    }

    private func logKimchiInitialState(for exchange: Exchange, now: Date) {
        let representativeState = representativeState(for: exchange, now: now)
        let source: String
        let initialBadge: String

        switch representativeState {
        case .cachedReady, .liveReady:
            source = "representative_cache_fresh"
            initialBadge = "ready"
        case .staleReady:
            source = "representative_cache_stale_usable"
            initialBadge = "delayed"
        case .loading, .none:
            source = "no_representative_cache"
            initialBadge = "sync"
        }

        AppLogger.debug(
            .network,
            "[KimchiInitialStateDebug] exchange=\(exchange.rawValue) action=select initialBadge=\(initialBadge) source=\(source)"
        )
    }

    private func hasVisibleNonRepresentativeKimchiData(for exchange: Exchange) -> Bool {
        guard kimchiPresentationState.selectedExchange == exchange else {
            return false
        }
        let representativeSymbols = Set(kimchiPresentationState.representativeRowsState.rows.map(\.symbol))
        return kimchiPresentationState.listRowsState.rows.contains {
            representativeSymbols.contains($0.symbol) == false && $0.status != .loading
        }
    }

    private func isKimchiFetchInFlight(for exchange: Exchange) -> Bool {
        if kimchiPremiumFetchContext?.exchange == exchange {
            return true
        }
        return kimchiPremiumFetchTasksByContext.keys.contains { $0.exchange == exchange }
    }

    private func isKimchiFullyHydrated(for exchange: Exchange) -> Bool {
        guard let presentation = activeKimchiPresentationSnapshot,
              presentation.exchange == exchange else {
            return false
        }
        return fullyHydratedKimchiSymbolsHashByExchange[exchange] == presentation.symbolsHash
            && presentation.rows.isEmpty == false
    }

    private func targetKimchiBadgeState(
        for exchange: Exchange,
        now: Date
    ) -> (state: KimchiHeaderBadgeState, reason: String) {
        let representativeState = representativeState(for: exchange, now: now)
        let isDelayed = kimchiLoadState.phase == .degradedPolling
            || kimchiLoadState.hasPartialFailure
            || kimchiHeaderFreshnessThresholdExceeded(for: exchange, now: now)
            || activeKimchiPresentationSnapshot?.meta.isStale == true
            || representativeState == .staleReady

        if representativeState.isReadyEnough {
            return (isDelayed ? .delayed : .ready, "representative_ready_enough")
        }
        if kimchiLoadState.phase == .hardFailure {
            return (.degraded, "pipeline_hard_failure")
        }
        switch representativeState {
        case .loading:
            return (.syncing, "representative_pending")
        case .none:
            if isKimchiFetchInFlight(for: exchange) || kimchiPremiumState.value == nil {
                return (.syncing, "representative_pending")
            }
            return (.idle, "no_representative_data")
        case .cachedReady, .staleReady, .liveReady:
            return (isDelayed ? .delayed : .ready, "representative_ready_enough")
        }
    }

    private func targetKimchiCopyState(
        for exchange: Exchange,
        now: Date
    ) -> (state: KimchiHeaderCopyState, reason: String) {
        let representativeState = representativeState(for: exchange, now: now)
        let fullHydrationState = fullHydrationState(for: exchange)
        let isDelayed = kimchiLoadState.phase == .degradedPolling
            || kimchiLoadState.hasPartialFailure
            || kimchiHeaderFreshnessThresholdExceeded(for: exchange, now: now)
            || activeKimchiPresentationSnapshot?.meta.isStale == true
            || representativeState == .staleReady

        if kimchiLoadState.phase == .hardFailure && representativeState.isReadyEnough == false {
            return (.degraded, "pipeline_hard_failure")
        }
        if representativeState.isReadyEnough == false {
            return (.representativeLoading, "representative_pending")
        }
        if isDelayed {
            return (.delayed, "freshness_threshold_exceeded")
        }
        if fullHydrationState == .complete {
            return (.fullyHydrated, "full_hydration_complete")
        }
        if fullHydrationState == .batching
            || fullHydrationState == .partial
            || hasVisibleNonRepresentativeKimchiData(for: exchange) {
            return (.progressiveHydrating, "background_batch_only")
        }
        return (.representativeVisible, "representative_visible")
    }

    private func stabilizedKimchiBadgeState(
        target: KimchiHeaderBadgeState,
        exchange: Exchange,
        reason: String,
        now: Date
    ) -> KimchiHeaderBadgeState {
        let currentState = kimchiHeaderState.badgeState
        let representativeState = representativeState(for: exchange, now: now)
        if (currentState == .ready || currentState == .delayed),
           target == .syncing,
           representativeState.isReadyEnough {
            AppLogger.debug(
                .network,
                "[KimchiBadgeDebug] action=drop_transition from=\(currentState) to=\(target) reason=already_readyable"
            )
            return currentState
        }
        if kimchiHeaderState.exchange != exchange {
            AppLogger.debug(
                .network,
                "[KimchiBadgeDebug] action=transition from=\(currentState) to=\(target) reason=exchange_changed"
            )
            lastKimchiBadgeTransitionAt = now
            return target
        }
        guard currentState != target else {
            if currentState == .ready && reason == "minor_background_refresh" {
                AppLogger.debug(
                    .network,
                    "[KimchiBadgeDebug] action=keep badge=ready reason=minor_background_refresh"
                )
            }
            return currentState
        }
        if currentState == .syncing && target != .syncing {
            AppLogger.debug(
                .network,
                "[KimchiBadgeDebug] action=transition from=\(currentState) to=\(target) reason=\(reason)"
            )
            lastKimchiBadgeTransitionAt = now
            return target
        }

        let minimumHold: TimeInterval
        switch currentState {
        case .ready:
            minimumHold = kimchiBadgeReadyMinimumHold
        case .syncing:
            minimumHold = kimchiBadgeSyncMinimumHold
        case .idle, .delayed, .degraded:
            minimumHold = 0
        }

        if now.timeIntervalSince(lastKimchiBadgeTransitionAt) < minimumHold {
            AppLogger.debug(
                .network,
                "[KimchiBadgeDebug] action=drop_transition from=\(currentState) to=\(target) reason=hold_window_active"
            )
            return currentState
        }

        AppLogger.debug(
            .network,
            "[KimchiBadgeDebug] action=transition from=\(currentState) to=\(target) reason=\(reason)"
        )
        lastKimchiBadgeTransitionAt = now
        return target
    }

    private func stabilizedKimchiCopyState(
        target: KimchiHeaderCopyState,
        exchange: Exchange,
        reason: String,
        now: Date
    ) -> KimchiHeaderCopyState {
        let currentState = kimchiHeaderState.copyState
        if kimchiHeaderState.exchange != exchange {
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=transition from=\(currentState) to=\(target)"
            )
            lastKimchiCopyTransitionAt = now
            return target
        }
        guard currentState != target else {
            if reason == "background_batch_only" {
                AppLogger.debug(
                    .network,
                    "[KimchiHeaderDebug] action=keep_copy copy=\(currentState) reason=background_batch_only"
                )
            }
            return currentState
        }
        if currentState != .representativeLoading && target == .representativeLoading {
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=drop_transition from=\(currentState) to=\(target) reason=already_visible"
            )
            return currentState
        }
        if currentState == .fullyHydrated && target == .progressiveHydrating {
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=keep_copy copy=fullyHydrated reason=background_batch_only"
            )
            return currentState
        }
        if currentState == .representativeLoading && target != .representativeLoading {
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=transition from=\(currentState) to=\(target)"
            )
            lastKimchiCopyTransitionAt = now
            return target
        }
        if now.timeIntervalSince(lastKimchiCopyTransitionAt) < kimchiHeaderCopyMinimumHold {
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=drop_transition from=\(currentState) to=\(target) reason=hold_window_active"
            )
            return currentState
        }

        AppLogger.debug(
            .network,
            "[KimchiHeaderDebug] action=transition from=\(currentState) to=\(target)"
        )
        lastKimchiCopyTransitionAt = now
        return target
    }

    private func refreshKimchiHeaderState(reason: String) {
        let exchange = currentKimchiDomesticExchange
        let now = Date()
        let badgeTarget = targetKimchiBadgeState(for: exchange, now: now)
        let copyTarget = targetKimchiCopyState(for: exchange, now: now)
        let nextState = KimchiHeaderViewState(
            exchange: exchange,
            badgeState: stabilizedKimchiBadgeState(
                target: badgeTarget.state,
                exchange: exchange,
                reason: badgeTarget.reason,
                now: now
            ),
            copyState: stabilizedKimchiCopyState(
                target: copyTarget.state,
                exchange: exchange,
                reason: copyTarget.reason,
                now: now
            )
        )

        if kimchiHeaderState != nextState {
            kimchiHeaderState = nextState
        } else if reason == "background_batch_only" && nextState.copyState == .progressiveHydrating {
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=keep_copy copy=progressiveHydrating reason=background_batch_only"
            )
        }
    }

    private func logMarketScreenCounts(reason: String, rows: [MarketRowViewState]? = nil) {
        let baseRows = rows ?? marketRowStates
        let filteredRows = filteredMarketRows(from: baseRows)
        let normalizedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let universe = marketUniverseSnapshot(for: selectedExchange)
        let signature = [
            selectedExchange.rawValue,
            universe.symbolsHash,
            "\(baseRows.count)",
            "\(filteredRows.count)",
            marketFilter.rawValue,
            normalizedSearch
        ].joined(separator: "|")

        guard lastLoggedMarketPipelineSignature != signature else {
            return
        }

        lastLoggedMarketPipelineSignature = signature
        AppLogger.debug(
            .lifecycle,
            "[MarketScreen] source=\(universe.source.rawValue) serverUniverseCount=\(universe.serverUniverseCount) tradableCount=\(universe.tradableCount) displayedCount=\(baseRows.count) filteredCount=\(filteredRows.count) droppedSymbols=\(formatDroppedSymbols(universe.droppedSymbols)) filteredUnsupported=\(formatDroppedSymbols(universe.filteredSymbols)) pending=\(universe.pendingSymbols.count) exchange=\(selectedExchange.rawValue) reason=\(reason)"
        )
        AppLogger.debug(
            .lifecycle,
            "[MarketScreen] filtered rows count=\(filteredRows.count) exchange=\(selectedExchange.rawValue) filter=\(marketFilter.rawValue) search=\(normalizedSearch.isEmpty ? "-" : normalizedSearch)"
        )
        AppLogger.debug(.lifecycle, "[MarketScreen] displayed items count=\(filteredRows.count) exchange=\(selectedExchange.rawValue)")
    }

    private func logAssetImageCoverageSummary(reason: String) {
        let rowsByMarketIdentity = Dictionary(uniqueKeysWithValues: marketRowStates.map { ($0.marketIdentity, $0) })
        var orderedRows = [MarketRowViewState]()
        var seen = Set<MarketIdentity>()

        func append(_ row: MarketRowViewState?) {
            guard let row,
                  row.exchange == selectedExchange,
                  seen.insert(row.marketIdentity).inserted else {
                return
            }
            orderedRows.append(row)
        }

        for marketIdentity in visibleMarketIdentitiesByExchange[selectedExchange] ?? [] {
            append(rowsByMarketIdentity[marketIdentity])
        }
        for row in marketRowStates.prefix(marketImageVisibleBatchSize) {
            append(row)
        }
        let rows = orderedRows.prefix(marketImageVisibleBatchSize)

        var liveCount = 0
        var placeholderPendingCount = 0
        var placeholderFinalCount = 0

        for row in rows {
            switch assetImageClient.assetState(for: row.symbolImageDescriptor) {
            case .liveCached, .liveNetwork:
                liveCount += 1
            case .idle, .warming, .placeholderPending:
                placeholderPendingCount += 1
            case .placeholderFinal:
                placeholderFinalCount += 1
            }
        }
        let visibleCount = liveCount + placeholderPendingCount + placeholderFinalCount
        let liveRatioPct = visibleCount == 0 ? 0 : Int((Double(liveCount) / Double(visibleCount) * 100).rounded())
        let eventCounts = AssetImageDebugClient.shared.snapshotEventCounts()
        let fallbackCounts = AssetImageDebugClient.shared.snapshotFallbackReasonCounts()

        AssetImageDebugClient.shared.log(
            .coverageSummary,
            marketIdentity: nil,
            category: .network,
            details: [
                "cacheHitDisk": "\(eventCounts["cache_hit_disk"] ?? 0)",
                "cacheHitMemory": "\(eventCounts["cache_hit_memory"] ?? 0)",
                "deduped": "\(eventCounts["request_deduped"] ?? 0)",
                "exchange": selectedExchange.rawValue,
                "live": "\(liveCount)",
                "liveRatioPct": "\(liveRatioPct)",
                "networkFetch": "\(eventCounts["request_start"] ?? 0)",
                "noImageURL": "\(fallbackCounts[AssetImageFallbackReason.noImageURL.rawValue] ?? 0)",
                "placeholderFinal": "\(placeholderFinalCount)",
                "placeholderFinalTotal": "\(eventCounts["placeholder_final"] ?? 0)",
                "placeholderPending": "\(placeholderPendingCount)",
                "reason": reason,
                "unsupportedAsset": "\(fallbackCounts[AssetImageFallbackReason.unsupportedAsset.rawValue] ?? 0)",
                "visible": "\(visibleCount)"
            ]
        )
    }

    private func ensureSelectedCoinForCurrentExchange() {
        ensureSelectedCoinIfPossible(for: selectedExchange)
    }

    private func ensureSelectedCoinIfPossible(for exchange: Exchange) {
        guard selectedExchange == exchange else { return }
        let supportedCoins = resolvedMarketUniverse(for: exchange)
        guard let firstCoin = supportedCoins.first else {
            return
        }

        if let selectedCoin {
            let selectedMarketIdentity = selectedCoin.marketIdentity(exchange: exchange)
            let supportedCoin = supportedCoins.first {
                $0.marketIdentity(exchange: exchange) == selectedMarketIdentity
            } ?? supportedCoins.first(where: { $0.symbol == selectedCoin.symbol })
            if let supportedCoin {
                let mergedCoin = selectedCoin.merged(with: supportedCoin)
                if mergedCoin != selectedCoin {
                    self.selectedCoin = mergedCoin
                }
                prefillOrderPriceIfPossible()
                return
            }
        }

        selectedCoin = firstCoin
        prefillOrderPriceIfPossible()
    }

    private func refreshPublicStatusViewStates() {
        let nextMarketStatus = screenStatusFactory.makeStatusViewState(
            meta: marketMetaForStatus,
            streamingStatus: currentPublicStreamingStatus,
            context: .market,
            warningMessage: currentPublicStreamingWarningMessage,
            loadState: marketLoadState
        )
        if marketStatusViewState != nextMarketStatus {
            marketStatusViewState = nextMarketStatus
        }

        let nextChartStatus = screenStatusFactory.makeStatusViewState(
            meta: chartMetaForStatus,
            streamingStatus: currentPublicStreamingStatus,
            context: .chart,
            warningMessage: currentPublicStreamingWarningMessage
        )
        if chartStatusViewState != nextChartStatus {
            chartStatusViewState = nextChartStatus
        }

        let nextKimchiStatus = screenStatusFactory.makeStatusViewState(
            meta: kimchiMetaForStatus,
            streamingStatus: kimchiStreamingStatus,
            context: .kimchi,
            warningMessage: nil,
            loadState: kimchiLoadState
        )
        if kimchiStatusViewState != nextKimchiStatus {
            kimchiStatusViewState = nextKimchiStatus
        }
        refreshKimchiHeaderState(reason: "public_status_refresh")
    }

    private func refreshPrivateStatusViewStates() {
        let nextPortfolioStatus = screenStatusFactory.makeStatusViewState(
            meta: portfolioMetaForStatus,
            streamingStatus: currentPrivateStreamingStatus,
            context: .portfolio,
            warningMessage: resolvedWarningMessage(
                primary: portfolioRefreshWarningMessage ?? portfolioMetaForStatus.partialFailureMessage,
                fallback: currentPrivateStreamingWarningMessage
            )
        )
        if portfolioStatusViewState != nextPortfolioStatus {
            portfolioStatusViewState = nextPortfolioStatus
        }

        let nextTradingStatus = screenStatusFactory.makeStatusViewState(
            meta: tradingMetaForStatus,
            streamingStatus: currentPrivateStreamingStatus,
            context: .trade,
            warningMessage: resolvedWarningMessage(
                primary: tradingChanceState.value?.warningMessage,
                fallback: currentPrivateStreamingWarningMessage
            )
        )
        if tradingStatusViewState != nextTradingStatus {
            tradingStatusViewState = nextTradingStatus
        }
    }

    private func targetMarketStreamingMarketIdentities(for exchange: Exchange, limit: Int = 24) -> [MarketIdentity] {
        let visibleMarketIdentities = visibleMarketIdentitiesByExchange[exchange] ?? []
        if !visibleMarketIdentities.isEmpty {
            return Array(visibleMarketIdentities.prefix(limit))
        }

        let visibleRows = displayedMarketRows
            .filter { $0.exchange == exchange }
            .prefix(limit)
            .map(\.marketIdentity)

        if !visibleRows.isEmpty {
            return Self.deduplicatedMarketIdentities(Array(visibleRows))
        }

        if let cachedRows = marketPresentationSnapshotsByExchange[exchange]?.rows, !cachedRows.isEmpty {
            return Self.deduplicatedMarketIdentities(Array(cachedRows.prefix(limit).map(\.marketIdentity)))
        }

        let snapshotMarketIdentities = (tickerSnapshotCoinsByExchange[exchange] ?? [])
            .map { $0.marketIdentity(exchange: exchange) }
        if !snapshotMarketIdentities.isEmpty {
            return Array(Self.deduplicatedMarketIdentities(snapshotMarketIdentities).prefix(limit))
        }

        return []
    }

    private var desiredPublicSubscriptions: Set<PublicMarketSubscription> {
        var subscriptions = Set<PublicMarketSubscription>()

        switch activeTab {
        case .market:
            targetMarketStreamingMarketIdentities(for: selectedExchange).forEach { marketIdentity in
                subscriptions.insert(
                    PublicMarketSubscription(
                        channel: .ticker,
                        marketIdentity: marketIdentity
                    )
                )
            }
        case .trade, .chart:
            let marketIdentities = selectedCoin.map { [$0.marketIdentity(exchange: selectedExchange)] }
                ?? targetMarketStreamingMarketIdentities(for: selectedExchange, limit: 8)
            marketIdentities.forEach { marketIdentity in
                subscriptions.insert(
                    PublicMarketSubscription(
                        channel: .ticker,
                        marketIdentity: marketIdentity
                    )
                )
            }
        case .portfolio, .kimchi:
            break
        }

        if activeTab == .chart, let selectedCoin, chartSecondarySubscriptionsEnabled {
            let selectedMarketIdentity = selectedCoin.marketIdentity(exchange: exchange)
            let mappedInterval = resolvedChartInterval(
                requestedInterval: chartPeriod,
                symbol: selectedMarketIdentity.symbol,
                exchange: exchange
            )
            subscriptions.insert(
                PublicMarketSubscription(
                    channel: .orderbook,
                    marketIdentity: selectedMarketIdentity
                )
            )
            subscriptions.insert(
                PublicMarketSubscription(
                    channel: .trades,
                    marketIdentity: selectedMarketIdentity
                )
            )
            subscriptions.insert(
                PublicMarketSubscription(
                    channel: .candles,
                    marketIdentity: selectedMarketIdentity,
                    interval: mappedInterval
                )
            )
        }

        return subscriptions
    }

    private var requiresPublicStreaming: Bool {
        !desiredPublicSubscriptions.isEmpty
    }

    private func shouldSkipChartSnapshot(for context: ChartRequestContext) -> Bool {
        guard let lastChartSnapshotContext, lastChartSnapshotContext == context else { return false }
        guard let lastChartSnapshotFetchedAt else { return false }
        guard Date().timeIntervalSince(lastChartSnapshotFetchedAt) < chartSnapshotStaleInterval else { return false }
        return hasChartSnapshotResult
    }

    private var hasChartSnapshotResult: Bool {
        candlesState.hasResolvedResult
            && orderbookState.hasResolvedResult
            && recentTradesState.hasResolvedResult
    }

    private func scheduleKimchiPremiumSettlementIfNeeded(
        snapshot: KimchiPremiumSnapshot,
        exchange: Exchange,
        comparableSymbols: [String],
        symbolsHash: String,
        requestVersion: Int
    ) {
        let rows = kimchiPremiumViewStateUseCase.makeCoinViewStates(
            from: snapshot,
            comparableSymbols: comparableSymbols,
            selectedDomesticExchange: exchange,
            phase: .responsePending
        )
        let requiresSettlement = rows.contains(where: isTransientKimchiStatus(_:))

        guard requiresSettlement else {
            return
        }

        kimchiPremiumSettleTask?.cancel()
        kimchiPremiumSettleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.kimchiPremiumSettleInterval))
            guard requestVersion == self.kimchiPremiumRequestVersion else { return }
            guard let cachedSnapshot = self.kimchiSnapshotsByExchange[exchange] else { return }

            let presentationBuildStartedAt = Date()
            let presentation = await self.prepareKimchiPresentationSnapshot(
                from: cachedSnapshot,
                exchange: exchange,
                comparableSymbols: comparableSymbols,
                symbolsHash: symbolsHash,
                phase: .settled
            )
            let presentationBuildElapsedMs = Int(Date().timeIntervalSince(presentationBuildStartedAt) * 1000)
            AppLogger.debug(
                .network,
                "[KimchiSwitchPerf] exchange=\(exchange.rawValue) phase=prepare_settlement elapsedMs=\(presentationBuildElapsedMs)"
            )
            let publishStartedAt = Date()
            self.swapKimchiPresentation(presentation, reason: "kimchi_settlement", clearTransition: true)
            let publishElapsedMs = Int(Date().timeIntervalSince(publishStartedAt) * 1000)
            AppLogger.debug(
                .network,
                "[KimchiSwitchPerf] exchange=\(exchange.rawValue) phase=publish_settlement elapsedMs=\(publishElapsedMs)"
            )
        }
    }

    private func prepareKimchiPresentationSnapshot(
        from snapshot: KimchiPremiumSnapshot,
        exchange: Exchange,
        comparableSymbols: [String],
        symbolsHash: String,
        phase: KimchiPremiumViewStateUseCase.PresentationPhase
    ) async -> KimchiPresentationSnapshot {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.buildKimchiPresentationSnapshot(
                    from: snapshot,
                    exchange: exchange,
                    comparableSymbols: comparableSymbols,
                    symbolsHash: symbolsHash,
                    phase: phase
                ))
            }
        }
    }

    private func makeKimchiPresentationSnapshot(
        from snapshot: KimchiPremiumSnapshot,
        exchange: Exchange,
        comparableSymbols: [String],
        symbolsHash: String,
        phase: KimchiPremiumViewStateUseCase.PresentationPhase
    ) -> KimchiPresentationSnapshot {
        Self.buildKimchiPresentationSnapshot(
            from: snapshot,
            exchange: exchange,
            comparableSymbols: comparableSymbols,
            symbolsHash: symbolsHash,
            phase: phase
        )
    }

    private nonisolated static func buildKimchiPresentationSnapshot(
        from snapshot: KimchiPremiumSnapshot,
        exchange: Exchange,
        comparableSymbols: [String],
        symbolsHash: String,
        phase: KimchiPremiumViewStateUseCase.PresentationPhase
    ) -> KimchiPresentationSnapshot {
        let rows = KimchiPremiumViewStateUseCase().makeCoinViewStates(
            from: snapshot,
            comparableSymbols: comparableSymbols,
            selectedDomesticExchange: exchange,
            phase: phase
        )
        let meta = ResponseMeta(
            fetchedAt: snapshot.fetchedAt,
            isStale: snapshot.isStale,
            warningMessage: snapshot.warningMessage,
            partialFailureMessage: snapshot.partialFailureMessage
        )

        return KimchiPresentationSnapshot(
            exchange: exchange,
            comparableSymbols: comparableSymbols,
            symbolsHash: symbolsHash,
            rows: rows,
            meta: meta,
            phase: phase
        )
    }

    private func representativeKimchiRows(from rows: [KimchiPremiumCoinViewState]) -> [KimchiPremiumCoinViewState] {
        Array(rows.prefix(kimchiRepresentativeRowLimit))
    }

    private func kimchiRowsPhase(for presentation: KimchiPresentationSnapshot) -> ExchangeRowsPhase {
        let isHydrated = fullyHydratedKimchiSymbolsHashByExchange[presentation.exchange] == presentation.symbolsHash
        if presentation.rows.isEmpty {
            return .loading
        }
        if isHydrated,
           presentation.meta.partialFailureMessage == nil,
           presentation.phase == .settled {
            return .hydrated
        }
        return .partial
    }

    private func makeKimchiPresentationState(
        from presentation: KimchiPresentationSnapshot,
        previousExchange: Exchange?,
        sameExchangeStaleReuse: Bool,
        transitionPhase: ExchangeTransitionPhase? = nil
    ) -> KimchiScreenPresentationState {
        let representativeRows = representativeKimchiRows(from: presentation.rows)
        let listPhase = kimchiRowsPhase(for: presentation)
        let representativePhase: ExchangeRowsPhase
        if representativeRows.isEmpty {
            representativePhase = .loading
        } else if listPhase == .hydrated {
            representativePhase = .hydrated
        } else {
            representativePhase = .partial
        }

        return KimchiScreenPresentationState(
            selectedExchange: presentation.exchange,
            representativeRowsState: ExchangeRowsState(
                exchange: presentation.exchange,
                rows: representativeRows,
                phase: representativePhase,
                showsPlaceholder: representativeRows.isEmpty
            ),
            listRowsState: ExchangeRowsState(
                exchange: presentation.exchange,
                rows: presentation.rows,
                phase: listPhase,
                showsPlaceholder: presentation.rows.isEmpty
            ),
            transitionState: ExchangeTransitionState(
                exchange: presentation.exchange,
                previousExchange: previousExchange,
                phase: transitionPhase
                    ?? (listPhase == .hydrated ? .hydrated : (presentation.rows.isEmpty ? .loading : .partial))
            ),
            sameExchangeStaleReuse: sameExchangeStaleReuse,
            crossExchangeStaleReuseAllowed: false
        )
    }

    private func swapKimchiPresentation(
        _ presentation: KimchiPresentationSnapshot,
        reason: String,
        clearTransition: Bool
    ) {
        let previousRows = kimchiPremiumState.value ?? []
        kimchiPresentationSnapshotsByExchange[presentation.exchange] = presentation
        activeKimchiPresentationSnapshot = presentation
        let hasReadyableRows = hasReadyableRepresentativeRows(in: presentation)
        let hasFailureMessage = presentation.meta.partialFailureMessage != nil
        if clearTransition == false {
            kimchiBasePhaseByExchange[presentation.exchange] = .showingCache
        } else if hasFailureMessage,
                  let existingPhase = kimchiBasePhaseByExchange[presentation.exchange],
                  existingPhase == .hardFailure || existingPhase == .partialFailure {
            kimchiBasePhaseByExchange[presentation.exchange] = existingPhase
        } else {
            kimchiBasePhaseByExchange[presentation.exchange] = .showingSnapshot
        }
        let transitionPhase: ExchangeTransitionPhase?
        if clearTransition {
            transitionPhase = nil
        } else if hasReadyableRows {
            transitionPhase = .hydrated
        } else if kimchiPresentationState.selectedExchange == presentation.exchange,
                  kimchiPresentationState.transitionState.isLoading {
            transitionPhase = kimchiPresentationState.transitionState.phase
        } else {
            transitionPhase = .loading
        }
        kimchiPresentationState = makeKimchiPresentationState(
            from: presentation,
            previousExchange: kimchiPresentationState.selectedExchange == presentation.exchange ? nil : kimchiPresentationState.selectedExchange,
            sameExchangeStaleReuse: false,
            transitionPhase: transitionPhase
        )
        logKimchiRowTransitions(from: previousRows, to: presentation.rows)
        updateKimchiPremiumState(
            presentation.rows.isEmpty ? .empty : .loaded(presentation.rows),
            rowsCount: presentation.rows.count
        )
        logKimchiSwitchProgressIfNeeded(presentation: presentation, reason: reason)
        refreshKimchiLoadState(reason: reason)
        kimchiStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: presentation.meta,
            streamingStatus: kimchiStreamingStatus,
            context: .kimchi,
            warningMessage: presentation.meta.warningMessage,
            loadState: kimchiLoadState
        )
        AppLogger.debug(
            .network,
            "[KimchiView] swapped staged rows exchange=\(presentation.exchange.rawValue) count=\(presentation.rows.count)"
        )

        if presentation.phase == .settled {
            presentation.rows.forEach { row in
                AppLogger.debug(.network, "[KimchiRow] settled symbol=\(row.symbol) state=\(describe(row.status))")
            }
        }

        if clearTransition, presentation.exchange == currentKimchiDomesticExchange {
            kimchiTransitionMessage = nil
        } else if clearTransition == false, hasReadyableRows == false {
            kimchiTransitionMessage = "\(presentation.exchange.displayName) 비교값 준비 중"
        } else {
            kimchiTransitionMessage = nil
        }

        AppLogger.debug(
            .network,
            "[KimchiView] displayed rows count=\(presentation.rows.count) exchange=\(presentation.exchange.rawValue) reason=\(reason)"
        )
        refreshKimchiHeaderState(reason: reason)
    }

    private func applyCachedKimchiPresentationIfAvailable(for exchange: Exchange, reason: String) {
        guard let presentation = cachedKimchiPresentation(for: exchange) else {
            AppLogger.debug(.network, "[KimchiCache] miss exchange=\(exchange.rawValue) reason=\(reason)")
            AppLogger.debug(.network, "[KimchiSwitch] cache miss exchange=\(exchange.rawValue) reason=\(reason)")
            AppLogger.debug(
                .network,
                "[KimchiInitialStateDebug] exchange=\(exchange.rawValue) action=select initialBadge=sync source=no_representative_cache"
            )
            return
        }

        let cacheApplyStartedAt = Date()
        AppLogger.debug(.network, "[KimchiCache] hit exchange=\(exchange.rawValue) rows=\(presentation.rows.count) reason=\(reason)")
        AppLogger.debug(.network, "[KimchiSwitch] cache hit exchange=\(exchange.rawValue) rows=\(presentation.rows.count) reason=\(reason)")
        if hasReadyableRepresentativeRows(in: presentation) {
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=preserve_shell reason=exchange_switch_with_cache"
            )
        }
        kimchiBasePhaseByExchange[exchange] = .showingCache
        refreshKimchiLoadState(reason: reason)
        kimchiTransitionMessage = nil
        swapKimchiPresentation(presentation, reason: reason, clearTransition: false)
        let cacheApplyElapsedMs = Int(Date().timeIntervalSince(cacheApplyStartedAt) * 1000)
        AppLogger.debug(
            .network,
            "[KimchiSwitchPerf] exchange=\(exchange.rawValue) phase=apply_cached_shell elapsedMs=\(cacheApplyElapsedMs)"
        )
    }

    private func beginSameExchangeKimchiReuse(reason: String) {
        guard activeKimchiPresentationSnapshot?.exchange == currentKimchiDomesticExchange else {
            return
        }

        kimchiPresentationState = KimchiScreenPresentationState(
            selectedExchange: currentKimchiDomesticExchange,
            representativeRowsState: kimchiPresentationState.representativeRowsState,
            listRowsState: kimchiPresentationState.listRowsState,
            transitionState: ExchangeTransitionState(
                exchange: currentKimchiDomesticExchange,
                previousExchange: currentKimchiDomesticExchange,
                phase: .loading
            ),
            sameExchangeStaleReuse: true,
            crossExchangeStaleReuseAllowed: false
        )
        kimchiTransitionMessage = "\(currentKimchiDomesticExchange.displayName) 비교값 업데이트 중"
        AppLogger.debug(.network, "[KimchiView] same exchange reuse exchange=\(currentKimchiDomesticExchange.rawValue) reason=\(reason)")
        refreshKimchiHeaderState(reason: "minor_background_refresh")
    }

    private func beginKimchiTransition(to exchange: Exchange, reason: String) {
        if hasReadyableRepresentativeRows(in: cachedKimchiPresentation(for: exchange)) {
            logKimchiInitialState(for: exchange, now: Date())
            AppLogger.debug(
                .network,
                "[KimchiHeaderDebug] action=preserve_shell reason=exchange_switch_with_cache"
            )
            applyCachedKimchiPresentationIfAvailable(for: exchange, reason: "\(reason)_cached")
            return
        }
        logKimchiInitialState(for: exchange, now: Date())

        let comparableSymbols = prioritizedSymbols(
            from: (marketsByExchange[exchange] ?? [])
                .filter(\.isKimchiComparable)
                .map(\.symbol),
            exchange: exchange
        )

        if comparableSymbols.isEmpty == false {
            let shellPresentation = makeKimchiPresentationSnapshot(
                from: emptyKimchiSnapshot(),
                exchange: exchange,
                comparableSymbols: comparableSymbols,
                symbolsHash: stableSymbolHash(from: comparableSymbols),
                phase: .responsePending
            )
            kimchiBasePhaseByExchange[exchange] = .initialLoading
            kimchiPresentationState = makeKimchiPresentationState(
                from: shellPresentation,
                previousExchange: activeKimchiPresentationSnapshot?.exchange,
                sameExchangeStaleReuse: false,
                transitionPhase: .exchangeChanged
            )
            updateKimchiPremiumState(.loaded(shellPresentation.rows), rowsCount: shellPresentation.rows.count)
        } else {
            kimchiBasePhaseByExchange[exchange] = .initialLoading
            kimchiPresentationState = KimchiScreenPresentationState(
                selectedExchange: exchange,
                representativeRowsState: .empty(for: exchange, phase: .loading, showsPlaceholder: true),
                listRowsState: .empty(for: exchange, phase: .loading, showsPlaceholder: true),
                transitionState: ExchangeTransitionState(
                    exchange: exchange,
                    previousExchange: activeKimchiPresentationSnapshot?.exchange,
                    phase: activeKimchiPresentationSnapshot == nil ? .loading : .exchangeChanged
                ),
                sameExchangeStaleReuse: false,
                crossExchangeStaleReuseAllowed: false
            )
            updateKimchiPremiumState(.loading)
        }
        refreshKimchiLoadState(reason: reason)
        kimchiTransitionMessage = "\(exchange.displayName) 비교값 준비 중"
        AppLogger.debug(.network, "[KimchiView] transition start exchange=\(exchange.rawValue) reason=\(reason)")
        refreshKimchiHeaderState(reason: reason)
    }

    private func logKimchiSwitchProgressIfNeeded(
        presentation: KimchiPresentationSnapshot,
        reason: String
    ) {
        guard let startedAt = kimchiSwitchStartedAtByExchange[presentation.exchange] else {
            return
        }
        guard kimchiFirstVisibleLoggedExchanges.contains(presentation.exchange) == false,
              presentation.rows.isEmpty == false else {
            return
        }

        kimchiFirstVisibleLoggedExchanges.insert(presentation.exchange)
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        AppLogger.debug(
            .network,
            "[KimchiSwitch] first visible rows exchange=\(presentation.exchange.rawValue) rows=\(presentation.rows.count) elapsedMs=\(elapsedMs) reason=\(reason)"
        )
    }

    private func isTransientKimchiStatus(_ row: KimchiPremiumCoinViewState) -> Bool {
        switch row.status {
        case .loading:
            return true
        case .loaded, .unavailable, .stale, .failed:
            return false
        }
    }

    private func logKimchiRowTransitions(
        from oldRows: [KimchiPremiumCoinViewState],
        to newRows: [KimchiPremiumCoinViewState]
    ) {
        let oldStatusByID = Dictionary(uniqueKeysWithValues: oldRows.map { ($0.id, $0.status) })
        for row in newRows {
            let oldStatus = oldStatusByID[row.id]
            guard oldStatus != row.status else { continue }
            AppLogger.debug(
                .network,
                "[KimchiRow] state transition symbol=\(row.symbol) \(describe(oldStatus)) -> \(describe(row.status))"
            )
        }
    }

    private func updateKimchiPremiumState(
        _ newState: Loadable<[KimchiPremiumCoinViewState]>,
        rowsCount: Int? = nil
    ) {
        let previousState = describe(kimchiPremiumState)
        let nextState = describe(newState)
        kimchiPremiumState = newState

        var logMessage = "[KimchiView] state \(previousState) -> \(nextState)"
        if let rowsCount {
            logMessage += " rows=\(rowsCount)"
        }
        AppLogger.debug(.network, logMessage)
    }

    private func describe(_ status: KimchiPremiumCoinStatus?) -> String {
        guard let status else { return "nil" }
        return describe(status)
    }

    private func describe(_ status: KimchiPremiumCoinStatus) -> String {
        switch status {
        case .loading:
            return "loading"
        case .loaded:
            return "loaded"
        case .unavailable:
            return "unavailable"
        case .stale:
            return "stale"
        case .failed:
            return "failed"
        }
    }

    private var currentPublicStreamingStatus: StreamingStatus {
        guard requiresPublicStreaming else {
            return .snapshotOnly
        }

        switch publicWebSocketState {
        case .connected:
            return .live
        case .connecting:
            return .snapshotOnly
        case .disconnected, .failed:
            return .pollingFallback
        }
    }

    private var currentPrivateStreamingStatus: StreamingStatus {
        switch privateWebSocketState {
        case .connected:
            return .live
        case .connecting:
            return .pollingFallback
        case .disconnected, .failed:
            return .pollingFallback
        }
    }

    private var kimchiStreamingStatus: StreamingStatus {
        kimchiLoadState.phase == .degradedPolling ? .pollingFallback : .snapshotOnly
    }

    private var currentPublicStreamingWarningMessage: String? {
        guard requiresPublicStreaming else { return nil }

        switch publicWebSocketState {
        case .failed(let message):
            return userFacingStreamingWarning(from: message)
        case .disconnected:
            return "연결이 잠시 불안정해 최신 정보를 다시 확인하고 있어요."
        case .connected, .connecting:
            return nil
        }
    }

    private var currentPrivateStreamingWarningMessage: String? {
        switch privateWebSocketState {
        case .failed(let message):
            return userFacingStreamingWarning(from: message)
        case .disconnected:
            return "연결이 잠시 불안정해 최신 정보를 다시 확인하고 있어요."
        case .connected, .connecting:
            return nil
        }
    }

    private func resolvedWarningMessage(primary: String?, fallback: String?) -> String? {
        primary ?? fallback
    }

    private func privateRequestKey(
        endpoint: PrivateRequestEndpoint,
        exchange: Exchange?,
        route: Tab
    ) -> PrivateRequestKey {
        PrivateRequestKey(endpoint: endpoint, exchange: exchange, route: route.rawValue)
    }

    private func isAutomaticPrivateRefreshReason(_ reason: String) -> Bool {
        let normalizedReason = reason.lowercased()
        return normalizedReason.contains("polling_fallback")
            || normalizedReason.contains("tab_changed")
            || normalizedReason.contains("scene_active")
            || normalizedReason.contains("content_on_appear")
            || normalizedReason.contains("exchange_changed")
            || normalizedReason.contains("login_success")
            || normalizedReason.contains("signup_success")
    }

    private func isUserInitiatedPrivateRetryReason(_ reason: String) -> Bool {
        let normalizedReason = reason.lowercased()
        return normalizedReason.contains("retry_tap")
            || normalizedReason.contains("user_retry")
    }

    private func shouldSuppressPrivateRequest(
        _ key: PrivateRequestKey,
        reason: String,
        now: Date = Date()
    ) -> Bool {
        guard isAutomaticPrivateRefreshReason(reason),
              let failureState = privateRequestFailureStates[key] else {
            return false
        }

        guard now < failureState.cooldownUntil else {
            privateRequestFailureStates.removeValue(forKey: key)
            return false
        }

        return true
    }

    private func shouldThrottleAutomaticPrivateRefresh(
        _ key: PrivateRequestKey,
        reason: String,
        now: Date = Date()
    ) -> Bool {
        guard isAutomaticPrivateRefreshReason(reason),
              let lastRequestedAt = lastAutomaticPrivateRequestAtByKey[key] else {
            return false
        }

        let elapsed = now.timeIntervalSince(lastRequestedAt)
        guard elapsed < automaticPrivateRefreshMinimumInterval else {
            return false
        }

        AppLogger.debug(
            .network,
            "[PrivateRequest] throttled endpoint=\(key.endpoint.rawValue) exchange=\(key.exchange?.rawValue ?? "-") route=\(key.route) elapsedMs=\(Int(elapsed * 1000)) reason=\(reason)"
        )
        return true
    }

    private func noteAutomaticPrivateRefresh(_ key: PrivateRequestKey, reason: String, now: Date = Date()) {
        guard isAutomaticPrivateRefreshReason(reason) else {
            return
        }
        lastAutomaticPrivateRequestAtByKey[key] = now
    }

    private func recordPrivateRequestFailure(
        _ key: PrivateRequestKey,
        error: Error,
        reason: String,
        now: Date = Date()
    ) {
        guard !isCancellationLike(error) else { return }

        let signature = privateRequestFailureSignature(for: error)
        let previousState = privateRequestFailureStates[key]
        let failureCount = previousState?.signature == signature
            ? previousState.map { $0.failureCount + 1 } ?? 1
            : 1
        let isServerResponseFailure: Bool
        let cooldownInterval: TimeInterval

        switch signature {
        case .http(let statusCode):
            isServerResponseFailure = true
            cooldownInterval = [403, 404, 501].contains(statusCode)
                ? terminalPrivateRequestCooldownInterval
                : serverFailureAutoRetryCooldownInterval
        case .transport:
            isServerResponseFailure = false
            cooldownInterval = transportFailureAutoRetryCooldownInterval
        case .other:
            isServerResponseFailure = false
            cooldownInterval = transportFailureAutoRetryCooldownInterval
        }

        privateRequestFailureStates[key] = PrivateRequestFailureState(
            signature: signature,
            failureCount: failureCount,
            cooldownUntil: now.addingTimeInterval(cooldownInterval),
            isServerResponseFailure: isServerResponseFailure
        )

        AppLogger.debug(
            .network,
            "[PrivateRequest] failure endpoint=\(key.endpoint.rawValue) exchange=\(key.exchange?.rawValue ?? "-") route=\(key.route) count=\(failureCount) serverResponse=\(isServerResponseFailure) cooldownMs=\(Int(cooldownInterval * 1000)) reason=\(reason)"
        )
    }

    private func clearPrivateRequestFailure(_ key: PrivateRequestKey) {
        privateRequestFailureStates.removeValue(forKey: key)
    }

    private func privateRequestFailureSignature(for error: Error) -> PrivateRequestFailureSignature {
        guard let networkError = error as? NetworkServiceError else {
            return .other
        }

        switch networkError {
        case .httpError(let statusCode, _, _):
            return .http(statusCode: statusCode)
        case .transportError(_, let category):
            return .transport(category: category)
        case .authenticationRequired:
            return .http(statusCode: 401)
        case .invalidURL, .invalidResponse, .parsingFailed:
            return .other
        }
    }

    private func shouldEnterLoadingState<Value>(
        from state: Loadable<Value>,
        reason: String
    ) -> Bool {
        if state.isLoading {
            return false
        }
        if state.errorMessage != nil,
           (isAutomaticPrivateRefreshReason(reason) || isUserInitiatedPrivateRetryReason(reason)) {
            return false
        }
        return true
    }

    private func assignPortfolioState(_ nextState: Loadable<PortfolioSnapshot>) {
        if shouldSkipEquivalentStateUpdate(current: portfolioState, next: nextState) {
            return
        }
        AppLogger.debug(
            .lifecycle,
            "[AssetScreenRenderDebug] render_reason=portfolio_state_changed state_transition=\(describe(portfolioState))->\(describe(nextState))"
        )
        portfolioState = nextState
    }

    private func assignPortfolioSummaryCardState(_ nextState: PortfolioSummaryCardState?) {
        guard portfolioSummaryCardState != nextState else {
            return
        }
        portfolioSummaryCardState = nextState
    }

    private func assignMarketState(_ nextState: Loadable<[CoinInfo]>) {
        if shouldSkipEquivalentStateUpdate(current: marketState, next: nextState) {
            return
        }
        marketState = nextState
    }

    private func assignPortfolioHistoryState(_ nextState: Loadable<[PortfolioHistoryItem]>) {
        if shouldSkipEquivalentStateUpdate(current: portfolioHistoryState, next: nextState) {
            return
        }
        portfolioHistoryState = nextState
    }

    private func assignTradingChanceState(_ nextState: Loadable<TradingChance>, reason: String) {
        if shouldSkipEquivalentStateUpdate(current: tradingChanceState, next: nextState) {
            return
        }
        AppLogger.debug(
            .lifecycle,
            "[OrderScreenRenderDebug] render_reason=\(reason) section_state_transition=chance:\(describeTradingLoadable(tradingChanceState))->\(describeTradingLoadable(nextState))"
        )
        tradingChanceState = nextState
    }

    private func assignOrderHistoryState(_ nextState: Loadable<[OrderRecord]>, reason: String) {
        if shouldSkipEquivalentStateUpdate(current: orderHistoryState, next: nextState) {
            return
        }
        AppLogger.debug(
            .lifecycle,
            "[OrderScreenRenderDebug] render_reason=\(reason) section_state_transition=open_orders:\(describeTradingLoadable(orderHistoryState))->\(describeTradingLoadable(nextState))"
        )
        orderHistoryState = nextState
    }

    private func assignFillsState(_ nextState: Loadable<[TradeFill]>, reason: String) {
        if shouldSkipEquivalentStateUpdate(current: fillsState, next: nextState) {
            return
        }
        AppLogger.debug(
            .lifecycle,
            "[OrderScreenRenderDebug] render_reason=\(reason) section_state_transition=fills:\(describeTradingLoadable(fillsState))->\(describeTradingLoadable(nextState))"
        )
        fillsState = nextState
    }

    private func assignSelectedOrderDetailState(_ nextState: Loadable<OrderRecord>, reason: String) {
        if shouldSkipEquivalentStateUpdate(current: selectedOrderDetailState, next: nextState) {
            return
        }
        selectedOrderDetailState = nextState
    }

    private func shouldShowTradingLoading<Value>(_ state: Loadable<Value>, reason: String) -> Bool {
        switch state {
        case .idle:
            return true
        case .loading, .loaded, .empty:
            return false
        case .failed:
            return !isAutomaticPrivateRefreshReason(reason)
        }
    }

    private func stableTradingFallback<Value>(
        previous: Loadable<Value>,
        current: Loadable<Value>,
        error: Error,
        message: String,
        section: String
    ) -> Loadable<Value> {
        if isCancellationLike(error) {
            AppLogger.debug(
                .lifecycle,
                "[OrderScreenRenderDebug] render_reason=request_cancellation_ignored_for_stable_ui section=\(section)"
            )
            switch previous {
            case .loaded, .empty:
                return previous
            case .idle, .loading, .failed:
                return .idle
            }
        }

        switch previous {
        case .loaded, .empty:
            return previous
        case .idle, .loading, .failed:
            if case .loaded = current {
                return current
            }
            if case .empty = current {
                return current
            }
            return .failed(message)
        }
    }

    private func tradingSectionFailureMessage(
        for error: Error,
        endpoint: PrivateRequestEndpoint
    ) -> String {
        if isCancellationLike(error) {
            switch endpoint {
            case .tradingChance:
                return "주문 가능 정보를 다시 확인하고 있어요."
            case .openOrders:
                return "미체결 주문을 다시 확인하고 있어요."
            case .fills:
                return "최근 체결을 다시 확인하고 있어요."
            case .exchangeConnections, .portfolioSummary, .portfolioHistory:
                return "정보를 다시 확인하고 있어요."
            }
        }

        if let networkError = error as? NetworkServiceError {
            switch networkError {
            case .authenticationRequired:
                return "로그인 상태를 다시 확인해주세요."
            case .httpError(let statusCode, _, let category):
                if statusCode == 403 || category == .permissionDenied {
                    switch endpoint {
                    case .tradingChance:
                        return "주문 가능 권한이 없어요. 주문 가능 권한의 거래소 연결을 추가해야 주문을 실행할 수 있어요."
                    case .openOrders:
                        return "미체결 주문 조회 권한이 없어요. 거래소 연결 권한을 확인해주세요."
                    case .fills:
                        return "체결 내역 조회 권한이 없어요. 거래소 연결 권한을 확인해주세요."
                    case .exchangeConnections, .portfolioSummary, .portfolioHistory:
                        return "권한 설정을 다시 확인해주세요."
                    }
                }

                switch statusCode {
                case 404:
                    switch endpoint {
                    case .tradingChance:
                        return "이 거래소의 주문 가능 정보 엔드포인트가 아직 준비되지 않았어요."
                    case .openOrders:
                        return "이 거래소의 미체결 주문 조회는 아직 지원하지 않아요."
                    case .fills:
                        return "이 거래소의 체결 내역 조회는 아직 지원하지 않아요."
                    case .exchangeConnections, .portfolioSummary, .portfolioHistory:
                        return "요청한 기능이 아직 서버에 준비되지 않았어요."
                    }
                case 501:
                    return "아직 지원하지 않는 거래소예요. 지원 전까지 이 영역은 마지막 상태를 유지합니다."
                case 502:
                    return "거래소 또는 서버 응답이 불안정해 지금은 불러올 수 없어요."
                default:
                    break
                }
            case .transportError, .invalidURL, .invalidResponse, .parsingFailed:
                break
            }
        }

        switch endpoint {
        case .tradingChance:
            return userFacingRefreshMessage(
                for: error,
                fallback: "주문 가능 정보를 불러오지 못했어요.",
                cancellationFallback: "주문 가능 정보를 다시 확인하고 있어요."
            )
        case .openOrders:
            return userFacingRefreshMessage(
                for: error,
                fallback: "미체결 주문을 불러오지 못했어요.",
                cancellationFallback: "미체결 주문을 다시 확인하고 있어요."
            )
        case .fills:
            return userFacingRefreshMessage(
                for: error,
                fallback: "최근 체결을 불러오지 못했어요.",
                cancellationFallback: "최근 체결을 다시 확인하고 있어요."
            )
        case .exchangeConnections, .portfolioSummary, .portfolioHistory:
            return userFacingRefreshMessage(
                for: error,
                fallback: "정보를 불러오지 못했어요.",
                cancellationFallback: "정보를 다시 확인하고 있어요."
            )
        }
    }

    private func describeTradingLoadable<Value>(_ state: Loadable<Value>) -> String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded(let value):
            if let collection = value as? any Collection {
                return "loaded(count:\(collection.count))"
            }
            return "loaded"
        case .empty:
            return "empty"
        case .failed:
            return "failed"
        }
    }

    private func refreshPortfolioOverviewViewState(reason: String) {
        let snapshots = Array(portfolioSnapshotsByExchange.values)
        let connectedExchanges = connectedAssetExchanges()
        let nextState: PortfolioOverviewViewState?
        if snapshots.isEmpty {
            nextState = nil
        } else {
            nextState = PortfolioOverviewViewState(
                snapshots: snapshots,
                connectedAssetExchanges: connectedExchanges,
                warningMessage: portfolioRefreshWarningMessage
            )
        }

        guard portfolioOverviewViewState != nextState else {
            return
        }

        AppLogger.debug(
            .lifecycle,
            "[PortfolioSectionDebug] render_reason=\(reason) section_state_transition=overview:\(portfolioOverviewViewState == nil ? "nil" : "ready")->\(nextState == nil ? "nil" : "ready")"
        )
        portfolioOverviewViewState = nextState
    }

    private func connectedAssetExchanges() -> [Exchange] {
        let activeConnectedExchanges = loadedExchangeConnections
            .filter { $0.isActive && capabilityResolver.supportsPortfolio(on: $0.exchange) }
            .map(\.exchange)
        let candidates = activeConnectedExchanges.isEmpty
            ? [selectedExchange].filter { capabilityResolver.supportsPortfolio(on: $0) }
            : activeConnectedExchanges

        var seen = Set<Exchange>()
        return Exchange.allCases.filter { exchange in
            candidates.contains(exchange) && seen.insert(exchange).inserted
        }
    }

    private func portfolioPrimaryExchange() -> Exchange? {
        if capabilityResolver.supportsPortfolio(on: selectedExchange) {
            return selectedExchange
        }
        if let connectedExchange = connectedAssetExchanges().first {
            return connectedExchange
        }
        return Exchange.allCases.first { capabilityResolver.supportsPortfolio(on: $0) }
    }

    private func prunePortfolioSnapshotsToConnectedAssetExchanges(reason: String) {
        let connected = Set(connectedAssetExchanges())
        guard !connected.isEmpty else {
            if portfolioSnapshotsByExchange.isEmpty == false {
                portfolioSnapshotsByExchange.removeAll()
                refreshPortfolioOverviewViewState(reason: reason)
            }
            return
        }

        let before = portfolioSnapshotsByExchange
        portfolioSnapshotsByExchange = portfolioSnapshotsByExchange.filter { connected.contains($0.key) }
        if before != portfolioSnapshotsByExchange {
            refreshPortfolioOverviewViewState(reason: reason)
        }
    }

    private func loadConnectedPortfolioSummaries(
        excluding excludedExchange: Exchange,
        session: AuthSession,
        reason: String
    ) async {
        let exchanges = connectedAssetExchanges().filter { $0 != excludedExchange }
        guard exchanges.isEmpty == false else {
            refreshPortfolioOverviewViewState(reason: "\(reason)_connected_summary_skipped")
            return
        }

        var warnings: [String] = []
        for exchange in exchanges {
            let isSameSession = authState.session?.accessToken == session.accessToken
                || acceptedStaleAccessTokens.contains(session.accessToken)
            guard activeTab == .portfolio,
                  isSameSession else {
                AppLogger.debug(
                    .lifecycle,
                    "[PortfolioSectionDebug] render_reason=stale_connected_summary_ignored exchange=\(exchange.rawValue)"
                )
                return
            }

            do {
                let snapshot = try await runAuthenticatedRequest(session: session) { [portfolioRepository] refreshedSession in
                    try await portfolioRepository.fetchSummary(session: refreshedSession, exchange: exchange)
                }
                portfolioSnapshotsByExchange[exchange] = snapshot
                if let partialFailureMessage = snapshot.partialFailureMessage {
                    warnings.append(partialFailureMessage)
                }
            } catch {
                guard !isCancellationLike(error) else {
                    AppLogger.debug(
                        .lifecycle,
                        "[PortfolioSectionDebug] render_reason=request_cancellation_ignored_for_stable_ui exchange=\(exchange.rawValue)"
                    )
                    continue
                }
                let message = userFacingRefreshMessage(
                    for: error,
                    fallback: "\(exchange.displayName) 자산 데이터를 불러오지 못했어요.",
                    cancellationFallback: "\(exchange.displayName) 자산 현황을 다시 확인하고 있어요."
                )
                warnings.append(message)
            }
        }

        if let warning = warnings.first {
            portfolioRefreshWarningMessage = warning
        }
        refreshPortfolioOverviewViewState(reason: "\(reason)_connected_summary_loaded")
    }

    private func assignExchangeConnectionsState(
        _ nextState: Loadable<[ExchangeConnectionCardViewState]>
    ) {
        if shouldSkipEquivalentStateUpdate(current: exchangeConnectionsState, next: nextState) {
            return
        }
        AppLogger.debug(
            .lifecycle,
            "[ExchangeConnectionSheetDebug] render_reason=exchange_connections_state_changed state_transition=\(describe(exchangeConnectionsState))->\(describe(nextState))"
        )
        exchangeConnectionsState = nextState
    }

    private func shouldSkipEquivalentStateUpdate<Value: Equatable>(
        current: Loadable<Value>,
        next: Loadable<Value>
    ) -> Bool {
        current == next
    }

    private func makePortfolioSummaryTask(
        for context: PortfolioLoadContext,
        session: AuthSession
    ) -> Task<PortfolioSnapshot, Error> {
        if let existingTask = portfolioSummaryFetchTask,
           portfolioSummaryFetchTaskContext == context {
            AppLogger.debug(
                .network,
                "[Portfolio] summary request deduped exchange=\(context.exchange.rawValue)"
            )
            return existingTask
        }

        portfolioSummaryFetchTask?.cancel()
        let repository = portfolioRepository
        let task = Task { @MainActor in
            try await self.runAuthenticatedRequest(session: session) { refreshedSession in
                try await repository.fetchSummary(session: refreshedSession, exchange: context.exchange)
            }
        }
        portfolioSummaryFetchTask = task
        portfolioSummaryFetchTaskContext = context
        return task
    }

    private func makePortfolioHistoryTask(
        for context: PortfolioLoadContext,
        session: AuthSession
    ) -> Task<PortfolioHistorySnapshot, Error> {
        if let existingTask = portfolioHistoryFetchTask,
           portfolioHistoryFetchTaskContext == context {
            AppLogger.debug(
                .network,
                "[Portfolio] history request deduped exchange=\(context.exchange.rawValue)"
            )
            return existingTask
        }

        portfolioHistoryFetchTask?.cancel()
        let repository = portfolioRepository
        let task = Task { @MainActor in
            try await self.runAuthenticatedRequest(session: session) { refreshedSession in
                try await repository.fetchHistory(session: refreshedSession, exchange: context.exchange)
            }
        }
        portfolioHistoryFetchTask = task
        portfolioHistoryFetchTaskContext = context
        return task
    }

    private func filteredPortfolioHistoryItems(
        _ items: [PortfolioHistoryItem],
        exchange: Exchange
    ) -> [PortfolioHistoryItem] {
        var removedMockCount = 0
        var removedZeroValueCount = 0
        var removedUnknownSourceCount = 0

        let filteredItems = items
            .sorted {
                ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast)
            }
            .filter { item in
                if item.isMockLike {
                    removedMockCount += 1
                    return false
                }
                guard item.symbol != "-", item.occurredAt != nil else {
                    removedUnknownSourceCount += 1
                    return false
                }
                guard item.eventSource != .unknown else {
                    removedUnknownSourceCount += 1
                    return false
                }
                if abs(item.amount) <= 0.00000001, item.isVerifiedUserEvent == false {
                    removedZeroValueCount += 1
                    return false
                }
                guard item.isVerifiedUserEvent else {
                    removedUnknownSourceCount += 1
                    return false
                }
                return true
            }

        let stats = AssetHistoryFilterStats(
            rawCount: items.count,
            filteredCount: filteredItems.count,
            removedMockCount: removedMockCount,
            removedZeroValueCount: removedZeroValueCount,
            removedUnknownSourceCount: removedUnknownSourceCount
        )
        AppLogger.debug(
            .network,
            "[AssetHistoryDebug] exchange=\(exchange.rawValue) rawCount=\(stats.rawCount) filteredCount=\(stats.filteredCount) removedMockCount=\(stats.removedMockCount) removedZeroValueCount=\(stats.removedZeroValueCount) removedUnknownSourceCount=\(stats.removedUnknownSourceCount)"
        )
        if filteredItems.isEmpty {
            AppLogger.debug(
                .network,
                "[AssetHistoryDebug] action=empty_state_shown reason=no_verified_user_events exchange=\(exchange.rawValue)"
            )
        }
        return filteredItems
    }

    private func makeTradingChanceTask(
        for context: TradingLoadContext,
        session: AuthSession
    ) -> Task<TradingChance, Error> {
        if let existingTask = tradingChanceFetchTask,
           tradingChanceFetchTaskContext == context {
            AppLogger.debug(
                .network,
                "[Trading] chance request deduped exchange=\(context.exchange.rawValue) symbol=\(context.symbol)"
            )
            return existingTask
        }

        tradingChanceFetchTask?.cancel()
        let repository = tradingRepository
        let task = Task { @MainActor in
            try await self.runAuthenticatedRequest(session: session) { refreshedSession in
                try await repository.fetchChance(
                    session: refreshedSession,
                    exchange: context.exchange,
                    symbol: context.symbol
                )
            }
        }
        tradingChanceFetchTask = task
        tradingChanceFetchTaskContext = context
        return task
    }

    private func makeTradingOpenOrdersTask(
        for context: TradingLoadContext,
        session: AuthSession
    ) -> Task<OrderRecordsSnapshot, Error> {
        if let existingTask = tradingOpenOrdersFetchTask,
           tradingOpenOrdersFetchTaskContext == context {
            AppLogger.debug(
                .network,
                "[Trading] open_orders request deduped exchange=\(context.exchange.rawValue) symbol=\(context.symbol)"
            )
            return existingTask
        }

        tradingOpenOrdersFetchTask?.cancel()
        let repository = tradingRepository
        let task = Task { @MainActor in
            try await self.runAuthenticatedRequest(session: session) { refreshedSession in
                try await repository.fetchOpenOrders(
                    session: refreshedSession,
                    exchange: context.exchange,
                    symbol: context.symbol
                )
            }
        }
        tradingOpenOrdersFetchTask = task
        tradingOpenOrdersFetchTaskContext = context
        return task
    }

    private func makeTradingFillsTask(
        for context: TradingLoadContext,
        session: AuthSession
    ) -> Task<TradeFillsSnapshot, Error> {
        if let existingTask = tradingFillsFetchTask,
           tradingFillsFetchTaskContext == context {
            AppLogger.debug(
                .network,
                "[Trading] fills request deduped exchange=\(context.exchange.rawValue) symbol=\(context.symbol)"
            )
            return existingTask
        }

        tradingFillsFetchTask?.cancel()
        let repository = tradingRepository
        let task = Task { @MainActor in
            try await self.runAuthenticatedRequest(session: session) { refreshedSession in
                try await repository.fetchFills(
                    session: refreshedSession,
                    exchange: context.exchange,
                    symbol: context.symbol
                )
            }
        }
        tradingFillsFetchTask = task
        tradingFillsFetchTaskContext = context
        return task
    }

    private func makeExchangeConnectionsTask(
        for context: ExchangeConnectionsLoadContext,
        session: AuthSession
    ) -> Task<ExchangeConnectionsSnapshot, Error> {
        if let existingTask = exchangeConnectionsFetchTask,
           exchangeConnectionsFetchTaskContext == context {
            AppLogger.debug(.network, "[ExchangeConnections] request deduped")
            return existingTask
        }

        exchangeConnectionsFetchTask?.cancel()
        let repository = exchangeConnectionsRepository
        let task = Task { @MainActor in
            try await self.runAuthenticatedRequest(session: session) { refreshedSession in
                try await repository.fetchConnections(session: refreshedSession)
            }
        }
        exchangeConnectionsFetchTask = task
        exchangeConnectionsFetchTaskContext = context
        return task
    }

    private func shouldApplyPortfolioLoad(for context: PortfolioLoadContext) -> Bool {
        guard let session = authState.session else {
            return false
        }

        guard session.accessToken == context.accessToken || acceptedStaleAccessTokens.contains(context.accessToken) else {
            return false
        }

        if activeTab == .portfolio {
            return capabilityResolver.supportsPortfolio(on: context.exchange)
        }

        return selectedExchange == context.exchange
    }

    private func shouldApplyTradingLoad(for context: TradingLoadContext) -> Bool {
        guard let session = authState.session else {
            return false
        }

        return selectedExchange == context.exchange
            && selectedCoin?.symbol == context.symbol
            && (session.accessToken == context.accessToken || acceptedStaleAccessTokens.contains(context.accessToken))
    }

    private func shouldApplyExchangeConnectionsLoad(for context: ExchangeConnectionsLoadContext) -> Bool {
        guard let session = authState.session else {
            return false
        }

        return session.accessToken == context.accessToken || acceptedStaleAccessTokens.contains(context.accessToken)
    }

    private func canRetainPortfolioSummary(for exchange: Exchange) -> Bool {
        guard lastResolvedPortfolioExchange == exchange else {
            return false
        }

        switch portfolioState {
        case .loaded, .empty:
            return true
        case .idle, .loading, .failed:
            return false
        }
    }

    private func canRetainPortfolioHistory(for exchange: Exchange) -> Bool {
        guard lastResolvedPortfolioHistoryExchange == exchange else {
            return false
        }

        switch portfolioHistoryState {
        case .loaded, .empty:
            return true
        case .idle, .loading, .failed:
            return false
        }
    }

    private func makeExchangeConnectionsNotice(
        from snapshot: ExchangeConnectionsSnapshot
    ) -> ExchangeConnectionsNoticeState? {
        let noticeMessage = resolvedWarningMessage(
            primary: snapshot.meta.partialFailureMessage,
            fallback: snapshot.meta.warningMessage
        )
        guard let noticeMessage, !noticeMessage.isEmpty else {
            return nil
        }

        return ExchangeConnectionsNoticeState(
            title: "일부 연결 상태가 늦어지고 있어요",
            message: noticeMessage,
            tone: .warning
        )
    }

    private func userFacingRefreshMessage(
        for error: Error,
        fallback: String,
        cancellationFallback: String
    ) -> String {
        if isCancellationLike(error) {
            return cancellationFallback
        }

        if let networkError = error as? NetworkServiceError {
            switch networkError {
            case .authenticationRequired:
                return "로그인 상태를 다시 확인해주세요."
            case .httpError(let statusCode, let message, let category):
                switch category {
                case .authenticationFailed:
                    return "로그인 상태를 다시 확인해주세요."
                case .permissionDenied:
                    return "권한 설정을 다시 확인해주세요."
                case .rateLimited:
                    return "요청이 많아 잠시 후 다시 시도해주세요."
                case .maintenance:
                    return "서버 점검 중이에요. 잠시 후 다시 시도해주세요."
                case .staleData:
                    return "최신 데이터를 확인하지 못했어요. 잠시 후 다시 시도해주세요."
                case .connectivity:
                    return fallback
                case .unknown:
                    if statusCode == 422 || statusCode >= 500 {
                        return fallback
                    }
                }
                return sanitizedRecoverableMessage(message) ?? fallback
            case .transportError(let message, _):
                return sanitizedRecoverableMessage(message) ?? fallback
            case .invalidURL, .invalidResponse, .parsingFailed:
                return fallback
            }
        }

        return sanitizedRecoverableMessage(error.localizedDescription) ?? fallback
    }

    private func isCancellationLike(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let networkError = error as? NetworkServiceError,
           case .transportError(let message, _) = networkError {
            return message.localizedCaseInsensitiveContains("취소")
                || message.localizedCaseInsensitiveContains("cancel")
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
    }

    private func sanitizedRecoverableMessage(_ message: String?) -> String? {
        guard let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedMessage.isEmpty else {
            return nil
        }

        let lowercasedMessage = trimmedMessage.lowercased()
        if lowercasedMessage.contains("cancel") || trimmedMessage.contains("취소") {
            return nil
        }
        if lowercasedMessage.contains("handshake")
            || lowercasedMessage.contains("bad response")
            || lowercasedMessage.contains("websocket") {
            return "실시간 연결이 불안정해 최신 정보를 다시 확인하고 있어요."
        }
        if lowercasedMessage.contains("polling fallback") || lowercasedMessage.contains("polling") {
            return "연결이 잠시 불안정해 최신 정보를 다시 확인하고 있어요."
        }
        if trimmedMessage.count > 140
            || lowercasedMessage.contains("prisma")
            || lowercasedMessage.contains("stack")
            || lowercasedMessage.contains("node_modules")
            || lowercasedMessage.contains(" at ")
            || lowercasedMessage.contains("/src/")
            || lowercasedMessage.contains(".ts:")
            || lowercasedMessage.contains(".js:")
            || lowercasedMessage.contains("sql") {
            return nil
        }
        return trimmedMessage
    }

    private func userFacingStreamingWarning(from message: String) -> String {
        sanitizedRecoverableMessage(message)
            ?? "연결이 잠시 불안정해 최신 정보를 다시 확인하고 있어요."
    }

    private func describe(_ state: Loadable<[KimchiPremiumCoinViewState]>) -> String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded(let rows):
            return "loaded(\(rows.count))"
        case .empty:
            return "empty"
        case .failed:
            return "failed"
        }
    }

    private func describe(_ state: Loadable<PortfolioSnapshot>) -> String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded(let snapshot):
            return "loaded(holdings:\(snapshot.holdings.count))"
        case .empty:
            return "empty"
        case .failed:
            return "failed"
        }
    }

    private func describe(_ state: Loadable<[ExchangeConnectionCardViewState]>) -> String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded(let cards):
            return "loaded(count:\(cards.count))"
        case .empty:
            return "empty"
        case .failed:
            return "failed"
        }
    }

    private func describe(_ state: PublicWebSocketConnectionState) -> String {
        switch state {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .failed(let message):
            return "failed(\(message))"
        }
    }

    private func describe(_ state: PrivateWebSocketConnectionState) -> String {
        switch state {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .failed(let message):
            return "failed(\(message))"
        }
    }

    private var supportedIntervals: [String] {
        guard let selectedCoin else {
            return CandleIntervalCatalog.defaultOptions.map(\.value)
        }

        let marketIdentity = selectedCoin.marketIdentity(exchange: selectedExchange)
        return supportedIntervalsByExchangeAndMarketIdentity[selectedExchange]?[marketIdentity]
            ?? CandleIntervalCatalog.defaultOptions.map(\.value)
    }

    private var marketMetaForStatus: ResponseMeta {
        if let activeMarketPresentationSnapshot {
            return activeMarketPresentationSnapshot.meta
        }
        return ResponseMeta(
            fetchedAt: currentTicker?.timestamp,
            isStale: currentTicker?.isStale ?? false,
            warningMessage: nil,
            partialFailureMessage: nil
        )
    }

    private var chartMetaForStatus: ResponseMeta {
        return combineMetas([
            activeChartCandleMeta,
            activeChartOrderbookMeta,
            activeChartTradesMeta
        ])
    }

    private var portfolioMetaForStatus: ResponseMeta {
        return combineMetas([portfolioSummaryResponseMeta, portfolioHistoryResponseMeta])
    }

    private var tradingMetaForStatus: ResponseMeta {
        if let firstOrder = orderHistoryState.value?.first, let createdAt = firstOrder.createdAt {
            return ResponseMeta(fetchedAt: createdAt, isStale: false, warningMessage: nil, partialFailureMessage: nil)
        }
        if let firstFill = fillsState.value?.first {
            return ResponseMeta(fetchedAt: firstFill.executedAt, isStale: false, warningMessage: nil, partialFailureMessage: nil)
        }
        return .empty
    }

    private var kimchiMetaForStatus: ResponseMeta {
        switch kimchiPremiumState {
        case .loaded, .empty:
            return activeKimchiPresentationSnapshot?.meta ?? .empty
        default:
            return .empty
        }
    }

    private func combineMetas(_ metas: [ResponseMeta]) -> ResponseMeta {
        let fetchedAt = metas.compactMap(\.fetchedAt).sorted(by: >).first
        let isStale = metas.contains(where: \.isStale)
        let warningMessage = metas.compactMap(\.warningMessage).first
        let partialFailureMessage = metas.compactMap(\.partialFailureMessage).first

        return ResponseMeta(
            fetchedAt: fetchedAt,
            isStale: isStale,
            warningMessage: warningMessage,
            partialFailureMessage: partialFailureMessage
        )
    }

    private func hasAnyTickerData(for exchange: Exchange) -> Bool {
        prices.contains { element in
            element.value[exchange.rawValue] != nil
        }
    }

    private var hasKimchiPremiumRequestResult: Bool {
        switch kimchiPremiumState {
        case .idle:
            return false
        case .loading, .loaded, .empty, .failed:
            return true
        }
    }

    private func cancelInFlightMarketRequests(excluding exchange: Exchange) {
        let canceledMarketExchanges = marketCatalogFetchTasks.keys.filter { $0 != exchange }
        canceledMarketExchanges.forEach { requestExchange in
            marketCatalogFetchTasks[requestExchange]?.cancel()
            marketCatalogFetchTasks[requestExchange] = nil
            AppLogger.debug(
                .network,
                "[MarketPipeline] exchange=\(requestExchange.rawValue) generation=\(marketPresentationGeneration) phase=request_cancelled kind=markets reason=exchange_changed"
            )
        }

        let canceledTickerExchanges = tickerFetchTasks.keys.filter { $0 != exchange }
        canceledTickerExchanges.forEach { requestExchange in
            tickerFetchTasks[requestExchange]?.cancel()
            tickerFetchTasks[requestExchange] = nil
            AppLogger.debug(
                .network,
                "[MarketPipeline] exchange=\(requestExchange.rawValue) generation=\(marketPresentationGeneration) phase=request_cancelled kind=tickers reason=exchange_changed"
            )
        }

        for key in Array(sparklineFetchTasksByKey.keys).filter({ $0.exchange != exchange }) {
            sparklineFetchTasksByKey[key]?.cancel()
            sparklineFetchTasksByKey[key] = nil
            AppLogger.debug(
                .network,
                "[GraphRequestDebug] \(key.marketIdentity.logFields) action=request_cancelled reason=exchange_changed"
            )
        }
    }

    private func coinoneMissingTickerSymbols(parsedSymbols: Set<String>) -> [String] {
        let marketSymbols = Set((marketsByExchange[.coinone] ?? []).map(\.symbol))
        return Array(marketSymbols.subtracting(parsedSymbols)).sorted().prefix(8).map { $0 }
    }

    private func kimchiPremiumUserFacingMessage(for error: Error) -> String {
        if let networkError = error as? NetworkServiceError, networkError.errorCategory == .maintenance {
            return "데이터를 불러오지 못했어요. 잠시 후 다시 시도해주세요."
        }

        return "데이터를 불러오지 못했어요. 잠시 후 다시 시도해주세요."
    }

    private func kimchiPremiumDebugDetail(for error: Error) -> String? {
        #if DEBUG
        return error.localizedDescription
        #else
        return nil
        #endif
    }
}

private extension PortfolioSnapshot {
    var meta: ResponseMeta {
        ResponseMeta(
            fetchedAt: fetchedAt,
            isStale: isStale,
            warningMessage: nil,
            partialFailureMessage: partialFailureMessage
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        var chunks: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let nextIndex = Swift.min(index + size, endIndex)
            chunks.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }
        return chunks
    }
}
