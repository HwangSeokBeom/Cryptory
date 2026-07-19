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
    private static func fixtureCoins() -> [CoinInfo] {
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
                isTradable: true
            )
        ]
    }

    private func makeRepository(price: Double = 125_000_000) -> SpyMarketRepository {
        let repository = SpyMarketRepository()
        repository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: Self.fixtureCoins(),
            supportedIntervalsBySymbol: ["BTC": ["1h"]],
            meta: .empty
        )
        repository.tickerSnapshots[.upbit] = Self.tickerSnapshot(price: price)
        return repository
    }

    private static func tickerSnapshot(price: Double) -> MarketTickerSnapshot {
        MarketTickerSnapshot(
            exchange: .upbit,
            coins: fixtureCoins(),
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

    // MARK: - Publication contract

    func testRefreshMarketDataPublishesRowsBeforeReturning() async {
        let repository = makeRepository()
        let vm = makeViewModel(repository: repository, suiteName: #function)

        await vm.refreshMarketData(forceRefresh: true, reason: "unit_publication_contract")

        // No polling: the awaited refresh must have published the rows.
        XCTAssertFalse(vm.displayedMarketRows.isEmpty, "rows must be published before refreshMarketData returns")
        XCTAssertEqual(repository.fetchedTickers.count, 1, "exactly one ticker fetch")
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
        vm.debugMarketPresentationBuildGate = { token in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                box.hold(token, continuation)
            }
        }

        repository.tickerSnapshots[.upbit] = Self.tickerSnapshot(price: 2_000)
        let refreshA = Task { await vm.refreshMarketData(forceRefresh: true, reason: "unit_stale_build") }
        let gatedA = await waitUntil { box.tokens().count == 2 }
        XCTAssertTrue(gatedA, "refresh A must park its builds at the gate (tokens=\(box.tokens()))")
        let tokensA = Set(box.tokens())

        repository.tickerSnapshots[.upbit] = Self.tickerSnapshot(price: 3_000)
        let refreshB = Task { await vm.refreshMarketData(forceRefresh: true, reason: "unit_newer_build") }
        let gatedB = await waitUntil { box.tokens().count == 4 }
        XCTAssertTrue(gatedB, "refresh B must park its builds at the gate (tokens=\(box.tokens()))")
        let newestToken = box.tokens().max()!
        XCTAssertFalse(tokensA.contains(newestToken), "the newest token belongs to refresh B")

        // Newest build publishes first…
        box.release(newestToken)
        await refreshB.value
        XCTAssertTrue(
            vm.displayedMarketRows.first?.priceText.contains("3,000") == true,
            "newest build publishes, got \(vm.displayedMarketRows.first?.priceText ?? "nil")"
        )

        // …then every superseded build resumes (oldest first) and must be
        // dropped by the ownership-token check, never published.
        for token in box.tokens().sorted() {
            box.release(token)
        }
        await refreshA.value
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
        await first.value
        await second.value

        XCTAssertFalse(vm.displayedMarketRows.isEmpty, "rows published after overlapping refreshes complete")
        XCTAssertEqual(spy.fetchedTickers.count, 1, "ticker fetch count stays exactly one across overlapping refreshes")
    }
}
