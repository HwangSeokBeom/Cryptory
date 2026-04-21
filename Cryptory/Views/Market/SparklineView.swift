import SwiftUI
import UIKit

private struct RetainedSparklineResolution {
    let payload: MarketSparklineRenderPayload
    let visualState: MarketSparklineVisualState
    let firstPaintSource: String
}

private final class RetainedSparklineStore {
    static let shared = RetainedSparklineStore()

    private let lock = NSLock()
    private var payloadsByBindingKey: [String: MarketSparklineRenderPayload] = [:]

    func resolve(
        incoming: MarketSparklineRenderPayload,
        marketIdentity: MarketIdentity
    ) -> RetainedSparklineResolution {
        lock.lock()
        defer { lock.unlock() }

        if incoming.hasRenderableGraph {
            let retainedPayload = payloadsByBindingKey[incoming.bindingKey]
            let displayPayload: MarketSparklineRenderPayload
            if let retainedPayload,
               retainedPayload.hasRenderableGraph,
               (retainedPayload.detailLevel.pathDetailRank > incoming.detailLevel.pathDetailRank
                || (retainedPayload.detailLevel.isDetailed
                    && incoming.detailLevel.isDetailed
                    && retainedPayload.pointCount > incoming.pointCount)) {
                displayPayload = retainedPayload
                AppLogger.debug(
                    .lifecycle,
                    "[GraphDetailDebug] \(marketIdentity.logFields) action=redraw_skipped reason=retained_refined_prevents_coarse_reverse oldDetail=\(retainedPayload.detailLevel.cacheComponent) newDetail=\(incoming.detailLevel.cacheComponent)"
                )
            } else {
                displayPayload = incoming
            }
            if shouldReplaceRetainedPayload(existing: retainedPayload, incoming: incoming) {
                payloadsByBindingKey[incoming.bindingKey] = incoming
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
        if incoming.detailLevel.pathDetailRank > existing.detailLevel.pathDetailRank {
            return true
        }
        if incoming.detailLevel.pathDetailRank < existing.detailLevel.pathDetailRank {
            return false
        }
        return incoming.pointCount >= existing.pointCount
    }
}

private final class MarketSparklinePathCache {
    static let shared = MarketSparklinePathCache()

    private let lock = NSLock()
    private var pathsByKey: [String: CGPath] = [:]

    func path(
        graphRenderIdentity: String,
        detailLevel: MarketSparklineDetailLevel,
        graphPathVersion: Int,
        size: CGSize,
        geometry: MarketSparklineGeometry,
        marketIdentity: MarketIdentity
    ) -> CGPath? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let scaledWidth = Int(size.width.rounded(.toNearestOrEven))
        let scaledHeight = Int(size.height.rounded(.toNearestOrEven))
        let cacheKey = "\(graphRenderIdentity)|detail=\(detailLevel.cacheComponent)|path=\(graphPathVersion)|\(scaledWidth)x\(scaledHeight)"
        AppLogger.debug(
            .lifecycle,
            "[GraphDetailDebug] \(marketIdentity.logFields) action=cache_key key=\(cacheKey) detailLevel=\(detailLevel.cacheComponent)"
        )

        lock.lock()
        if let cachedPath = pathsByKey[cacheKey] {
            lock.unlock()
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
        return builtPath
    }

    private static func makePath(
        size: CGSize,
        geometry: MarketSparklineGeometry
    ) -> CGPath? {
        guard geometry.normalizedPoints.count >= MarketSparklineRenderPolicy.minimumRenderablePointCount else {
            return nil
        }

        let path = UIBezierPath()
        let scaledPoints = geometry.normalizedPoints.map { point in
            CGPoint(
                x: point.x * size.width,
                y: point.y * size.height
            )
        }

        guard let firstPoint = scaledPoints.first else {
            return nil
        }

        path.move(to: firstPoint)

        if scaledPoints.count == 2 {
            path.addLine(to: scaledPoints[1])
            return path.cgPath
        }

        for index in 1..<scaledPoints.count {
            let previousPoint = scaledPoints[index - 1]
            let point = scaledPoints[index]
            let midpoint = CGPoint(
                x: (previousPoint.x + point.x) / 2,
                y: (previousPoint.y + point.y) / 2
            )
            path.addQuadCurve(to: midpoint, controlPoint: previousPoint)
            path.addQuadCurve(to: point, controlPoint: point)
        }

        return path.cgPath
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
}

struct SparklineRenderDebugSnapshot: Equatable {
    let hasVisibleGraph: Bool
    let hasPlaceholder: Bool
    let graphPathVersion: Int?
    let renderVersion: Int?
    let detailLevel: MarketSparklineDetailLevel?
    let visualState: MarketSparklineVisualState?
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
            redrawCount: redrawCount,
            lastRedrawReason: lastRedrawReason
        )
    }

    func apply(configuration: SparklineCanvasConfiguration) {
        let previousConfiguration = currentConfiguration
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
        strokeLayer.lineWidth = 1.5
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
            currentConfiguration.payload.graphRenderIdentity,
            currentConfiguration.payload.detailLevel.cacheComponent,
            String(currentConfiguration.payload.graphPathVersion),
            String(currentConfiguration.payload.renderVersion),
            String(currentConfiguration.payload.pointCount),
            String(Int(renderSize.width.rounded(.toNearestOrEven))),
            String(Int(renderSize.height.rounded(.toNearestOrEven))),
            String(currentConfiguration.visualState.rawValue)
        ].joined(separator: "|")

        let effectiveReason = pendingRedrawReason ?? reason
        if lastRenderSignature == renderSignature {
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=redraw_skipped reason=same_render_signature detailLevel=\(currentConfiguration.payload.detailLevel.cacheComponent) pointCount=\(currentConfiguration.payload.pointCount)"
            )
            return
        }

        if effectiveReason == "first_paint" {
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=first_paint detailLevel=\(currentConfiguration.payload.detailLevel.cacheComponent) pointCount=\(currentConfiguration.payload.pointCount) source=\(currentConfiguration.firstPaintSource)"
            )
        }

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
                  let graphPath = MarketSparklinePathCache.shared.path(
                    graphRenderIdentity: currentConfiguration.payload.graphRenderIdentity,
                    detailLevel: currentConfiguration.payload.detailLevel,
                    graphPathVersion: currentConfiguration.payload.graphPathVersion,
                    size: renderSize,
                    geometry: geometry,
                    marketIdentity: currentConfiguration.marketIdentity
                  ) else {
                AppLogger.debug(
                    .lifecycle,
                    "[GraphRenderDebug] \(currentConfiguration.marketIdentity.logFields) action=draw_skipped reason=missing_path"
                )
                showPlaceholder(
                    path: placeholderPath,
                    isUnavailable: false
                )
                lastRenderSignature = renderSignature
                pendingRedrawReason = nil
                return
            }

            let pathIdentity = [
                currentConfiguration.payload.graphRenderIdentity,
                currentConfiguration.payload.detailLevel.cacheComponent,
                String(currentConfiguration.payload.graphPathVersion),
                String(currentConfiguration.payload.renderVersion),
                String(currentConfiguration.payload.pointCount),
                String(Int(renderSize.width.rounded(.toNearestOrEven))),
                String(Int(renderSize.height.rounded(.toNearestOrEven)))
            ].joined(separator: "|")
            strokeLayer.path = graphPath
            strokeLayer.strokeColor = (currentConfiguration.isUp ? UIColor(Color.up) : UIColor(Color.down)).cgColor
            strokeLayer.opacity = currentConfiguration.visualState.strokeOpacity
            strokeLayer.isHidden = false
            placeholderFillLayer.isHidden = true
            placeholderBorderLayer.isHidden = true
            strokeLayer.setNeedsDisplay()
            layer.setNeedsDisplay()
            currentRenderedPathIdentity = pathIdentity
            redrawCount += 1
            lastRedrawReason = effectiveReason

            AppLogger.debug(
                .lifecycle,
                "[GraphRenderDebug] \(currentConfiguration.marketIdentity.logFields) action=draw_started size=\(Int(renderSize.width.rounded(.toNearestOrEven)))x\(Int(renderSize.height.rounded(.toNearestOrEven))) pointCount=\(currentConfiguration.payload.pointCount)"
            )
            if effectiveReason == "detail_upgrade" {
                AppLogger.debug(
                    .lifecycle,
                    "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=redraw_triggered reason=detail_upgrade"
                )
            }
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(currentConfiguration.marketIdentity.logFields) action=refined_patch_applied renderVersion=\(currentConfiguration.payload.renderVersion) pathVersion=\(currentConfiguration.payload.graphPathVersion)"
            )
        case .placeholder:
            showPlaceholder(
                path: placeholderPath,
                isUnavailable: false
            )
        case .unavailable:
            showPlaceholder(
                path: placeholderPath,
                isUnavailable: true
            )
        case .none:
            clearRenderedGraph()
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
        if newDetail.pathDetailRank > oldDetail.pathDetailRank
            || (newDetail.isDetailed && nextConfiguration.payload.pointCount > previousConfiguration.payload.pointCount) {
            AppLogger.debug(
                .lifecycle,
                "[GraphDetailDebug] \(nextConfiguration.marketIdentity.logFields) action=refined_patch_received oldDetail=\(oldDetail.cacheComponent) newDetail=\(newDetail.cacheComponent) oldPointCount=\(previousConfiguration.payload.pointCount) newPointCount=\(nextConfiguration.payload.pointCount)"
            )
            return "detail_upgrade"
        }
        if previousConfiguration.payload.graphPathVersion != nextConfiguration.payload.graphPathVersion {
            return "path_update"
        }
        if previousConfiguration.payload.renderVersion != nextConfiguration.payload.renderVersion
            || previousConfiguration.visualState != nextConfiguration.visualState {
            return "visual_state"
        }
        return "same_render_signature"
    }

    private func showPlaceholder(path: CGPath, isUnavailable: Bool) {
        strokeLayer.isHidden = true
        placeholderFillLayer.isHidden = false
        placeholderBorderLayer.isHidden = false
        placeholderFillLayer.path = path
        placeholderBorderLayer.path = path
        placeholderFillLayer.fillColor = UIColor(Color.bgTertiary.opacity(isUnavailable ? 0.55 : 0.75)).cgColor
        placeholderBorderLayer.strokeColor = UIColor(Color.themeBorder.opacity(isUnavailable ? 0.25 : 0.35)).cgColor
        placeholderBorderLayer.lineDashPattern = isUnavailable ? nil : [3, 2]
    }

    private func clearRenderedGraph() {
        strokeLayer.path = nil
        strokeLayer.isHidden = true
        currentRenderedPathIdentity = nil
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
        uiView.apply(configuration: configuration)
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
        width: CGFloat = 76,
        height: CGFloat = 20
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
    }
}
