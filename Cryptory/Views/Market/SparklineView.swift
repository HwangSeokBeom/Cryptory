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
        exchange: Exchange,
        symbol: String
    ) -> RetainedSparklineResolution {
        lock.lock()
        defer { lock.unlock() }

        if incoming.hasRenderableGraph {
            payloadsByBindingKey[incoming.bindingKey] = incoming
            let source = incoming.graphState == .liveVisible ? "live" : "retained"
            return RetainedSparklineResolution(
                payload: incoming,
                visualState: incoming.graphVisualState,
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
            "[GraphReuseDebug] symbol=\(symbol) action=prepare_for_reuse keptGraph=true exchange=\(exchange.rawValue)"
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
}

private final class MarketSparklinePathCache {
    static let shared = MarketSparklinePathCache()

    private let lock = NSLock()
    private var pathsByKey: [String: CGPath] = [:]

    func path(
        graphRenderIdentity: String,
        graphPathVersion: Int,
        size: CGSize,
        geometry: MarketSparklineGeometry
    ) -> CGPath? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let scaledWidth = Int(size.width.rounded(.toNearestOrEven))
        let scaledHeight = Int(size.height.rounded(.toNearestOrEven))
        let cacheKey = "\(graphRenderIdentity)|\(graphPathVersion)|\(scaledWidth)x\(scaledHeight)"

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
    let exchange: Exchange
    let symbol: String
    let width: CGFloat
    let height: CGFloat
    let firstPaintSource: String
}

struct SparklineRenderDebugSnapshot: Equatable {
    let hasVisibleGraph: Bool
    let hasPlaceholder: Bool
    let graphPathVersion: Int?
    let renderVersion: Int?
    let visualState: MarketSparklineVisualState?
}

final class SparklineRenderView: UIView {
    private let strokeLayer = CAShapeLayer()
    private let placeholderFillLayer = CAShapeLayer()
    private let placeholderBorderLayer = CAShapeLayer()

    private var currentConfiguration: SparklineCanvasConfiguration?
    private var lastRenderSignature: String?

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
            visualState: currentConfiguration?.visualState
        )
    }

    func apply(configuration: SparklineCanvasConfiguration) {
        let previousConfiguration = currentConfiguration
        let isBindingKeyChanged = previousConfiguration?.payload.bindingKey != configuration.payload.bindingKey

        if isBindingKeyChanged, let previousConfiguration {
            AppLogger.debug(
                .lifecycle,
                "[GraphReuseDebug] symbol=\(previousConfiguration.symbol) action=prepare_for_reuse keptGraph=\(previousConfiguration.payload.hasRenderableGraph)"
            )
            clearRenderedGraph()
        }

        currentConfiguration = configuration

        renderCurrentConfiguration(reason: "update")
    }

    func debugApply(
        payload: MarketSparklineRenderPayload,
        visualState: MarketSparklineVisualState,
        isUp: Bool,
        exchange: Exchange,
        symbol: String,
        size: CGSize
    ) {
        frame = CGRect(origin: .zero, size: size)
        bounds = CGRect(origin: .zero, size: size)
        apply(
            configuration: SparklineCanvasConfiguration(
                payload: payload,
                visualState: visualState,
                isUp: isUp,
                exchange: exchange,
                symbol: symbol,
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
                "[GraphRenderDebug] symbol=<none> action=draw_skipped reason=no_configuration"
            )
            return
        }

        guard bounds.width > 0, bounds.height > 0 else {
            AppLogger.debug(
                .lifecycle,
                "[GraphRenderDebug] symbol=\(currentConfiguration.symbol) action=draw_skipped reason=layout_zero"
            )
            return
        }

        let renderSignature = [
            currentConfiguration.payload.graphRenderIdentity,
            String(currentConfiguration.payload.graphPathVersion),
            String(currentConfiguration.payload.renderVersion),
            String(Int(bounds.width.rounded(.toNearestOrEven))),
            String(Int(bounds.height.rounded(.toNearestOrEven))),
            String(currentConfiguration.visualState.rawValue)
        ].joined(separator: "|")

        if lastRenderSignature == renderSignature, reason == "layout" {
            return
        }

        let placeholderFrame = CGRect(
            x: 0,
            y: bounds.height * 0.14,
            width: bounds.width,
            height: bounds.height * 0.72
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
                    graphPathVersion: currentConfiguration.payload.graphPathVersion,
                    size: bounds.size,
                    geometry: geometry
                  ) else {
                AppLogger.debug(
                    .lifecycle,
                    "[GraphRenderDebug] symbol=\(currentConfiguration.symbol) action=draw_skipped reason=missing_path"
                )
                showPlaceholder(
                    path: placeholderPath,
                    isUnavailable: false
                )
                lastRenderSignature = renderSignature
                return
            }

            strokeLayer.path = graphPath
            strokeLayer.strokeColor = (currentConfiguration.isUp ? UIColor(Color.up) : UIColor(Color.down)).cgColor
            strokeLayer.opacity = currentConfiguration.visualState.strokeOpacity
            strokeLayer.isHidden = false
            placeholderFillLayer.isHidden = true
            placeholderBorderLayer.isHidden = true

            AppLogger.debug(
                .lifecycle,
                "[GraphRenderDebug] symbol=\(currentConfiguration.symbol) action=draw_started size=\(Int(bounds.width.rounded(.toNearestOrEven)))x\(Int(bounds.height.rounded(.toNearestOrEven))) pointCount=\(currentConfiguration.payload.pointCount)"
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
    let exchange: Exchange
    let symbol: String
    let width: CGFloat
    let height: CGFloat

    private let resolvedConfiguration: SparklineCanvasConfiguration

    init(
        payload: MarketSparklineRenderPayload,
        isUp: Bool,
        exchange: Exchange,
        symbol: String,
        width: CGFloat = 76,
        height: CGFloat = 20
    ) {
        let resolution = RetainedSparklineStore.shared.resolve(
            incoming: payload,
            exchange: exchange,
            symbol: symbol
        )

        self.payload = payload
        self.isUp = isUp
        self.exchange = exchange
        self.symbol = symbol
        self.width = width
        self.height = height
        self.resolvedConfiguration = SparklineCanvasConfiguration(
            payload: resolution.payload,
            visualState: resolution.visualState,
            isUp: isUp,
            exchange: exchange,
            symbol: symbol,
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
            && lhs.exchange == rhs.exchange
            && lhs.symbol == rhs.symbol
    }

    var body: some View {
        SparklineCanvasView(configuration: resolvedConfiguration)
            .frame(width: width, height: height)
    }
}
