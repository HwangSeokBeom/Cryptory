import Foundation
import CoreGraphics

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

enum DataLoadPhase: Equatable {
    case initialLoading
    case showingCache
    case showingSnapshot
    case streaming
    case degradedPolling
    case partialFailure
    case hardFailure
}

struct SourceAwareLoadState: Equatable {
    let phase: DataLoadPhase
    let hasPartialFailure: Bool

    static let initialLoading = SourceAwareLoadState(
        phase: .initialLoading,
        hasPartialFailure: false
    )

    static let hardFailure = SourceAwareLoadState(
        phase: .hardFailure,
        hasPartialFailure: false
    )
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

enum ExchangeRowsPhase: Equatable {
    case idle
    case loading
    case partial
    case hydrated
}

struct ExchangeRowsState<Row: Equatable>: Equatable {
    let exchange: Exchange
    let rows: [Row]
    let phase: ExchangeRowsPhase
    let showsPlaceholder: Bool

    var isLoading: Bool {
        showsPlaceholder || phase == .loading
    }
}

extension ExchangeRowsState {
    static func empty(
        for exchange: Exchange,
        phase: ExchangeRowsPhase = .idle,
        showsPlaceholder: Bool = false
    ) -> ExchangeRowsState<Row> {
        ExchangeRowsState(
            exchange: exchange,
            rows: [],
            phase: phase,
            showsPlaceholder: showsPlaceholder
        )
    }
}

enum ExchangeTransitionPhase: Equatable {
    case exchangeChanged
    case loading
    case partial
    case hydrated
}

struct ExchangeTransitionState: Equatable {
    let exchange: Exchange
    let previousExchange: Exchange?
    let phase: ExchangeTransitionPhase

    var isLoading: Bool {
        phase == .exchangeChanged || phase == .loading
    }
}

struct SparklineAvailabilityState: Equatable {
    let exchange: Exchange
    let availableSymbols: Set<String>
    let placeholderSymbols: Set<String>
    let hiddenSymbols: Set<String>

    static func empty(for exchange: Exchange) -> SparklineAvailabilityState {
        SparklineAvailabilityState(
            exchange: exchange,
            availableSymbols: [],
            placeholderSymbols: [],
            hiddenSymbols: []
        )
    }
}

struct MarketScreenPresentationState: Equatable {
    let selectedExchange: Exchange
    let representativeRowsState: ExchangeRowsState<MarketRowViewState>
    let listRowsState: ExchangeRowsState<MarketRowViewState>
    let sparklineAvailabilityState: SparklineAvailabilityState
    let transitionState: ExchangeTransitionState
    let sameExchangeStaleReuse: Bool
    let crossExchangeStaleReuseAllowed: Bool

    static func initial(exchange: Exchange) -> MarketScreenPresentationState {
        MarketScreenPresentationState(
            selectedExchange: exchange,
            representativeRowsState: .empty(for: exchange),
            listRowsState: .empty(for: exchange),
            sparklineAvailabilityState: .empty(for: exchange),
            transitionState: ExchangeTransitionState(
                exchange: exchange,
                previousExchange: nil,
                phase: .hydrated
            ),
            sameExchangeStaleReuse: false,
            crossExchangeStaleReuseAllowed: false
        )
    }
}

struct KimchiScreenPresentationState: Equatable {
    let selectedExchange: Exchange
    let representativeRowsState: ExchangeRowsState<KimchiPremiumCoinViewState>
    let listRowsState: ExchangeRowsState<KimchiPremiumCoinViewState>
    let transitionState: ExchangeTransitionState
    let sameExchangeStaleReuse: Bool
    let crossExchangeStaleReuseAllowed: Bool

    static func initial(exchange: Exchange) -> KimchiScreenPresentationState {
        KimchiScreenPresentationState(
            selectedExchange: exchange,
            representativeRowsState: .empty(for: exchange),
            listRowsState: .empty(for: exchange),
            transitionState: ExchangeTransitionState(
                exchange: exchange,
                previousExchange: nil,
                phase: .hydrated
            ),
            sameExchangeStaleReuse: false,
            crossExchangeStaleReuseAllowed: false
        )
    }
}

enum MarketRowChartPresentation: Equatable {
    case none
    case placeholder
    case live
    case cached
    case staleLive
    case unavailable
}

enum MarketRowFreshnessState: Equatable {
    case pending
    case cached
    case refreshing
    case live
    case stale
    case unavailable
}

enum MarketRowGraphState: Equatable {
    case none
    case placeholder
    case cachedVisible
    case liveVisible
    case staleVisible
    case unavailable

    nonisolated var chartPresentation: MarketRowChartPresentation {
        switch self {
        case .none:
            return .none
        case .cachedVisible:
            return .cached
        case .liveVisible:
            return .live
        case .staleVisible:
            return .staleLive
        case .unavailable:
            return .unavailable
        case .placeholder:
            return .placeholder
        }
    }

    nonisolated var keepsVisibleGraph: Bool {
        switch self {
        case .cachedVisible, .liveVisible, .staleVisible:
            return true
        case .none, .placeholder, .unavailable:
            return false
        }
    }

    nonisolated var needsPlaceholderChrome: Bool {
        switch self {
        case .placeholder:
            return true
        case .none, .cachedVisible, .liveVisible, .staleVisible, .unavailable:
            return false
        }
    }
}

enum MarketSparklineRenderPolicy {
    static let minimumRenderablePointCount = 2
    static let hydratedPointCount = 4

    static func hasRenderableGraph(points: [Double], pointCount: Int) -> Bool {
        points.count >= minimumRenderablePointCount && pointCount >= minimumRenderablePointCount
    }

    static func hasHydratedGraph(points: [Double], pointCount: Int) -> Bool {
        points.count >= hydratedPointCount && pointCount >= hydratedPointCount
    }
}

enum MarketSparklineVisualState: Int, Equatable {
    case none
    case placeholder
    case cached
    case live
    case stale
    case unavailable

    init(graphState: MarketRowGraphState) {
        switch graphState {
        case .none:
            self = .none
        case .placeholder:
            self = .placeholder
        case .cachedVisible:
            self = .cached
        case .liveVisible:
            self = .live
        case .staleVisible:
            self = .stale
        case .unavailable:
            self = .unavailable
        }
    }

    var keepsVisibleGraph: Bool {
        switch self {
        case .cached, .live, .stale:
            return true
        case .none, .placeholder, .unavailable:
            return false
        }
    }
}

enum MarketListDisplayMode: String, CaseIterable, Codable {
    case chart
    case info
    case emphasis

    nonisolated var title: String {
        switch self {
        case .chart:
            return "차트형"
        case .info:
            return "정보형"
        case .emphasis:
            return "강조형"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .chart:
            return "추이 그래프를 유지하고 현재가 흐름을 함께 봅니다."
        case .info:
            return "그래프를 빼고 심볼 이미지와 텍스트 정보를 넓게 봅니다."
        case .emphasis:
            return "등락률을 더 크게 강조하고 그래프는 축약해서 봅니다."
        }
    }

    nonisolated var configuration: MarketListDisplayConfiguration {
        switch self {
        case .chart:
            return MarketListDisplayConfiguration(
                mode: self,
                title: title,
                subtitle: subtitle,
                showsSparkline: true,
                sparklineWidth: 68,
                sparklineHeight: 18,
                showsSymbolImage: true,
                emphasizesChangeRate: false,
                compactLayout: true,
                showsVolume: true,
                rowHeight: 44,
                rowVerticalPadding: 6,
                symbolColumnMinimumWidth: 94,
                symbolImageSize: 20,
                priceWidth: 80,
                changeWidth: 54,
                volumeWidth: 46
            )
        case .info:
            return MarketListDisplayConfiguration(
                mode: self,
                title: title,
                subtitle: subtitle,
                showsSparkline: false,
                sparklineWidth: 0,
                sparklineHeight: 0,
                showsSymbolImage: true,
                emphasizesChangeRate: false,
                compactLayout: true,
                showsVolume: true,
                rowHeight: 48,
                rowVerticalPadding: 7,
                symbolColumnMinimumWidth: 98,
                symbolImageSize: 24,
                priceWidth: 82,
                changeWidth: 54,
                volumeWidth: 46
            )
        case .emphasis:
            return MarketListDisplayConfiguration(
                mode: self,
                title: title,
                subtitle: subtitle,
                showsSparkline: true,
                sparklineWidth: 50,
                sparklineHeight: 16,
                showsSymbolImage: true,
                emphasizesChangeRate: true,
                compactLayout: true,
                showsVolume: false,
                rowHeight: 46,
                rowVerticalPadding: 6,
                symbolColumnMinimumWidth: 104,
                symbolImageSize: 24,
                priceWidth: 82,
                changeWidth: 70,
                volumeWidth: 0
            )
        }
    }
}

struct MarketListDisplayConfiguration: Equatable {
    let mode: MarketListDisplayMode
    let title: String
    let subtitle: String
    let showsSparkline: Bool
    let sparklineWidth: CGFloat
    let sparklineHeight: CGFloat
    let showsSymbolImage: Bool
    let emphasizesChangeRate: Bool
    let compactLayout: Bool
    let showsVolume: Bool
    let rowHeight: CGFloat
    let rowVerticalPadding: CGFloat
    let symbolColumnMinimumWidth: CGFloat
    let symbolImageSize: CGFloat
    let priceWidth: CGFloat
    let changeWidth: CGFloat
    let volumeWidth: CGFloat
}

enum MarketRowDataState: Equatable {
    case pending
    case snapshot
    case live
}

struct MarketSparklineGeometry: Equatable {
    let normalizedPoints: [CGPoint]
}

private final class MarketSparklineGeometryCache {
    nonisolated(unsafe) static let shared = MarketSparklineGeometryCache()

    private let lock = NSLock()
    private var geometries: [String: MarketSparklineGeometry] = [:]

    nonisolated func geometry(
        graphRenderIdentity: String,
        graphPathVersion: Int,
        points: [Double],
        pointCount: Int
    ) -> MarketSparklineGeometry? {
        guard MarketSparklineRenderPolicy.hasRenderableGraph(points: points, pointCount: pointCount) else {
            return nil
        }

        let cacheKey = "\(graphRenderIdentity)|\(graphPathVersion)"

        lock.lock()
        if let cached = geometries[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let geometry = Self.makeGeometry(from: points)
        guard let geometry else {
            return nil
        }

        lock.lock()
        if geometries.count > 2048 {
            geometries.removeAll(keepingCapacity: true)
        }
        geometries[cacheKey] = geometry
        lock.unlock()
        return geometry
    }

    private nonisolated static func makeGeometry(from points: [Double]) -> MarketSparklineGeometry? {
        guard points.count >= MarketSparklineRenderPolicy.minimumRenderablePointCount else {
            return nil
        }

        let minValue = points.min() ?? 0
        let maxValue = points.max() ?? 1
        let range = maxValue - minValue
        let verticalPadding: CGFloat = 0.12
        let drawableHeight = max(1 - verticalPadding * 2, 0.001)
        let normalizedPoints = points.enumerated().map { index, value -> CGPoint in
            let x = points.count == 1 ? 0 : CGFloat(index) / CGFloat(points.count - 1)
            let y: CGFloat
            if range > 0 {
                let normalizedValue = (value - minValue) / range
                y = verticalPadding + (1 - normalizedValue) * drawableHeight
            } else {
                y = 0.5
            }
            return CGPoint(x: x, y: y)
        }

        guard normalizedPoints.isEmpty == false else {
            return nil
        }

        return MarketSparklineGeometry(
            normalizedPoints: normalizedPoints
        )
    }
}

struct MarketSparklineRenderPayload: Equatable {
    let bindingKey: String
    let graphRenderIdentity: String
    let graphVisualState: MarketSparklineVisualState
    let graphPathVersion: Int
    let renderToken: String
    let renderVersion: Int
    let graphState: MarketRowGraphState
    let pointCount: Int
    let hasEnoughData: Bool
    let geometry: MarketSparklineGeometry?

    nonisolated init(
        bindingKey: String,
        graphRenderIdentity: String,
        renderToken: String,
        graphState: MarketRowGraphState,
        points: [Double],
        pointCount: Int,
        hasEnoughData: Bool,
        graphPathVersion: Int? = nil,
        renderVersion: Int? = nil
    ) {
        self.bindingKey = bindingKey
        self.graphRenderIdentity = graphRenderIdentity
        self.graphVisualState = MarketSparklineVisualState(graphState: graphState)
        self.graphPathVersion = graphPathVersion ?? Self.sparklinePathVersion(
            graphState: graphState,
            points: points,
            pointCount: pointCount
        )
        self.renderToken = renderToken
        self.renderVersion = renderVersion ?? Self.sparklineRenderVersion(
            graphVisualState: self.graphVisualState,
            graphPathVersion: self.graphPathVersion
        )
        self.graphState = graphState
        self.pointCount = pointCount
        self.hasEnoughData = hasEnoughData
        self.geometry = MarketSparklineRenderPolicy.hasRenderableGraph(points: points, pointCount: pointCount)
            ? MarketSparklineGeometryCache.shared.geometry(
                graphRenderIdentity: graphRenderIdentity,
                graphPathVersion: self.graphPathVersion,
                points: points,
                pointCount: pointCount
            )
            : nil
    }

    nonisolated var hasRenderableGraph: Bool {
        graphState.keepsVisibleGraph
            && pointCount >= MarketSparklineRenderPolicy.minimumRenderablePointCount
            && geometry != nil
    }

    private nonisolated static func sparklinePathVersion(
        graphState: MarketRowGraphState,
        points: [Double],
        pointCount: Int
    ) -> Int {
        var pointHash = pointCount
        for point in points {
            pointHash = pointHash &* 31 &+ Int((point * 100).rounded())
        }
        return graphStateOrdinal(graphState) * 1_000_000 + abs(pointHash % 1_000_000)
    }

    private nonisolated static func sparklineRenderVersion(
        graphVisualState: MarketSparklineVisualState,
        graphPathVersion: Int
    ) -> Int {
        abs((graphPathVersion &* 31) &+ graphVisualState.rawValue)
    }

    private nonisolated static func graphStateOrdinal(_ state: MarketRowGraphState) -> Int {
        switch state {
        case .none:
            return 0
        case .placeholder:
            return 1
        case .cachedVisible:
            return 2
        case .liveVisible:
            return 3
        case .staleVisible:
            return 4
        case .unavailable:
            return 5
        }
    }
}

struct MarketRowViewState: Identifiable, Equatable {
    nonisolated var id: String { "\(exchange.rawValue):\(coin.symbol)" }

    let selectedExchange: Exchange
    let exchange: Exchange
    let sourceExchange: Exchange
    let coin: CoinInfo
    let priceText: String
    let changeText: String
    let volumeText: String
    let sparkline: [Double]
    let sparklinePointCount: Int
    let sparklineTimeframe: String
    let sparklinePayload: MarketSparklineRenderPayload
    let hasEnoughSparklineData: Bool
    let chartPresentation: MarketRowChartPresentation
    let baseFreshnessState: MarketRowFreshnessState
    let graphState: MarketRowGraphState
    let isPricePlaceholder: Bool
    let isChangePlaceholder: Bool
    let isVolumePlaceholder: Bool
    let isUp: Bool
    let flash: FlashType?
    let isFavorite: Bool
    let dataState: MarketRowDataState

    nonisolated var symbol: String { coin.symbol }
    nonisolated var graphBindingKey: String { sparklinePayload.bindingKey }
    nonisolated var sparklineRenderToken: String { sparklinePayload.renderToken }
    nonisolated var displayName: String { coin.name }
    nonisolated var displayNameEn: String { coin.nameEn }
    nonisolated var imageURL: String? { coin.imageURL }
    nonisolated var hasPrice: Bool { !isPricePlaceholder }
    nonisolated var hasVolume: Bool { !isVolumePlaceholder }
    nonisolated var sparklinePoints: Int { sparklinePointCount }
    nonisolated var graphIdentity: String { "\(exchange.rawValue):\(coin.symbol):\(sparklineTimeframe)" }
    nonisolated var graphPathVersion: Int { sparklinePayload.graphPathVersion }
    nonisolated var graphRenderVersion: Int { sparklinePayload.renderVersion }
    nonisolated var isSourceExchangeMismatch: Bool { selectedExchange != sourceExchange }
    var isSparklinePlaceholder: Bool { chartPresentation == .placeholder }
    var reusesCachedSparkline: Bool { chartPresentation == .cached }

    nonisolated init(
        selectedExchange: Exchange,
        exchange: Exchange,
        sourceExchange: Exchange,
        coin: CoinInfo,
        priceText: String,
        changeText: String,
        volumeText: String,
        sparkline: [Double],
        sparklinePointCount: Int,
        sparklineTimeframe: String,
        hasEnoughSparklineData: Bool,
        chartPresentation: MarketRowChartPresentation,
        baseFreshnessState: MarketRowFreshnessState,
        graphState: MarketRowGraphState,
        isPricePlaceholder: Bool,
        isChangePlaceholder: Bool,
        isVolumePlaceholder: Bool,
        isUp: Bool,
        flash: FlashType?,
        isFavorite: Bool,
        dataState: MarketRowDataState
    ) {
        self.selectedExchange = selectedExchange
        self.exchange = exchange
        self.sourceExchange = sourceExchange
        self.coin = coin
        self.priceText = priceText
        self.changeText = changeText
        self.volumeText = volumeText
        self.sparkline = sparkline
        self.sparklinePointCount = sparklinePointCount
        self.sparklineTimeframe = sparklineTimeframe
        let bindingKey = "\(exchange.rawValue):\(coin.symbol):\(sparklineTimeframe)"
        let graphRenderIdentity = bindingKey
        let graphPathVersion = Self.sparklinePathVersion(
            points: sparkline,
            pointCount: sparklinePointCount,
            graphState: graphState
        )
        let renderVersion = Self.sparklineRenderVersion(
            graphState: graphState,
            graphPathVersion: graphPathVersion
        )
        let renderToken = Self.sparklineRenderToken(
            graphRenderIdentity: graphRenderIdentity,
            graphPathVersion: graphPathVersion,
            renderVersion: renderVersion
        )
        self.sparklinePayload = MarketSparklineRenderPayload(
            bindingKey: bindingKey,
            graphRenderIdentity: graphRenderIdentity,
            renderToken: renderToken,
            graphState: graphState,
            points: sparkline,
            pointCount: sparklinePointCount,
            hasEnoughData: hasEnoughSparklineData,
            graphPathVersion: graphPathVersion,
            renderVersion: renderVersion
        )
        self.hasEnoughSparklineData = hasEnoughSparklineData
        self.chartPresentation = chartPresentation
        self.baseFreshnessState = baseFreshnessState
        self.graphState = graphState
        self.isPricePlaceholder = isPricePlaceholder
        self.isChangePlaceholder = isChangePlaceholder
        self.isVolumePlaceholder = isVolumePlaceholder
        self.isUp = isUp
        self.flash = flash
        self.isFavorite = isFavorite
        self.dataState = dataState
    }

    func replacingSparkline(
        points: [Double],
        pointCount: Int,
        graphState: MarketRowGraphState
    ) -> MarketRowViewState {
        MarketRowViewState(
            selectedExchange: selectedExchange,
            exchange: exchange,
            sourceExchange: sourceExchange,
            coin: coin,
            priceText: priceText,
            changeText: changeText,
            volumeText: volumeText,
            sparkline: points,
            sparklinePointCount: pointCount,
            sparklineTimeframe: sparklineTimeframe,
            hasEnoughSparklineData: MarketSparklineRenderPolicy.hasHydratedGraph(points: points, pointCount: pointCount),
            chartPresentation: graphState.chartPresentation,
            baseFreshnessState: baseFreshnessState,
            graphState: graphState,
            isPricePlaceholder: isPricePlaceholder,
            isChangePlaceholder: isChangePlaceholder,
            isVolumePlaceholder: isVolumePlaceholder,
            isUp: isUp,
            flash: flash,
            isFavorite: isFavorite,
            dataState: dataState
        )
    }

    private nonisolated static func sparklineRenderToken(
        graphRenderIdentity: String,
        graphPathVersion: Int,
        renderVersion: Int
    ) -> String {
        "\(graphRenderIdentity)|\(graphPathVersion)|\(renderVersion)"
    }

    private nonisolated static func sparklinePathVersion(
        points: [Double],
        pointCount: Int,
        graphState: MarketRowGraphState
    ) -> Int {
        var pointHash = pointCount
        for point in points {
            pointHash = pointHash &* 31 &+ Int((point * 100).rounded())
        }
        return graphStateOrdinal(graphState) * 1_000_000 + abs(pointHash % 1_000_000)
    }

    private nonisolated static func sparklineRenderVersion(
        graphState: MarketRowGraphState,
        graphPathVersion: Int
    ) -> Int {
        abs((graphPathVersion &* 31) &+ MarketSparklineVisualState(graphState: graphState).rawValue)
    }

    private nonisolated static func graphStateOrdinal(_ state: MarketRowGraphState) -> Int {
        switch state {
        case .none:
            return 0
        case .placeholder:
            return 1
        case .cachedVisible:
            return 2
        case .liveVisible:
            return 3
        case .staleVisible:
            return 4
        case .unavailable:
            return 5
        }
    }
}

enum KimchiHeaderBadgeState: Equatable {
    case idle
    case syncing
    case ready
    case delayed
    case degraded
}

enum KimchiHeaderCopyState: Equatable {
    case representativeLoading
    case representativeVisible
    case progressiveHydrating
    case fullyHydrated
    case degraded
    case delayed
}

struct KimchiHeaderViewState: Equatable {
    let exchange: Exchange
    let badgeState: KimchiHeaderBadgeState
    let copyState: KimchiHeaderCopyState

    static func initial(exchange: Exchange) -> KimchiHeaderViewState {
        KimchiHeaderViewState(
            exchange: exchange,
            badgeState: .idle,
            copyState: .representativeLoading
        )
    }
}

enum KimchiPremiumCellStatus: Equatable {
    case loading
    case loaded
    case unavailable
    case stale
    case failed
}

enum KimchiPremiumCoinStatus: Equatable {
    case loading
    case loaded
    case unavailable
    case stale
    case failed

    var badgeTitle: String? {
        switch self {
        case .loading:
            return nil
        case .unavailable:
            return "데이터 없음"
        case .stale:
            return "약간 지연"
        case .failed:
            return "일부 지연"
        case .loaded:
            return "실시간"
        }
    }
}

struct KimchiPremiumExchangeCellViewState: Identifiable, Equatable {
    var id: String { exchange.rawValue }

    let selectedExchange: Exchange
    let exchange: Exchange
    let sourceExchange: Exchange
    let premiumText: String
    let domesticPriceText: String
    let referencePriceText: String
    let premiumIsPlaceholder: Bool
    let domesticPriceIsPlaceholder: Bool
    let referencePriceIsPlaceholder: Bool
    let warningMessage: String?
    let isStale: Bool
    let status: KimchiPremiumCellStatus
    let freshnessState: KimchiPremiumFreshnessState
    let freshnessReason: String?
    let updatedAt: Date?
    let updatedAgoText: String?
    let isPreviousSnapshot: Bool
    let isSourceExchangeMismatch: Bool
}

struct KimchiPremiumCoinViewState: Identifiable, Equatable {
    var id: String { symbol }

    let symbol: String
    let displayName: String
    let selectedExchange: Exchange
    let sourceExchange: Exchange?
    let referenceLabel: String
    let cells: [KimchiPremiumExchangeCellViewState]
    let status: KimchiPremiumCoinStatus
    let freshnessState: KimchiPremiumFreshnessState
    let freshnessReason: String?
    let updatedAt: Date?
    let isPreviousSnapshot: Bool
}
