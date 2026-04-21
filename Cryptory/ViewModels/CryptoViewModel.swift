import SwiftUI
import Combine

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
        case .market, .chart, .trade, .portfolio:
            return true
        case .kimchi:
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

private struct PendingMarketRowPatch {
    let marketIdentity: MarketIdentity
    let exchange: Exchange
    let generation: Int
    var sparklinePatch: MarketSparklinePatch?
    var symbolImagePatch: MarketSymbolImagePatch?
    var rebuildReasons: [String] = []

    var reasons: [String] {
        var values = rebuildReasons
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
        let hasRebuild = rebuildReasons.isEmpty == false
        switch (hasGraph, hasImage, hasRebuild) {
        case (true, false, false):
            return "graph_only"
        case (false, true, false):
            return "image_only"
        case (false, false, true):
            return rebuildReasons.contains("ticker_flash_reset") ? "flash_only" : "base_ticker_refresh"
        default:
            return "coalesced"
        }
    }

    mutating func merge(
        sparklinePatch incomingSparklinePatch: MarketSparklinePatch?,
        symbolImagePatch incomingSymbolImagePatch: MarketSymbolImagePatch?,
        rebuildReason: String?,
        preferredSparklinePatch: (MarketSparklinePatch, MarketSparklinePatch) -> MarketSparklinePatch,
        preferredImagePatch: (MarketSymbolImagePatch, MarketSymbolImagePatch) -> MarketSymbolImagePatch
    ) {
        if let incomingSparklinePatch {
            if let existingSparklinePatch = sparklinePatch {
                sparklinePatch = preferredSparklinePatch(existingSparklinePatch, incomingSparklinePatch)
            } else {
                sparklinePatch = incomingSparklinePatch
            }
        }

        if let incomingSymbolImagePatch {
            if let existingSymbolImagePatch = symbolImagePatch {
                symbolImagePatch = preferredImagePatch(existingSymbolImagePatch, incomingSymbolImagePatch)
            } else {
                symbolImagePatch = incomingSymbolImagePatch
            }
        }

        if let rebuildReason,
           rebuildReasons.contains(rebuildReason) == false {
            rebuildReasons.append(rebuildReason)
        }
    }
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
    let selectedCoinIdentity: MarketIdentity?
    let favoriteSymbols: Set<String>
    let shouldLimitFirstPaint: Bool
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

    @Published var orderSide: OrderSide = .buy
    @Published var orderType: OrderType = .limit
    @Published var orderPrice = ""
    @Published var orderQty = ""
    @Published private(set) var isSubmittingOrder = false
    @Published private(set) var tradingChanceState: Loadable<TradingChance> = .idle
    @Published private(set) var orderHistoryState: Loadable<[OrderRecord]> = .idle
    @Published private(set) var fillsState: Loadable<[TradeFill]> = .idle
    @Published private(set) var selectedOrderDetailState: Loadable<OrderRecord> = .idle
    @Published private(set) var tradingStatusViewState: ScreenStatusViewState = .idle

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
    @Published private(set) var authState: AuthState = .guest
    @Published private(set) var activeAuthGate: ProtectedFeature?
    @Published private(set) var publicWebSocketState: PublicWebSocketConnectionState = .disconnected
    @Published private(set) var privateWebSocketState: PrivateWebSocketConnectionState = .disconnected

    @Published var notification: (msg: String, type: NotifType)?
    @Published var isLoginPresented = false
    @Published var isExchangeConnectionsPresented = false
    @Published var authFlowMode: AuthFlowMode = .login
    @Published var loginEmail = ""
    @Published var loginPassword = ""
    @Published var loginErrorMessage: String?
    @Published var signupEmail = ""
    @Published var signupPassword = ""
    @Published var signupPasswordConfirm = ""
    @Published var signupNickname = ""
    @Published var signupAcceptedTerms = false
    @Published var signupErrorMessage: String?
    @Published private(set) var isSigningUp = false

    private let marketRepository: MarketRepositoryProtocol
    private let tradingRepository: TradingRepositoryProtocol
    private let portfolioRepository: PortfolioRepositoryProtocol
    private let kimchiPremiumRepository: KimchiPremiumRepositoryProtocol
    private let exchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol
    private let authService: AuthenticationServiceProtocol
    private let authSessionStore: AuthSessionStoring?
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

    private let favoritesKey = "guest.favorite.symbols"
    private let marketDisplayModeKey = "market.display.mode"
    private let marketDisplayGuideSeenKey = "market.display.guide.seen"
    private let instanceID = AppLogger.nextInstanceID(scope: "CryptoViewModel")
    private let marketCatalogStaleInterval: TimeInterval = 60 * 5
    private let tickerStaleInterval: TimeInterval = 4
    private let chartSnapshotStaleInterval: TimeInterval = 5
    private let sparklineCacheStaleInterval: TimeInterval = 60
    private let sparklineSchedulerDebounceNanoseconds: UInt64 = 80_000_000
    private let sparklineVisibleBatchSize = 12
    private let sparklineBackgroundBatchSize = 16
    private let sparklineRepresentativeLimit = 20
    private let sparklineFailureCooldownInterval: TimeInterval = 4
    private let sparklineRefreshThrottleInterval: TimeInterval = 1.2
    private let marketRepresentativeRowLimit = 4
    private let marketFirstPaintRowLimit = 24
    private let marketHydrationDelayNanoseconds: UInt64 = 350_000_000
    private let marketImageHydrationDebounceNanoseconds: UInt64 = 20_000_000
    private let marketRowPatchCoalesceNanoseconds: UInt64 = 16_000_000
    private let marketImageVisibleBatchSize = 18
    private let marketImagePrefetchBatchSize = 36
    private let chartCacheStaleInterval: TimeInterval = 30
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

    private var hasBootstrapped = false
    private var pendingPostLoginFeature: ProtectedFeature?
    private var marketsByExchange: [Exchange: [CoinInfo]] = [:]
    private var tickerSnapshotCoinsByExchange: [Exchange: [CoinInfo]] = [:]
    private var supportedIntervalsByExchangeAndMarketIdentity: [Exchange: [MarketIdentity: [String]]] = [:]
    private var filteredMarketIdentitiesByExchange: [Exchange: [MarketIdentity]] = [:]
    private var filteredTickerIdentitiesByExchange: [Exchange: [MarketIdentity]] = [:]
    private var loadedExchangeConnections: [ExchangeConnection] = []
    private var publicPollingTask: Task<Void, Never>?
    private var privatePollingTask: Task<Void, Never>?
    private var marketHydrationTask: Task<Void, Never>?
    private var marketImageHydrationTask: Task<Void, Never>?
    private var marketRowPatchTask: Task<Void, Never>?
    private var sparklineHydrationTask: Task<Void, Never>?
    private var kimchiHydrationTask: Task<Void, Never>?
    private var kimchiVisibleHydrationTask: Task<Void, Never>?
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
    private var visibleMarketIdentitiesByExchange: [Exchange: [MarketIdentity]] = [:]
    private var lastVisibleMarketRowAtByExchange: [Exchange: Date] = [:]
    private var sparklineSnapshotsByKey: [SparklineCacheKey: SparklineLayerSnapshot] = [:]
    // UI-only display cache: keeps the last renderable graph visible across SwiftUI row teardown/recreation.
    private var stableSparklineDisplaysByKey: [MarketGraphBindingKey: StableSparklineDisplay] = [:]
    private var loadingSparklineMarketIdentitiesByExchange: [Exchange: Set<MarketIdentity>] = [:]
    private var unavailableSparklineMarketIdentitiesByExchange: [Exchange: Set<MarketIdentity>] = [:]
    private var sparklineFetchTasksByKey: [SparklineCacheKey: Task<SparklineLayerSnapshot, Error>] = [:]
    private var sparklineFailureCooldownUntilByKey: [SparklineCacheKey: Date] = [:]
    private var lastSparklineRefreshAttemptAtByKey: [SparklineCacheKey: Date] = [:]
    private var runningSparklineHydrationExchanges: Set<Exchange> = []
    private var pendingSparklineHydrationReasonsByExchange: [Exchange: String] = [:]
    private var lastLoggedGraphDisplaySignaturesByBindingKey: [String: String] = [:]
    private var pendingMarketRowPatchesByExchange: [Exchange: [MarketIdentity: PendingMarketRowPatch]] = [:]
    private var marketPresentationGeneration = 0
    private var routeRefreshGeneration = 0
    private var activeChartRequestGeneration = 0
    private var activeChartRequestKey: ChartRequestKey?
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
    private var activeChartCandleMeta: ResponseMeta = .empty
    private var activeChartOrderbookMeta: ResponseMeta = .empty
    private var activeChartTradesMeta: ResponseMeta = .empty
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

    init(
        marketRepository: MarketRepositoryProtocol? = nil,
        tradingRepository: TradingRepositoryProtocol? = nil,
        portfolioRepository: PortfolioRepositoryProtocol? = nil,
        kimchiPremiumRepository: KimchiPremiumRepositoryProtocol? = nil,
        exchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol? = nil,
        authService: AuthenticationServiceProtocol? = nil,
        authSessionStore: AuthSessionStoring? = nil,
        publicWebSocketService: PublicWebSocketServicing? = nil,
        privateWebSocketService: PrivateWebSocketServicing? = nil,
        marketSnapshotCacheStore: MarketSnapshotCacheStoring? = nil,
        assetImageClient: AssetImageClient = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        let resolvedDisplayMode = Self.loadMarketDisplayMode(from: userDefaults)
        self.marketRepository = marketRepository ?? LiveMarketRepository()
        self.tradingRepository = tradingRepository ?? LiveTradingRepository()
        self.portfolioRepository = portfolioRepository ?? LivePortfolioRepository()
        self.kimchiPremiumRepository = kimchiPremiumRepository ?? LiveKimchiPremiumRepository()
        self.exchangeConnectionsRepository = exchangeConnectionsRepository ?? LiveExchangeConnectionsRepository()
        self.authService = authService ?? LiveAuthenticationService()
        self.authSessionStore = authSessionStore ?? Self.defaultAuthSessionStore()
        self.publicWebSocketService = publicWebSocketService ?? WebSocketService()
        self.privateWebSocketService = privateWebSocketService ?? PrivateWebSocketService()
        self.marketSnapshotCacheStore = marketSnapshotCacheStore ?? Self.defaultMarketSnapshotCacheStore()
        self.assetImageClient = assetImageClient
        self.defaults = userDefaults
        self.marketDisplayMode = resolvedDisplayMode
        self.favCoins = Set(userDefaults.stringArray(forKey: favoritesKey) ?? [])
        if let restoredSession = authSessionStore?.loadSession() {
            self.authState = .authenticated(restoredSession)
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
    }

    deinit {
        AppLogger.debug(.lifecycle, "CryptoViewModel deinit #\(instanceID)")
        marketSearchDebounceTask?.cancel()
        publicPollingTask?.cancel()
        privatePollingTask?.cancel()
        marketHydrationTask?.cancel()
        marketImageHydrationTask?.cancel()
        marketRowPatchTask?.cancel()
        sparklineHydrationTask?.cancel()
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
        marketState = snapshot.rows.isEmpty ? .empty : .loaded(snapshot.universe.tradableCoins)
        marketLoadState = SourceAwareLoadState(
            phase: .showingCache,
            hasPartialFailure: snapshot.meta.partialFailureMessage != nil
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
        marketId: String? = nil
    ) -> MarketIdentity {
        if let marketId, marketId.isEmpty == false {
            return MarketIdentity(exchange: exchange, marketId: marketId, symbol: symbol)
        }

        if let selectedCoin,
           selectedExchange == exchange,
           selectedCoin.symbol == symbol {
            return selectedCoin.marketIdentity(exchange: exchange)
        }

        let candidates = (marketsByExchange[exchange] ?? [])
            + (tickerSnapshotCoinsByExchange[exchange] ?? [])
            + (marketPresentationSnapshotsByExchange[exchange]?.rows.map(\.coin) ?? [])

        let matchingCandidates = candidates.filter { $0.symbol == symbol }
        if let bestCandidate = matchingCandidates.max(by: {
            let leftScore = marketIdentityLookupScore(for: $0)
            let rightScore = marketIdentityLookupScore(for: $1)
            if leftScore == rightScore {
                return $0.marketIdentity(exchange: exchange).cacheKey < $1.marketIdentity(exchange: exchange).cacheKey
            }
            return leftScore < rightScore
        }) {
            return bestCandidate.marketIdentity(exchange: exchange)
        }

        return MarketIdentity(exchange: exchange, symbol: symbol)
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

    private func marketIdentityLookupScore(for coin: CoinInfo) -> Int {
        var score = 0
        if coin.marketId != nil { score += 8 }
        if coin.iconURL != nil { score += 3 }
        if coin.name.isEmpty == false { score += 2 }
        if coin.nameEn.isEmpty == false { score += 2 }
        return score
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
        let existingRenderableScore = existing.hasRenderableGraph ? 1 : 0
        let incomingRenderableScore = incoming.hasRenderableGraph ? 1 : 0
        if existingRenderableScore != incomingRenderableScore {
            return incomingRenderableScore > existingRenderableScore ? incoming : existing
        }

        func freshnessScore(for state: MarketRowGraphState) -> Int {
            switch state {
            case .liveVisible:
                return 3
            case .cachedVisible:
                return 2
            case .staleVisible:
                return 1
            case .none, .placeholder, .unavailable:
                return 0
            }
        }

        let existingFreshness = freshnessScore(for: existing.graphState)
        let incomingFreshness = freshnessScore(for: incoming.graphState)
        if existingFreshness != incomingFreshness {
            return incomingFreshness > existingFreshness ? incoming : existing
        }

        if existing.pointCount != incoming.pointCount {
            return incoming.pointCount > existing.pointCount ? incoming : existing
        }

        if existing.updatedAt != incoming.updatedAt {
            return incoming.updatedAt > existing.updatedAt ? incoming : existing
        }

        return incoming.generation >= existing.generation ? incoming : existing
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
                updatedAt: display.updatedAt
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
        markMarketRowVisible(marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol))
    }

    func markMarketRowVisible(marketIdentity: MarketIdentity) {
        let exchange = marketIdentity.exchange
        guard exchange == selectedExchange else {
            return
        }

        var orderedMarketIdentities = visibleMarketIdentitiesByExchange[exchange] ?? []
        orderedMarketIdentities.removeAll { $0 == marketIdentity }
        orderedMarketIdentities.insert(marketIdentity, at: 0)
        visibleMarketIdentitiesByExchange[exchange] = Array(orderedMarketIdentities.prefix(48))
        lastVisibleMarketRowAtByExchange[exchange] = Date()
        if shouldFetchSparkline(marketIdentity: marketIdentity, now: Date()) {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(marketIdentity.logFields) action=visible_priority_refine queued=true"
            )
            let generation = marketPresentationGeneration
            Task { @MainActor [weak self] in
                await self?.hydrateSparklineBatch(
                    marketIdentities: [marketIdentity],
                    exchange: exchange,
                    generation: generation,
                    phase: "visible_priority",
                    batchIndex: nil,
                    reason: "row_visible_priority_\(marketIdentity.cacheKey)"
                )
            }
        }
        scheduleVisibleSparklineHydration(
            for: exchange,
            reason: "row_visible_\(marketIdentity.cacheKey)"
        )
        scheduleMarketImageHydration(
            for: exchange,
            reason: "row_visible_\(marketIdentity.cacheKey)"
        )
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
        marketImageHydrationTask?.cancel()

        guard activeTab == .market, selectedExchange == exchange else {
            return
        }

        let generation = marketPresentationSnapshotsByExchange[exchange]?.generation ?? marketPresentationGeneration
        marketImageHydrationTask = Task { @MainActor [weak self] in
            guard let self, Task.isCancelled == false else {
                return
            }
            try? await Task.sleep(nanoseconds: self.marketImageHydrationDebounceNanoseconds)
            guard Task.isCancelled == false else {
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
        let nearVisibleRows = Array(
            prioritizedPrefetchImageRows(
                from: snapshot.rows,
                exchange: snapshot.exchange,
                excluding: visibleIdentities
            )
            .prefix(marketImagePrefetchBatchSize)
        )

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

    private func shouldHydrateMarketImage(for row: MarketRowViewState) -> Bool {
        guard row.hasImage != false,
              row.imageURL != nil else {
            return false
        }

        switch row.symbolImageState {
        case .placeholder:
            return true
        case .missing:
            return assetImageClient.assetState(for: row.symbolImageDescriptor) == .placeholderPending
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
                symbol: key.symbol,
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
        let marketIdentity = coin.marketIdentity(exchange: exchange)
        return pricesByMarketIdentity[marketIdentity]
            ?? pricesByMarketIdentity[resolvedMarketIdentity(exchange: exchange, symbol: coin.symbol)]
    }

    var currentPrice: Double {
        currentTicker?.price ?? 0
    }

    var totalAsset: Double {
        portfolioState.value?.totalAsset ?? 0
    }

    var totalPnl: Double {
        portfolio.reduce(0) { $0 + $1.profitLoss }
    }

    var totalPnlPercent: Double {
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
        showExchangeMenu = false

        AppLogger.debug(.route, "[TabState] activeTab changed \(previousTab.rawValue) -> \(tab.rawValue)")
        AppLogger.debug(.lifecycle, "[ScreenEnter] \(tab.rawValue) exchange=\(selectedExchange.rawValue)")
        if previousTab == .market, tab != .market {
            marketImageHydrationTask?.cancel()
            sparklineHydrationTask?.cancel()
            AppLogger.debug(
                .network,
                "[GraphPipeline] exchange=\(selectedExchange.rawValue) generation=\(marketPresentationGeneration) phase=cancel reason=tab_changed"
            )
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
            scheduleMarketImageHydration(
                for: selectedExchange,
                reason: "tab_changed_cached"
            )
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
        sparklineHydrationTask?.cancel()
        loadingSparklineMarketIdentitiesByExchange[previousExchange] = []
        AppLogger.debug(.route, "Exchange changed \(previousExchange.rawValue) -> \(exchange.rawValue) (source=\(source))")
        AppLogger.debug(
            .route,
            "[ExchangeDebug] selected exchange changed previous=\(previousExchange.rawValue) selected=\(exchange.rawValue) source=\(source)"
        )
        marketSwitchStartedAtByExchange[exchange] = Date()
        marketFirstVisibleLoggedExchanges.remove(exchange)
        marketFullHydrationPendingExchanges.insert(exchange)
        AppLogger.debug(
            .lifecycle,
            "[ExchangeSwitch] started exchange=\(exchange.rawValue) previous=\(previousExchange.rawValue) source=\(source)"
        )
        AppLogger.debug(
            .network,
            "[GraphPipeline] exchange=\(previousExchange.rawValue) generation=\(marketPresentationGeneration) phase=cancel reason=exchange_changed targetExchange=\(exchange.rawValue)"
        )

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
        applyCachedMarketPresentationIfAvailable(for: exchange, reason: "exchange_changed_cached")

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
        let requestKey = chartRequestKey(marketIdentity: context.marketIdentity, interval: context.mappedInterval)
        let resourceKey = chartResourceKey(marketIdentity: context.marketIdentity)
        let endpoint = marketRepository.marketCandlesEndpointPath
        refreshChartSummaryStates(reason: "\(reason)_chart_start")

        AppLogger.debug(
            .route,
            "Public chart path -> \(selectedMarketIdentity.logFields) interval=\(chartPeriod) mappedInterval=\(mappedInterval) endpoint=\(endpoint) reason=\(reason)"
        )
        AppLogger.debug(
            .network,
            "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.requestedInterval.uppercased()) phase=request_start mappedInterval=\(context.mappedInterval.uppercased()) endpoint=\(endpoint) key=\(requestKey.debugValue)"
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
            return
        }

        if let candleCache = lastSuccessfulCandles[requestKey] ?? candleCacheByKey[requestKey],
           candleCache.candles.isEmpty == false {
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
                "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.mappedInterval.uppercased()) phase=show_stale_cache candles=\(candleCache.candles.count) key=\(requestKey.debugValue)"
            )
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

        async let candleResult: Result<CandleSnapshot, Error> = fetchCandleSnapshot(for: requestKey)
        async let orderbookResult: Result<OrderbookSnapshot, Error> = fetchOrderbookSnapshot(for: resourceKey)
        async let tradesResult: Result<PublicTradesSnapshot, Error> = fetchTradesSnapshot(for: resourceKey)

        let candleResponse = await candleResult
        if shouldApplyChartResult(generation: generation, key: requestKey) {
            switch candleResponse {
            case .success(let candleSnapshot):
                let preparedCandles = prepareCandlesForLive(
                    candleSnapshot.candles,
                    interval: context.mappedInterval,
                    seedPrice: currentTicker?.price
                )
                let entry = CandleCacheEntry(
                    key: requestKey,
                    candles: preparedCandles,
                    meta: candleSnapshot.meta,
                    fetchedAt: candleSnapshot.meta.fetchedAt ?? Date()
                )
                candleCacheByKey[requestKey] = entry
                activeChartCandleMeta = candleSnapshot.meta
                if candleSnapshot.meta.isChartAvailable == false {
                    updateCandleState(
                        .unavailable(chartUnavailableMessage(kind: .candles, exchange: context.exchange)),
                        exchange: context.exchange,
                        symbol: context.symbol,
                        interval: context.mappedInterval,
                        phase: "response_unavailable"
                    )
                } else if preparedCandles.isEmpty {
                    updateCandleState(.empty, exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "response_empty")
                    AppLogger.debug(
                        .network,
                        "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.mappedInterval.uppercased()) phase=response_empty key=\(requestKey.debugValue)"
                    )
                } else {
                    lastSuccessfulCandles[requestKey] = entry
                    updateCandleState(.loaded(preparedCandles), exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "response_success")
                }
            case .failure(let error):
                let presentation = userFacingChartMessage(for: error, kind: .candles, exchange: context.exchange)
                let userMessage = presentation.message
                if let cache = lastSuccessfulCandles[requestKey] ?? candleCacheByKey[requestKey],
                   cache.candles.isEmpty == false {
                    activeChartCandleMeta = ResponseMeta(
                        fetchedAt: cache.meta.fetchedAt,
                        isStale: true,
                        warningMessage: staleWarningMessage(kind: .candles),
                        partialFailureMessage: userMessage
                    )
                    updateCandleState(.staleCache(cache.candles), exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "response_failure_keep_stale")
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
                } else {
                    updateCandleState(.failed(userMessage), exchange: context.exchange, symbol: context.symbol, interval: context.mappedInterval, phase: "response_failure")
                }
                AppLogger.debug(
                    .network,
                    "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.mappedInterval.uppercased()) phase=response_failure key=\(requestKey.debugValue) message=\(userMessage)"
                )
            }
        } else {
            AppLogger.debug(
                .network,
                "[ChartPipeline] \(context.marketIdentity.logFields) interval=\(context.mappedInterval.uppercased()) phase=drop_stale_generation generation=\(generation) key=\(requestKey.debugValue)"
            )
        }

        let orderbookResponse = await orderbookResult
        if shouldApplyChartResult(generation: generation, key: requestKey) {
            switch orderbookResponse {
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

        let tradesResponse = await tradesResult
        if shouldApplyChartResult(generation: generation, key: requestKey) {
            switch tradesResponse {
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

        lastChartSnapshotContext = context
        lastChartSnapshotFetchedAt = Date()
        refreshChartSummaryStates(reason: "\(reason)_chart_finished")
        refreshPublicStatusViewStates()
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
        signupErrorMessage = nil
        authFlowMode = .login
        isLoginPresented = true
        AppLogger.debug(.auth, "Present login for \(feature.rawValue)")
    }

    func switchAuthFlowMode(_ mode: AuthFlowMode) {
        guard authFlowMode != mode else { return }
        authFlowMode = mode
        loginErrorMessage = nil
        signupErrorMessage = nil
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

        do {
            let session = try await authService.signIn(email: loginEmail, password: loginPassword)
            await completeAuthentication(with: session, source: "login_success")
        } catch {
            authState = .guest
            loginErrorMessage = friendlyAuthErrorMessage(error, mode: .login)
        }
    }

    func submitSignUp() async {
        let validation = signUpValidation
        guard let validationMessage = validation.primaryMessage else {
            signupErrorMessage = nil
            isSigningUp = true

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
                await completeAuthentication(with: session, source: "signup_success")
                clearSignUpFields()
            } catch {
                signupErrorMessage = friendlyAuthErrorMessage(error, mode: .signUp)
            }

            isSigningUp = false
            return
        }

        signupErrorMessage = nil
        AppLogger.debug(.auth, "Sign up blocked by local validation -> \(validationMessage)")
    }

    func logout() {
        authState = .guest
        pendingPostLoginFeature = nil
        loginPassword = ""
        clearSignUpFields()
        authSessionStore?.clearSession()
        isExchangeConnectionsPresented = false
        portfolioState = .idle
        portfolioHistoryState = .idle
        orderHistoryState = .idle
        fillsState = .idle
        selectedOrderDetailState = .idle
        exchangeConnectionsState = .idle
        loadedExchangeConnections = []
        privateWebSocketService.disconnect()
        updateAuthGate()
        updatePrivateSubscriptions(reason: "logout")
        AppLogger.debug(.auth, "User session cleared")
    }

    func openStatusAction() {
        if isAuthenticated {
            isExchangeConnectionsPresented = true
            Task {
                await loadExchangeConnections()
            }
        } else {
            presentLogin(for: activeTab.protectedFeature ?? .portfolio)
        }
    }

    func openExchangeConnections() {
        if isAuthenticated {
            isExchangeConnectionsPresented = true
            Task {
                await loadExchangeConnections()
            }
        } else {
            presentLogin(for: .exchangeConnections)
        }
    }

    private func completeAuthentication(with session: AuthSession, source: String) async {
        authState = .authenticated(session)
        authSessionStore?.saveSession(session)
        AppLogger.debug(.auth, "Authentication success -> \(session.email ?? session.userID ?? "user")")

        loginPassword = ""
        loginErrorMessage = nil
        signupErrorMessage = nil
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
            isExchangeConnectionsPresented = true
        }
        pendingPostLoginFeature = nil
    }

    private func clearSignUpFields() {
        signupEmail = ""
        signupPassword = ""
        signupPasswordConfirm = ""
        signupNickname = ""
        signupAcceptedTerms = false
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
            _ = try await exchangeConnectionsRepository.createConnection(
                session: session,
                request: ExchangeConnectionUpsertRequest(
                    exchange: exchange,
                    permission: permission,
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    credentials: credentials.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                )
            )
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
            _ = try await exchangeConnectionsRepository.updateConnection(
                session: session,
                request: ExchangeConnectionUpdateRequest(
                    id: connection.id,
                    permission: permission,
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    credentials: filteredCredentials
                )
            )
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
            try await exchangeConnectionsRepository.deleteConnection(session: session, connectionID: id)
            showNotification("거래소 연결을 삭제했어요", type: .success)
            await loadExchangeConnections()
            return true
        } catch {
            showNotification(error.localizedDescription, type: .error)
            return false
        }
    }

    func loadPortfolio() async {
        guard capabilityResolver.supportsPortfolio(on: selectedExchange) else {
            portfolioState = .failed("이 거래소는 자산 조회를 지원하지 않아요.")
            portfolioHistoryState = .idle
            portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: currentPrivateStreamingStatus,
                context: .portfolio,
                warningMessage: "지원하지 않는 기능입니다."
            )
            return
        }

        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip portfolio fetch in guest state")
            portfolioState = .idle
            portfolioHistoryState = .idle
            return
        }

        AppLogger.debug(.route, "Authenticated portfolio path -> \(exchange.rawValue)")
        portfolioState = .loading
        portfolioHistoryState = .loading

        do {
            async let summaryTask = portfolioRepository.fetchSummary(session: session, exchange: exchange)
            async let historyTask = portfolioRepository.fetchHistory(session: session, exchange: exchange)

            let summary = try await summaryTask
            portfolioState = summary.holdings.isEmpty && summary.cash == 0 ? .empty : .loaded(summary)

            do {
                let historySnapshot = try await historyTask
                portfolioHistoryState = historySnapshot.items.isEmpty ? .empty : .loaded(historySnapshot.items)
                portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
                    meta: combineMetas([summary.meta, historySnapshot.meta]),
                    streamingStatus: currentPrivateStreamingStatus,
                    context: .portfolio,
                    warningMessage: resolvedWarningMessage(
                        primary: summary.partialFailureMessage ?? historySnapshot.meta.partialFailureMessage,
                        fallback: currentPrivateStreamingWarningMessage
                    )
                )
            } catch {
                portfolioHistoryState = .failed(error.localizedDescription)
                portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
                    meta: summary.meta,
                    streamingStatus: currentPrivateStreamingStatus,
                    context: .portfolio,
                    warningMessage: resolvedWarningMessage(
                        primary: summary.partialFailureMessage ?? "일부 히스토리를 불러오지 못했어요.",
                        fallback: currentPrivateStreamingWarningMessage
                    )
                )
            }
        } catch {
            portfolioState = .failed(error.localizedDescription)
            portfolioHistoryState = .idle
            portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: currentPrivateStreamingStatus,
                context: .portfolio,
                warningMessage: resolvedWarningMessage(
                    primary: error.localizedDescription,
                    fallback: currentPrivateStreamingWarningMessage
                )
            )
        }
    }

    func loadOrders() async {
        guard capabilityResolver.supportsTrading(on: selectedExchange) else {
            orderHistoryState = .failed("이 거래소는 주문 기능을 지원하지 않아요.")
            fillsState = .idle
            tradingChanceState = .idle
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
            orderHistoryState = .idle
            fillsState = .idle
            tradingChanceState = .idle
            return
        }

        guard let coin = selectedCoin else {
            tradingChanceState = .idle
            orderHistoryState = .idle
            fillsState = .idle
            selectedOrderDetailState = .idle
            return
        }

        tradingChanceState = .loading
        orderHistoryState = .loading
        fillsState = .loading

        var metas: [ResponseMeta] = []
        var warningMessages: [String] = []

        do {
            let chance = try await tradingRepository.fetchChance(session: session, exchange: selectedExchange, symbol: coin.symbol)
            tradingChanceState = .loaded(chance)
            if !chance.supportedOrderTypes.contains(orderType) {
                orderType = chance.supportedOrderTypes.first ?? .limit
            }
            if let warningMessage = chance.warningMessage {
                warningMessages.append(warningMessage)
            }
        } catch {
            tradingChanceState = .failed(error.localizedDescription)
        }

        do {
            let openOrdersSnapshot = try await tradingRepository.fetchOpenOrders(session: session, exchange: selectedExchange, symbol: coin.symbol)
            metas.append(openOrdersSnapshot.meta)
            if let warningMessage = openOrdersSnapshot.meta.warningMessage {
                warningMessages.append(warningMessage)
            }
            orderHistoryState = openOrdersSnapshot.orders.isEmpty ? .empty : .loaded(openOrdersSnapshot.orders)
        } catch {
            orderHistoryState = .failed(error.localizedDescription)
        }

        do {
            let fillsSnapshot = try await tradingRepository.fetchFills(session: session, exchange: selectedExchange, symbol: coin.symbol)
            metas.append(fillsSnapshot.meta)
            if let warningMessage = fillsSnapshot.meta.warningMessage {
                warningMessages.append(warningMessage)
            }
            fillsState = fillsSnapshot.fills.isEmpty ? .empty : .loaded(fillsSnapshot.fills)
        } catch {
            fillsState = .failed(error.localizedDescription)
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
            let detail = try await tradingRepository.fetchOrderDetail(session: session, exchange: selectedExchange, orderID: orderID)
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
            try await tradingRepository.cancelOrder(session: session, exchange: selectedExchange, orderID: order.id)
            showNotification("주문을 취소했어요", type: .success)
            await loadOrders()
            await loadPortfolio()
        } catch {
            showNotification(error.localizedDescription, type: .error)
        }
    }

    func loadExchangeConnections() async {
        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip exchange connections fetch in guest state")
            exchangeConnectionsState = .idle
            loadedExchangeConnections = []
            return
        }

        exchangeConnectionsState = .loading

        do {
            let snapshot = try await exchangeConnectionsRepository.fetchConnections(session: session)
            loadedExchangeConnections = snapshot.connections
            let cards = exchangeConnectionsUseCase.makeCardViewStates(
                connections: snapshot.connections,
                crudCapability: exchangeConnectionCRUDCapability
            )
            exchangeConnectionsState = cards.isEmpty ? .empty : .loaded(cards)
            updatePrivateSubscriptions(reason: "exchange_connections_loaded")
        } catch {
            exchangeConnectionsState = .failed(error.localizedDescription)
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
        showExchangeMenu = false
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
            _ = try await tradingRepository.createOrder(
                session: session,
                request: TradingOrderCreateRequest(
                    symbol: coin.symbol,
                    exchange: selectedExchange,
                    side: orderSide,
                    type: orderType,
                    price: price,
                    quantity: quantity
                )
            )

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            showNotification("\(coin.name) 주문 요청을 전송했어요", type: .success)
            orderQty = ""
            await loadOrders()
            await loadPortfolio()
        } catch {
            showNotification(error.localizedDescription, type: .error)
        }

        isSubmittingOrder = false
    }

    func applyPercent(_ percent: Double) {
        guard let coin = selectedCoin else { return }

        let price: Double
        switch orderType {
        case .market:
            price = currentPrice
        case .limit:
            price = Double(orderPrice.replacingOccurrences(of: ",", with: "")) ?? currentPrice
        }

        guard price > 0 else { return }

        if orderSide == .buy {
            let buyingBalance = tradingChanceState.value?.bidBalance ?? cash
            let quantity = (buyingBalance * percent / 100.0) / price
            orderQty = String(format: "%.6f", quantity)
        } else {
            let holdingQuantity = portfolio.first { $0.symbol == coin.symbol }?.totalQuantity ?? 0
            let quantity = holdingQuantity * percent / 100.0
            orderQty = String(format: "%.6f", quantity)
        }
    }

    func adjustPrice(up: Bool) {
        let baseValue = Double(orderPrice.replacingOccurrences(of: ",", with: "")) ?? currentPrice
        let priceUnit = tradingChanceState.value?.priceUnit ?? max(baseValue * 0.001, 1)
        let newPrice = up ? baseValue + priceUnit : max(baseValue - priceUnit, 0)
        orderPrice = PriceFormatter.formatPrice(newPrice)
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
            await loadExchangeConnections()
            await loadPortfolio()
        case .trade:
            await loadMarkets(for: selectedExchange, forceRefresh: false, reason: "\(reason)_trade_markets")
            ensureSelectedCoinIfPossible(for: selectedExchange)
            await loadExchangeConnections()
            await loadOrders()
            if portfolioState.value == nil || forceRefresh {
                await loadPortfolio()
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
            }
            isPrivatePollingFallbackActive = false
            return
        }

        if !isPrivatePollingFallbackActive {
            AppLogger.debug(
                .network,
                "Private polling fallback -> active (state=\(describe(privateWebSocketState)), exchange=\(selectedExchange.rawValue), route=\(activeTab.rawValue))"
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
            await loadExchangeConnections()
            await loadPortfolio()
        case .trade:
            await loadExchangeConnections()
            await loadOrders()
        case .market, .chart, .kimchi:
            break
        }
    }

    private func applyTickerUpdate(_ payload: TickerStreamPayload) {
        guard shouldApplyVisibleTickerUpdate(for: payload.exchange) else {
            AppLogger.debug(
                .network,
                "[MarketScreen] stale response ignored exchange=\(payload.exchange) route=\(activeTab.rawValue) generation=\(marketPresentationGeneration) source=websocket"
            )
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

        let didEnqueue = enqueueMarketRowPatch(
            marketIdentity: marketIdentity,
            exchange: exchange,
            generation: snapshot.generation,
            sparklinePatch: nil,
            symbolImagePatch: nil,
            rebuildReason: reason
        )
        if didEnqueue {
            AppLogger.debug(
                .lifecycle,
                "[MarketRows] reconfigure_queued count=1 \(marketIdentity.logFields) reason=\(reason) scope=\(reason == "ticker_flash_reset" ? "price_subview_flash" : "base_ticker_refresh")"
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
        ticker.flash = incoming.price > previousPrice ? .up : (incoming.price < previousPrice ? .down : nil)

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
            prefillOrderPriceIfPossible()
            refreshChartSummaryStates(reason: "ticker_merge")
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
            return true
        }

        let now = Date()
        let oldDetail = MarketSparklineDetailLevel(
            graphState: existing.graphState(staleInterval: sparklineCacheStaleInterval, now: now),
            points: existing.points,
            pointCount: existing.pointCount
        )
        let newDetail = MarketSparklineDetailLevel(
            graphState: incoming.graphState(staleInterval: sparklineCacheStaleInterval, now: now),
            points: incoming.points,
            pointCount: incoming.pointCount
        )
        if oldDetail.pathDetailRank > newDetail.pathDetailRank {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(marketIdentity.logFields) action=redraw_skipped reason=coarse_snapshot_rejected oldDetail=\(oldDetail.cacheComponent) newDetail=\(newDetail.cacheComponent)"
            )
            return false
        }
        if oldDetail.isDetailed,
           newDetail.isDetailed,
           existing.pointCount > incoming.pointCount {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(marketIdentity.logFields) action=redraw_skipped reason=lower_point_snapshot_rejected oldPointCount=\(existing.pointCount) newPointCount=\(incoming.pointCount)"
            )
            return false
        }
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
                let shouldReplace = value.graphState.keepsVisibleGraph && existing.graphState.keepsVisibleGraph == false
                    || value.pointCount > existing.pointCount
                    || value.updatedAt > existing.updatedAt
                if shouldReplace {
                    displays[key.marketIdentity] = value
                }
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
                updatedAt: now
            )
        }
    }

    private func sparklineSnapshotsByMarketIdentity(for exchange: Exchange) -> [MarketIdentity: SparklineLayerSnapshot] {
        var snapshots = [MarketIdentity: SparklineLayerSnapshot]()
        let marketIdentities = Self.deduplicatedMarketIdentities(
            (marketPresentationSnapshotsByExchange[exchange]?.rows.map(\.marketIdentity) ?? [])
                + (tickerSnapshotCoinsByExchange[exchange]?.map { $0.marketIdentity(exchange: exchange) } ?? [])
        )
        for marketIdentity in marketIdentities {
            if let snapshot = sparklineSnapshot(marketIdentity: marketIdentity) {
                snapshots[marketIdentity] = snapshot
            }
        }
        return snapshots
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
            AppLogger.debug(
                .network,
                "[GraphRequestDebug] exchange=\(exchange.rawValue) action=queue_visible_refresh reason=hydration_inflight"
            )
            return
        }

        let generation = marketPresentationGeneration
        sparklineHydrationTask?.cancel()
        sparklineHydrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.sparklineSchedulerDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.runSparklineHydrationLoop(
                for: exchange,
                generation: generation,
                reason: reason
            )
        }
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
            shouldFetchSparkline(marketIdentity: $0, now: Date())
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
            AppLogger.debug(
                .network,
                "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=cache_hit markets=\(cacheHits.prefix(8).map(\.cacheKey).joined(separator: ",")) count=\(cacheHits.count)"
            )
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
        let visibleBatch = Array(candidates.filter { visibleSet.contains($0) }.prefix(sparklineVisibleBatchSize))
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

        guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
            return
        }

        let alreadyRequested = Set(visibleBatch)
        let backgroundCandidates = candidates.filter { alreadyRequested.contains($0) == false }
        guard backgroundCandidates.isEmpty == false else {
            return
        }
        if visibleBatch.isEmpty == false {
            try? await Task.sleep(for: .milliseconds(180))
        }
        if let lastVisibleAt = lastVisibleMarketRowAtByExchange[exchange],
           Date().timeIntervalSince(lastVisibleAt) < 0.45 {
            AppLogger.debug(
                .network,
                "[GraphPipeline] exchange=\(exchange.rawValue) generation=\(generation) phase=deferred_offscreen markets=\(backgroundCandidates.prefix(10).map(\.cacheKey).joined(separator: ","))"
            )
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
            MarketPerformanceDebugClient.shared.increment(.offscreenBatch)
            await hydrateSparklineBatch(
                marketIdentities: batch,
                exchange: exchange,
                generation: generation,
                phase: "offscreen_batch",
                batchIndex: index + 1,
                reason: reason
            )
        }
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

    private func shouldFetchSparkline(symbol: String, exchange: Exchange, now: Date) -> Bool {
        shouldFetchSparkline(
            marketIdentity: resolvedMarketIdentity(exchange: exchange, symbol: symbol),
            now: now
        )
    }

    private func shouldFetchSparkline(marketIdentity: MarketIdentity, now: Date) -> Bool {
        let key = sparklineCacheKey(marketIdentity: marketIdentity)
        if sparklineFetchTasksByKey[key] != nil {
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

        if let lastAttemptAt = lastSparklineRefreshAttemptAtByKey[key],
           now.timeIntervalSince(lastAttemptAt) < sparklineRefreshThrottleInterval,
           hasUsableSparklineGraph(marketIdentity: marketIdentity) {
            AppLogger.debug(
                .network,
                "[GraphRequestDebug] \(marketIdentity.logFields) action=skip_refresh reason=stale_usable_within_cooldown"
            )
            return false
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
        let batchMarketIdentities = Self.deduplicatedMarketIdentities(
            marketIdentities.filter {
                $0.exchange == exchange && shouldFetchSparkline(marketIdentity: $0, now: Date())
            }
        )
        guard batchMarketIdentities.isEmpty == false else {
            return
        }
        let batchSet = Set(batchMarketIdentities)
        guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
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

        loadingSparklineMarketIdentitiesByExchange[exchange, default: []].subtract(batchSet)
        guard shouldRunSparklineHydration(exchange: exchange, generation: generation) else {
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
                    symbol: marketIdentity.symbol,
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
        for request in tasks {
            do {
                let snapshot = try await request.task.value
                sparklineFetchTasksByKey[request.key] = nil
                sparklineFailureCooldownUntilByKey[request.key] = nil
                results.append((request.marketIdentity, .success(snapshot)))
            } catch {
                sparklineFetchTasksByKey[request.key] = nil
                sparklineFailureCooldownUntilByKey[request.key] = Date().addingTimeInterval(sparklineFailureCooldownInterval)
                results.append((request.marketIdentity, .failure(error)))
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
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(marketIdentity.logFields) action=drop_patch reason=identity_mismatch"
                )
            }
            return
        }

        for marketIdentity in marketIdentities {
            guard let row = presentation.rows.first(where: { $0.marketIdentity == marketIdentity }) else {
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(marketIdentity.logFields) action=drop_patch reason=identity_mismatch"
                )
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
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(patch.marketIdentity.logFields) action=drop_patch reason=identity_mismatch"
                )
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
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(patch.marketIdentity.logFields) action=drop_patch reason=identity_mismatch"
                )
                continue
            }
            if enqueueMarketRowPatch(
                marketIdentity: patch.marketIdentity,
                exchange: exchange,
                generation: generation,
                sparklinePatch: patch,
                symbolImagePatch: nil,
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
        guard let selectedCoin else { return }
        let marketIdentity = selectedCoin.marketIdentity(exchange: selectedExchange)
        guard let price = pricesByMarketIdentity[marketIdentity]?.price
            ?? pricesByMarketIdentity[resolvedMarketIdentity(exchange: selectedExchange, symbol: selectedCoin.symbol)]?.price else {
            return
        }
        orderPrice = PriceFormatter.formatPrice(price)
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
                marketState = .failed("데이터를 불러오지 못했어요. 잠시 후 다시 시도해주세요.")
                marketLoadState = .hardFailure
            } else {
                marketState = .loading
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
        overrideMeta: ResponseMeta
    ) -> MarketPresentationBuildInput {
        let normalizedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return MarketPresentationBuildInput(
            exchange: exchange,
            generation: marketPresentationGeneration,
            assetImageClient: assetImageClient,
            catalogCoins: marketsByExchange[exchange] ?? [],
            tickerSnapshotCoins: tickerSnapshotCoinsByExchange[exchange] ?? [],
            cachedRows: marketPresentationSnapshotsByExchange[exchange]?.rows ?? [],
            pricesByMarketIdentity: pricesByMarketIdentity.filter { $0.key.exchange == exchange },
            sparklineSnapshotsByMarketIdentity: sparklineSnapshotsByMarketIdentity(for: exchange),
            stableSparklineDisplaysByMarketIdentity: stableSparklineDisplaysByMarketIdentity(for: exchange),
            loadingSparklineMarketIdentities: loadingSparklineMarketIdentitiesByExchange[exchange] ?? [],
            unavailableSparklineMarketIdentities: unavailableSparklineMarketIdentitiesByExchange[exchange] ?? [],
            filteredMarketIdentities: filteredMarketIdentitiesByExchange[exchange] ?? [],
            filteredTickerIdentities: filteredTickerIdentitiesByExchange[exchange] ?? [],
            selectedCoinIdentity: selectedExchange == exchange ? selectedCoin?.marketIdentity(exchange: exchange) : nil,
            favoriteSymbols: favCoins,
            shouldLimitFirstPaint: fullyHydratedMarketExchanges.contains(exchange) == false
                && marketFilter == .all
                && normalizedSearch.isEmpty,
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
            let prioritizedMarketIdentities = Self.prioritizedMarketIdentities(
                from: sortedTradableCoins,
                exchange: input.exchange,
                selectedCoinIdentity: input.selectedCoinIdentity,
                favoriteSymbols: input.favoriteSymbols
            )
            presentationCoinIdentities = Array(prioritizedMarketIdentities.prefix(input.marketFirstPaintRowLimit))
        } else {
            presentationCoinIdentities = sortedTradableCoins.map { $0.marketIdentity(exchange: input.exchange) }
        }

        let coinsByMarketIdentity = coinsByMarketIdentity(sortedTradableCoins, exchange: input.exchange)
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

    private nonisolated static func preferredMarketRow(
        existing: MarketRowViewState,
        incoming: MarketRowViewState
    ) -> MarketRowViewState {
        let existingDetail = existing.sparklinePayload.detailLevel
        let incomingDetail = incoming.sparklinePayload.detailLevel
        if incomingDetail.pathDetailRank != existingDetail.pathDetailRank {
            return incomingDetail.pathDetailRank > existingDetail.pathDetailRank ? incoming : existing
        }
        if incoming.graphState.keepsVisibleGraph != existing.graphState.keepsVisibleGraph {
            return incoming.graphState.keepsVisibleGraph ? incoming : existing
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
            dataState: dataState
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
        staleInterval: TimeInterval,
        now: Date,
        hasResolvedBaseData: Bool
    ) -> (points: [Double], pointCount: Int, graphState: MarketRowGraphState, source: SparklineDisplayResolutionSource) {
        if let snapshot {
            let snapshotState = snapshot.graphState(staleInterval: staleInterval, now: now)
            return (
                snapshot.points,
                snapshot.pointCount,
                snapshotState,
                .snapshot
            )
        }

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

            return (
                stableSparklineDisplay.points,
                stableSparklineDisplay.pointCount,
                retainedState,
                .displayCache
            )
        }

        if let cachedRow,
           MarketSparklineRenderPolicy.hasRenderableGraph(
            points: cachedRow.sparkline,
            pointCount: cachedRow.sparklinePointCount
           ),
           cachedRow.graphState.keepsVisibleGraph {
            let retainedState: MarketRowGraphState
            switch cachedRow.graphState {
            case .liveVisible:
                retainedState = isUnavailable ? .staleVisible : (isLoading ? .liveVisible : .staleVisible)
            case .cachedVisible:
                retainedState = .cachedVisible
            case .staleVisible:
                retainedState = .staleVisible
            case .none, .placeholder, .unavailable:
                retainedState = .cachedVisible
            }

            return (
                cachedRow.sparkline,
                cachedRow.sparklinePointCount,
                retainedState,
                .rowState
            )
        }

        switch cachedRow?.graphState {
        case .some(.unavailable):
            return ([], 0, .unavailable, .unavailable)
        case .some(.none), .some(.placeholder), .some(.cachedVisible), .some(.liveVisible), .some(.staleVisible), nil:
            break
        }

        if isUnavailable {
            return ([], 0, .unavailable, .unavailable)
        }

        return (
            [],
            0,
            hasResolvedBaseData ? .placeholder : .none,
            hasResolvedBaseData ? .placeholder : .none
        )
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

        let prioritizedCoinIdentities = Self.prioritizedMarketIdentities(
            from: universe.tradableCoins,
            exchange: exchange,
            selectedCoinIdentity: selectedExchange == exchange ? selectedCoin?.marketIdentity(exchange: exchange) : nil,
            favoriteSymbols: favCoins
        )
        let coinsByMarketIdentity = Self.coinsByMarketIdentity(universe.tradableCoins, exchange: exchange)
        let limitedCoins = prioritizedCoinIdentities
            .prefix(marketFirstPaintRowLimit)
            .compactMap { coinsByMarketIdentity[$0] }

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
        rebuildReason: String?
    ) -> Bool {
        guard marketIdentity.exchange == exchange,
              let presentation = marketPresentationSnapshotsByExchange[exchange],
              presentation.generation == generation,
              presentation.rows.contains(where: { $0.marketIdentity == marketIdentity }) else {
            if let sparklinePatch {
                AppLogger.debug(
                    .network,
                    "[GraphScrollDebug] \(sparklinePatch.marketIdentity.logFields) action=drop_patch reason=identity_mismatch"
                )
            }
            return false
        }

        var patches = pendingMarketRowPatchesByExchange[exchange] ?? [:]
        if var existingPatch = patches[marketIdentity] {
            existingPatch.merge(
                sparklinePatch: sparklinePatch,
                symbolImagePatch: symbolImagePatch,
                rebuildReason: rebuildReason,
                preferredSparklinePatch: { [self] existing, incoming in
                    preferredSparklinePatch(existing: existing, incoming: incoming)
                },
                preferredImagePatch: { [self] existing, incoming in
                    preferredSymbolImagePatch(existing: existing, incoming: incoming)
                }
            )
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
                rebuildReason: rebuildReason,
                preferredSparklinePatch: { [self] existing, incoming in
                    preferredSparklinePatch(existing: existing, incoming: incoming)
                },
                preferredImagePatch: { [self] existing, incoming in
                    preferredSymbolImagePatch(existing: existing, incoming: incoming)
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

    private func applySparklinePatchToRow(
        _ patch: MarketSparklinePatch,
        row previousRow: MarketRowViewState,
        exchange: Exchange,
        generation: Int
    ) -> MarketRowViewState? {
        if previousRow.exchange != exchange || previousRow.sparklineTimeframe != sparklineInterval(for: patch.marketIdentity) {
            AppLogger.debug(
                .network,
                "[GraphScrollDebug] \(patch.marketIdentity.logFields) action=drop_patch reason=identity_mismatch"
            )
            return nil
        }
        if let snapshot = patch.snapshot,
           snapshot.interval != previousRow.sparklineTimeframe {
            AppLogger.debug(
                .network,
                "[GraphScrollDebug] \(patch.marketIdentity.logFields) action=drop_patch reason=identity_mismatch"
            )
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

        let nextGraphState: MarketRowGraphState
        let nextPoints: [Double]
        let nextPointCount: Int

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
        } else {
            switch patch.graphState {
            case .unavailable:
                nextGraphState = .unavailable
                nextPoints = []
                nextPointCount = 0
            case .cachedVisible, .liveVisible, .staleVisible:
                nextGraphState = patch.graphState
                nextPoints = patch.snapshot?.points ?? previousRow.sparkline
                nextPointCount = patch.snapshot?.pointCount ?? previousRow.sparklinePointCount
            case .none, .placeholder:
                nextGraphState = previousRow.hasPrice || previousRow.hasVolume ? .placeholder : .none
                nextPoints = []
                nextPointCount = 0
            }
        }

        let previousDetail = previousRow.sparklinePayload.detailLevel
        let nextDetail = MarketSparklineDetailLevel(
            graphState: nextGraphState,
            points: nextPoints,
            pointCount: nextPointCount
        )
        if previousDetail.pathDetailRank > nextDetail.pathDetailRank {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(patch.marketIdentity.logFields) action=redraw_skipped reason=coarse_patch_rejected oldDetail=\(previousDetail.cacheComponent) newDetail=\(nextDetail.cacheComponent)"
            )
            return nil
        }
        if previousDetail.isDetailed,
           nextDetail.isDetailed,
           previousRow.sparklinePointCount > nextPointCount {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(patch.marketIdentity.logFields) action=redraw_skipped reason=lower_point_patch_rejected oldPointCount=\(previousRow.sparklinePointCount) newPointCount=\(nextPointCount)"
            )
            return nil
        }
        if nextDetail.pathDetailRank > previousDetail.pathDetailRank
            || (nextDetail.isDetailed && nextPointCount > previousRow.sparklinePointCount) {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(patch.marketIdentity.logFields) action=refined_patch_received oldDetail=\(previousDetail.cacheComponent) newDetail=\(nextDetail.cacheComponent) oldPointCount=\(previousRow.sparklinePointCount) newPointCount=\(nextPointCount)"
            )
        }

        let updatedRow = previousRow.replacingSparkline(
            points: nextPoints,
            pointCount: nextPointCount,
            graphState: nextGraphState
        )
        guard updatedRow != previousRow else {
            AppLogger.debug(
                .network,
                "[GraphDetailDebug] \(patch.marketIdentity.logFields) action=redraw_skipped reason=detailed_same_signature detailLevel=\(previousDetail.cacheComponent) pointCount=\(previousRow.sparklinePointCount)"
            )
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
            "[GraphPipeline] \(patch.marketIdentity.logFields) generation=\(generation) phase=row_patch state=\(nextGraphState) reason=\(patch.reason) scope=graph_subview_payload"
        )
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
        let rows = presentationCoins.map { coin in
            let marketIdentity = coin.marketIdentity(exchange: exchange)
            return makeMarketRowViewState(
                for: coin,
                exchange: exchange,
                cachedRow: cachedRowsByMarketIdentity[marketIdentity]
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
                marketState = .loading
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
                marketState = .loading
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
            let snapshot = await self.prepareMarketPresentationSnapshot(from: buildInput)
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
        _ = exchange
        _ = hasCatalog
        _ = hasTickerSnapshot
        _ = hasTickerData
        return false
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

        marketPresentationSnapshotsByExchange[snapshot.exchange] = snapshot
        activeMarketPresentationSnapshot = snapshot
        persistStableSparklineDisplays(from: snapshot.rows, exchange: snapshot.exchange, generation: snapshot.generation)
        if clearTransition == false {
            marketBasePhaseByExchange[snapshot.exchange] = .showingCache
        } else {
            marketBasePhaseByExchange[snapshot.exchange] = .showingSnapshot
        }

        applyMarketRowsDiff(snapshot.rows, reason: "exchange_switch_staged_swap:\(reason)")
        marketPresentationState = makeMarketPresentationState(
            from: snapshot,
            previousExchange: marketPresentationState.selectedExchange == snapshot.exchange ? nil : marketPresentationState.selectedExchange,
            sameExchangeStaleReuse: false,
            transitionPhase: clearTransition ? nil : .hydrated
        )
        logMarketSwitchProgressIfNeeded(snapshot: snapshot, reason: reason)

        if snapshot.rows.isEmpty {
            marketState = .empty
        } else {
            marketState = .loaded(snapshot.universe.tradableCoins)
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
        AppLogger.debug(
            .lifecycle,
            "[MarketScreen] swapped staged rows exchange=\(snapshot.exchange.rawValue) count=\(snapshot.rows.count)"
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
        if marketFirstVisibleLoggedExchanges.contains(snapshot.exchange) == false,
           snapshot.rows.isEmpty == false {
            marketFirstVisibleLoggedExchanges.insert(snapshot.exchange)
            AppLogger.debug(
                .lifecycle,
                "[ExchangeSwitch] first visible rows exchange=\(snapshot.exchange.rawValue) rows=\(snapshot.rows.count) elapsedMs=\(elapsedMs) reason=\(reason)"
            )
            MarketPerformanceDebugClient.shared.log(
                .initialVisibleFirstPaintElapsed,
                exchange: snapshot.exchange,
                details: [
                    "elapsedMs": "\(elapsedMs)",
                    "reason": reason,
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
                "[ExchangeSwitch] completed exchange=\(snapshot.exchange.rawValue) hydratedRows=\(snapshot.rows.count) elapsedMs=\(elapsedMs) reason=\(reason)"
            )
            MarketPerformanceDebugClient.shared.log(
                .exchangeSwitchElapsed,
                exchange: snapshot.exchange,
                details: [
                    "elapsedMs": "\(elapsedMs)",
                    "reason": reason,
                    "rows": "\(snapshot.rows.count)"
                ]
            )
        }
    }

    private func applyMarketRowsDiff(
        _ newRows: [MarketRowViewState],
        reason: String = "unspecified",
        reconfigureTraces: [MarketRowReconfigureTrace] = []
    ) {
        let previousIDs = marketRowStates.map(\.id)
        let nextIDs = newRows.map(\.id)
        let previousRows = marketRowStates

        guard previousIDs == nextIDs else {
            logGraphDisplayTransitions(from: previousRows, to: newRows)
            AppLogger.debug(
                .lifecycle,
                "[MarketRows] reload count=\(newRows.count) exchange=\(newRows.first?.exchange.rawValue ?? selectedExchange.rawValue) reason=\(reason) scope=exchange_switch_staged_swap"
            )
            marketRowStates = newRows
            return
        }

        var mergedRows = marketRowStates
        var changedIndices = [Int]()

        for index in newRows.indices where mergedRows[index] != newRows[index] {
            mergedRows[index] = newRows[index]
            changedIndices.append(index)
        }

        guard changedIndices.isEmpty == false else {
            return
        }

        AppLogger.debug(
            .lifecycle,
            "[MarketRows] reconfigure count=\(changedIndices.count) exchange=\(newRows.first?.exchange.rawValue ?? selectedExchange.rawValue) reason=\(reason) causes=\(marketRowsReconfigureCauseSummary(reconfigureTraces))"
        )
        MarketPerformanceDebugClient.shared.increment(.visibleRowReconfigure, by: changedIndices.count)
        logGraphDisplayTransitions(from: previousRows, to: mergedRows)
        marketRowStates = mergedRows
    }

    private func marketRowsReconfigureCauseSummary(_ traces: [MarketRowReconfigureTrace]) -> String {
        guard traces.isEmpty == false else {
            return "unspecified"
        }
        var countsByReason = [String: Int]()
        for trace in traces {
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
            let signature = "\(row.graphState)|\(row.graphRenderVersion)|\(row.graphPathVersion)|\(row.sparklinePointCount)"
            guard lastLoggedGraphDisplaySignaturesByBindingKey[row.graphBindingKey] != signature else {
                continue
            }
            lastLoggedGraphDisplaySignaturesByBindingKey[row.graphBindingKey] = signature

            guard let previousRow = oldRowsByID[row.id] else {
                AppLogger.debug(
                    .network,
                    "[GraphFirstPaintDebug] \(row.marketLogFields) source=\(graphLogSource(for: row)) graphState=\(row.graphState)"
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
                || previousRow.sparklinePointCount != row.sparklinePointCount else {
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
                marketState = .loading
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
        marketState = activeSnapshot.rows.isEmpty ? .loading : .loaded(activeSnapshot.universe.tradableCoins)
        marketTransitionMessage = "\(selectedExchange.displayName) 시세 업데이트 중"
        AppLogger.debug(.lifecycle, "[MarketScreen] same exchange reuse exchange=\(selectedExchange.rawValue) reason=\(reason)")
    }

    private func beginMarketTransition(to exchange: Exchange, from previousExchange: Exchange?, reason: String) {
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
        marketState = .loading
        marketLoadState = .initialLoading
        marketTransitionMessage = "\(exchange.displayName) 시세 준비 중"
        AppLogger.debug(.lifecycle, "[MarketScreen] transition start exchange=\(exchange.rawValue) reason=\(reason)")
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
        selectedExchange.rawValue == exchange
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
                primary: portfolioState.value?.partialFailureMessage,
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

        if activeTab == .chart, let selectedCoin {
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
            return .snapshotOnly
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
            return message
        case .disconnected:
            return "연결이 잠시 불안정해 최신 정보를 다시 확인하고 있어요."
        case .connected, .connecting:
            return nil
        }
    }

    private var currentPrivateStreamingWarningMessage: String? {
        switch privateWebSocketState {
        case .failed(let message):
            return message
        case .disconnected:
            return "연결이 잠시 불안정해 최신 정보를 다시 확인하고 있어요."
        case .connected, .connecting:
            return nil
        }
    }

    private func resolvedWarningMessage(primary: String?, fallback: String?) -> String? {
        primary ?? fallback
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
        guard let snapshot = portfolioState.value else { return .empty }
        return snapshot.meta
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
