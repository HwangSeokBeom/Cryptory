import SwiftUI
import UIKit

private struct RetainedSparklineResolution {
    let payload: MarketSparklineRenderPayload
    let visualState: MarketSparklineVisualState
    let firstPaintSource: String
}

private func sparklineQuality(
    for payload: MarketSparklineRenderPayload
) -> MarketSparklineQuality {
    MarketSparklineQuality(
        detailLevel: payload.detailLevel,
        graphState: payload.graphState,
        pointCount: payload.pointCount,
        hasRenderableGraph: payload.hasRenderableGraph,
        graphPathVersion: payload.graphPathVersion,
        renderVersion: payload.renderVersion,
        sourceVersion: payload.sourceVersion,
        pointsHash: payload.pointsHash,
        sourceName: payload.sourceName,
        shapeQuality: payload.shapeQuality
    )
}

private func logGraphQualityDecision(
    marketIdentity: MarketIdentity,
    existing: MarketSparklineQuality?,
    incoming: MarketSparklineQuality,
    decision: MarketSparklineQualityDecision
) {
    AppLogger.debug(
        .lifecycle,
            "[GraphSignatureDebug] exchange=\(marketIdentity.exchange.rawValue) quoteCurrency=\(marketIdentity.quoteCurrency.rawValue) canonicalMarketId=\(marketIdentity.marketId ?? marketIdentity.symbol) oldQuality=\(existing?.sourceName ?? existing?.detailLevel.cacheComponent ?? "none") newQuality=\(incoming.sourceName ?? incoming.detailLevel.cacheComponent) oldPointCount=\(existing?.pointCount ?? 0) newPointCount=\(incoming.pointCount) oldPointsHash=\(existing?.pointsHash ?? 0) newPointsHash=\(incoming.pointsHash) oldUpdatedAt=\(existing?.sourceVersion ?? 0) newUpdatedAt=\(incoming.sourceVersion) decision=\(decision.accepted ? "accept" : "reject") reason=\(decision.reason) pointsHashEqual=\((existing?.pointsHash).map { $0 == incoming.pointsHash } ?? false)"
    )
}

private final class RetainedSparklineStore {
    static let shared = RetainedSparklineStore()

    private let firstPaintHoldInterval: TimeInterval = 0.14
    private let lock = NSLock()
    private var payloadsByBindingKey: [String: MarketSparklineRenderPayload] = [:]
    private var heldFirstPaintsByBindingKey: [String: Date] = [:]

    func resolve(
        incoming: MarketSparklineRenderPayload,
        marketIdentity: MarketIdentity
    ) -> RetainedSparklineResolution {
        lock.lock()
        defer { lock.unlock() }

        if incoming.hasRenderableGraph {
            let retainedPayload = payloadsByBindingKey[incoming.bindingKey]
            let retainedQuality = retainedPayload.map(sparklineQuality(for:))
            let incomingQuality = sparklineQuality(for: incoming)
            let visibleBindReason = incomingQuality.visibleBindableChangeReason(over: retainedQuality)
            if let heldStartedAt = heldFirstPaintsByBindingKey[incoming.bindingKey],
               incomingQuality.isMinimumVisualQualityForFirstPaint {
                heldFirstPaintsByBindingKey.removeValue(forKey: incoming.bindingKey)
                AppLogger.debug(
                    .lifecycle,
                    "[GraphHoldDebug] \(marketIdentity.logFields) action=held_paint_promoted_to_live detailLevel=\(incoming.detailLevel.cacheComponent) pointCount=\(incoming.pointCount)"
                )
                _ = heldStartedAt
            }
            if retainedPayload?.hasRenderableGraph != true,
               incoming.suppressesCoarseRetainedReuse,
               incomingQuality.isLowInformationFirstPaintCandidate,
               incomingQuality.isMinimumVisualQualityForFirstPaint == false {
                heldFirstPaintsByBindingKey.removeValue(forKey: incoming.bindingKey)
                AppLogger.debug(
                    .lifecycle,
                    "[GraphHoldDebug] \(marketIdentity.logFields) action=first_paint_low_information_allowed detailLevel=\(incoming.detailLevel.cacheComponent) pointCount=\(incoming.pointCount)"
                )
            }
            let decision = MarketSparklineQuality.graphQualityDecision(
                current: retainedQuality,
                incoming: incomingQuality
            )
            let displayPayload: MarketSparklineRenderPayload
            if let retainedPayload,
               retainedPayload.hasRenderableGraph,
               decision.accepted == false,
               visibleBindReason == nil {
                displayPayload = retainedPayload
                logGraphQualityDecision(
                    marketIdentity: marketIdentity,
                    existing: retainedQuality,
                    incoming: incomingQuality,
                    decision: decision
                )
                AppLogger.debug(
                    .lifecycle,
                    "[GraphFirstPaintDebug] \(marketIdentity.logFields) action=skip reason=existing_better_graph_retained"
                )
                AppLogger.debug(
                    .lifecycle,
                    "[GraphDetailDebug] \(marketIdentity.logFields) action=redraw_skipped reason=retained_refined_prevents_coarse_reverse oldDetail=\(retainedPayload.detailLevel.cacheComponent) newDetail=\(incoming.detailLevel.cacheComponent)"
                )
            } else {
                displayPayload = incoming
                if retainedQuality != nil {
                    logGraphQualityDecision(
                        marketIdentity: marketIdentity,
                        existing: retainedQuality,
                        incoming: incomingQuality,
                        decision: decision
                    )
                    if decision.accepted == false,
                       let visibleBindReason {
                        AppLogger.debug(
                            .lifecycle,
                            "[GraphVisibleDebug] \(marketIdentity.logFields) action=visible_fast_lane_applied source=incoming reason=\(visibleBindReason)"
                        )
                    }
                }
            }
            if shouldReplaceRetainedPayload(existing: retainedPayload, incoming: incoming) {
                payloadsByBindingKey[incoming.bindingKey] = incoming
                heldFirstPaintsByBindingKey.removeValue(forKey: incoming.bindingKey)
            }
            let source = displayPayload.graphState == .liveVisible ? "live" : "retained"
            return RetainedSparklineResolution(
                payload: displayPayload,
                visualState: displayPayload.graphVisualState,
                firstPaintSource: source
            )
        }

        guard let retainedPayload = payloadsByBindingKey[incoming.bindingKey],
              retainedPayload.hasRenderableGraph else {
            return RetainedSparklineResolution(
                payload: incoming,
                visualState: incoming.graphVisualState,
                firstPaintSource: "placeholder"
            )
        }

        AppLogger.debug(
            .lifecycle,
            "[GraphReuseDebug] \(marketIdentity.logFields) action=prepare_for_reuse keptGraph=true"
        )
        AppLogger.debug(
            .lifecycle,
            "[GraphDetailDebug] \(marketIdentity.logFields) action=placeholder_first_paint_blocked reason=usable_graph_exists retainedDetail=\(retainedPayload.detailLevel.cacheComponent) retainedPointCount=\(retainedPayload.pointCount)"
        )

        let retainedVisualState: MarketSparklineVisualState
        switch incoming.graphState {
        case .unavailable:
            retainedVisualState = .stale
        case .cachedVisible, .liveVisible, .staleVisible:
            retainedVisualState = incoming.graphVisualState
        case .none, .placeholder:
            retainedVisualState = retainedPayload.graphVisualState
        }

        return RetainedSparklineResolution(
            payload: retainedPayload,
            visualState: retainedVisualState,
            firstPaintSource: "retained"
        )
    }

    private func shouldReplaceRetainedPayload(
        existing: MarketSparklineRenderPayload?,
        incoming: MarketSparklineRenderPayload
    ) -> Bool {
        guard let existing, existing.hasRenderableGraph else {
            return true
        }
        let existingQuality = sparklineQuality(for: existing)
        let incomingQuality = sparklineQuality(for: incoming)
        if MarketSparklineQuality.shouldReplaceGraph(current: existingQuality, incoming: incomingQuality) {
            return true
        }
        return incomingQuality.visibleBindableChangeReason(over: existingQuality) != nil
    }
}

fileprivate struct MarketSparklinePathResult {
    let path: CGPath
    let didApplyTinyRangeBoost: Bool
}

private final class MarketSparklinePathCache {
    static let shared = MarketSparklinePathCache()

    private let lock = NSLock()
    private var pathsByKey: [String: MarketSparklinePathResult] = [:]

    func path(
        graphRenderIdentity: String,
        detailLevel: MarketSparklineDetailLevel,
        graphPathVersion: Int,
        pointsHash: Int,
        size: CGSize,
        geometry: MarketSparklineGeometry,
        marketIdentity _: MarketIdentity
    ) -> MarketSparklinePathResult? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let scaledWidth = Int(size.width.rounded(.toNearestOrEven))
        let scaledHeight = Int(size.height.rounded(.toNearestOrEven))
        let cacheKey = "\(graphRenderIdentity)|detail=\(detailLevel.cacheComponent)|path=\(graphPathVersion)|points=\(pointsHash)|\(scaledWidth)x\(scaledHeight)|domain=v1"

        lock.lock()
        if let cachedPath = pathsByKey[cacheKey] {
            lock.unlock()
            AppLogger.debug(
                .lifecycle,
                "[GraphPathCacheDebug] canonicalGraphKey=\(graphRenderIdentity) width=\(scaledWidth) height=\(scaledHeight) pointsHash=\(pointsHash) cacheHit=true pathReused=true reason=same_render_signature"
            )
            return cachedPath
        }
        lock.unlock()

        let builtPath = Self.makePath(size: size, geometry: geometry)
        guard let builtPath else {
            return nil
        }

        lock.lock()
        if pathsByKey.count > 4096 {
            pathsByKey.removeAll(keepingCapacity: true)
        }
        pathsByKey[cacheKey] = builtPath
        lock.unlock()
        AppLogger.debug(
            .lifecycle,
            "[GraphPathCacheDebug] canonicalGraphKey=\(graphRenderIdentity) width=\(scaledWidth) height=\(scaledHeight) pointsHash=\(pointsHash) cacheHit=false pathReused=false reason=points_or_size_changed"
        )
        return builtPath
    }

    private static func makePath(
        size: CGSize,
        geometry: MarketSparklineGeometry
    ) -> MarketSparklinePathResult? {
        guard geometry.normalizedPoints.count >= MarketSparklineRenderPolicy.minimumRenderablePointCount else {
            return nil
        }

        let path = UIBezierPath()
        let graphHeightUsage = MarketSparklineRenderPolicy.graphHeightUsage(
            rangeRatio: geometry.relativeRange,
            width: size.width,
            height: size.height
        )
        let usageScale = geometry.graphHeightUsage > 0
            ? graphHeightUsage / geometry.graphHeightUsage
            : 1
        let scaledPoints: [CGPoint] = geometry.normalizedPoints.map { point in
            let adjustedY = 0.5 + (point.y - 0.5) * CGFloat(usageScale)
            return CGPoint(
                x: point.x * size.width,
                y: min(max(adjustedY, 0.08), 0.92) * size.height
            )
        }
        let boostedPoints = boostScaledPointsIfNeeded(
            scaledPoints,
            size: size,
            geometry: geometry
        )

        guard let firstPoint = boostedPoints.first else {
            return nil
        }

        path.move(to: firstPoint)

        for index in 1..<boostedPoints.count {
            path.addLine(to: boostedPoints[index])
        }

        return MarketSparklinePathResult(
            path: path.cgPath,
            didApplyTinyRangeBoost: boostedPoints != scaledPoints
        )
    }

    private static func boostScaledPointsIfNeeded(
        _ points: [CGPoint],
        size: CGSize,
        geometry: MarketSparklineGeometry
    ) -> [CGPoint] {
        guard geometry.rawRange > 0,
              geometry.hasTinyRangeVisualBoost,
              points.count >= MarketSparklineRenderPolicy.minimumRenderablePointCount else {
            return points
        }

        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let verticalSpan = maxY - minY
        let minimumVisualAmplitude = max(2, min(size.height * 0.18, size.height * 0.45))
        guard verticalSpan > 0,
              verticalSpan < minimumVisualAmplitude else {
            return points
        }

        let centerY = (minY + maxY) / 2
        let scaleFactor = minimumVisualAmplitude / verticalSpan
        let minAllowedY = size.height * 0.12
        let maxAllowedY = size.height * 0.88

        return points.map { point in
            let boostedY = centerY + (point.y - centerY) * scaleFactor
            return CGPoint(
                x: point.x,
                y: min(max(boostedY, minAllowedY), maxAllowedY)
            )
        }
    }
}

struct SparklineCanvasConfiguration: Equatable {
    let payload: MarketSparklineRenderPayload
    let visualState: MarketSparklineVisualState
    let isUp: Bool
    let marketIdentity: MarketIdentity
    let width: CGFloat
    let height: CGFloat
    let firstPaintSource: String

    var lowConfidenceReason: String {
        let source = (payload.sourceName ?? "").lowercased()
        if source.contains("fallbacklistsparkline") || source.contains("fallback_list_sparkline") {
            return "providerLowLiquidity"
        }
        if payload.shapeQuality.rawRange == 0 {
            return "flatSeries"
        }
        if payload.shapeQuality.uniqueValueBucketCount < 3 {
            return "insufficientUniquePrices"
        }
        if payload.shapeQuality.directionChangeCount == 0 {
            return "lowDirectionChanges"
        }
        if payload.shapeQuality.isLowInformationListSparkline || payload.shapeQuality.relativeRange < 0.002 {
            return "lowRangeRatio"
        }
        return "-"
    }

    var lowConfidenceStrokeOpacity: Float {
        let source = (payload.sourceName ?? "").lowercased()
        let isLowConfidence = source.contains("fallbacklistsparkline")
            || payload.shapeQuality.isLowInformationListSparkline
        guard isLowConfidence else {
            return visualState.strokeOpacity
        }
        return min(visualState.strokeOpacity, MarketSparklineVisualState.stale.strokeOpacity)
    }
}

struct SparklineRenderDebugSnapshot: Equatable {
    let hasVisibleGraph: Bool
    let hasPlaceholder: Bool
    let graphPathVersion: Int?
    let renderVersion: Int?
    let detailLevel: MarketSparklineDetailLevel?
    let visualState: MarketSparklineVisualState?
    let graphBoundsHeight: CGFloat
    let redrawCount: Int
    let lastRedrawReason: String?
}

final class SparklineRenderView: UIView {
    private let strokeLayer = CAShapeLayer()
    private let placeholderFillLayer = CAShapeLayer()
    private let placeholderBorderLayer = CAShapeLayer()

    private var currentConfiguration: SparklineCanvasConfiguration?
    private var lastRenderSignature: String?
    private var currentRenderedPathIdentity: String?
    private var currentRenderedBindingKey: String?
    private var pendingRedrawReason: String?
    private var hasScheduledDeferredLayoutRender = false
    private var redrawCount = 0
    private var lastRedrawReason: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        layer.addSublayer(placeholderFillLayer)
        layer.addSublayer(placeholderBorderLayer)
        layer.addSublayer(strokeLayer)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderCurrentConfiguration(reason: "layout")
    }

    var debugSnapshot: SparklineRenderDebugSnapshot {
        SparklineRenderDebugSnapshot(
            hasVisibleGraph: strokeLayer.isHidden == false && strokeLayer.path != nil,
            hasPlaceholder: placeholderFillLayer.isHidden == false && placeholderFillLayer.path != nil,
            graphPathVersion: currentConfiguration?.payload.graphPathVersion,
            renderVersion: currentConfiguration?.payload.renderVersion,
            detailLevel: currentConfiguration?.payload.detailLevel,
            visualState: currentConfiguration?.visualState,
            graphBoundsHeight: strokeLayer.path?.boundingBoxOfPath.height ?? 0,
            redrawCount: redrawCount,
            lastRedrawReason: lastRedrawReason
        )
    }

    func apply(configuration: SparklineCanvasConfiguration) {
        let previousConfiguration = currentConfiguration
        ensureInitialRenderBounds(for: configuration)
        if previousConfiguration == configuration, lastRenderSignature != nil {
            return
        }
        let isBindingKeyChanged = previousConfiguration?.payload.bindingKey != configuration.payload.bindingKey

        if isBindingKeyChanged, let previousConfiguration {
            AppLogger.debug(
                .lifecycle,
                "[GraphReuseDebug] \(previousConfiguration.marketIdentity.logFields) action=prepare_for_reuse keptGraph=\(previousConfiguration.payload.hasRenderableGraph)"
            )
            clearRenderedGraph()
        }

        pendingRedrawReason = redrawReason(
            previousConfiguration: previousConfiguration,
            nextConfiguration: configuration,
            bindingKeyChanged: isBindingKeyChanged
        )
        currentConfiguration = configuration

        renderCurrentConfiguration(reason: "update")
    }

    func prepareForReuse() {
        let canKeepUsableGraph = currentConfiguration?.payload.hasRenderableGraph == true
            && strokeLayer.path != nil
            && strokeLayer.isHidden == false
        if let currentConfiguration {
            AppLogger.debug(
                .lifecycle,
                "[GraphReuseDebug] \(currentConfiguration.marketIdentity.logFields) action=prepare_for_reuse keptGraph=\(canKeepUsableGraph)"
            )
        }
        pendingRedrawReason = nil
        hasScheduledDeferredLayoutRender = false
        layer.removeAllAnimations()
        strokeLayer.removeAllAnimations()
        placeholderFillLayer.removeAllAnimations()
        placeholderBorderLayer.removeAllAnimations()
        if canKeepUsableGraph == false {
            currentConfiguration = nil
            clearRenderedGraph()
        }
    }

    func debugApply(
        payload: MarketSparklineRenderPayload,
        visualState: MarketSparklineVisualState,
        isUp: Bool,
        marketIdentity: MarketIdentity,
        size: CGSize
    ) {
        frame = CGRect(origin: .zero, size: size)
        bounds = CGRect(origin: .zero, size: size)
        apply(
            configuration: SparklineCanvasConfiguration(
                payload: payload,
                visualState: visualState,
                isUp: isUp,
                marketIdentity: marketIdentity,
                width: size.width,
                height: size.height,
                firstPaintSource: "debug"
            )
        )
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func configureLayers() {
        let displayScale = traitCollection.displayScale
        strokeLayer.fillColor = UIColor.clear.cgColor
        strokeLayer.lineWidth = 1.25
        strokeLayer.lineCap = .round
        strokeLayer.lineJoin = .round
        strokeLayer.contentsScale = displayScale

        placeholderFillLayer.contentsScale = displayScale
        placeholderBorderLayer.contentsScale = displayScale
        placeholderBorderLayer.fillColor = UIColor.clear.cgColor
        placeholderBorderLayer.lineWidth = 1
        placeholderBorderLayer.lineDashPattern = [3, 2]
    }

    private func renderCurrentConfiguration(reason: String) {
        guard let currentConfiguration else {
            AppLogger.debug(
                .lifecycle,
                "[GraphRenderDebug] exchange=- marketId=- symbol=- action=draw_skipped reason=no_configuration"
            )
            return
        }

        let renderSize = effectiveRenderSize(for: currentConfiguration, reason: reason)
        guard renderSize.width > 0, renderSize.height > 0 else {
            return
        }

        let renderSignature = [
            currentConfiguration.marketIdentity.exchange.rawValue,
            currentConfiguration.marketIdentity.marketId ?? "-",
            currentConfiguration.marketIdentity.symbol,
            currentConfiguration.payload.graphRenderIdentity,
            currentConfiguration.payload.detailLevel.cacheComponent,
            String(currentConfiguration.payload.graphPathVersion),
            String(currentConfiguration.payload.pointsHash),
            String(currentConfiguration.payload.renderVersion),
            String(currentConfiguration.payload.sourceVersion),
            String(currentConfiguration.payload.pointCount),
            String(currentConfiguration.payload.shapeQuality.minValue.bitPattern, radix: 16),
            String(currentConfiguration.payload.shapeQuality.maxValue.bitPattern, radix: 16),
            String(currentConfiguration.payload.shapeQuality.firstValue.bitPattern, radix: 16),
            String(currentConfiguration.payload.shapeQuality.lastValue.bitPattern, radix: 16),
            String(currentConfiguration.payload.shapeQuality.rawRange.bitPattern, radix: 16),
            String(MarketSparklineRenderPolicy.pointCountBucket(currentConfiguration.payload.pointCount)),
            String(currentConfiguration.payload.graphState.preservationRank),
            currentConfiguration.payload.graphState.keepsVisibleGraph ? "visible" : "hidden",
            MarketSparklineRenderPolicy.isPromotedPointCount(currentConfiguration.payload.pointCount) ? "promoted" : "fallback",
            String(Int(renderSize.width.rounded(.toNearestOrEven))),
            String(Int(renderSize.height.rounded(.toNearestOrEven))),
            String(currentConfiguration.visualState.rawValue),
            currentConfiguration.isUp ? "up" : "down"
        ].joined(separator: "|")

        let effectiveReason = pendingRedrawReason ?? reason
        let hasBlankRenderableLayer = currentConfiguration.payload.hasRenderableGraph
            && (strokeLayer.path == nil || strokeLayer.isHidden)
        if lastRenderSignature == renderSignature,
           hasBlankRenderableLayer == false {
            if lastRedrawReason == nil {
                AppLogger.debug(
                    .lifecycle,
                    "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=redraw_skipped reason=same_render_signature detailLevel=\(currentConfiguration.payload.detailLevel.cacheComponent) pointCount=\(currentConfiguration.payload.pointCount)"
                )
                lastRedrawReason = "same_render_signature"
            }
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=duplicate_redraw_prevented reason=same_render_signature detailLevel=\(currentConfiguration.payload.detailLevel.cacheComponent) pointCount=\(currentConfiguration.payload.pointCount)"
            )
            pendingRedrawReason = nil
            return
        }
        if hasBlankRenderableLayer {
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=redraw_allowed_despite_state_skip reason=blank_render_layer detailLevel=\(currentConfiguration.payload.detailLevel.cacheComponent) pointCount=\(currentConfiguration.payload.pointCount)"
            )
        }

        if effectiveReason == "first_paint" {
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=first_paint detailLevel=\(currentConfiguration.payload.detailLevel.cacheComponent) pointCount=\(currentConfiguration.payload.pointCount) source=\(currentConfiguration.firstPaintSource)"
            )
        } else if effectiveReason == "visible_fast_lane" {
            AppLogger.debug(
                .lifecycle,
                "[GraphVisibleDebug] \(currentConfiguration.marketIdentity.logFields) action=visible_fast_lane_applied source=\(currentConfiguration.firstPaintSource) detailLevel=\(currentConfiguration.payload.detailLevel.cacheComponent)"
            )
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let placeholderFrame = CGRect(
            x: 0,
            y: renderSize.height * 0.14,
            width: renderSize.width,
            height: renderSize.height * 0.72
        )
        let placeholderPath = UIBezierPath(
            roundedRect: placeholderFrame,
            cornerRadius: 5
        ).cgPath

        switch currentConfiguration.visualState {
        case .cached, .live, .stale:
            guard let geometry = currentConfiguration.payload.geometry,
                  let pathResult = MarketSparklinePathCache.shared.path(
                    graphRenderIdentity: currentConfiguration.payload.graphRenderIdentity,
                    detailLevel: currentConfiguration.payload.detailLevel,
                    graphPathVersion: currentConfiguration.payload.graphPathVersion,
                    pointsHash: currentConfiguration.payload.pointsHash,
                    size: renderSize,
                    geometry: geometry,
                    marketIdentity: currentConfiguration.marketIdentity
                  ) else {
                AppLogger.debug(
                    .lifecycle,
                    "[GraphRenderDebug] \(currentConfiguration.marketIdentity.logFields) action=draw_skipped reason=missing_path"
                )
                if preservePreviousUsableGraphIfPossible(
                    for: currentConfiguration,
                    reason: "missing_path"
                ) {
                    lastRenderSignature = nil
                    pendingRedrawReason = nil
                    return
                }
                showPlaceholder(
                    path: placeholderPath,
                    isUnavailable: false
                )
                lastRenderSignature = renderSignature
                pendingRedrawReason = nil
                return
            }

            let graphPath = pathResult.path
            let pathIdentity = [
                currentConfiguration.marketIdentity.exchange.rawValue,
                currentConfiguration.marketIdentity.marketId ?? "-",
                currentConfiguration.marketIdentity.symbol,
                currentConfiguration.payload.graphRenderIdentity,
                currentConfiguration.payload.detailLevel.cacheComponent,
                String(currentConfiguration.payload.graphPathVersion),
                String(currentConfiguration.payload.pointsHash),
                String(currentConfiguration.payload.renderVersion),
                String(currentConfiguration.payload.sourceVersion),
                String(currentConfiguration.payload.pointCount),
                String(currentConfiguration.payload.shapeQuality.minValue.bitPattern, radix: 16),
                String(currentConfiguration.payload.shapeQuality.maxValue.bitPattern, radix: 16),
                String(currentConfiguration.payload.shapeQuality.firstValue.bitPattern, radix: 16),
                String(currentConfiguration.payload.shapeQuality.lastValue.bitPattern, radix: 16),
                String(Int(renderSize.width.rounded(.toNearestOrEven))),
                String(Int(renderSize.height.rounded(.toNearestOrEven)))
            ].joined(separator: "|")
            let previousOpacity = strokeLayer.opacity
            let wasHidden = strokeLayer.isHidden
            let didChangePath = currentRenderedPathIdentity != pathIdentity || strokeLayer.path == nil
            if didChangePath {
                strokeLayer.path = graphPath
                currentRenderedPathIdentity = pathIdentity
                currentRenderedBindingKey = currentConfiguration.payload.bindingKey
            }
            strokeLayer.strokeColor = (currentConfiguration.isUp ? UIColor(Color.up) : UIColor(Color.down)).cgColor
            strokeLayer.opacity = currentConfiguration.lowConfidenceStrokeOpacity
            strokeLayer.isHidden = false
            placeholderFillLayer.isHidden = true
            placeholderBorderLayer.isHidden = true
            let didChangeStyle = previousOpacity != strokeLayer.opacity
                || wasHidden
                || didChangePath == false

            if didChangePath || didChangeStyle {
                strokeLayer.setNeedsDisplay()
                layer.setNeedsDisplay()
                redrawCount += 1
                lastRedrawReason = effectiveReason

                AppLogger.debug(
                    .lifecycle,
                    "[GraphRenderDebug] \(currentConfiguration.marketIdentity.logFields) action=draw_started size=\(Int(renderSize.width.rounded(.toNearestOrEven)))x\(Int(renderSize.height.rounded(.toNearestOrEven))) pointCount=\(currentConfiguration.payload.pointCount)"
                )
                if pathResult.didApplyTinyRangeBoost {
                    AppLogger.debug(
                        .lifecycle,
                        "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=flat_range_visual_boost_applied rawRange=\(geometry.rawRange) relativeRange=\(geometry.relativeRange)"
                    )
                }
                AppLogger.debug(
                    .network,
	                    "[GraphRender] exchange=\(currentConfiguration.marketIdentity.exchange.rawValue) quoteCurrency=\(currentConfiguration.marketIdentity.quoteCurrency.rawValue) marketId=\(currentConfiguration.marketIdentity.marketId ?? currentConfiguration.marketIdentity.symbol) state=\(currentConfiguration.payload.graphState) pointCount=\(currentConfiguration.payload.pointCount) quality=\(currentConfiguration.payload.sourceName ?? currentConfiguration.payload.detailLevel.cacheComponent) isDerived=\(currentConfiguration.payload.detailLevel == .derivedPreview) realSeries=\(MarketSparklineRenderPolicy.isRealSeriesSource(currentConfiguration.payload.sourceName)) width=\(Int(renderSize.width.rounded(.toNearestOrEven))) height=\(Int(renderSize.height.rounded(.toNearestOrEven))) min=\(currentConfiguration.payload.shapeQuality.minValue) max=\(currentConfiguration.payload.shapeQuality.maxValue) mean=\(currentConfiguration.payload.geometry?.meanValue ?? 0) range=\(currentConfiguration.payload.shapeQuality.rawRange) rangeRatio=\(currentConfiguration.payload.geometry?.relativeRange ?? currentConfiguration.payload.shapeQuality.relativeRange) graphHeightUsage=\(MarketSparklineRenderPolicy.graphHeightUsage(rangeRatio: currentConfiguration.payload.geometry?.relativeRange ?? currentConfiguration.payload.shapeQuality.relativeRange, width: renderSize.width, height: renderSize.height)) flat=\(currentConfiguration.payload.shapeQuality.rawRange == 0) directionChanges=\(currentConfiguration.payload.shapeQuality.directionChangeCount) sampledCount=\(currentConfiguration.payload.geometry?.normalizedPoints.count ?? 0) clipped=false lowConfidence=\(currentConfiguration.lowConfidenceStrokeOpacity < currentConfiguration.visualState.strokeOpacity) lowConfidenceReason=\(currentConfiguration.lowConfidenceReason)"
                )
                if effectiveReason == "detail_upgrade" {
                    AppLogger.debug(
                        .lifecycle,
                        "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=redraw_triggered reason=detail_upgrade"
                    )
                }
            } else {
                AppLogger.debug(
                    .lifecycle,
                    "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=duplicate_redraw_prevented reason=same_path_identity detailLevel=\(currentConfiguration.payload.detailLevel.cacheComponent) pointCount=\(currentConfiguration.payload.pointCount)"
                )
            }
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=refined_patch_applied renderVersion=\(currentConfiguration.payload.renderVersion) pathVersion=\(currentConfiguration.payload.graphPathVersion)"
            )
        case .placeholder:
            if preservePreviousUsableGraphIfPossible(
                for: currentConfiguration,
                reason: "placeholder_blank_guard"
            ) {
                break
            }
            showPlaceholder(
                path: placeholderPath,
                isUnavailable: false
            )
        case .unavailable:
            if preservePreviousUsableGraphIfPossible(
                for: currentConfiguration,
                reason: "unavailable_blank_guard"
            ) {
                break
            }
            showPlaceholder(
                path: placeholderPath,
                isUnavailable: true
            )
        case .none:
            if preservePreviousUsableGraphIfPossible(
                for: currentConfiguration,
                reason: "none_blank_guard"
            ) == false {
                clearRenderedGraph()
            }
        }

        lastRenderSignature = renderSignature
        pendingRedrawReason = nil
    }

    private func effectiveRenderSize(
        for configuration: SparklineCanvasConfiguration,
        reason: String
    ) -> CGSize {
        if bounds.width > 0, bounds.height > 0 {
            hasScheduledDeferredLayoutRender = false
            return bounds.size
        }

        MarketPerformanceDebugClient.shared.increment(.graphLayoutZero)
        let fallbackSize = CGSize(width: configuration.width, height: configuration.height)
        guard fallbackSize.width > 0, fallbackSize.height > 0 else {
            AppLogger.debug(
                .lifecycle,
                "[GraphRenderDebug] \(configuration.marketIdentity.logFields) action=draw_skipped reason=layout_zero"
            )
            return .zero
        }

        AppLogger.debug(
            .lifecycle,
            "[GraphRenderDebug] \(configuration.marketIdentity.logFields) action=draw_deferred reason=layout_zero fallbackSize=\(Int(fallbackSize.width))x\(Int(fallbackSize.height)) source=\(reason)"
        )
        if hasScheduledDeferredLayoutRender == false {
            hasScheduledDeferredLayoutRender = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.renderCurrentConfiguration(reason: "deferred_layout")
            }
        }
        return fallbackSize
    }

    private func ensureInitialRenderBounds(for configuration: SparklineCanvasConfiguration) {
        guard bounds.width <= 0 || bounds.height <= 0 else {
            return
        }
        guard configuration.width > 0, configuration.height > 0 else {
            return
        }

        let renderBounds = CGRect(
            origin: .zero,
            size: CGSize(width: configuration.width, height: configuration.height)
        )
        bounds = renderBounds
        if frame.width <= 0 || frame.height <= 0 {
            frame = CGRect(origin: frame.origin, size: renderBounds.size)
        }
    }

    private func redrawReason(
        previousConfiguration: SparklineCanvasConfiguration?,
        nextConfiguration: SparklineCanvasConfiguration,
        bindingKeyChanged: Bool
    ) -> String {
        guard let previousConfiguration else {
            return "first_paint"
        }
        if bindingKeyChanged {
            return "binding_change"
        }
        let oldDetail = previousConfiguration.payload.detailLevel
        let newDetail = nextConfiguration.payload.detailLevel
        let oldPointCount = previousConfiguration.payload.pointCount
        let newPointCount = nextConfiguration.payload.pointCount
        let oldState = previousConfiguration.payload.graphState
        let newState = nextConfiguration.payload.graphState
        let oldBucket = MarketSparklineRenderPolicy.pointCountBucket(oldPointCount)
        let newBucket = MarketSparklineRenderPolicy.pointCountBucket(newPointCount)
        let forcedUpgradeReason: String?
        if oldDetail == .placeholder && newDetail.pathDetailRank >= MarketSparklineDetailLevel.refinedMini.pathDetailRank {
            forcedUpgradeReason = "placeholder_to_live"
        } else if oldPointCount == 0 && newPointCount > 0 {
            forcedUpgradeReason = "placeholder_to_live"
        } else if (oldDetail == .retainedCoarse || oldDetail == .derivedPreview) && newPointCount > oldPointCount {
            forcedUpgradeReason = "coarse_to_live"
        } else if (oldState == .placeholder || oldState == .staleVisible || oldState == .cachedVisible) && newState == .liveVisible {
            forcedUpgradeReason = "placeholder_to_live"
        } else if (oldDetail == .retainedCoarse || oldDetail == .liveCoarse || oldDetail == .derivedPreview || oldDetail == .providerMini)
            && (MarketSparklineRenderPolicy.minimumRenderablePointCount...MarketSparklineRenderPolicy.coarseUpperBoundPointCount).contains(oldPointCount)
            && MarketSparklineRenderPolicy.isPromotedPointCount(newPointCount)
            && newDetail.isDetailed {
            forcedUpgradeReason = "coarse_to_live"
        } else {
            forcedUpgradeReason = nil
        }
        if let forcedUpgradeReason {
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(nextConfiguration.marketIdentity.logFields) action=detail_upgrade_forced oldDetail=\(oldDetail.cacheComponent) newDetail=\(newDetail.cacheComponent) oldPointCount=\(oldPointCount) newPointCount=\(newPointCount)"
            )
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(nextConfiguration.marketIdentity.logFields) action=suppression_bypassed reason=\(forcedUpgradeReason)"
            )
            return "detail_upgrade"
        }
        if newDetail.pathDetailRank > oldDetail.pathDetailRank
            || (newDetail.isDetailed && newPointCount > oldPointCount)
            || newBucket > oldBucket {
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(nextConfiguration.marketIdentity.logFields) action=refined_patch_received oldDetail=\(oldDetail.cacheComponent) newDetail=\(newDetail.cacheComponent) oldPointCount=\(oldPointCount) newPointCount=\(newPointCount)"
            )
            return "detail_upgrade"
        }
        if nextConfiguration.payload.sourceVersion > previousConfiguration.payload.sourceVersion,
           nextConfiguration.payload.graphState.keepsVisibleGraph {
            return "visible_fast_lane"
        }
        if previousConfiguration.payload.graphPathVersion != nextConfiguration.payload.graphPathVersion {
            return "path_update"
        }
        if previousConfiguration.payload.renderVersion != nextConfiguration.payload.renderVersion
            || previousConfiguration.payload.graphState != nextConfiguration.payload.graphState
            || previousConfiguration.visualState != nextConfiguration.visualState {
            return "visual_state"
        }
        return "same_render_signature"
    }

    private func showPlaceholder(path: CGPath, isUnavailable: Bool) {
        strokeLayer.isHidden = true
        placeholderFillLayer.isHidden = false
        placeholderBorderLayer.isHidden = false
        if isUnavailable {
            let bounds = path.boundingBoxOfPath
            let width = max(min(bounds.width * 0.34, 34), 14)
            let y = bounds.midY
            let dashPath = UIBezierPath()
            dashPath.move(to: CGPoint(x: bounds.midX - width / 2, y: y))
            dashPath.addLine(to: CGPoint(x: bounds.midX + width / 2, y: y))
            placeholderFillLayer.path = nil
            placeholderFillLayer.isHidden = true
            placeholderBorderLayer.path = dashPath.cgPath
            placeholderBorderLayer.strokeColor = UIColor(Color.textMuted.opacity(0.55)).cgColor
            placeholderBorderLayer.lineWidth = 2
            placeholderBorderLayer.lineCap = .round
            placeholderBorderLayer.lineDashPattern = nil
        } else {
            placeholderFillLayer.path = path
            placeholderBorderLayer.path = path
            placeholderFillLayer.fillColor = UIColor(Color.bgTertiary.opacity(0.75)).cgColor
            placeholderBorderLayer.strokeColor = UIColor(Color.themeBorder.opacity(0.35)).cgColor
            placeholderBorderLayer.lineWidth = 1
            placeholderBorderLayer.lineCap = .butt
            placeholderBorderLayer.lineDashPattern = [3, 2]
        }
    }

    private func preservePreviousUsableGraphIfPossible(
        for configuration: SparklineCanvasConfiguration,
        reason: String
    ) -> Bool {
        guard currentRenderedBindingKey == configuration.payload.bindingKey,
              strokeLayer.path != nil else {
            return false
        }

        strokeLayer.isHidden = false
        strokeLayer.opacity = max(strokeLayer.opacity, MarketSparklineVisualState.stale.strokeOpacity)
        placeholderFillLayer.isHidden = true
        placeholderBorderLayer.isHidden = true
        AppLogger.debug(
            .lifecycle,
            "[GraphDetailDebug] \(configuration.marketIdentity.logFields) action=blank_path_guard_applied reason=\(reason)"
        )
        return true
    }

    private func clearRenderedGraph() {
        strokeLayer.removeAllAnimations()
        placeholderFillLayer.removeAllAnimations()
        placeholderBorderLayer.removeAllAnimations()
        strokeLayer.path = nil
        strokeLayer.isHidden = true
        currentRenderedPathIdentity = nil
        currentRenderedBindingKey = nil
        placeholderFillLayer.path = nil
        placeholderFillLayer.isHidden = true
        placeholderBorderLayer.path = nil
        placeholderBorderLayer.isHidden = true
        lastRenderSignature = nil
    }
}

private struct SparklineCanvasView: UIViewRepresentable, Equatable {
    let configuration: SparklineCanvasConfiguration

    func makeUIView(context: Context) -> SparklineRenderView {
        let view = SparklineRenderView(frame: .zero)
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: SparklineRenderView, context: Context) {
        let renderSize = CGSize(
            width: configuration.width,
            height: configuration.height
        )
        if renderSize.width > 0, renderSize.height > 0 {
            uiView.bounds = CGRect(origin: .zero, size: renderSize)
            if uiView.frame.size != renderSize {
                uiView.frame = CGRect(origin: uiView.frame.origin, size: renderSize)
            }
        }
        uiView.apply(configuration: configuration)
    }

    static func dismantleUIView(_ uiView: SparklineRenderView, coordinator: ()) {
        uiView.prepareForReuse()
    }
}

private extension MarketSparklineVisualState {
    var strokeOpacity: Float {
        switch self {
        case .cached:
            return 0.82
        case .stale:
            return 0.58
        case .live:
            return 1
        case .none, .placeholder, .unavailable:
            return 0
        }
    }
}

struct SparklineView: View, Equatable {
    let payload: MarketSparklineRenderPayload
    let isUp: Bool
    let marketIdentity: MarketIdentity
    let width: CGFloat
    let height: CGFloat

    private let resolvedConfiguration: SparklineCanvasConfiguration

    init(
        payload: MarketSparklineRenderPayload,
        isUp: Bool,
        marketIdentity: MarketIdentity,
        width: CGFloat = 84,
        height: CGFloat = 34
    ) {
        let resolution = RetainedSparklineStore.shared.resolve(
            incoming: payload,
            marketIdentity: marketIdentity
        )

        self.payload = payload
        self.isUp = isUp
        self.marketIdentity = marketIdentity
        self.width = width
        self.height = height
        self.resolvedConfiguration = SparklineCanvasConfiguration(
            payload: resolution.payload,
            visualState: resolution.visualState,
            isUp: isUp,
            marketIdentity: marketIdentity,
            width: width,
            height: height,
            firstPaintSource: resolution.firstPaintSource
        )
    }

    static func == (lhs: SparklineView, rhs: SparklineView) -> Bool {
        lhs.payload == rhs.payload
            && lhs.isUp == rhs.isUp
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.marketIdentity == rhs.marketIdentity
    }

    var body: some View {
        SparklineCanvasView(configuration: resolvedConfiguration)
            .frame(width: width, height: height)
            .onAppear {
                AppLogger.debug(
                    .network,
	                    "[GraphRender] exchange=\(marketIdentity.exchange.rawValue) quoteCurrency=\(marketIdentity.quoteCurrency.rawValue) marketId=\(marketIdentity.marketId ?? marketIdentity.symbol) state=\(resolvedConfiguration.payload.graphState) pointCount=\(resolvedConfiguration.payload.pointCount) quality=\(resolvedConfiguration.payload.sourceName ?? resolvedConfiguration.payload.detailLevel.cacheComponent) isDerived=\(resolvedConfiguration.payload.detailLevel == .derivedPreview) realSeries=\(MarketSparklineRenderPolicy.isRealSeriesSource(resolvedConfiguration.payload.sourceName)) width=\(Int(width)) height=\(Int(height)) min=\(resolvedConfiguration.payload.shapeQuality.minValue) max=\(resolvedConfiguration.payload.shapeQuality.maxValue) mean=\(resolvedConfiguration.payload.geometry?.meanValue ?? 0) range=\(resolvedConfiguration.payload.shapeQuality.rawRange) rangeRatio=\(resolvedConfiguration.payload.geometry?.relativeRange ?? resolvedConfiguration.payload.shapeQuality.relativeRange) graphHeightUsage=\(MarketSparklineRenderPolicy.graphHeightUsage(rangeRatio: resolvedConfiguration.payload.geometry?.relativeRange ?? resolvedConfiguration.payload.shapeQuality.relativeRange, width: width, height: height)) flat=\(resolvedConfiguration.payload.shapeQuality.rawRange == 0) directionChanges=\(resolvedConfiguration.payload.shapeQuality.directionChangeCount) sampledCount=\(resolvedConfiguration.payload.geometry?.normalizedPoints.count ?? 0) clipped=false lowConfidence=\(resolvedConfiguration.lowConfidenceStrokeOpacity < resolvedConfiguration.visualState.strokeOpacity) lowConfidenceReason=\(resolvedConfiguration.lowConfidenceReason)"
                )
            }
    }
}
