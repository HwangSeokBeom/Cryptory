import CryptoKit
import SwiftUI
import UIKit

enum AssetImageLoadSource: String, Sendable {
    case memory
    case disk
    case network
}

enum AssetImageFallbackReason: String, Sendable {
    case requestInflight = "request_inflight"
    case noImageURL = "no_image_url"
    case aliasMiss = "alias_miss"
    case symbolNormalizationFailed = "symbol_normalization_failed"
    case marketIdentityMappingFailed = "market_identity_mapping_failed"
    case unsupportedAsset = "unsupported_asset"
    case fetchFailed = "fetch_failed"
    case cooldownBlocked = "cooldown_blocked"
    case missingCachedImage = "missing_cached_image"
}

enum AssetImageClientDebugAction: String, Sendable {
    case warmupStart = "warmup_start"
    case requestStart = "request_start"
    case cacheHitMemory = "cache_hit_memory"
    case cacheHitDisk = "cache_hit_disk"
    case requestDeduped = "request_deduped"
    case placeholderApplied = "placeholder_applied"
    case placeholderFinal = "placeholder_final"
    case imageApplied = "image_applied"
    case liveImageApplied = "live_image_applied"
    case imageLoadFailed = "image_load_failed"
    case reuseCancelled = "reuse_cancelled"
    case visibleRowPatch = "visible_row_patch"
    case batchedVisiblePatch = "batched_visible_patch"
    case prefetchStart = "prefetch_start"
    case coverageSummary = "coverage_summary"
}

final class AssetImageDebugClient: @unchecked Sendable {
    nonisolated static let shared = AssetImageDebugClient()

    private let lock = NSLock()
    nonisolated(unsafe) private var eventCounts: [AssetImageClientDebugAction: Int] = [:]
    nonisolated(unsafe) private var fallbackReasonCounts: [AssetImageFallbackReason: Int] = [:]

    nonisolated func log(
        _ action: AssetImageClientDebugAction,
        marketIdentity: MarketIdentity?,
        category: AppLogCategory = .lifecycle,
        details: [String: String] = [:]
    ) {
        lock.withLock {
            eventCounts[action, default: 0] += 1
            if action == .placeholderFinal,
               let reasonValue = details["reason"],
               let reason = AssetImageFallbackReason(rawValue: reasonValue) {
                fallbackReasonCounts[reason, default: 0] += 1
            }
        }
        if action == .placeholderFinal {
            MarketPerformanceDebugClient.shared.increment(.placeholderFinal)
            if details["reason"] == AssetImageFallbackReason.noImageURL.rawValue {
                MarketPerformanceDebugClient.shared.increment(.noImageURL)
            }
        }

        let sortedDetails = details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let suffix = sortedDetails.isEmpty ? "" : " \(sortedDetails)"
        AppLogger.debug(
            category,
            "[AssetImageClientDebug] \(marketIdentity?.logFields ?? "exchange=- marketId=- symbol=-") action=\(action.rawValue)\(suffix)"
        )
    }

    nonisolated func reset() {
        lock.withLock {
            eventCounts.removeAll(keepingCapacity: true)
            fallbackReasonCounts.removeAll(keepingCapacity: true)
        }
    }

    nonisolated func snapshotEventCounts() -> [String: Int] {
        lock.withLock {
            Dictionary(uniqueKeysWithValues: eventCounts.map { ($0.key.rawValue, $0.value) })
        }
    }

    nonisolated func snapshotFallbackReasonCounts() -> [String: Int] {
        lock.withLock {
            Dictionary(uniqueKeysWithValues: fallbackReasonCounts.map { ($0.key.rawValue, $0.value) })
        }
    }
}

struct AssetImageRequestOutcome {
    let state: MarketRowSymbolImageState
    let assetState: AssetImageState
    let source: AssetImageLoadSource?
    let fallbackReason: AssetImageFallbackReason?
}

enum AssetImageRequestMode: Equatable, Sendable {
    case warmup
    case visible
    case prefetch

    nonisolated var triggerValue: String {
        switch self {
        case .warmup:
            return "warmup"
        case .visible:
            return "visible"
        case .prefetch:
            return "prefetch"
        }
    }
}

private enum AssetImageClientError: Error {
    case invalidResponse
    case decodeFailed
}

enum AssetImageState: String, Equatable, Sendable {
    case idle
    case warming
    case placeholderPending
    case liveCached
    case liveNetwork
    case placeholderFinal

    nonisolated var rowState: MarketRowSymbolImageState {
        switch self {
        case .idle, .warming, .placeholderPending:
            return .placeholder
        case .liveCached:
            return .cached
        case .liveNetwork:
            return .live
        case .placeholderFinal:
            return .missing
        }
    }
}

struct AssetImageRequestHandle {
    let immediateOutcome: AssetImageRequestOutcome?
    let task: Task<AssetImageRequestOutcome, Never>?

    nonisolated var outcomeTask: Task<AssetImageRequestOutcome, Never>? {
        if let task {
            return task
        }
        guard let immediateOutcome else {
            return nil
        }
        return Task { immediateOutcome }
    }
}

final class AssetImageClient: @unchecked Sendable {
    nonisolated static let shared = AssetImageClient(namespace: "shared")

    private let lock = NSLock()
    nonisolated(unsafe) private let memoryCache = NSCache<NSURL, UIImage>()
    nonisolated(unsafe) private let symbolMemoryCache = NSCache<NSString, UIImage>()
    nonisolated(unsafe) private let fileManager = FileManager.default
    private let diskCacheDirectoryURL: URL
    private let failureCooldown: TimeInterval

    nonisolated(unsafe) private var sourceByURL: [URL: AssetImageLoadSource] = [:]
    nonisolated(unsafe) private var sourceByCanonicalSymbol: [String: AssetImageLoadSource] = [:]
    nonisolated(unsafe) private var stateByRequestKey: [String: AssetImageState] = [:]
    nonisolated(unsafe) private var fallbackReasonByRequestKey: [String: AssetImageFallbackReason] = [:]
    nonisolated(unsafe) private var inFlightTasks: [URL: Task<AssetImageRequestOutcome, Never>] = [:]
    nonisolated(unsafe) private var failureCooldownUntilByURL: [URL: Date] = [:]

    nonisolated init(
        namespace: String = UUID().uuidString,
        failureCooldown: TimeInterval = 90
    ) {
        let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.diskCacheDirectoryURL = cachesDirectory
            .appendingPathComponent("CryptoryAssetImages", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
        self.failureCooldown = failureCooldown

        try? FileManager.default.createDirectory(
            at: diskCacheDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    nonisolated func renderState(for descriptor: AssetImageRequestDescriptor) -> MarketRowSymbolImageState {
        assetState(for: descriptor).rowState
    }

    nonisolated func assetState(for descriptor: AssetImageRequestDescriptor) -> AssetImageState {
        if descriptor.hasImage == false {
            recordPlaceholderFinal(for: descriptor, reason: .unsupportedAsset)
            return .placeholderFinal
        }

        if let url = descriptor.normalizedImageURL {
            let requestKey = requestStateKey(for: descriptor)
            if lock.withLock({ memoryCache.object(forKey: url as NSURL) }) != nil {
                return cachedAssetState(for: requestKey)
            }
            if diskCachedImage(for: url, descriptor: descriptor, shouldLog: false) != nil {
                recordAssetState(.liveCached, for: descriptor)
                return .liveCached
            }
            if cachedSymbolImage(for: descriptor) != nil {
                recordAssetState(.liveCached, for: descriptor)
                return .liveCached
            }
            if lock.withLock({ inFlightTasks[url] != nil }) {
                recordAssetState(.placeholderPending, for: descriptor)
                return .placeholderPending
            }
            if isCoolingDown(url: url) {
                recordPlaceholderFinal(for: descriptor, reason: .cooldownBlocked)
                return .placeholderFinal
            }
            return .placeholderPending
        }

        if cachedSymbolImage(for: descriptor) != nil {
            recordAssetState(.liveCached, for: descriptor)
            return .liveCached
        }

        recordPlaceholderFinal(for: descriptor, reason: missingURLReason(for: descriptor))
        return .placeholderFinal
    }

    nonisolated func cachedImage(for descriptor: AssetImageRequestDescriptor) -> UIImage? {
        if let url = descriptor.normalizedImageURL {
            if let image = lock.withLock({ memoryCache.object(forKey: url as NSURL) }) {
                cacheSymbolImage(image, descriptor: descriptor, source: sourceByURLValue(for: url) ?? .memory)
                return image
            }
            if let image = diskCachedImage(for: url, descriptor: descriptor, shouldLog: false) {
                return image
            }
        }

        guard descriptor.hasImage != false else {
            return nil
        }
        return cachedSymbolImage(for: descriptor)
    }

    nonisolated func source(for descriptor: AssetImageRequestDescriptor) -> AssetImageLoadSource? {
        if let url = descriptor.normalizedImageURL {
            if lock.withLock({ memoryCache.object(forKey: url as NSURL) }) != nil {
                return .memory
            }
            if let source = sourceByURLValue(for: url) {
                return source
            }
        }
        return lock.withLock {
            sourceByCanonicalSymbol[symbolCacheKey(for: descriptor)]
        }
    }

    nonisolated func fallbackReason(for descriptor: AssetImageRequestDescriptor) -> AssetImageFallbackReason {
        let requestKey = requestStateKey(for: descriptor)
        if let reason = lock.withLock({ fallbackReasonByRequestKey[requestKey] }) {
            return reason
        }

        if descriptor.hasImage == false {
            return .unsupportedAsset
        }
        guard let url = descriptor.normalizedImageURL else {
            return missingURLReason(for: descriptor)
        }
        if lock.withLock({ inFlightTasks[url] != nil }) {
            return .requestInflight
        }
        if isCoolingDown(url: url) {
            return .cooldownBlocked
        }
        return .requestInflight
    }

    nonisolated func prepareImageRequest(
        for descriptor: AssetImageRequestDescriptor,
        mode: AssetImageRequestMode
    ) -> AssetImageRequestHandle {
        if mode == .prefetch {
            AssetImageDebugClient.shared.log(
                .prefetchStart,
                marketIdentity: descriptor.marketIdentity,
                category: .network,
                details: [
                    "symbol": descriptor.canonicalSymbol,
                    "trigger": mode.triggerValue
                ]
            )
        }

        if descriptor.hasImage == false {
            recordPlaceholderFinal(for: descriptor, reason: .unsupportedAsset)
            return AssetImageRequestHandle(
                immediateOutcome: outcome(
                    assetState: .placeholderFinal,
                    source: nil,
                    fallbackReason: .unsupportedAsset
                ),
                task: nil
            )
        }

        guard let url = descriptor.normalizedImageURL else {
            if cachedSymbolImage(for: descriptor) != nil {
                recordAssetState(.liveCached, for: descriptor)
                return AssetImageRequestHandle(
                    immediateOutcome: outcome(
                        assetState: .liveCached,
                        source: source(for: descriptor) ?? .memory,
                        fallbackReason: nil
                    ),
                    task: nil
                )
            }

            let reason = missingURLReason(for: descriptor)
            recordPlaceholderFinal(for: descriptor, reason: reason)
            return AssetImageRequestHandle(
                immediateOutcome: outcome(
                    assetState: .placeholderFinal,
                    source: nil,
                    fallbackReason: reason
                ),
                task: nil
            )
        }

        let requestKey = requestStateKey(for: descriptor)
        if let image = lock.withLock({ memoryCache.object(forKey: url as NSURL) }) {
            cacheSymbolImage(image, descriptor: descriptor, source: sourceByURLValue(for: url) ?? .memory)
            let assetState = cachedAssetState(for: requestKey)
            AssetImageDebugClient.shared.log(
                .cacheHitMemory,
                marketIdentity: descriptor.marketIdentity,
                category: .network,
                details: ["symbol": descriptor.canonicalSymbol]
            )
            recordAssetState(assetState, for: descriptor)
            return AssetImageRequestHandle(
                immediateOutcome: outcome(
                    assetState: assetState,
                    source: .memory,
                    fallbackReason: nil
                ),
                task: nil
            )
        }

        if diskCachedImage(for: url, descriptor: descriptor, shouldLog: true) != nil {
            recordAssetState(.liveCached, for: descriptor)
            return AssetImageRequestHandle(
                immediateOutcome: outcome(
                    assetState: .liveCached,
                    source: .disk,
                    fallbackReason: nil
                ),
                task: nil
            )
        }

        if cachedSymbolImage(for: descriptor) != nil {
            AssetImageDebugClient.shared.log(
                .cacheHitMemory,
                marketIdentity: descriptor.marketIdentity,
                category: .network,
                details: [
                    "symbol": descriptor.canonicalSymbol,
                    "scope": "canonical"
                ]
            )
            recordAssetState(.liveCached, for: descriptor)
            return AssetImageRequestHandle(
                immediateOutcome: outcome(
                    assetState: .liveCached,
                    source: source(for: descriptor) ?? .memory,
                    fallbackReason: nil
                ),
                task: nil
            )
        }

        if isCoolingDown(url: url) {
            recordPlaceholderFinal(for: descriptor, reason: .cooldownBlocked)
            return AssetImageRequestHandle(
                immediateOutcome: outcome(
                    assetState: .placeholderFinal,
                    source: nil,
                    fallbackReason: .cooldownBlocked
                ),
                task: nil
            )
        }

        if let existingTask = lock.withLock({ inFlightTasks[url] }) {
            recordAssetState(.placeholderPending, for: descriptor)
            AssetImageDebugClient.shared.log(
                .requestDeduped,
                marketIdentity: descriptor.marketIdentity,
                category: .network,
                details: [
                    "symbol": descriptor.canonicalSymbol,
                    "trigger": mode.triggerValue
                ]
            )
            return AssetImageRequestHandle(immediateOutcome: nil, task: existingTask)
        }

        recordAssetState(.warming, for: descriptor)
        AssetImageDebugClient.shared.log(
            .requestStart,
            marketIdentity: descriptor.marketIdentity,
            category: .network,
            details: [
                "assetState": AssetImageState.warming.rawValue,
                "symbol": descriptor.canonicalSymbol,
                "trigger": mode.triggerValue
            ]
        )

        let task = Task<AssetImageRequestOutcome, Never> { [weak self] in
            guard let self else {
                return AssetImageRequestOutcome(
                    state: .placeholder,
                    assetState: .placeholderPending,
                    source: nil,
                    fallbackReason: .requestInflight
                )
            }

            defer {
                self.clearInFlightTask(for: url)
            }

            do {
                let data = try await self.loadImageData(from: url)
                guard let image = UIImage(data: data) else {
                    throw AssetImageClientError.decodeFailed
                }
                self.store(image: image, data: data, for: url, descriptor: descriptor, source: .network)
                self.recordAssetState(.liveNetwork, for: descriptor)
                return self.outcome(
                    assetState: .liveNetwork,
                    source: .network,
                    fallbackReason: nil
                )
            } catch {
                self.recordFailure(for: url)
                self.recordPlaceholderFinal(for: descriptor, reason: .fetchFailed)
                AssetImageDebugClient.shared.log(
                    .imageLoadFailed,
                    marketIdentity: descriptor.marketIdentity,
                    category: .network,
                    details: [
                        "reason": AssetImageFallbackReason.fetchFailed.rawValue,
                        "symbol": descriptor.canonicalSymbol
                    ]
                )
                return self.outcome(
                    assetState: .placeholderFinal,
                    source: nil,
                    fallbackReason: .fetchFailed
                )
            }
        }

        lock.withLock {
            inFlightTasks[url] = task
        }
        return AssetImageRequestHandle(immediateOutcome: nil, task: task)
    }

    nonisolated func requestImage(
        for descriptor: AssetImageRequestDescriptor,
        mode: AssetImageRequestMode
    ) async -> AssetImageRequestOutcome {
        let handle = prepareImageRequest(for: descriptor, mode: mode)
        if let immediateOutcome = handle.immediateOutcome {
            return immediateOutcome
        }
        if let task = handle.task {
            return await task.value
        }
        return outcome(
            assetState: .placeholderPending,
            source: nil,
            fallbackReason: .requestInflight
        )
    }

    nonisolated func debugReset() {
        let runningTasks = lock.withLock { () -> [Task<AssetImageRequestOutcome, Never>] in
            let tasks = Array(inFlightTasks.values)
            inFlightTasks.removeAll()
            sourceByURL.removeAll()
            sourceByCanonicalSymbol.removeAll()
            stateByRequestKey.removeAll()
            fallbackReasonByRequestKey.removeAll()
            failureCooldownUntilByURL.removeAll()
            memoryCache.removeAllObjects()
            symbolMemoryCache.removeAllObjects()
            return tasks
        }

        runningTasks.forEach { $0.cancel() }
        try? fileManager.removeItem(at: diskCacheDirectoryURL)
        try? fileManager.createDirectory(
            at: diskCacheDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private nonisolated func loadImageData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw AssetImageClientError.invalidResponse
        }
        return data
    }

    private nonisolated func diskCachedImage(
        for url: URL,
        descriptor: AssetImageRequestDescriptor?,
        shouldLog: Bool
    ) -> UIImage? {
        let cacheURL = diskCacheFileURL(for: url)
        guard let data = try? Data(contentsOf: cacheURL),
              let image = UIImage(data: data) else {
            return nil
        }

        lock.withLock {
            memoryCache.setObject(image, forKey: url as NSURL)
            if sourceByURL[url] == nil {
                sourceByURL[url] = .disk
            }
            if let descriptor {
                let symbolKey = symbolCacheKey(for: descriptor)
                symbolMemoryCache.setObject(image, forKey: symbolKey as NSString)
                if sourceByCanonicalSymbol[symbolKey] == nil {
                    sourceByCanonicalSymbol[symbolKey] = .disk
                }
            }
        }

        if shouldLog {
            AssetImageDebugClient.shared.log(
                .cacheHitDisk,
                marketIdentity: descriptor?.marketIdentity,
                category: .network,
                details: ["symbol": descriptor?.canonicalSymbol ?? "-"]
            )
        }
        return image
    }

    private nonisolated func store(
        image: UIImage,
        data: Data,
        for url: URL,
        descriptor: AssetImageRequestDescriptor,
        source: AssetImageLoadSource
    ) {
        lock.withLock {
            memoryCache.setObject(image, forKey: url as NSURL)
            sourceByURL[url] = source
            let symbolKey = symbolCacheKey(for: descriptor)
            symbolMemoryCache.setObject(image, forKey: symbolKey as NSString)
            sourceByCanonicalSymbol[symbolKey] = source
            failureCooldownUntilByURL[url] = nil
        }

        let fileURL = diskCacheFileURL(for: url)
        Task.detached(priority: .utility) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private nonisolated func recordFailure(for url: URL) {
        let cooldownUntil = Date().addingTimeInterval(failureCooldown)
        lock.withLock {
            failureCooldownUntilByURL[url] = cooldownUntil
            pruneFailures(now: Date())
        }
    }

    private nonisolated func isCoolingDown(url: URL) -> Bool {
        lock.withLock {
            pruneFailures(now: Date())
            guard let cooldownUntil = failureCooldownUntilByURL[url] else {
                return false
            }
            return cooldownUntil > Date()
        }
    }

    private nonisolated func pruneFailures(now: Date) {
        failureCooldownUntilByURL = failureCooldownUntilByURL.filter { $0.value > now }
    }

    private nonisolated func outcome(
        assetState: AssetImageState,
        source: AssetImageLoadSource?,
        fallbackReason: AssetImageFallbackReason?
    ) -> AssetImageRequestOutcome {
        AssetImageRequestOutcome(
            state: assetState.rowState,
            assetState: assetState,
            source: source,
            fallbackReason: fallbackReason
        )
    }

    private nonisolated func cachedAssetState(for requestKey: String) -> AssetImageState {
        let storedState = lock.withLock { stateByRequestKey[requestKey] }
        return storedState == .liveNetwork ? .liveNetwork : .liveCached
    }

    private nonisolated func recordAssetState(
        _ state: AssetImageState,
        for descriptor: AssetImageRequestDescriptor
    ) {
        let requestKey = requestStateKey(for: descriptor)
        lock.withLock {
            stateByRequestKey[requestKey] = state
            if state != .placeholderFinal {
                fallbackReasonByRequestKey[requestKey] = nil
            }
        }
    }

    private nonisolated func recordPlaceholderFinal(
        for descriptor: AssetImageRequestDescriptor,
        reason: AssetImageFallbackReason
    ) {
        let requestKey = requestStateKey(for: descriptor)
        let shouldLog = lock.withLock { () -> Bool in
            let didChange = stateByRequestKey[requestKey] != .placeholderFinal
                || fallbackReasonByRequestKey[requestKey] != reason
            stateByRequestKey[requestKey] = .placeholderFinal
            fallbackReasonByRequestKey[requestKey] = reason
            return didChange
        }

        guard shouldLog else {
            return
        }

        AssetImageDebugClient.shared.log(
            .placeholderFinal,
            marketIdentity: descriptor.marketIdentity,
            category: .network,
            details: [
                "reason": reason.rawValue,
                "state": AssetImageState.placeholderFinal.rawValue,
                "symbol": descriptor.canonicalSymbol
            ]
        )
    }

    private nonisolated func clearInFlightTask(for url: URL) {
        lock.withLock {
            inFlightTasks[url] = nil
        }
    }

    private nonisolated func sourceByURLValue(for url: URL) -> AssetImageLoadSource? {
        lock.withLock {
            sourceByURL[url]
        }
    }

    private nonisolated func cachedSymbolImage(for descriptor: AssetImageRequestDescriptor) -> UIImage? {
        let symbolKey = symbolCacheKey(for: descriptor)
        return lock.withLock {
            symbolMemoryCache.object(forKey: symbolKey as NSString)
        }
    }

    private nonisolated func cacheSymbolImage(
        _ image: UIImage,
        descriptor: AssetImageRequestDescriptor,
        source: AssetImageLoadSource
    ) {
        let symbolKey = symbolCacheKey(for: descriptor)
        lock.withLock {
            symbolMemoryCache.setObject(image, forKey: symbolKey as NSString)
            if sourceByCanonicalSymbol[symbolKey] == nil || source == .network {
                sourceByCanonicalSymbol[symbolKey] = source
            }
        }
    }

    private nonisolated func requestStateKey(for descriptor: AssetImageRequestDescriptor) -> String {
        if let url = descriptor.normalizedImageURL {
            return "url:\(url.absoluteString)"
        }
        return "symbol:\(symbolCacheKey(for: descriptor))|\(descriptor.marketIdentity.cacheKey)"
    }

    private nonisolated func symbolCacheKey(for descriptor: AssetImageRequestDescriptor) -> String {
        descriptor.canonicalSymbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private nonisolated func missingURLReason(for descriptor: AssetImageRequestDescriptor) -> AssetImageFallbackReason {
        let rawValue = descriptor.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if descriptor.hasImage == false {
            return .unsupportedAsset
        }
        if descriptor.canonicalSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .symbolNormalizationFailed
        }
        if Self.looksLikePairSymbol(descriptor.symbol),
           descriptor.canonicalSymbol == descriptor.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            return .symbolNormalizationFailed
        }
        if let marketId = descriptor.marketIdentity.marketId,
           marketId == descriptor.marketIdentity.symbol,
           Self.looksLikePairSymbol(marketId) {
            return .marketIdentityMappingFailed
        }
        if rawValue == nil || rawValue?.isEmpty == true {
            return .noImageURL
        }
        return .aliasMiss
    }

    private nonisolated static func looksLikePairSymbol(_ rawValue: String) -> Bool {
        let normalizedValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard normalizedValue.isEmpty == false else {
            return false
        }
        if normalizedValue.contains("-") || normalizedValue.contains("_") || normalizedValue.contains("/") || normalizedValue.contains(":") {
            return true
        }
        for quoteCurrency in ["KRW", "USDT", "USD", "BTC", "ETH"] {
            if normalizedValue.hasPrefix(quoteCurrency), normalizedValue.count > quoteCurrency.count {
                return true
            }
            if normalizedValue.hasSuffix(quoteCurrency), normalizedValue.count > quoteCurrency.count {
                return true
            }
        }
        return false
    }

    private nonisolated func diskCacheFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined()
        return diskCacheDirectoryURL.appendingPathComponent(fileName).appendingPathExtension("img")
    }
}

struct SymbolImageConfiguration: Equatable {
    let descriptor: AssetImageRequestDescriptor
    let state: MarketRowSymbolImageState
    let size: CGFloat
}

enum SymbolImageRenderDebugState: Equatable {
    case idle
    case success
    case fallback(String)
}

final class SymbolImageRenderView: UIView {
    private let imageView = UIImageView()
    private let fallbackView = UIView()
    private let fallbackGradientLayer = CAGradientLayer()
    private let fallbackLabel = UILabel()

    private var currentConfiguration: SymbolImageConfiguration?
    private var currentDebugState: SymbolImageRenderDebugState = .idle

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        fallbackGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        fallbackGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        fallbackView.layer.addSublayer(fallbackGradientLayer)

        fallbackLabel.textAlignment = .center
        fallbackLabel.textColor = UIColor(Color.themeText)
        fallbackLabel.adjustsFontSizeToFitWidth = true
        fallbackLabel.minimumScaleFactor = 0.65
        fallbackView.addSubview(fallbackLabel)

        addSubview(fallbackView)
        addSubview(imageView)
        layer.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var debugState: SymbolImageRenderDebugState {
        currentDebugState
    }

    var debugPlaceholderText: String {
        fallbackLabel.text ?? ""
    }

    var debugEventCounts: [String: Int] {
        AssetImageDebugClient.shared.snapshotEventCounts()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        fallbackView.frame = bounds
        fallbackGradientLayer.frame = fallbackView.bounds
        imageView.frame = bounds
        fallbackLabel.frame = fallbackView.bounds.insetBy(dx: max(2, bounds.width * 0.08), dy: 0)

        let cornerRadius = min(bounds.width, bounds.height) * 0.5
        fallbackView.layer.cornerRadius = cornerRadius
        fallbackView.layer.masksToBounds = true
        imageView.layer.cornerRadius = cornerRadius
        imageView.layer.masksToBounds = true
        layer.cornerRadius = cornerRadius
    }

    func apply(configuration: SymbolImageConfiguration) {
        let previousConfiguration = currentConfiguration
        if previousConfiguration == configuration {
            if configuration.state.showsRenderedImage, imageView.image != nil {
                return
            }
            if configuration.state.showsRenderedImage == false, imageView.image == nil {
                return
            }
        }

        if shouldReset(previousConfiguration: previousConfiguration, nextConfiguration: configuration) {
            AssetImageDebugClient.shared.log(
                .reuseCancelled,
                marketIdentity: previousConfiguration?.descriptor.marketIdentity ?? configuration.descriptor.marketIdentity,
                details: ["symbol": previousConfiguration?.descriptor.canonicalSymbol ?? configuration.descriptor.canonicalSymbol]
            )
            resetVisuals()
        }

        currentConfiguration = configuration
        applyFallbackBranding(for: configuration)

        switch configuration.state {
        case .cached, .live:
            guard let image = AssetImageClient.shared.cachedImage(for: configuration.descriptor) else {
                showFallback(reason: .missingCachedImage)
                return
            }
            renderImage(
                image,
                source: AssetImageClient.shared.source(for: configuration.descriptor),
                state: configuration.state
            )
        case .missing:
            showFallback(reason: AssetImageClient.shared.fallbackReason(for: configuration.descriptor))
        case .placeholder:
            showFallback(reason: AssetImageClient.shared.fallbackReason(for: configuration.descriptor))
        }
    }

    func prepareForReuse() {
        guard let configuration = currentConfiguration else {
            resetVisuals()
            return
        }

        AssetImageDebugClient.shared.log(
            .reuseCancelled,
            marketIdentity: configuration.descriptor.marketIdentity,
            details: ["symbol": configuration.descriptor.canonicalSymbol]
        )
        currentConfiguration = nil
        imageView.layer.removeAllAnimations()
        fallbackView.layer.removeAllAnimations()
        if imageView.image == nil {
            resetVisuals()
        }
    }

    func debugApply(
        marketIdentity: MarketIdentity,
        symbol: String,
        imageURL: String?,
        hasImage: Bool? = nil,
        symbolImageState: MarketRowSymbolImageState? = nil,
        size: CGFloat
    ) {
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: symbol,
            canonicalSymbol: SymbolNormalization.canonicalAssetCode(rawSymbol: symbol),
            imageURL: imageURL,
            hasImage: hasImage,
            localAssetName: SymbolNormalization.localAssetName(
                for: SymbolNormalization.canonicalAssetCode(rawSymbol: symbol)
            )
        )
        apply(
            configuration: SymbolImageConfiguration(
                descriptor: descriptor,
                state: symbolImageState ?? AssetImageClient.shared.renderState(for: descriptor),
                size: size
            )
        )
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func renderImage(
        _ image: UIImage,
        source: AssetImageLoadSource?,
        state: MarketRowSymbolImageState
    ) {
        let applyImage = {
            self.imageView.image = image
            self.imageView.isHidden = false
            self.fallbackView.isHidden = true
        }

        if state == .live, source == .network, fallbackView.isHidden == false {
            UIView.transition(
                with: self,
                duration: 0.08,
                options: [.transitionCrossDissolve, .allowAnimatedContent],
                animations: applyImage
            )
        } else {
            applyImage()
        }

        layer.borderColor = UIColor(Color.themeBorder.opacity(0.4)).cgColor
        currentDebugState = .success
        AssetImageDebugClient.shared.log(
            .imageApplied,
            marketIdentity: currentConfiguration?.descriptor.marketIdentity,
            details: [
                "source": source?.rawValue ?? "memory",
                "state": state.rawValue,
                "symbol": currentConfiguration?.descriptor.canonicalSymbol ?? "-"
            ]
        )
        if state == .live {
            AssetImageDebugClient.shared.log(
                .liveImageApplied,
                marketIdentity: currentConfiguration?.descriptor.marketIdentity,
                details: [
                    "source": source?.rawValue ?? "network",
                    "symbol": currentConfiguration?.descriptor.canonicalSymbol ?? "-"
                ]
            )
        }
    }

    private func showFallback(reason: AssetImageFallbackReason) {
        imageView.image = nil
        imageView.isHidden = true
        fallbackView.isHidden = false
        layer.borderColor = UIColor(Color.themeBorder.opacity(0.65)).cgColor
        currentDebugState = .fallback(reason.rawValue)
        AssetImageDebugClient.shared.log(
            .placeholderApplied,
            marketIdentity: currentConfiguration?.descriptor.marketIdentity,
            details: [
                "reason": reason.rawValue,
                "symbol": currentConfiguration?.descriptor.canonicalSymbol ?? "-",
                "symbolText": fallbackLabel.text ?? "-"
            ]
        )
    }

    private func applyFallbackBranding(for configuration: SymbolImageConfiguration) {
        let symbolText = configuration.descriptor.placeholderText
        fallbackLabel.text = symbolText
        fallbackLabel.font = UIFont.systemFont(
            ofSize: max(
                symbolText.count > 1 ? 8 : 11,
                configuration.size * (symbolText.count > 1 ? 0.34 : 0.44)
            ),
            weight: .heavy
        )

        let accentColor = UIColor(configuration.descriptor.marketIdentity.exchange.color)
        fallbackGradientLayer.colors = [
            accentColor.withAlphaComponent(0.38).cgColor,
            UIColor(Color.bgSecondary).withAlphaComponent(0.96).cgColor
        ]
        fallbackGradientLayer.locations = [0, 1]
    }

    private func shouldReset(
        previousConfiguration: SymbolImageConfiguration?,
        nextConfiguration: SymbolImageConfiguration
    ) -> Bool {
        guard let previousConfiguration else {
            return false
        }

        return previousConfiguration.descriptor != nextConfiguration.descriptor
            || previousConfiguration.state != nextConfiguration.state
    }

    private func resetVisuals() {
        imageView.layer.removeAllAnimations()
        fallbackView.layer.removeAllAnimations()
        imageView.image = nil
        imageView.isHidden = true
        fallbackView.isHidden = false
        layer.borderColor = UIColor(Color.themeBorder.opacity(0.65)).cgColor
        currentDebugState = .idle
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

    static func dismantleUIView(_ uiView: SymbolImageRenderView, coordinator: ()) {
        uiView.prepareForReuse()
    }
}

struct SymbolImageView: View, Equatable {
    let descriptor: AssetImageRequestDescriptor
    let state: MarketRowSymbolImageState
    let size: CGFloat

    init(
        marketIdentity: MarketIdentity,
        symbol: String,
        canonicalSymbol: String? = nil,
        imageURL: String?,
        hasImage: Bool? = nil,
        localAssetName: String? = nil,
        symbolImageState: MarketRowSymbolImageState,
        size: CGFloat
    ) {
        self.descriptor = AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: symbol,
            canonicalSymbol: canonicalSymbol ?? SymbolNormalization.canonicalAssetCode(rawSymbol: symbol),
            imageURL: imageURL,
            hasImage: hasImage,
            localAssetName: localAssetName ?? SymbolNormalization.localAssetName(
                for: canonicalSymbol ?? SymbolNormalization.canonicalAssetCode(rawSymbol: symbol)
            )
        )
        self.state = symbolImageState
        self.size = size
    }

    static func == (lhs: SymbolImageView, rhs: SymbolImageView) -> Bool {
        lhs.descriptor == rhs.descriptor
            && lhs.state == rhs.state
            && lhs.size == rhs.size
    }

    var body: some View {
        SymbolImageCanvasView(
            configuration: SymbolImageConfiguration(
                descriptor: descriptor,
                state: state,
                size: size
            )
        )
        .frame(width: size, height: size)
        .clipped()
        .accessibilityLabel(Text("\(descriptor.canonicalSymbol) icon"))
    }
}
