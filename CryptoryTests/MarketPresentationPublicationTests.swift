import UIKit
import XCTest
@testable import Cryptory

/// Forwards to a SpyMarketRepository but can suspend ticker fetches on an
/// explicit continuation gate, so overlapping-refresh interleavings are
/// scripted rather than timed.
private final class GatedMarketRepository: MarketRepositoryProtocol {
    let inner: SpyMarketRepository

    private struct Gate {
        var enabled = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let lock = NSLock()
    private var state = Gate()

    init(inner: SpyMarketRepository) {
        self.inner = inner
    }

    var marketCandlesEndpointPath: String { inner.marketCandlesEndpointPath }

    func enableTickerGate() {
        lock.lock()
        state.enabled = true
        lock.unlock()
    }

    var suspendedTickerFetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return state.waiters.count
    }

    /// Releases every suspended ticker fetch and reopens the gate.
    func releaseTickerFetches() {
        lock.lock()
        state.enabled = false
        let waiters = state.waiters
        state.waiters = []
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func passGate() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if state.enabled {
                state.waiters.append(continuation)
                lock.unlock()
            } else {
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func fetchMarkets(exchange: Exchange) async throws -> MarketCatalogSnapshot {
        try await inner.fetchMarkets(exchange: exchange)
    }

    func fetchTickers(exchange: Exchange) async throws -> MarketTickerSnapshot {
        await passGate()
        return try await inner.fetchTickers(exchange: exchange)
    }

    func fetchTickers(exchange: Exchange, quoteCurrency: MarketQuoteCurrency) async throws -> MarketTickerSnapshot {
        await passGate()
        return try await inner.fetchTickers(exchange: exchange, quoteCurrency: quoteCurrency)
    }

    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookSnapshot {
        try await inner.fetchOrderbook(symbol: symbol, exchange: exchange)
    }

    func fetchTrades(symbol: String, exchange: Exchange) async throws -> PublicTradesSnapshot {
        try await inner.fetchTrades(symbol: symbol, exchange: exchange)
    }

    func fetchCandles(symbol: String, exchange: Exchange, interval: String) async throws -> CandleSnapshot {
        try await inner.fetchCandles(symbol: symbol, exchange: exchange, interval: interval)
    }

    func fetchSparklines(
        marketIdentities: [MarketIdentity],
        exchange: Exchange,
        quoteCurrency: MarketQuoteCurrency,
        interval: String,
        limit: Int
    ) async throws -> [MarketIdentity: MarketSparklineSnapshot] {
        try await inner.fetchSparklines(
            marketIdentities: marketIdentities,
            exchange: exchange,
            quoteCurrency: quoteCurrency,
            interval: interval,
            limit: limit
        )
    }

    func fetchSparklines(
        marketIdentities: [MarketIdentity],
        exchange: Exchange,
        quoteCurrency: MarketQuoteCurrency,
        interval: String,
        limit: Int,
        priority: String?,
        timeout: TimeInterval?
    ) async throws -> [MarketIdentity: MarketSparklineSnapshot] {
        try await inner.fetchSparklines(
            marketIdentities: marketIdentities,
            exchange: exchange,
            quoteCurrency: quoteCurrency,
            interval: interval,
            limit: limit,
            priority: priority,
            timeout: timeout
        )
    }
}

/// MainActor-confined boolean flag for observing task completion without
/// polling or capturing mutable locals in a sendable closure.
@MainActor
private final class CompletionFlag {
    private(set) var value = false

    func set() { value = true }
}

/// Collects presentation-build gate continuations keyed by ownership token.
private final class BuildGateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UInt64: CheckedContinuation<Void, Never>] = [:]

    func hold(_ token: UInt64, _ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        continuations[token] = continuation
        lock.unlock()
    }

    func tokens() -> [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return Array(continuations.keys)
    }

    func release(_ token: UInt64) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: token)
        lock.unlock()
        continuation?.resume()
    }

    func releaseAll() {
        lock.lock()
        let all = Array(continuations.values)
        continuations = [:]
        lock.unlock()
        for continuation in all {
            continuation.resume()
        }
    }
}

/// Deterministic tests for the market presentation publication contract:
/// `refreshMarketData()` returns only after staged rows are published, only
/// the newest presentation build may publish (latest token wins), and a
/// superseded builder can never overwrite a newer generation's rows.
@MainActor
final class MarketPresentationPublicationTests: XCTestCase {
    private static func fixtureCoins(imageURL: String? = nil) -> [CoinInfo] {
        [
            CoinCatalog.coin(
                symbol: "BTC",
                exchange: .upbit,
                marketId: "KRW-BTC",
                baseAsset: "BTC",
                quoteAsset: "KRW",
                canonicalSymbol: "BTC",
                displaySymbol: "BTC",
                displayName: "Bitcoin",
                englishName: "Bitcoin",
                imageURL: imageURL,
                isTradable: true
            )
        ]
    }

    private func makeRepository(price: Double = 125_000_000, imageURL: String? = nil) -> SpyMarketRepository {
        let repository = SpyMarketRepository()
        repository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: Self.fixtureCoins(imageURL: imageURL),
            supportedIntervalsBySymbol: ["BTC": ["1h"]],
            meta: .empty
        )
        repository.tickerSnapshots[.upbit] = Self.tickerSnapshot(price: price, imageURL: imageURL)
        return repository
    }

    private static func tickerSnapshot(price: Double, imageURL: String? = nil) -> MarketTickerSnapshot {
        MarketTickerSnapshot(
            exchange: .upbit,
            coins: fixtureCoins(imageURL: imageURL),
            tickers: [
                "BTC": TickerData(
                    price: price,
                    change: 1.2,
                    volume: 100_000_000,
                    high24: price,
                    low24: price,
                    sparkline: [price, price],
                    hasServerSparkline: true
                )
            ],
            meta: .empty
        )
    }

    /// Local temp PNG so image assertions never depend on live DNS.
    private func makeTemporaryPNGURL() throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("publication-\(UUID().uuidString).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeViewModel(
        repository: MarketRepositoryProtocol,
        suiteName: String
    ) -> CryptoViewModel {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            publicContentRepository: SpyPublicContentRepository(),
            authService: StubAuthenticationService(),
            authSessionStore: SpyAuthSessionStore(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            marketSnapshotCacheStore: InMemoryMarketSnapshotCacheStore(),
            userDefaults: defaults
        )
    }

    @discardableResult
    private func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await condition()) {
            if ContinuousClock.now >= deadline { return false }
            await Task.yield()
        }
        return true
    }

    private func settle(yields: Int = 500) async {
        for _ in 0..<yields {
            await Task.yield()
        }
    }

    /// Bounded deadlock guard around awaiting a task that is only unblocked
    /// by test-controlled gates: returns false instead of hanging the suite
    /// (and the CI job) if a precondition failed and the gate never opens.
    private func awaitCompletion(
        of task: Task<Void, Never>,
        timeout: Duration = .seconds(30)
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await task.value; return true }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    // MARK: - Publication contract

    /// Proves the awaited publication contract with a staged build gate, not
    /// polling: while the presentation build is suspended, `refreshMarketData`
    /// must not have returned and no rows may be visible; releasing the gate
    /// completes the refresh with rows and image URLs already published, and
    /// a superseded (stale-token) build released afterwards cannot publish.
    func testRefreshMarketDataPublishesRowsBeforeReturning() async throws {
        let imageFileURL = try makeTemporaryPNGURL()
        let repository = makeRepository(imageURL: imageFileURL.absoluteString)
        let vm = makeViewModel(repository: repository, suiteName: #function)

        let box = BuildGateBox()
        addTeardownBlock { box.releaseAll() }
        vm.debugMarketPresentationBuildGate = { token in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                box.hold(token, continuation)
            }
        }

        // MainActor-confined completion flag: set as the refresh's final
        // statement, so "refresh returned" is observable without polling.
        let refreshReturned = CompletionFlag()
        let refresh = Task { @MainActor in
            await vm.refreshMarketData(forceRefresh: true, reason: "unit_publication_contract")
            refreshReturned.set()
        }

        // The first-ever refresh stages at least one presentation build; it
        // must park at the gate before anything publishes.
        let gated = await waitUntil { box.tokens().count >= 1 }
        guard gated else {
            let parked = box.tokens()
            box.releaseAll()
            return XCTFail("refresh must park its build at the gate (tokens=\(parked))")
        }

        // While the presentation build is suspended the refresh cannot have
        // completed (it awaits the parked build) and nothing may be visible.
        await settle()
        XCTAssertFalse(refreshReturned.value, "refreshMarketData must not return before its rows are published")
        XCTAssertTrue(vm.displayedMarketRows.isEmpty, "no rows may publish while the build gate is closed")

        // Release only the newest build: the publication contract resumes the
        // caller once the winning build has published.
        let newestToken = try XCTUnwrap(box.tokens().max())
        box.release(newestToken)
        let refreshFinished = await awaitCompletion(of: refresh)
        guard refreshFinished else {
            box.releaseAll()
            return XCTFail("refresh must complete once the newest build is released (tokens=\(box.tokens()))")
        }
        XCTAssertTrue(refreshReturned.value)

        // Immediately after the awaited return: rows and image URLs are
        // published — no polling window.
        XCTAssertEqual(vm.displayedMarketRows.first?.symbol, "BTC")
        XCTAssertEqual(
            vm.displayedMarketRows.first?.imageURL,
            imageFileURL.absoluteString,
            "image URLs must be published before refreshMarketData returns"
        )
        XCTAssertEqual(repository.fetchedTickers.count, 1, "exactly one ticker fetch")

        // The superseded build (stale ownership token) resumes late and must
        // be dropped, never published over the newer rows.
        let publishedRows = vm.displayedMarketRows
        box.releaseAll()
        await settle()
        XCTAssertEqual(
            vm.displayedMarketRows.first?.imageURL,
            publishedRows.first?.imageURL,
            "a stale-generation build must not overwrite published rows"
        )
        XCTAssertEqual(vm.displayedMarketRows.count, publishedRows.count)
        vm.debugMarketPresentationBuildGate = nil
    }

    func testSupersededPresentationBuildCannotOverwriteNewerRows() async {
        let repository = makeRepository(price: 1_000)
        let vm = makeViewModel(repository: repository, suiteName: #function)

        // First refresh publishes dataset 1 normally (gate not installed yet).
        await vm.refreshMarketData(forceRefresh: true, reason: "unit_initial")
        XCTAssertTrue(
            vm.displayedMarketRows.first?.priceText.contains("1,000") == true,
            "dataset 1 published, got \(vm.displayedMarketRows.first?.priceText ?? "nil")"
        )

        // Install the build gate: every staged presentation build suspends
        // until the test releases its token. One refresh stages twice (after
        // the ticker load and again from refreshMarketState), so refresh A
        // parks two builds and refresh B two more.
        let box = BuildGateBox()
        // A failed precondition must never leave a build parked forever: the
        // teardown opens every gate so no await outlives the test.
        addTeardownBlock { box.releaseAll() }
        vm.debugMarketPresentationBuildGate = { token in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                box.hold(token, continuation)
            }
        }

        repository.tickerSnapshots[.upbit] = Self.tickerSnapshot(price: 2_000)
        let refreshA = Task { await vm.refreshMarketData(forceRefresh: true, reason: "unit_stale_build") }
        let gatedA = await waitUntil { box.tokens().count == 2 }
        guard gatedA else {
            box.releaseAll()
            return XCTFail("refresh A must park its builds at the gate (tokens=\(box.tokens()))")
        }
        let tokensA = Set(box.tokens())

        repository.tickerSnapshots[.upbit] = Self.tickerSnapshot(price: 3_000)
        let refreshB = Task { await vm.refreshMarketData(forceRefresh: true, reason: "unit_newer_build") }
        let gatedB = await waitUntil { box.tokens().count == 4 }
        guard gatedB else {
            box.releaseAll()
            return XCTFail("refresh B must park its builds at the gate (tokens=\(box.tokens()))")
        }
        let newestToken = box.tokens().max()!
        XCTAssertFalse(tokensA.contains(newestToken), "the newest token belongs to refresh B")

        // Newest build publishes first…
        box.release(newestToken)
        let refreshBFinished = await awaitCompletion(of: refreshB)
        guard refreshBFinished else {
            box.releaseAll()
            return XCTFail("refresh B must complete once its build is released (tokens=\(box.tokens()))")
        }
        XCTAssertTrue(
            vm.displayedMarketRows.first?.priceText.contains("3,000") == true,
            "newest build publishes, got \(vm.displayedMarketRows.first?.priceText ?? "nil")"
        )

        // …then every superseded build resumes (oldest first) and must be
        // dropped by the ownership-token check, never published.
        for token in box.tokens().sorted() {
            box.release(token)
        }
        let refreshAFinished = await awaitCompletion(of: refreshA)
        guard refreshAFinished else {
            box.releaseAll()
            return XCTFail("refresh A must complete once all builds are released (tokens=\(box.tokens()))")
        }
        await settle()
        XCTAssertTrue(
            vm.displayedMarketRows.first?.priceText.contains("3,000") == true,
            "superseded builds must not overwrite newer rows, got \(vm.displayedMarketRows.first?.priceText ?? "nil")"
        )
        vm.debugMarketPresentationBuildGate = nil
        box.releaseAll()
    }

    func testOverlappingRefreshesDedupeFetchAndPublishOnce() async {
        let spy = makeRepository()
        let repository = GatedMarketRepository(inner: spy)
        let vm = makeViewModel(repository: repository, suiteName: #function)

        repository.enableTickerGate()
        let first = Task { await vm.refreshMarketData(forceRefresh: true, reason: "unit_overlap_first") }
        let suspended = await waitUntil { repository.suspendedTickerFetchCount == 1 }
        XCTAssertTrue(suspended, "first ticker fetch suspended at the gate")
        let second = Task { await vm.refreshMarketData(forceRefresh: true, reason: "unit_overlap_second") }
        await settle()
        XCTAssertEqual(repository.suspendedTickerFetchCount, 1, "overlapping refresh dedupes onto the in-flight fetch")

        repository.releaseTickerFetches()
        let firstFinished = await awaitCompletion(of: first)
        let secondFinished = await awaitCompletion(of: second)
        guard firstFinished, secondFinished else {
            return XCTFail("refreshes must complete once the fetch gate opens (first=\(firstFinished) second=\(secondFinished))")
        }

        XCTAssertFalse(vm.displayedMarketRows.isEmpty, "rows published after overlapping refreshes complete")
        XCTAssertEqual(spy.fetchedTickers.count, 1, "ticker fetch count stays exactly one across overlapping refreshes")
    }
}
