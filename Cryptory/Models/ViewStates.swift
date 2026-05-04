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

    nonisolated var preservationRank: Int {
        switch self {
        case .liveVisible:
            return 5
        case .cachedVisible:
            return 4
        case .staleVisible:
            return 3
        case .placeholder:
            return 1
        case .none, .unavailable:
            return 0
        }
    }
}

struct MarketSparklineShapeQuality: Equatable {
    let pointCount: Int
    let finitePointCount: Int
    let rawRange: Double
    let relativeRange: Double
    let normalizedAmplitude: Double
    let minValue: Double
    let maxValue: Double
    let firstValue: Double
    let lastValue: Double
    let directionChangeCount: Int
    let uniqueValueBucketCount: Int
    let straightSegmentRatio: Double

    nonisolated var isFlatLookingLowInformation: Bool {
        guard finitePointCount >= MarketSparklineRenderPolicy.minimumRenderablePointCount else {
            return true
        }

        let isCoarse = pointCount <= MarketSparklineRenderPolicy.coarseUpperBoundPointCount
        let isVeryLowAmplitude = normalizedAmplitude <= 0.015 || relativeRange <= 0.0015
        let hasLittleValueInformation = uniqueValueBucketCount <= 2
        let isMostlyStraight = straightSegmentRatio >= 0.86 && directionChangeCount == 0

        return isCoarse
            && isVeryLowAmplitude
            && (hasLittleValueInformation || isMostlyStraight)
    }
}

enum MarketSparklineRenderPolicy {
    nonisolated static let minimumRenderablePointCount = 2
    nonisolated static let hydratedPointCount = 4
    nonisolated static let coarseUpperBoundPointCount = 8
    nonisolated static let promotedGraphPointCountThreshold = 24

    nonisolated static func hasRenderableGraph(points: [Double], pointCount: Int) -> Bool {
        points.count >= minimumRenderablePointCount && pointCount >= minimumRenderablePointCount
    }

    nonisolated static func hasHydratedGraph(points: [Double], pointCount: Int) -> Bool {
        points.count >= hydratedPointCount && pointCount >= hydratedPointCount
    }

    nonisolated static func sourceQualityRank(
        sourceName: String?,
        pointCount: Int,
        shapeQuality: MarketSparklineShapeQuality
    ) -> Int {
        let source = (sourceName ?? "").lowercased()
        guard source.isEmpty == false else {
            return 0
        }
        if source.contains("candle_selected_detail") || source.contains("selected_chart") {
            return 6
        }
        if source.contains("sparkline_endpoint") {
            return pointCount >= 12 ? 5 : 3
        }
        if source.contains("provider_sparkline") || source.contains("ticker_sparkline_points") {
            return pointCount >= 8 ? 4 : 3
        }
        if source.contains("flat_current") {
            return 1
        }
        if source.contains("derived_change24h")
            || source.contains("ticker_sparkline_derived")
            || source.contains("retained_store_derived") {
            return 2
        }
        if source.contains("ticker_sparkline"),
           pointCount <= 6,
           shapeQuality.directionChangeCount == 0,
           shapeQuality.straightSegmentRatio >= 0.86 {
            return 2
        }
        if source.contains("ticker_sparkline") {
            return pointCount >= 8 ? 4 : 3
        }
        return 0
    }

    nonisolated static func isPromotedPointCount(_ pointCount: Int) -> Bool {
        pointCount >= promotedGraphPointCountThreshold
    }

    nonisolated static func pointCountBucket(_ pointCount: Int) -> Int {
        switch pointCount {
        case ..<1:
            return 0
        case 1:
            return 1
        case 2:
            return 2
        case minimumRenderablePointCount...coarseUpperBoundPointCount:
            return 2
        case 9..<promotedGraphPointCountThreshold:
            return 3
        case promotedGraphPointCountThreshold..<60:
            return 4
        default:
            return 5
        }
    }

    nonisolated static func shapeQuality(points: [Double], pointCount: Int) -> MarketSparklineShapeQuality {
        let finitePoints = points.filter(\.isFinite)
        guard finitePoints.isEmpty == false else {
            return MarketSparklineShapeQuality(
                pointCount: pointCount,
                finitePointCount: 0,
                rawRange: 0,
                relativeRange: 0,
                normalizedAmplitude: 0,
                minValue: 0,
                maxValue: 0,
                firstValue: 0,
                lastValue: 0,
                directionChangeCount: 0,
                uniqueValueBucketCount: 0,
                straightSegmentRatio: 1
            )
        }

        let minValue = finitePoints.min() ?? 0
        let maxValue = finitePoints.max() ?? minValue
        let rawRange = max(maxValue - minValue, 0)
        let scale = max(abs(maxValue), abs(minValue), 1)
        let relativeRange = rawRange / scale
        let normalizedAmplitude = rawRange <= 0 ? 0 : min(relativeRange, 1)
        let bucketScale = max(scale * 0.0005, 0.000_000_1)
        let uniqueValueBucketCount = Set(finitePoints.map { Int(($0 / bucketScale).rounded()) }).count

        let deltaNoiseFloor = max(rawRange * 0.08, scale * 0.00005)
        let directionalDeltas = zip(finitePoints.dropFirst(), finitePoints)
            .map { $0 - $1 }
            .filter { abs($0) > deltaNoiseFloor }
        var directionChangeCount = 0
        if directionalDeltas.count > 1 {
            var previousSign = directionalDeltas[0].sign == .minus ? -1 : 1
            for delta in directionalDeltas.dropFirst() {
                let sign = delta.sign == .minus ? -1 : 1
                if sign != previousSign {
                    directionChangeCount += 1
                }
                previousSign = sign
            }
        }

        let straightSegmentRatio: Double
        if directionalDeltas.count < 2 || rawRange <= 0 {
            straightSegmentRatio = 1
        } else {
            let normalizedDeltas = directionalDeltas.map { $0 / rawRange }
            let matchingAdjacentPairs = zip(normalizedDeltas.dropFirst(), normalizedDeltas)
                .filter { abs($0 - $1) <= 0.12 }
                .count
            straightSegmentRatio = Double(matchingAdjacentPairs) / Double(max(normalizedDeltas.count - 1, 1))
        }

        return MarketSparklineShapeQuality(
            pointCount: pointCount,
            finitePointCount: finitePoints.count,
            rawRange: rawRange,
            relativeRange: relativeRange,
            normalizedAmplitude: normalizedAmplitude,
            minValue: minValue,
            maxValue: maxValue,
            firstValue: finitePoints.first ?? minValue,
            lastValue: finitePoints.last ?? maxValue,
            directionChangeCount: directionChangeCount,
            uniqueValueBucketCount: uniqueValueBucketCount,
            straightSegmentRatio: straightSegmentRatio
        )
    }

    nonisolated static func isFlatLookingLowInformation(points: [Double], pointCount: Int) -> Bool {
        shapeQuality(points: points, pointCount: pointCount).isFlatLookingLowInformation
    }

    nonisolated static func isLowInformationFirstPaintCandidate(points: [Double], pointCount: Int) -> Bool {
        pointCount <= 3 || isFlatLookingLowInformation(points: points, pointCount: pointCount)
    }
}

enum MarketSparklineDetailLevel: Int, Equatable {
    case none = 0
    case placeholder = 1
    case derivedPreview = 2
    case providerMini = 3
    case refinedMini = 4
    case selectedChart = 5
    case retainedCoarse = 6
    case liveCoarse = 7
    case retainedDetailed = 8
    case liveDetailed = 9

    nonisolated init(
        graphState: MarketRowGraphState,
        points: [Double],
        pointCount: Int,
        sourceVersion: Int = 0,
        sourceName: String? = nil
    ) {
        guard MarketSparklineRenderPolicy.hasRenderableGraph(points: points, pointCount: pointCount) else {
            switch graphState {
            case .none:
                self = .none
            case .placeholder, .cachedVisible, .liveVisible, .staleVisible, .unavailable:
                self = .placeholder
            }
            return
        }

        let shapeQuality = MarketSparklineRenderPolicy.shapeQuality(points: points, pointCount: pointCount)
        switch MarketSparklineRenderPolicy.sourceQualityRank(
            sourceName: sourceName,
            pointCount: pointCount,
            shapeQuality: shapeQuality
        ) {
        case 6:
            self = .selectedChart
            return
        case 5:
            self = .refinedMini
            return
        case 3...4:
            self = .providerMini
            return
        case 1...2:
            self = .derivedPreview
            return
        default:
            break
        }

        let isDetailed = MarketSparklineRenderPolicy.hasHydratedGraph(
            points: points,
            pointCount: pointCount
        )

        switch graphState {
        case .liveVisible:
            self = isDetailed ? .liveDetailed : .liveCoarse
        case .cachedVisible, .staleVisible:
            self = isDetailed ? .retainedDetailed : .retainedCoarse
        case .none:
            self = .none
        case .placeholder, .unavailable:
            self = .placeholder
        }
    }

    nonisolated var cacheComponent: String {
        switch self {
        case .none:
            return "none"
        case .placeholder:
            return "placeholder"
        case .derivedPreview:
            return "derivedPreview"
        case .providerMini:
            return "providerMini"
        case .refinedMini:
            return "refinedMini"
        case .selectedChart:
            return "selectedChart"
        case .retainedCoarse:
            return "retainedCoarse"
        case .liveCoarse:
            return "liveCoarse"
        case .retainedDetailed:
            return "retainedDetailed"
        case .liveDetailed:
            return "liveDetailed"
        }
    }

    nonisolated var pathDetailRank: Int {
        switch self {
        case .none, .placeholder:
            return 0
        case .derivedPreview:
            return 1
        case .providerMini:
            return 2
        case .refinedMini, .selectedChart:
            return 3
        case .retainedCoarse, .liveCoarse:
            return 1
        case .retainedDetailed, .liveDetailed:
            return 2
        }
    }

    nonisolated var isDetailed: Bool {
        pathDetailRank == 2
    }
}

enum MarketSparklineQualityDecision: Equatable {
    case accept(String)
    case reject(String)

    nonisolated var accepted: Bool {
        switch self {
        case .accept:
            return true
        case .reject:
            return false
        }
    }

    nonisolated var reason: String {
        switch self {
        case .accept(let reason), .reject(let reason):
            return reason
        }
    }
}

struct MarketSparklineQuality: Equatable {
    let detailLevel: MarketSparklineDetailLevel
    let graphState: MarketRowGraphState
    let pointCount: Int
    let pointBucket: Int
    let hasRenderableGraph: Bool
    let graphPathVersion: Int
    let renderVersion: Int
    let sourceVersion: Int
    let sourceName: String?
    let shapeQuality: MarketSparklineShapeQuality

    nonisolated init(
        detailLevel: MarketSparklineDetailLevel,
        graphState: MarketRowGraphState,
        pointCount: Int,
        hasRenderableGraph: Bool,
        graphPathVersion: Int,
        renderVersion: Int,
        sourceVersion: Int = 0,
        sourceName: String? = nil,
        shapeQuality: MarketSparklineShapeQuality? = nil
    ) {
        self.detailLevel = detailLevel
        self.graphState = graphState
        self.pointCount = pointCount
        self.pointBucket = MarketSparklineRenderPolicy.pointCountBucket(pointCount)
        self.hasRenderableGraph = hasRenderableGraph
        self.graphPathVersion = graphPathVersion
        self.renderVersion = renderVersion
        self.sourceVersion = sourceVersion
        self.sourceName = sourceName
        self.shapeQuality = shapeQuality ?? MarketSparklineRenderPolicy.shapeQuality(points: [], pointCount: pointCount)
    }

    nonisolated init(
        graphState: MarketRowGraphState,
        points: [Double],
        pointCount: Int,
        sourceVersion: Int = 0,
        sourceName: String? = nil
    ) {
        let shapeQuality = MarketSparklineRenderPolicy.shapeQuality(points: points, pointCount: pointCount)
        let detailLevel = MarketSparklineDetailLevel(
            graphState: graphState,
            points: points,
            pointCount: pointCount,
            sourceName: sourceName
        )
        let hasRenderableGraph = graphState.keepsVisibleGraph
            && MarketSparklineRenderPolicy.hasRenderableGraph(points: points, pointCount: pointCount)
        let graphPathVersion = Self.makeGraphPathVersion(
            graphState: graphState,
            detailLevel: detailLevel,
            points: points,
            pointCount: pointCount
        )
        self.init(
            detailLevel: detailLevel,
            graphState: graphState,
            pointCount: pointCount,
            hasRenderableGraph: hasRenderableGraph,
            graphPathVersion: graphPathVersion,
            renderVersion: Self.makeRenderVersion(
                graphState: graphState,
                detailLevel: detailLevel,
                graphPathVersion: graphPathVersion
            ),
            sourceVersion: sourceVersion,
            sourceName: sourceName,
            shapeQuality: shapeQuality
        )
    }

    nonisolated var isUsableGraph: Bool {
        hasRenderableGraph && graphState.keepsVisibleGraph
    }

    nonisolated var isVeryLowCoarse: Bool {
        isUsableGraph
            && qualityRank <= 2
            && pointCount <= 3
    }

    nonisolated var qualityRank: Int {
        guard isUsableGraph else {
            return detailLevel == .placeholder ? 0 : 0
        }
        let rank = MarketSparklineRenderPolicy.sourceQualityRank(
            sourceName: sourceName,
            pointCount: pointCount,
            shapeQuality: shapeQuality
        )
        return max(rank, detailLevel.pathDetailRank)
    }

    private nonisolated var normalizedSourceName: String {
        (sourceName ?? "").lowercased()
    }

    private nonisolated var isDerivedPreviewSource: Bool {
        let source = normalizedSourceName
        return qualityRank <= 2
            || source.contains("derived_change24h")
            || source.contains("ticker_sparkline_derived")
            || source.contains("retained_store_derived")
            || source.contains("flat_current")
    }

    private nonisolated var isRefinedMiniSource: Bool {
        let source = normalizedSourceName
        return source.contains("sparkline_endpoint")
            || source.contains("provider_sparkline")
    }

    nonisolated var isFlatLookingLowInformation: Bool {
        isUsableGraph && shapeQuality.isFlatLookingLowInformation
    }

    nonisolated var isLowInformationFirstPaintCandidate: Bool {
        isVeryLowCoarse || isFlatLookingLowInformation
    }

    nonisolated var isMinimumVisualQualityForFirstPaint: Bool {
        isUsableGraph
            && isLowInformationFirstPaintCandidate == false
            && (detailLevel.isDetailed || pointCount > 3)
    }

    nonisolated var visibleFirstPaintPriority: Int {
        let detailPriority: Int
        switch detailLevel {
        case .selectedChart:
            detailPriority = 600
        case .refinedMini:
            detailPriority = 500
        case .liveDetailed:
            detailPriority = 500
        case .providerMini:
            detailPriority = 350
        case .retainedDetailed:
            detailPriority = 400
        case .derivedPreview:
            detailPriority = 150
        case .liveCoarse:
            detailPriority = 300
        case .retainedCoarse:
            detailPriority = 200
        case .placeholder:
            detailPriority = 50
        case .none:
            detailPriority = 0
        }

        return detailPriority
            + graphState.preservationRank * 10
            + pointBucket
    }

    nonisolated func visibleBindableChangeReason(
        over existing: MarketSparklineQuality?
    ) -> String? {
        guard let existing else {
            return isUsableGraph ? "usable_graph_arrived" : nil
        }

        if existing.isUsableGraph == false, isUsableGraph {
            return "usable_graph_arrived"
        }
        if existing.detailLevel == .retainedDetailed,
           detailLevel == .liveDetailed {
            return "retained_to_live"
        }
        if graphState == .liveVisible,
           existing.graphState != .liveVisible,
           detailLevel.pathDetailRank >= existing.detailLevel.pathDetailRank {
            return "live_path_arrived"
        }
        if detailLevel.pathDetailRank > existing.detailLevel.pathDetailRank {
            return "detail_upgrade"
        }
        if qualityRank > existing.qualityRank {
            return "source_quality_upgrade"
        }
        if pointCount > existing.pointCount,
           detailLevel.pathDetailRank >= existing.detailLevel.pathDetailRank {
            return "point_count_upgrade"
        }
        if sourceVersion > existing.sourceVersion,
           detailLevel.pathDetailRank >= existing.detailLevel.pathDetailRank {
            return "newer_source_version"
        }
        if detailLevel == existing.detailLevel,
           pointCount == existing.pointCount,
           graphPathVersion != existing.graphPathVersion {
            return "same_count_new_points"
        }
        if detailLevel == existing.detailLevel,
           renderVersion != existing.renderVersion {
            return "newer_render_signature"
        }
        if isUsableGraph,
           detailLevel.pathDetailRank >= existing.detailLevel.pathDetailRank,
           (graphPathVersion != existing.graphPathVersion
            || renderVersion != existing.renderVersion) {
            return "newer_bindable_identity"
        }
        return nil
    }

    nonisolated func promotionDecision(
        over existing: MarketSparklineQuality?
    ) -> MarketSparklineQualityDecision {
        guard let existing else {
            return .accept("quality_upgrade")
        }

        if existing.detailLevel == detailLevel,
           existing.graphState == graphState,
           existing.pointCount == pointCount,
           existing.graphPathVersion == graphPathVersion,
           existing.renderVersion == renderVersion,
           existing.hasRenderableGraph == hasRenderableGraph,
           existing.qualityRank == qualityRank {
            return .reject("same_quality_skip")
        }

        if existing.isUsableGraph && isUsableGraph == false {
            return .reject("quality_downgrade_blocked")
        }

        if existing.detailLevel == .liveDetailed,
           detailLevel == .retainedDetailed {
            return .reject("quality_downgrade_blocked")
        }

        if existing.isDerivedPreviewSource,
           isRefinedMiniSource,
           isUsableGraph {
            return .accept("upgrade_derived_to_refined")
        }

        if existing.pointCount == 6,
           pointCount >= 12,
           isUsableGraph,
           qualityRank >= existing.qualityRank {
            return .accept("upgrade_point_count")
        }

        if qualityRank > existing.qualityRank {
            return .accept("upgrade_source_quality")
        }

        if existing.qualityRank >= 5,
           qualityRank < existing.qualityRank {
            return .reject("quality_downgrade_blocked")
        }

        if existing.qualityRank > qualityRank,
           existing.isUsableGraph {
            return .reject("quality_downgrade_blocked")
        }

        if existing.pointCount > pointCount,
           existing.qualityRank >= qualityRank,
           existing.isUsableGraph {
            return .reject("quality_downgrade_blocked")
        }

        if existing.detailLevel == detailLevel,
           existing.graphState.preservationRank > graphState.preservationRank,
           existing.pointCount >= pointCount,
           existing.qualityRank >= qualityRank {
            return .reject("quality_downgrade_blocked")
        }

        if detailLevel.pathDetailRank > existing.detailLevel.pathDetailRank
            || pointBucket > existing.pointBucket
            || pointCount > existing.pointCount
            || graphState.preservationRank > existing.graphState.preservationRank
            || (graphPathVersion != existing.graphPathVersion && pointCount >= existing.pointCount)
            || renderVersion != existing.renderVersion {
            return .accept("quality_upgrade")
        }

        return .reject("same_quality_skip")
    }

    private nonisolated static func makeGraphPathVersion(
        graphState: MarketRowGraphState,
        detailLevel: MarketSparklineDetailLevel,
        points: [Double],
        pointCount: Int
    ) -> Int {
        var pointHash = pointCount
        for point in points {
            let component = point.isFinite ? Int(truncatingIfNeeded: point.bitPattern) : 0
            pointHash = pointHash &* 31 &+ component
        }
        return detailLevel.rawValue * 100_000_000
            + graphStateOrdinal(graphState) * 10_000_000
            + abs(pointHash % 10_000_000)
    }

    private nonisolated static func makeRenderVersion(
        graphState: MarketRowGraphState,
        detailLevel: MarketSparklineDetailLevel,
        graphPathVersion: Int
    ) -> Int {
        let visualState = MarketSparklineVisualState(graphState: graphState)
        return abs((graphPathVersion &* 31) &+ visualState.rawValue &+ detailLevel.rawValue &* 101)
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

enum MarketSparklineVisualState: Int, Equatable {
    case none
    case placeholder
    case cached
    case live
    case stale
    case unavailable

    nonisolated init(graphState: MarketRowGraphState) {
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

    nonisolated var keepsVisibleGraph: Bool {
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
                volumeWidth: 46,
                changeColumnLeadingPadding: 8,
                sparklineColumnLeadingPadding: 10,
                changeBadgeMinWidth: 0,
                changeBadgeHeight: 0,
                sparklineMinimumWidth: 64
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
                volumeWidth: 46,
                changeColumnLeadingPadding: 8,
                sparklineColumnLeadingPadding: 0,
                changeBadgeMinWidth: 0,
                changeBadgeHeight: 0,
                sparklineMinimumWidth: 0
            )
        case .emphasis:
            return MarketListDisplayConfiguration(
                mode: self,
                title: title,
                subtitle: subtitle,
                showsSparkline: true,
                sparklineWidth: 58,
                sparklineHeight: 18,
                showsSymbolImage: true,
                emphasizesChangeRate: true,
                compactLayout: true,
                showsVolume: false,
                rowHeight: 50,
                rowVerticalPadding: 6,
                symbolColumnMinimumWidth: 108,
                symbolImageSize: 24,
                priceWidth: 86,
                changeWidth: 94,
                volumeWidth: 0,
                changeColumnLeadingPadding: 10,
                sparklineColumnLeadingPadding: 10,
                changeBadgeMinWidth: 74,
                changeBadgeHeight: 30,
                sparklineMinimumWidth: 58
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
    let changeColumnLeadingPadding: CGFloat
    let sparklineColumnLeadingPadding: CGFloat
    let changeBadgeMinWidth: CGFloat
    let changeBadgeHeight: CGFloat
    let sparklineMinimumWidth: CGFloat
}

enum MarketRowDataState: Equatable {
    case pending
    case snapshot
    case live
}

enum MarketRowSymbolImageState: String, Equatable {
    case missing
    case placeholder
    case cached
    case live

    nonisolated var renderRank: Int {
        switch self {
        case .missing:
            return 0
        case .placeholder:
            return 1
        case .cached:
            return 2
        case .live:
            return 3
        }
    }

    nonisolated var showsRenderedImage: Bool {
        switch self {
        case .cached, .live:
            return true
        case .missing, .placeholder:
            return false
        }
    }
}

struct AssetImageRequestDescriptor: Hashable, Equatable {
    let marketIdentity: MarketIdentity
    let symbol: String
    let canonicalSymbol: String
    let imageURL: String?
    let hasImage: Bool?
    let localAssetName: String?

    nonisolated var normalizedImageURL: URL? {
        guard let rawValue = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false else {
            return nil
        }

        if rawValue.hasPrefix("/") {
            return URL(fileURLWithPath: rawValue)
        }

        var candidates = [rawValue]
        if rawValue.hasPrefix("//") {
            candidates.append("https:\(rawValue)")
        } else if rawValue.contains("://") == false, rawValue.contains(".") {
            candidates.append("https://\(rawValue)")
        }

        for candidate in candidates {
            if let url = Self.normalizedURL(candidate), url.scheme?.isEmpty == false {
                return url
            }
        }

        return nil
    }

    nonisolated var hasResolvableImageURL: Bool {
        normalizedImageURL != nil
    }

    nonisolated var isExplicitlyUnsupportedAsset: Bool {
        hasImage == false && hasResolvableImageURL == false
    }

    private nonisolated static func normalizedURL(_ rawValue: String) -> URL? {
        if let url = URL(string: rawValue) {
            return url
        }

        guard let encodedValue = rawValue.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) else {
            return nil
        }
        return URL(string: encodedValue)
    }

    nonisolated var placeholderText: String {
        let normalizedSymbol = canonicalSymbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard normalizedSymbol.isEmpty == false else {
            return "?"
        }
        return String(normalizedSymbol.prefix(min(max(normalizedSymbol.count, 1), 2)))
    }
}

struct MarketSparklineGeometry: Equatable {
    let normalizedPoints: [CGPoint]
    let rawRange: Double
    let relativeRange: Double
    let hasTinyRangeVisualBoost: Bool
}

private final class MarketSparklineGeometryCache {
    nonisolated(unsafe) static let shared = MarketSparklineGeometryCache()

    private let lock = NSLock()
    private var geometries: [String: MarketSparklineGeometry] = [:]

    nonisolated func geometry(
        graphRenderIdentity: String,
        graphDetailLevel: MarketSparklineDetailLevel,
        graphPathVersion: Int,
        points: [Double],
        pointCount: Int
    ) -> MarketSparklineGeometry? {
        guard MarketSparklineRenderPolicy.hasRenderableGraph(points: points, pointCount: pointCount) else {
            return nil
        }

        let cacheKey = "\(graphRenderIdentity)|detail=\(graphDetailLevel.cacheComponent)|\(graphPathVersion)"

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
        let finitePoints = points.filter(\.isFinite)
        guard finitePoints.count >= MarketSparklineRenderPolicy.minimumRenderablePointCount else {
            return nil
        }

        let minValue = finitePoints.min() ?? 0
        let maxValue = finitePoints.max() ?? 1
        let range = maxValue - minValue
        let scale = max(abs(maxValue), abs(minValue), 1)
        let relativeRange = range / scale
        let verticalPadding: CGFloat = 0.12
        let drawableHeight = max(1 - verticalPadding * 2, 0.001)
        let tinyRangeNeedsVisualBoost = range > 0 && relativeRange < 0.002
        let normalizedPoints = finitePoints.enumerated().map { index, value -> CGPoint in
            let x = finitePoints.count == 1 ? 0 : CGFloat(index) / CGFloat(finitePoints.count - 1)
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
            normalizedPoints: normalizedPoints,
            rawRange: range,
            relativeRange: relativeRange,
            hasTinyRangeVisualBoost: tinyRangeNeedsVisualBoost
        )
    }
}

struct MarketSparklineRenderPayload: Equatable {
    let bindingKey: String
    let graphRenderIdentity: String
    let detailLevel: MarketSparklineDetailLevel
    let graphVisualState: MarketSparklineVisualState
    let graphPathVersion: Int
    let renderToken: String
    let renderVersion: Int
    let sourceVersion: Int
    let sourceName: String?
    let graphState: MarketRowGraphState
    let pointCount: Int
    let shapeQuality: MarketSparklineShapeQuality
    let hasEnoughData: Bool
    let suppressesCoarseRetainedReuse: Bool
    let geometry: MarketSparklineGeometry?

    nonisolated init(
        bindingKey: String,
        graphRenderIdentity: String,
        renderToken: String,
        graphState: MarketRowGraphState,
        points: [Double],
        pointCount: Int,
        hasEnoughData: Bool,
        suppressesCoarseRetainedReuse: Bool = false,
        graphPathVersion: Int? = nil,
        renderVersion: Int? = nil,
        sourceVersion: Int = 0,
        sourceName: String? = nil
    ) {
        let resolvedDetailLevel = MarketSparklineDetailLevel(
            graphState: graphState,
            points: points,
            pointCount: pointCount,
            sourceName: sourceName
        )
        let resolvedGraphRenderIdentity = graphRenderIdentity.contains(":detail=")
            ? graphRenderIdentity
            : "\(graphRenderIdentity):detail=\(resolvedDetailLevel.cacheComponent)"
        self.bindingKey = bindingKey
        self.graphRenderIdentity = resolvedGraphRenderIdentity
        self.detailLevel = resolvedDetailLevel
        self.graphVisualState = MarketSparklineVisualState(graphState: graphState)
        self.graphPathVersion = graphPathVersion ?? Self.sparklinePathVersion(
            graphState: graphState,
            detailLevel: resolvedDetailLevel,
            points: points,
            pointCount: pointCount
        )
        self.renderToken = renderToken
        self.renderVersion = renderVersion ?? Self.sparklineRenderVersion(
            graphVisualState: self.graphVisualState,
            detailLevel: resolvedDetailLevel,
            graphPathVersion: self.graphPathVersion
        )
        self.sourceVersion = sourceVersion
        self.sourceName = sourceName
        self.graphState = graphState
        self.pointCount = pointCount
        self.shapeQuality = MarketSparklineRenderPolicy.shapeQuality(
            points: points,
            pointCount: pointCount
        )
        self.hasEnoughData = hasEnoughData
        self.suppressesCoarseRetainedReuse = suppressesCoarseRetainedReuse
        self.geometry = MarketSparklineRenderPolicy.hasRenderableGraph(points: points, pointCount: pointCount)
            ? MarketSparklineGeometryCache.shared.geometry(
                graphRenderIdentity: resolvedGraphRenderIdentity,
                graphDetailLevel: resolvedDetailLevel,
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

    nonisolated var isLowInformationFirstPaintCandidate: Bool {
        hasRenderableGraph
            && (pointCount <= 3 || shapeQuality.isFlatLookingLowInformation)
    }

    private nonisolated static func sparklinePathVersion(
        graphState: MarketRowGraphState,
        detailLevel: MarketSparklineDetailLevel,
        points: [Double],
        pointCount: Int
    ) -> Int {
        var pointHash = pointCount
        for point in points {
            let component = point.isFinite ? Int(truncatingIfNeeded: point.bitPattern) : 0
            pointHash = pointHash &* 31 &+ component
        }
        return detailLevel.rawValue * 100_000_000
            + graphStateOrdinal(graphState) * 10_000_000
            + abs(pointHash % 10_000_000)
    }

    private nonisolated static func sparklineRenderVersion(
        graphVisualState: MarketSparklineVisualState,
        detailLevel: MarketSparklineDetailLevel,
        graphPathVersion: Int
    ) -> Int {
        abs((graphPathVersion &* 31) &+ graphVisualState.rawValue &+ detailLevel.rawValue &* 101)
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
    nonisolated var id: String { marketIdentity.cacheKey }

    let selectedExchange: Exchange
    let exchange: Exchange
    let sourceExchange: Exchange
    let marketIdentity: MarketIdentity
    let coin: CoinInfo
    let priceText: String
    let changeText: String
    let volumeText: String
    let sparkline: [Double]
    let sparklinePointCount: Int
    let sparklineSource: String?
    let sparklineTimeframe: String
    let sparklinePayload: MarketSparklineRenderPayload
    let hasEnoughSparklineData: Bool
    let chartPresentation: MarketRowChartPresentation
    let baseFreshnessState: MarketRowFreshnessState
    let graphState: MarketRowGraphState
    let symbolImageState: MarketRowSymbolImageState
    let isPricePlaceholder: Bool
    let isChangePlaceholder: Bool
    let isVolumePlaceholder: Bool
    let isUp: Bool
    let flash: FlashType?
    let isFavorite: Bool
    let dataState: MarketRowDataState

    nonisolated var symbol: String { coin.symbol }
    nonisolated var marketId: String? { marketIdentity.marketId }
    nonisolated var canonicalSymbol: String { coin.canonicalSymbol }
    nonisolated var displaySymbol: String { coin.displaySymbol }
    nonisolated var graphBindingKey: String { sparklinePayload.bindingKey }
    nonisolated var sparklineRenderToken: String { sparklinePayload.renderToken }
    nonisolated var displayName: String { coin.name }
    nonisolated var displayNameEn: String { coin.nameEn }
    nonisolated var imageURL: String? { coin.iconURL }
    nonisolated var hasImage: Bool? { coin.resolvedHasImage }
    nonisolated var localAssetName: String { coin.localAssetName }
    nonisolated var symbolImageDescriptor: AssetImageRequestDescriptor {
        AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: symbol,
            canonicalSymbol: canonicalSymbol,
            imageURL: imageURL,
            hasImage: hasImage,
            localAssetName: localAssetName
        )
    }
    nonisolated var hasPrice: Bool { !isPricePlaceholder }
    nonisolated var hasVolume: Bool { !isVolumePlaceholder }
    nonisolated var sparklineValues: [Double] { sparkline }
    nonisolated var sparklinePointItems: [SparklinePoint] {
        sparkline.map { SparklinePoint(price: $0, timestamp: nil) }
    }
    nonisolated var sparklinePoints: Int { sparklinePointCount }
    nonisolated var graphPointCount: Int { sparklinePointCount }
    nonisolated var graphIdentity: String { sparklinePayload.graphRenderIdentity }
    nonisolated var graphPathVersion: Int { sparklinePayload.graphPathVersion }
    nonisolated var graphRenderVersion: Int { sparklinePayload.renderVersion }
    nonisolated var marketLogFields: String { marketIdentity.logFields }
    nonisolated var isSourceExchangeMismatch: Bool { selectedExchange != sourceExchange }
    var isSparklinePlaceholder: Bool { chartPresentation == .placeholder }
    var reusesCachedSparkline: Bool { chartPresentation == .cached }

    nonisolated init(
        selectedExchange: Exchange,
        exchange: Exchange,
        sourceExchange: Exchange,
        quoteCurrency: MarketQuoteCurrency = .krw,
        coin: CoinInfo,
        priceText: String,
        changeText: String,
        volumeText: String,
        sparkline: [Double],
        sparklinePointCount: Int,
        sparklineSource: String? = nil,
        sparklineTimeframe: String,
        hasEnoughSparklineData: Bool,
        chartPresentation: MarketRowChartPresentation,
        baseFreshnessState: MarketRowFreshnessState,
        graphState: MarketRowGraphState,
        symbolImageState: MarketRowSymbolImageState,
        isPricePlaceholder: Bool,
        isChangePlaceholder: Bool,
        isVolumePlaceholder: Bool,
        isUp: Bool,
        flash: FlashType?,
        isFavorite: Bool,
        dataState: MarketRowDataState,
        suppressesCoarseRetainedReuse: Bool = false,
        sparklineSourceVersion: Int = 0
    ) {
        let resolvedMarketIdentity = coin.marketIdentity(exchange: exchange, quoteCurrency: quoteCurrency)
        self.selectedExchange = selectedExchange
        self.exchange = exchange
        self.sourceExchange = sourceExchange
        self.marketIdentity = resolvedMarketIdentity
        self.coin = coin
        self.priceText = priceText
        self.changeText = changeText
        self.volumeText = volumeText
        self.sparkline = sparkline
        self.sparklinePointCount = sparklinePointCount
        self.sparklineSource = sparklineSource
        self.sparklineTimeframe = sparklineTimeframe
        let bindingKey = "\(resolvedMarketIdentity.cacheKey):\(sparklineTimeframe)"
        let detailLevel = MarketSparklineDetailLevel(
            graphState: graphState,
            points: sparkline,
            pointCount: sparklinePointCount,
            sourceName: sparklineSource
        )
        let graphRenderIdentity = "\(bindingKey):detail=\(detailLevel.cacheComponent)"
        let graphPathVersion = Self.sparklinePathVersion(
            points: sparkline,
            pointCount: sparklinePointCount,
            graphState: graphState,
            detailLevel: detailLevel
        )
        let renderVersion = Self.sparklineRenderVersion(
            graphState: graphState,
            detailLevel: detailLevel,
            graphPathVersion: graphPathVersion
        )
        let renderToken = Self.sparklineRenderToken(
            graphRenderIdentity: graphRenderIdentity,
            graphPathVersion: graphPathVersion,
            renderVersion: renderVersion,
            sourceVersion: sparklineSourceVersion
        )
        self.sparklinePayload = MarketSparklineRenderPayload(
            bindingKey: bindingKey,
            graphRenderIdentity: graphRenderIdentity,
            renderToken: renderToken,
            graphState: graphState,
            points: sparkline,
            pointCount: sparklinePointCount,
            hasEnoughData: hasEnoughSparklineData,
            suppressesCoarseRetainedReuse: suppressesCoarseRetainedReuse,
            graphPathVersion: graphPathVersion,
            renderVersion: renderVersion,
            sourceVersion: sparklineSourceVersion,
            sourceName: sparklineSource
        )
        self.hasEnoughSparklineData = hasEnoughSparklineData
        self.chartPresentation = chartPresentation
        self.baseFreshnessState = baseFreshnessState
        self.graphState = graphState
        self.symbolImageState = symbolImageState
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
        graphState: MarketRowGraphState,
        sparklineSource: String? = nil,
        sourceVersion: Int? = nil
    ) -> MarketRowViewState {
        MarketRowViewState(
            selectedExchange: selectedExchange,
            exchange: exchange,
            sourceExchange: sourceExchange,
            quoteCurrency: marketIdentity.quoteCurrency,
            coin: coin,
            priceText: priceText,
            changeText: changeText,
            volumeText: volumeText,
            sparkline: points,
            sparklinePointCount: pointCount,
            sparklineSource: graphState.keepsVisibleGraph ? (sparklineSource ?? "sparkline_patch") : sparklineSource,
            sparklineTimeframe: sparklineTimeframe,
            hasEnoughSparklineData: MarketSparklineRenderPolicy.hasHydratedGraph(points: points, pointCount: pointCount),
            chartPresentation: graphState.chartPresentation,
            baseFreshnessState: baseFreshnessState,
            graphState: graphState,
            symbolImageState: symbolImageState,
            isPricePlaceholder: isPricePlaceholder,
            isChangePlaceholder: isChangePlaceholder,
            isVolumePlaceholder: isVolumePlaceholder,
            isUp: isUp,
            flash: flash,
            isFavorite: isFavorite,
            dataState: dataState,
            suppressesCoarseRetainedReuse: sparklinePayload.suppressesCoarseRetainedReuse,
            sparklineSourceVersion: sourceVersion ?? sparklinePayload.sourceVersion
        )
    }

    func replacingSymbolImage(
        state: MarketRowSymbolImageState
    ) -> MarketRowViewState {
        MarketRowViewState(
            selectedExchange: selectedExchange,
            exchange: exchange,
            sourceExchange: sourceExchange,
            quoteCurrency: marketIdentity.quoteCurrency,
            coin: coin,
            priceText: priceText,
            changeText: changeText,
            volumeText: volumeText,
            sparkline: sparkline,
            sparklinePointCount: sparklinePointCount,
            sparklineSource: sparklineSource,
            sparklineTimeframe: sparklineTimeframe,
            hasEnoughSparklineData: hasEnoughSparklineData,
            chartPresentation: chartPresentation,
            baseFreshnessState: baseFreshnessState,
            graphState: graphState,
            symbolImageState: state,
            isPricePlaceholder: isPricePlaceholder,
            isChangePlaceholder: isChangePlaceholder,
            isVolumePlaceholder: isVolumePlaceholder,
            isUp: isUp,
            flash: flash,
            isFavorite: isFavorite,
            dataState: dataState,
            suppressesCoarseRetainedReuse: sparklinePayload.suppressesCoarseRetainedReuse,
            sparklineSourceVersion: sparklinePayload.sourceVersion
        )
    }

    func replacingTickerDisplay(
        sourceExchange: Exchange,
        priceText: String,
        changeText: String,
        volumeText: String,
        isPricePlaceholder: Bool,
        isChangePlaceholder: Bool,
        isVolumePlaceholder: Bool,
        isUp: Bool,
        flash: FlashType?,
        dataState: MarketRowDataState,
        baseFreshnessState: MarketRowFreshnessState
    ) -> MarketRowViewState {
        MarketRowViewState(
            selectedExchange: selectedExchange,
            exchange: exchange,
            sourceExchange: sourceExchange,
            quoteCurrency: marketIdentity.quoteCurrency,
            coin: coin,
            priceText: priceText,
            changeText: changeText,
            volumeText: volumeText,
            sparkline: sparkline,
            sparklinePointCount: sparklinePointCount,
            sparklineSource: sparklineSource,
            sparklineTimeframe: sparklineTimeframe,
            hasEnoughSparklineData: hasEnoughSparklineData,
            chartPresentation: graphState.chartPresentation,
            baseFreshnessState: baseFreshnessState,
            graphState: graphState,
            symbolImageState: symbolImageState,
            isPricePlaceholder: isPricePlaceholder,
            isChangePlaceholder: isChangePlaceholder,
            isVolumePlaceholder: isVolumePlaceholder,
            isUp: isUp,
            flash: flash,
            isFavorite: isFavorite,
            dataState: dataState,
            suppressesCoarseRetainedReuse: sparklinePayload.suppressesCoarseRetainedReuse,
            sparklineSourceVersion: sparklinePayload.sourceVersion
        )
    }

    private nonisolated static func sparklineRenderToken(
        graphRenderIdentity: String,
        graphPathVersion: Int,
        renderVersion: Int,
        sourceVersion: Int
    ) -> String {
        "\(graphRenderIdentity)|\(graphPathVersion)|\(renderVersion)|\(sourceVersion)"
    }

    private nonisolated static func sparklinePathVersion(
        points: [Double],
        pointCount: Int,
        graphState: MarketRowGraphState,
        detailLevel: MarketSparklineDetailLevel
    ) -> Int {
        var pointHash = pointCount
        for point in points {
            let component = point.isFinite ? Int(truncatingIfNeeded: point.bitPattern) : 0
            pointHash = pointHash &* 31 &+ component
        }
        return detailLevel.rawValue * 100_000_000
            + graphStateOrdinal(graphState) * 10_000_000
            + abs(pointHash % 10_000_000)
    }

    private nonisolated static func sparklineRenderVersion(
        graphState: MarketRowGraphState,
        detailLevel: MarketSparklineDetailLevel,
        graphPathVersion: Int
    ) -> Int {
        abs((graphPathVersion &* 31)
            &+ MarketSparklineVisualState(graphState: graphState).rawValue
            &+ detailLevel.rawValue &* 101)
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
    var id: String { "\(selectedExchange.rawValue)|\(symbol)" }

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
