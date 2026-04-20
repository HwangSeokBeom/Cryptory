import SwiftUI
import UIKit

private enum SymbolImageLoadSource: String {
    case memory
    case disk
    case network
}

private enum SymbolImageFallbackReason: String {
    case nilURL = "nil_url"
    case decodeFailed = "decode_failed"
    case layoutZero = "layout_zero"
}

private struct SymbolImageLoadResult {
    let image: UIImage?
    let source: SymbolImageLoadSource
    let fallbackReason: SymbolImageFallbackReason?
}

private final class SymbolImagePipeline {
    static let shared = SymbolImagePipeline()

    private let lock = NSLock()
    private let memoryCache = NSCache<NSURL, UIImage>()
    private var inFlightTasks: [URL: Task<SymbolImageLoadResult, Never>] = [:]

    func predictedSource(for url: URL) -> SymbolImageLoadSource {
        if cachedImage(for: url) != nil {
            return .memory
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        if URLCache.shared.cachedResponse(for: request) != nil {
            return .disk
        }
        return .network
    }

    func cachedImage(for url: URL) -> UIImage? {
        lock.withLock {
            memoryCache.object(forKey: url as NSURL)
        }
    }

    func loadImage(from url: URL) async -> SymbolImageLoadResult {
        if let cachedImage = cachedImage(for: url) {
            return SymbolImageLoadResult(
                image: cachedImage,
                source: .memory,
                fallbackReason: nil
            )
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        if let cachedResponse = URLCache.shared.cachedResponse(for: request) {
            if let cachedImage = UIImage(data: cachedResponse.data) {
                lock.withLock {
                    memoryCache.setObject(cachedImage, forKey: url as NSURL)
                }
                return SymbolImageLoadResult(
                    image: cachedImage,
                    source: .disk,
                    fallbackReason: nil
                )
            }
            URLCache.shared.removeCachedResponse(for: request)
            return SymbolImageLoadResult(
                image: nil,
                source: .disk,
                fallbackReason: .decodeFailed
            )
        }

        if let existingTask = lock.withLock({ inFlightTasks[url] }) {
            return await existingTask.value
        }

        let task = Task<SymbolImageLoadResult, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   (200..<300).contains(httpResponse.statusCode) == false {
                    return SymbolImageLoadResult(
                        image: nil,
                        source: .network,
                        fallbackReason: .decodeFailed
                    )
                }
                guard let image = UIImage(data: data) else {
                    return SymbolImageLoadResult(
                        image: nil,
                        source: .network,
                        fallbackReason: .decodeFailed
                    )
                }
                return SymbolImageLoadResult(
                    image: image,
                    source: .network,
                    fallbackReason: nil
                )
            } catch {
                return SymbolImageLoadResult(
                    image: nil,
                    source: .network,
                    fallbackReason: .decodeFailed
                )
            }
        }

        lock.withLock {
            inFlightTasks[url] = task
        }

        let result = await task.value
        lock.withLock {
            inFlightTasks[url] = nil
            if let image = result.image {
                memoryCache.setObject(image, forKey: url as NSURL)
            }
        }

        return result
    }
}

struct SymbolImageConfiguration: Equatable {
    let symbol: String
    let imageURL: String?
    let size: CGFloat
}

enum SymbolImageRenderDebugState: Equatable {
    case idle
    case loading
    case success
    case fallback(String)
}

final class SymbolImageRenderView: UIView {
    private let imageView = UIImageView()
    private let fallbackView = UIView()
    private let fallbackGradientLayer = CAGradientLayer()
    private let fallbackLabel = UILabel()

    private var currentConfiguration: SymbolImageConfiguration?
    private var activeURL: URL?
    private var imageTask: Task<Void, Never>?
    private var currentDebugState: SymbolImageRenderDebugState = .idle

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        clipsToBounds = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        fallbackGradientLayer.colors = [
            UIColor(Color.bgTertiary.opacity(0.95)).cgColor,
            UIColor(Color.bgSecondary.opacity(0.95)).cgColor
        ]
        fallbackGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        fallbackGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        fallbackView.layer.addSublayer(fallbackGradientLayer)

        fallbackLabel.textAlignment = .center
        fallbackLabel.textColor = UIColor(Color.themeText)
        fallbackLabel.font = UIFont.systemFont(ofSize: 12, weight: .heavy)
        fallbackView.addSubview(fallbackLabel)

        addSubview(fallbackView)
        addSubview(imageView)
        layer.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        imageTask?.cancel()
    }

    var debugState: SymbolImageRenderDebugState {
        currentDebugState
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        fallbackView.frame = bounds
        fallbackGradientLayer.frame = fallbackView.bounds
        imageView.frame = bounds
        fallbackLabel.frame = fallbackView.bounds

        let cornerRadius = bounds.width * 0.32
        fallbackView.layer.cornerRadius = cornerRadius
        fallbackView.layer.masksToBounds = true
        imageView.layer.cornerRadius = cornerRadius
        imageView.layer.masksToBounds = true
        layer.cornerRadius = cornerRadius
        layer.borderColor = UIColor(Color.themeBorder.opacity(imageView.image == nil ? 0.65 : 0.4)).cgColor

        if bounds.width == 0 || bounds.height == 0 {
            AppLogger.debug(
                .lifecycle,
                "[ImageDebug] symbol=\(currentConfiguration?.symbol ?? "<nil>") action=fallback reason=\(SymbolImageFallbackReason.layoutZero.rawValue)"
            )
        }
    }

    func apply(configuration: SymbolImageConfiguration) {
        let previousConfiguration = currentConfiguration
        currentConfiguration = configuration
        fallbackLabel.text = String(configuration.symbol.prefix(1)).uppercased()
        fallbackLabel.font = UIFont.systemFont(
            ofSize: max(12, configuration.size * 0.42),
            weight: .heavy
        )

        let normalizedURL = normalizedImageURL(from: configuration.imageURL)
        if previousConfiguration?.symbol != configuration.symbol
            || previousConfiguration?.imageURL != configuration.imageURL {
            imageTask?.cancel()
            activeURL = nil
        }

        guard let normalizedURL else {
            showFallback(reason: .nilURL)
            return
        }

        if activeURL == normalizedURL, imageView.image != nil {
            return
        }

        if activeURL == normalizedURL, imageTask != nil {
            return
        }

        activeURL = normalizedURL
        let loadSource = SymbolImagePipeline.shared.predictedSource(for: normalizedURL)
        currentDebugState = .loading
        AppLogger.debug(
            .network,
            "[ImageDebug] symbol=\(configuration.symbol) action=load_started source=\(loadSource.rawValue)"
        )

        imageTask = Task { [weak self] in
            guard let self else { return }
            let result = await SymbolImagePipeline.shared.loadImage(from: normalizedURL)
            guard !Task.isCancelled, activeURL == normalizedURL else {
                return
            }

            await MainActor.run {
                if let loadedImage = result.image {
                    self.renderImage(loadedImage)
                    AppLogger.debug(
                        .network,
                        "[ImageDebug] symbol=\(configuration.symbol) action=load_success"
                    )
                } else {
                    self.showFallback(reason: result.fallbackReason ?? .decodeFailed)
                }
            }
        }
    }

    private func renderImage(_ image: UIImage) {
        imageView.image = image
        imageView.isHidden = false
        fallbackView.isHidden = true
        layer.borderColor = UIColor(Color.themeBorder.opacity(0.4)).cgColor
        currentDebugState = .success

        if bounds.width > 0, bounds.height > 0 {
            AppLogger.debug(
                .lifecycle,
                "[ImageDebug] symbol=\(currentConfiguration?.symbol ?? "<nil>") action=render_success size=\(Int(bounds.width.rounded(.toNearestOrEven)))x\(Int(bounds.height.rounded(.toNearestOrEven)))"
            )
        } else {
            AppLogger.debug(
                .lifecycle,
                "[ImageDebug] symbol=\(currentConfiguration?.symbol ?? "<nil>") action=fallback reason=\(SymbolImageFallbackReason.layoutZero.rawValue)"
            )
        }
    }

    private func showFallback(reason: SymbolImageFallbackReason) {
        imageView.image = nil
        imageView.isHidden = true
        fallbackView.isHidden = false
        layer.borderColor = UIColor(Color.themeBorder.opacity(0.65)).cgColor
        currentDebugState = .fallback(reason.rawValue)
        AppLogger.debug(
            .lifecycle,
            "[ImageDebug] symbol=\(currentConfiguration?.symbol ?? "<nil>") action=fallback reason=\(reason.rawValue)"
        )
    }

    func debugApply(symbol: String, imageURL: String?, size: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        apply(
            configuration: SymbolImageConfiguration(
                symbol: symbol,
                imageURL: imageURL,
                size: size
            )
        )
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func normalizedImageURL(from rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }
        return URL(string: rawValue)
    }
}

private struct SymbolImageCanvasView: UIViewRepresentable, Equatable {
    let configuration: SymbolImageConfiguration

    func makeUIView(context: Context) -> SymbolImageRenderView {
        SymbolImageRenderView(frame: .zero)
    }

    func updateUIView(_ uiView: SymbolImageRenderView, context: Context) {
        uiView.apply(configuration: configuration)
    }
}

struct SymbolImageView: View, Equatable {
    let symbol: String
    let imageURL: String?
    let size: CGFloat

    static func == (lhs: SymbolImageView, rhs: SymbolImageView) -> Bool {
        lhs.symbol == rhs.symbol
            && lhs.imageURL == rhs.imageURL
            && lhs.size == rhs.size
    }

    var body: some View {
        SymbolImageCanvasView(
            configuration: SymbolImageConfiguration(
                symbol: symbol,
                imageURL: imageURL,
                size: size
            )
        )
        .frame(width: size, height: size)
    }
}

private extension NSLock {
    func withLock<T>(_ work: () -> T) -> T {
        lock()
        defer { unlock() }
        return work()
    }
}
