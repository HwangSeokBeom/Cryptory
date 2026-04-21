import XCTest
import UIKit
@testable import Cryptory

final class ViewModelStateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AssetImageDebugClient.shared.reset()
        AssetImageClient.shared.debugReset()
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        condition: @MainActor @escaping () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                break
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            await Task.yield()
        }
    }

    private func makeIsolatedDefaults(testName: String = #function) -> UserDefaults {
        let suiteName = "CryptoryTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeMarketCoin(
        exchange: Exchange,
        marketId: String,
        symbol: String,
        imageURL: String? = nil
    ) -> CoinInfo {
        CoinCatalog.coin(
            symbol: symbol,
            exchange: exchange,
            marketId: marketId,
            displayName: "\(exchange.rawValue.uppercased()) \(symbol)",
            englishName: "\(exchange.rawValue.uppercased()) \(symbol)",
            imageURL: imageURL
        )
    }

    private func makeCatalogSnapshot(
        exchange: Exchange,
        entries: [(marketId: String, symbol: String, imageURL: String?)]
    ) -> MarketCatalogSnapshot {
        let markets = entries.map {
            makeMarketCoin(
                exchange: exchange,
                marketId: $0.marketId,
                symbol: $0.symbol,
                imageURL: $0.imageURL
            )
        }
        let supportedIntervals = entries.reduce(into: [String: [String]]()) { partialResult, entry in
            partialResult[entry.symbol] = ["1m", "1h"]
        }
        return MarketCatalogSnapshot(
            exchange: exchange,
            markets: markets,
            supportedIntervalsBySymbol: supportedIntervals,
            meta: .empty
        )
    }

    private func makeTickerSnapshot(
        exchange: Exchange,
        entries: [(marketId: String, symbol: String, price: Double, imageURL: String?, sparkline: [Double])]
    ) -> MarketTickerSnapshot {
        let coins = entries.map {
            makeMarketCoin(
                exchange: exchange,
                marketId: $0.marketId,
                symbol: $0.symbol,
                imageURL: $0.imageURL
            )
        }
        let tickers = entries.reduce(into: [String: TickerData]()) { partialResult, entry in
            partialResult[entry.symbol] = TickerData(
                price: entry.price,
                change: 0.5,
                volume: 10_000,
                high24: entry.price * 1.05,
                low24: entry.price * 0.95,
                sparkline: entry.sparkline,
                sparklinePointCount: entry.sparkline.count,
                hasServerSparkline: entry.sparkline.isEmpty == false
            )
        }
        return MarketTickerSnapshot(
            exchange: exchange,
            coins: coins,
            tickers: tickers,
            meta: .empty
        )
    }

    private func makeCandleSnapshot(exchange: Exchange, symbol: String, closes: [Double]) -> CandleSnapshot {
        CandleSnapshot(
            exchange: exchange,
            symbol: symbol,
            interval: "1h",
            candles: closes.enumerated().map { index, close in
                CandleData(
                    time: index + 1,
                    open: close,
                    high: close + 1,
                    low: max(close - 1, 0),
                    close: close,
                    volume: 1
                )
            },
            meta: .empty
        )
    }

    private func makeTemporaryPNGURL(color: UIColor = .systemBlue) throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        guard let pngData = image.pngData() else {
            throw XCTSkip("Failed to create png data")
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try pngData.write(to: fileURL)
        return fileURL
    }

    @MainActor
    func testGuestProtectedLoadsDoNotCallPrivateRepositories() async {
        let portfolioRepository = SpyPortfolioRepository()
        let tradingRepository = SpyTradingRepository()
        let connectionsRepository = SpyExchangeConnectionsRepository()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: tradingRepository,
            portfolioRepository: portfolioRepository,
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: connectionsRepository,
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        await Task.yield()

        await vm.loadPortfolio()
        await vm.loadOrders()
        await vm.loadExchangeConnections()

        XCTAssertEqual(portfolioRepository.fetchSummaryCount, 0)
        XCTAssertEqual(tradingRepository.fetchChanceCount, 0)
        XCTAssertEqual(connectionsRepository.fetchConnectionsCount, 0)
        XCTAssertFalse(vm.isAuthenticated)
    }

    @MainActor
    func testLoginOnPortfolioGateReturnsToPortfolioAndLoadsAuthenticatedData() async {
        let portfolioRepository = SpyPortfolioRepository()
        let tradingRepository = SpyTradingRepository()
        let connectionsRepository = SpyExchangeConnectionsRepository()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: tradingRepository,
            portfolioRepository: portfolioRepository,
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: connectionsRepository,
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        await Task.yield()

        vm.setActiveTab(.portfolio)
        await Task.yield()
        vm.presentLogin(for: .portfolio)
        vm.loginEmail = "user@example.com"
        vm.loginPassword = "password"

        await vm.submitLogin()

        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertEqual(connectionsRepository.fetchConnectionsCount, 1)
        XCTAssertEqual(portfolioRepository.fetchSummaryCount, 1)
        XCTAssertEqual(portfolioRepository.fetchHistoryCount, 1)
        XCTAssertEqual(vm.activeAuthGate, nil)
    }

    @MainActor
    func testLoginOnTradeGateReturnsToTradeAndLoadsTradingData() async {
        let portfolioRepository = SpyPortfolioRepository()
        let tradingRepository = SpyTradingRepository()
        let connectionsRepository = SpyExchangeConnectionsRepository()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: tradingRepository,
            portfolioRepository: portfolioRepository,
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: connectionsRepository,
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        await Task.yield()

        vm.onAppear()
        vm.selectedCoin = CoinCatalog.coin(symbol: "BTC")
        vm.setActiveTab(.trade)
        await Task.yield()
        vm.presentLogin(for: .trade)
        vm.loginEmail = "user@example.com"
        vm.loginPassword = "password"

        await vm.submitLogin()
        await waitUntil {
            connectionsRepository.fetchConnectionsCount == 1
                && tradingRepository.fetchChanceCount == 1
                && tradingRepository.fetchOpenOrdersCount == 1
                && tradingRepository.fetchFillsCount == 1
        }

        XCTAssertEqual(vm.activeTab, .trade)
        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertEqual(connectionsRepository.fetchConnectionsCount, 1)
        XCTAssertEqual(tradingRepository.fetchChanceCount, 1)
        XCTAssertEqual(tradingRepository.fetchOpenOrdersCount, 1)
        XCTAssertEqual(tradingRepository.fetchFillsCount, 1)
        XCTAssertEqual(vm.activeAuthGate, nil)
    }

    @MainActor
    func testLoadKimchiPremiumUpdatesState() async {
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        await Task.yield()

        vm.onAppear()
        await Task.yield()
        await vm.loadKimchiPremium(forceRefresh: true, reason: "test")
        await waitUntil {
            vm.kimchiPremiumState.value?.first?.status == .loaded
        }

        guard case .loaded(let coinViewStates) = vm.kimchiPremiumState else {
            return XCTFail("Expected loaded kimchi premium state")
        }

        XCTAssertEqual(coinViewStates.first?.symbol, "BTC")
        XCTAssertEqual(coinViewStates.first?.status, .loaded)
        XCTAssertEqual(vm.kimchiStatusViewState.refreshMode, .snapshot)
    }

    @MainActor
    func testKimchiRefreshFailureRetainsLastGoodUsableData() async {
        let liveSnapshot = StubKimchiPremiumRepository().snapshot
        let kimchiRepository = SequencedKimchiPremiumRepository(
            results: [
                .success(liveSnapshot),
                .failure(NetworkServiceError.httpError(503, "temporarily unavailable", .maintenance))
            ]
        )
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: kimchiRepository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        await vm.loadKimchiPremium(forceRefresh: true, reason: "initial_success")
        await waitUntil {
            vm.kimchiPremiumState.value?.first?.status == .loaded
        }

        let previousPremiumText = vm.kimchiPremiumState.value?.first?.cells.first?.premiumText

        await vm.refreshKimchiPremium(forceRefresh: true, reason: "failure_retain")
        await Task.yield()

        guard case .loaded(let rows) = vm.kimchiPremiumState else {
            return XCTFail("Expected kimchi rows to stay loaded after refresh failure")
        }
        XCTAssertEqual(rows.first?.status, .loaded)
        XCTAssertEqual(rows.first?.cells.first?.premiumText, previousPremiumText)
        XCTAssertNotEqual(rows.first?.status, .unavailable)
        XCTAssertTrue(vm.kimchiLoadState.hasPartialFailure)
    }

    @MainActor
    func testKimchiExchangeSelectionDoesNotTriggerMarketTickerRefresh() async {
        let marketRepository = SpyMarketRepository()
        let kimchiRepository = SpyKimchiPremiumRepository()
        kimchiRepository.snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                KimchiPremiumRow(
                    id: "btc-coinone",
                    symbol: "BTC",
                    exchange: .coinone,
                    sourceExchange: .coinone,
                    domesticPrice: 149_000_000,
                    referenceExchangePrice: 100_000,
                    premiumPercent: 2.8,
                    krwConvertedReference: 145_000_000,
                    usdKrwRate: 1450,
                    timestamp: Date(),
                    sourceExchangeTimestamp: Date(),
                    referenceTimestamp: Date(),
                    isStale: false,
                    staleReason: nil
                )
            ],
            fetchedAt: Date(),
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil,
            failedSymbols: []
        )

        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: kimchiRepository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        await Task.yield()

        vm.onAppear()
        await waitUntil {
            marketRepository.fetchedTickers.contains(.upbit)
        }

        vm.setActiveTab(.kimchi)
        await waitUntil {
            vm.activeTab == .kimchi
        }
        marketRepository.resetFetchHistory()

        vm.updateSelectedDomesticKimchiExchange(.coinone, source: "test_kimchi_exchange_switch")
        await waitUntil {
            kimchiRepository.requestedExchanges.contains(.coinone)
        }

        XCTAssertEqual(vm.selectedDomesticKimchiExchange, .coinone)
        XCTAssertEqual(vm.exchange, .coinone)
        XCTAssertFalse(marketRepository.fetchedTickers.contains(.coinone))
        XCTAssertFalse(marketRepository.fetchedMarkets.isEmpty)
    }

    @MainActor
    func testOnAppearFetchesOnlySelectedExchangeMarketData() async {
        let marketRepository = SpyMarketRepository()
        let publicWebSocketService = RecordingPublicWebSocketService()
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: publicWebSocketService,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            marketRepository.fetchedMarkets == [.upbit]
                && marketRepository.fetchedTickers == [.upbit]
                && publicWebSocketService.lastSubscriptions.count == 2
                && Set(publicWebSocketService.lastSubscriptions.compactMap(\.symbol)) == Set(["BTC", "ETH"])
                && Set(publicWebSocketService.lastSubscriptions.compactMap(\.exchange)) == Set([Exchange.upbit.rawValue])
                && Set(publicWebSocketService.lastSubscriptions.map(\.channel)) == Set([.ticker])
        }

        XCTAssertEqual(marketRepository.fetchedMarkets, [.upbit])
        XCTAssertEqual(marketRepository.fetchedTickers, [.upbit])
        XCTAssertEqual(publicWebSocketService.lastSubscriptions.count, 2)
        XCTAssertEqual(Set(publicWebSocketService.lastSubscriptions.compactMap(\.symbol)), Set(["BTC", "ETH"]))
        XCTAssertEqual(Set(publicWebSocketService.lastSubscriptions.compactMap(\.exchange)), Set([Exchange.upbit.rawValue]))
        XCTAssertEqual(Set(publicWebSocketService.lastSubscriptions.map(\.channel)), Set([.ticker]))
    }

    @MainActor
    func testMarketDisplayModeLoadsAndPersistsSelection() async {
        let defaults = makeIsolatedDefaults()
        defaults.set(MarketListDisplayMode.info.rawValue, forKey: "market.display.mode")

        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            userDefaults: defaults
        )

        XCTAssertEqual(vm.marketDisplayMode, .info)

        vm.applyMarketDisplayMode(.emphasis, source: "test")

        XCTAssertEqual(defaults.string(forKey: "market.display.mode"), MarketListDisplayMode.emphasis.rawValue)

        let reloadedVM = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            userDefaults: defaults
        )

        XCTAssertEqual(reloadedVM.marketDisplayMode, .emphasis)
    }

    @MainActor
    func testMarketDisplayGuideIsConsumedOnlyOnce() async {
        let defaults = makeIsolatedDefaults()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            userDefaults: defaults
        )

        XCTAssertTrue(vm.consumeMarketDisplayGuidePresentationIfNeeded(reason: "test_first_launch"))
        vm.dismissMarketDisplayGuide(reason: "close")
        XCTAssertFalse(vm.consumeMarketDisplayGuidePresentationIfNeeded(reason: "test_second_launch"))

        let reloadedVM = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            userDefaults: defaults
        )
        XCTAssertFalse(reloadedVM.consumeMarketDisplayGuidePresentationIfNeeded(reason: "test_reloaded"))
    }

    @MainActor
    func testMarketDisplayModePreviewDoesNotPersistUntilApply() async {
        let defaults = makeIsolatedDefaults()
        defaults.set(MarketListDisplayMode.chart.rawValue, forKey: "market.display.mode")
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            userDefaults: defaults
        )

        vm.beginMarketDisplayModePreview(source: "test")
        vm.previewMarketDisplayMode(.info, source: "test")

        XCTAssertEqual(vm.marketDisplayMode, .chart)
        XCTAssertEqual(vm.activeMarketDisplayMode, .info)
        XCTAssertEqual(defaults.string(forKey: "market.display.mode"), MarketListDisplayMode.chart.rawValue)

        vm.cancelMarketDisplayModePreview(source: "test")
        XCTAssertEqual(vm.activeMarketDisplayMode, .chart)
        XCTAssertEqual(defaults.string(forKey: "market.display.mode"), MarketListDisplayMode.chart.rawValue)

        vm.beginMarketDisplayModePreview(source: "test")
        vm.previewMarketDisplayMode(.emphasis, source: "test")
        vm.applyMarketDisplayModePreview(source: "test")

        XCTAssertEqual(vm.marketDisplayMode, .emphasis)
        XCTAssertEqual(vm.activeMarketDisplayMode, .emphasis)
        XCTAssertEqual(defaults.string(forKey: "market.display.mode"), MarketListDisplayMode.emphasis.rawValue)
    }

    @MainActor
    func testTickerSnapshotImageURLIsMergedIntoDisplayedRow() async {
        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [
                CoinCatalog.coin(
                    symbol: "BTC",
                    displayName: "비트코인",
                    englishName: "Bitcoin"
                )
            ],
            supportedIntervalsBySymbol: ["BTC": ["1h"]],
            meta: .empty
        )
        marketRepository.tickerSnapshots[.upbit] = MarketTickerSnapshot(
            exchange: .upbit,
            coins: [
                CoinCatalog.coin(
                    symbol: "BTC",
                    displayName: "비트코인",
                    englishName: "Bitcoin",
                    imageURL: "https://assets.example.com/btc.png"
                )
            ],
            tickers: [
                "BTC": TickerData(
                    price: 125_000_000,
                    change: 1.1,
                    volume: 100_000_000,
                    high24: 126_000_000,
                    low24: 124_500_000,
                    sparkline: [124_000_000, 124_400_000, 124_900_000, 125_000_000],
                    sparklinePointCount: 4,
                    hasServerSparkline: true
                )
            ],
            meta: .empty
        )

        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.first?.imageURL == "https://assets.example.com/btc.png"
        }

        XCTAssertEqual(vm.displayedMarketRows.first?.symbol, "BTC")
        XCTAssertEqual(vm.displayedMarketRows.first?.imageURL, "https://assets.example.com/btc.png")
    }

    @MainActor
    func testCatalogImageURLIsPreservedWhenTickerSnapshotImageURLIsNil() async {
        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [
                CoinCatalog.coin(
                    symbol: "BTC",
                    displayName: "비트코인",
                    englishName: "Bitcoin",
                    imageURL: "https://assets.example.com/btc.png"
                )
            ],
            supportedIntervalsBySymbol: ["BTC": ["1h"]],
            meta: .empty
        )
        marketRepository.tickerSnapshots[.upbit] = MarketTickerSnapshot(
            exchange: .upbit,
            coins: [
                CoinCatalog.coin(
                    symbol: "BTC",
                    displayName: "비트코인",
                    englishName: "Bitcoin",
                    imageURL: nil
                )
            ],
            tickers: [
                "BTC": TickerData(
                    price: 125_000_000,
                    change: 1.1,
                    volume: 100_000_000,
                    high24: 126_000_000,
                    low24: 124_500_000,
                    sparkline: [124_000_000, 124_400_000],
                    sparklinePointCount: 2,
                    hasServerSparkline: true
                )
            ],
            meta: .empty
        )

        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.first?.imageURL == "https://assets.example.com/btc.png"
        }

        XCTAssertEqual(vm.displayedMarketRows.first?.imageURL, "https://assets.example.com/btc.png")
    }

    @MainActor
    func testMarketRowsPatchVisibleSymbolImageFromPlaceholderToLive() async throws {
        let imageURL = try makeTemporaryPNGURL(color: .systemGreen)
        let assetImageClient = AssetImageClient(namespace: UUID().uuidString)
        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = makeCatalogSnapshot(
            exchange: .upbit,
            entries: [(marketId: "KRW-BTC", symbol: "BTC", imageURL: imageURL.absoluteString)]
        )
        marketRepository.tickerSnapshots[.upbit] = makeTickerSnapshot(
            exchange: .upbit,
            entries: [
                (
                    marketId: "KRW-BTC",
                    symbol: "BTC",
                    price: 125_000_000,
                    imageURL: imageURL.absoluteString,
                    sparkline: [124_000_000, 124_400_000, 124_900_000]
                )
            ]
        )

        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            assetImageClient: assetImageClient
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.first?.symbolImageState == .live
        }

        XCTAssertEqual(vm.displayedMarketRows.first?.symbolImageState, .live)
        XCTAssertGreaterThanOrEqual(AssetImageDebugClient.shared.snapshotEventCounts()["request_start"] ?? 0, 1)
        XCTAssertEqual(AssetImageDebugClient.shared.snapshotEventCounts()["batched_visible_patch"], 1)
    }

    @MainActor
    func testMarketRowsUsePreloadedSymbolImageStateOnFirstPaint() async throws {
        let imageURL = try makeTemporaryPNGURL(color: .systemOrange)
        let assetImageClient = AssetImageClient(namespace: UUID().uuidString)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")
        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: "BTC",
            canonicalSymbol: "BTC",
            imageURL: imageURL.absoluteString,
            hasImage: true,
            localAssetName: nil
        )
        _ = await assetImageClient.requestImage(for: descriptor, mode: .prefetch)

        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = makeCatalogSnapshot(
            exchange: .upbit,
            entries: [(marketId: "KRW-BTC", symbol: "BTC", imageURL: imageURL.absoluteString)]
        )
        marketRepository.tickerSnapshots[.upbit] = makeTickerSnapshot(
            exchange: .upbit,
            entries: [
                (
                    marketId: "KRW-BTC",
                    symbol: "BTC",
                    price: 125_000_000,
                    imageURL: imageURL.absoluteString,
                    sparkline: [124_000_000, 124_400_000, 124_900_000]
                )
            ]
        )

        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            assetImageClient: assetImageClient
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.first?.symbol == "BTC"
        }

        XCTAssertEqual(vm.displayedMarketRows.first?.symbolImageState, .live)
    }

    @MainActor
    func testMarketDisplayModeChangeKeepsImageAndGraphState() async {
        let marketRepository = SpyMarketRepository()
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            guard let row = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
                return false
            }
            return row.imageURL != nil && row.graphState.keepsVisibleGraph
        }

        guard let initialRow = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
            return XCTFail("Expected BTC row")
        }

        let initialImageURL = initialRow.imageURL
        let initialSparkline = initialRow.sparkline

        vm.applyMarketDisplayMode(.info, source: "test")
        vm.applyMarketDisplayMode(.emphasis, source: "test")

        guard let updatedRow = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
            return XCTFail("Expected BTC row after display mode change")
        }

        XCTAssertEqual(updatedRow.imageURL, initialImageURL)
        XCTAssertEqual(updatedRow.sparkline, initialSparkline)
        XCTAssertTrue(updatedRow.graphState.keepsVisibleGraph)
    }

    @MainActor
    func testTickerSnapshotSeedsSparklineForMultipleRows() async {
        let marketRepository = SpyMarketRepository()
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            vm.prices["BTC"]?[Exchange.upbit.rawValue]?.sparkline.count == 2
                && vm.prices["ETH"]?[Exchange.upbit.rawValue]?.sparkline.count == 2
        }

        XCTAssertEqual(vm.prices["BTC"]?[Exchange.upbit.rawValue]?.sparkline.count, 2)
        XCTAssertEqual(vm.prices["ETH"]?[Exchange.upbit.rawValue]?.sparkline.count, 2)
    }

    @MainActor
    func testMarketRowsPublishPriceVolumeAndSparklineTogether() async {
        let marketRepository = SpyMarketRepository()
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            guard let row = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
                return false
            }
            return row.isPricePlaceholder == false && row.sparklinePointCount == 2
        }

        guard let btcRow = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
            return XCTFail("Expected BTC market row")
        }

        XCTAssertEqual(btcRow.id, MarketIdentity(exchange: .upbit, symbol: "BTC").cacheKey)
        XCTAssertFalse(btcRow.isPricePlaceholder)
        XCTAssertFalse(btcRow.isVolumePlaceholder)
        XCTAssertEqual(btcRow.sparkline.count, 2)
        XCTAssertEqual(btcRow.sparklinePointCount, 2)
        XCTAssertFalse(btcRow.hasEnoughSparklineData)
        XCTAssertNotEqual(btcRow.chartPresentation, .placeholder)
        XCTAssertTrue(btcRow.graphState.keepsVisibleGraph)
        XCTAssertFalse(vm.marketPresentationState.sparklineAvailabilityState.placeholderSymbols.contains("BTC"))
        XCTAssertTrue(vm.marketPresentationState.sparklineAvailabilityState.availableSymbols.contains("BTC"))
        XCTAssertNotEqual(btcRow.volumeText, "대기")
    }

    @MainActor
    func testVisibleMarketRowLiveTickerUpdatesSparklineImmediately() async {
        let publicWebSocketService = ManualPublicWebSocketService()
        let vm = CryptoViewModel(
            marketRepository: SpyMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: publicWebSocketService,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            guard let row = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
                return false
            }
            return row.isPricePlaceholder == false && row.sparkline.count == 2
        }

        publicWebSocketService.emitTicker(
            TickerStreamPayload(
                symbol: "BTC",
                exchange: Exchange.upbit.rawValue,
                ticker: TickerData(
                    price: 126_100_000,
                    change: 1.6,
                    volume: 101_000_000,
                    high24: 126_500_000,
                    low24: 120_000_000,
                    timestamp: Date(),
                    delivery: .live
                )
            )
        )

        await waitUntil {
            vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.sparkline.last == 126_100_000
                && vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.sparkline.count == 3
        }

        XCTAssertEqual(vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.sparkline.last, 126_100_000)
        XCTAssertEqual(vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.sparkline.count, 3)
    }

    @MainActor
    func testChangingExchangeFetchesOnlyNewExchangeTickerData() async {
        let marketRepository = SpyMarketRepository()
        let publicWebSocketService = RecordingPublicWebSocketService()
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: publicWebSocketService,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            marketRepository.fetchedMarkets == [.upbit]
                && marketRepository.fetchedTickers == [.upbit]
        }

        marketRepository.resetFetchHistory()

        vm.updateExchange(.coinone, source: "test")
        await waitUntil {
            marketRepository.fetchedMarkets == [.coinone]
                && marketRepository.fetchedTickers == [.coinone]
                && publicWebSocketService.lastSubscriptions.count == 2
                && Set(publicWebSocketService.lastSubscriptions.compactMap(\.symbol)) == Set(["BTC", "XRP"])
                && Set(publicWebSocketService.lastSubscriptions.compactMap(\.exchange)) == Set([Exchange.coinone.rawValue])
                && Set(publicWebSocketService.lastSubscriptions.map(\.channel)) == Set([.ticker])
                && vm.prices["BTC"]?[Exchange.coinone.rawValue] != nil
        }

        XCTAssertEqual(marketRepository.fetchedMarkets, [.coinone])
        XCTAssertEqual(marketRepository.fetchedTickers, [.coinone])
        XCTAssertEqual(publicWebSocketService.lastSubscriptions.count, 2)
        XCTAssertEqual(Set(publicWebSocketService.lastSubscriptions.compactMap(\.symbol)), Set(["BTC", "XRP"]))
        XCTAssertEqual(Set(publicWebSocketService.lastSubscriptions.compactMap(\.exchange)), Set([Exchange.coinone.rawValue]))
        XCTAssertEqual(Set(publicWebSocketService.lastSubscriptions.map(\.channel)), Set([.ticker]))
        XCTAssertNotNil(vm.prices["BTC"]?[Exchange.coinone.rawValue])
    }

    @MainActor
    func testChangingExchangeKeepsRenderedMarketRowCountAlignedWithCatalog() async {
        let marketRepository = SpyMarketRepository()
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.contains(where: { $0.id == MarketIdentity(exchange: .upbit, symbol: "BTC").cacheKey })
        }

        vm.updateExchange(.coinone, source: "test")
        await waitUntil {
            vm.displayedMarketRows.count == 2
                && Set(vm.displayedMarketRows.map(\.id)) == Set([
                    MarketIdentity(exchange: .coinone, symbol: "BTC").cacheKey,
                    MarketIdentity(exchange: .coinone, symbol: "XRP").cacheKey
                ])
        }

        XCTAssertEqual(vm.displayedMarketRows.count, 2)
        XCTAssertEqual(Set(vm.displayedMarketRows.map(\.id)), Set([
            MarketIdentity(exchange: .coinone, symbol: "BTC").cacheKey,
            MarketIdentity(exchange: .coinone, symbol: "XRP").cacheKey
        ]))
    }

    @MainActor
    func testMarketUsesFullTradableUniverseFromServer() async {
        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [
                CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true),
                CoinCatalog.coin(symbol: "ETH", isTradable: true, isKimchiComparable: true),
                CoinCatalog.coin(symbol: "XRP", isTradable: true, isKimchiComparable: false),
                CoinCatalog.coin(symbol: "DOGE", isTradable: false, isKimchiComparable: false)
            ],
            supportedIntervalsBySymbol: [
                "BTC": ["1m", "1h"],
                "ETH": ["1m", "1h"],
                "XRP": ["1m", "1h"],
                "DOGE": ["1m", "1h"]
            ],
            meta: .empty
        )
        marketRepository.tickerSnapshots[.upbit] = MarketTickerSnapshot(
            exchange: .upbit,
            tickers: [
                "BTC": TickerData(
                    price: 125_000_000,
                    change: 1.2,
                    volume: 100_000_000,
                    high24: 126_000_000,
                    low24: 120_000_000,
                    sparkline: [123_500_000, 125_000_000],
                    hasServerSparkline: true
                )
            ],
            meta: .empty
        )
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.count == 3
        }

        XCTAssertEqual(Set(vm.displayedMarketRows.map(\.symbol)), Set(["BTC", "ETH", "XRP"]))
        XCTAssertFalse(vm.displayedMarketRows.contains(where: { $0.symbol == "DOGE" }))
    }

    @MainActor
    func testMarketRepresentativeRowsAppearBeforeFullHydration() async {
        let coins = (1...30).map { index in
            CoinCatalog.coin(symbol: "C\(index)", isTradable: true, isKimchiComparable: index <= 8)
        }
        let tickers = Dictionary(uniqueKeysWithValues: coins.enumerated().map { index, coin in
            (
                coin.symbol,
                TickerData(
                    price: Double(1_000 + index),
                    change: Double(index) / 100,
                    volume: Double(10_000 + index),
                    high24: Double(1_100 + index),
                    low24: Double(900 + index),
                    sparkline: [Double(980 + index), Double(1_000 + index)],
                    hasServerSparkline: true
                )
            )
        })
        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: coins,
            supportedIntervalsBySymbol: Dictionary(uniqueKeysWithValues: coins.map { ($0.symbol, ["1m", "1h"]) }),
            meta: .empty
        )
        marketRepository.tickerSnapshots[.upbit] = MarketTickerSnapshot(
            exchange: .upbit,
            tickers: tickers,
            meta: .empty
        )
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            vm.marketPresentationState.representativeRowsState.rows.count == 4
                && vm.marketPresentationState.listRowsState.rows.isEmpty == false
        }

        XCTAssertEqual(vm.representativeMarketRows.count, 4)
        XCTAssertGreaterThanOrEqual(vm.marketPresentationState.listRowsState.rows.count, 24)
        XCTAssertLessThanOrEqual(vm.marketPresentationState.listRowsState.rows.count, 30)

        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.marketPresentationState.listRowsState.rows.count == 30
                && vm.marketPresentationState.transitionState.phase == .hydrated
        }

        XCTAssertEqual(vm.marketPresentationState.listRowsState.rows.count, 30)
        XCTAssertEqual(vm.marketPresentationState.transitionState.phase, .hydrated)
        XCTAssertEqual(vm.marketPresentationState.listRowsState.phase, .hydrated)
    }

    @MainActor
    func testMarketPartialSnapshotKeepsNormalListPresentation() async {
        let repository = SpyMarketRepository()
        repository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [
                CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true),
                CoinCatalog.coin(symbol: "ETH", isTradable: true, isKimchiComparable: true)
            ],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "ETH": ["1m", "1h"]],
            meta: .empty
        )
        repository.tickerSnapshots[.upbit] = MarketTickerSnapshot(
            exchange: .upbit,
            tickers: [
                "BTC": TickerData(
                    price: 125_000_000,
                    change: 1.2,
                    volume: 100_000_000,
                    high24: 126_000_000,
                    low24: 120_000_000,
                    sparkline: [123_500_000, 125_000_000],
                    hasServerSparkline: true
                )
            ],
            meta: ResponseMeta(
                fetchedAt: Date(),
                isStale: false,
                warningMessage: nil,
                partialFailureMessage: "ETH validation failed"
            )
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.marketPresentationState.listRowsState.rows.count == 2
        }

        guard case .loaded = vm.marketState else {
            return XCTFail("Expected partial market rows to remain in loaded state")
        }
        XCTAssertEqual(vm.displayedMarketRows.map(\.symbol), ["BTC", "ETH"])
        XCTAssertFalse(vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.isPricePlaceholder ?? true)
        XCTAssertEqual(vm.marketPresentationState.listRowsState.phase, .partial)
        XCTAssertEqual(vm.marketPresentationState.transitionState.phase, .partial)
        XCTAssertEqual(vm.marketLoadState.phase, .showingSnapshot)
        XCTAssertTrue(vm.marketStatusViewState.badges.contains(where: { $0.title == "일부 지연" }))
    }

    @MainActor
    func testExchangeSwitchShowsBaseRowsBeforeTickerSnapshotArrives() async {
        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: MarketCatalogSnapshot(
                    exchange: .upbit,
                    markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
                    supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "ETH": ["1m", "1h"]],
                    meta: .empty
                ),
                .coinone: MarketCatalogSnapshot(
                    exchange: .coinone,
                    markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "XRP")],
                    supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "XRP": ["1m", "1h"]],
                    meta: .empty
                )
            ],
            tickerSnapshots: [
                .upbit: MarketTickerSnapshot(
                    exchange: .upbit,
                    tickers: [
                        "BTC": TickerData(price: 125_000_000, change: 1.2, volume: 100_000_000, high24: 126_000_000, low24: 120_000_000, sparkline: [123_500_000, 125_000_000], hasServerSparkline: true),
                        "ETH": TickerData(price: 5_000_000, change: -0.4, volume: 50_000_000, high24: 5_100_000, low24: 4_900_000, sparkline: [5_020_000, 5_000_000], hasServerSparkline: true)
                    ],
                    meta: .empty
                ),
                .coinone: MarketTickerSnapshot(
                    exchange: .coinone,
                    tickers: [
                        "BTC": TickerData(price: 124_500_000, change: 0.9, volume: 98_000_000, high24: 125_000_000, low24: 123_000_000, sparkline: [123_800_000, 124_500_000], hasServerSparkline: true),
                        "XRP": TickerData(price: 800, change: 0.2, volume: 40_000_000, high24: 820, low24: 780, sparkline: [790, 800], hasServerSparkline: true)
                    ],
                    meta: .empty
                )
            ],
            tickerDelaysByExchange: [.coinone: 300_000_000]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            Set(vm.displayedMarketRows.map(\.id)) == Set([
                MarketIdentity(exchange: .upbit, symbol: "BTC").cacheKey,
                MarketIdentity(exchange: .upbit, symbol: "ETH").cacheKey
            ])
        }

        vm.updateExchange(.coinone, source: "test")
        try? await Task.sleep(for: .milliseconds(120))
        await Task.yield()

        XCTAssertEqual(vm.selectedExchange, .coinone)
        XCTAssertEqual(Set(vm.displayedMarketRows.map(\.id)), Set([
            MarketIdentity(exchange: .coinone, symbol: "BTC").cacheKey,
            MarketIdentity(exchange: .coinone, symbol: "XRP").cacheKey
        ]))
        XCTAssertTrue(vm.displayedMarketRows.allSatisfy(\.isPricePlaceholder))
        XCTAssertEqual(vm.marketPresentationState.selectedExchange, .coinone)
        XCTAssertEqual(vm.marketPresentationState.transitionState.phase, .partial)
        XCTAssertFalse(vm.marketPresentationState.representativeRowsState.isLoading)
        XCTAssertFalse(vm.marketPresentationState.listRowsState.isLoading)
        XCTAssertFalse(vm.marketPresentationState.sameExchangeStaleReuse)
        XCTAssertFalse(vm.marketPresentationState.crossExchangeStaleReuseAllowed)
        XCTAssertNil(vm.marketTransitionMessage)

        await waitUntil {
            Set(vm.displayedMarketRows.map(\.id)) == Set([
                MarketIdentity(exchange: .coinone, symbol: "BTC").cacheKey,
                MarketIdentity(exchange: .coinone, symbol: "XRP").cacheKey
            ])
                && vm.displayedMarketRows.allSatisfy { $0.isPricePlaceholder == false }
        }

        XCTAssertEqual(vm.marketPresentationState.transitionState.phase, .hydrated)
        XCTAssertNil(vm.marketTransitionMessage)
    }

    @MainActor
    func testSameExchangeRefreshKeepsVisibleGraphDuringBackgroundRefresh() async {
        let candleSnapshot = CandleSnapshot(
            exchange: .upbit,
            symbol: "BTC",
            interval: "1h",
            candles: [
                CandleData(time: 1, open: 123_000_000, high: 123_500_000, low: 122_800_000, close: 123_200_000, volume: 10),
                CandleData(time: 2, open: 123_200_000, high: 123_900_000, low: 123_100_000, close: 123_800_000, volume: 12),
                CandleData(time: 3, open: 123_800_000, high: 124_800_000, low: 123_700_000, close: 124_500_000, volume: 15),
                CandleData(time: 4, open: 124_500_000, high: 125_200_000, low: 124_300_000, close: 125_000_000, volume: 18)
            ],
            meta: .empty
        )
        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: MarketCatalogSnapshot(
                    exchange: .upbit,
                    markets: [CoinCatalog.coin(symbol: "BTC")],
                    supportedIntervalsBySymbol: ["BTC": ["1h"]],
                    meta: .empty
                )
            ],
            tickerSnapshots: [
                .upbit: MarketTickerSnapshot(
                    exchange: .upbit,
                    tickers: [
                        "BTC": TickerData(
                            price: 125_000_000,
                            change: 1.2,
                            volume: 100_000_000,
                            high24: 126_000_000,
                            low24: 120_000_000,
                            sparkline: [123_500_000, 125_000_000],
                            hasServerSparkline: true
                        )
                    ],
                    meta: .empty
                )
            ],
            candleSnapshotsByKey: [
                "upbit:BTC:1h": candleSnapshot
            ]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.graphState.keepsVisibleGraph == true
                && vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.sparkline.count == 4
        }

        guard let initialRow = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
            return XCTFail("Expected BTC market row")
        }
        XCTAssertTrue(initialRow.graphState.keepsVisibleGraph)
        XCTAssertGreaterThanOrEqual(initialRow.sparkline.count, 4)

        repository.marketDelaysByExchange[.upbit] = 300_000_000
        repository.tickerDelaysByExchange[.upbit] = 300_000_000

        Task {
            await vm.refreshMarketData(forceRefresh: true, reason: "same_exchange_graph_refresh")
        }

        try? await Task.sleep(for: .milliseconds(80))
        await Task.yield()

        guard let refreshingRow = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
            return XCTFail("Expected BTC market row during refresh")
        }
        XCTAssertTrue(refreshingRow.graphState.keepsVisibleGraph)
        XCTAssertNotEqual(refreshingRow.chartPresentation, .placeholder)
        XCTAssertGreaterThanOrEqual(refreshingRow.sparkline.count, 4)
        XCTAssertEqual(refreshingRow.id, MarketIdentity(exchange: .upbit, symbol: "BTC").cacheKey)
    }

    @MainActor
    func testFirstPaintCoarseGraphRefinesWithoutScrollRebind() async {
        let candleSnapshot = CandleSnapshot(
            exchange: .upbit,
            symbol: "BTC",
            interval: "1h",
            candles: [
                CandleData(time: 1, open: 1, high: 2, low: 1, close: 1, volume: 1),
                CandleData(time: 2, open: 2, high: 3, low: 2, close: 2, volume: 1),
                CandleData(time: 3, open: 1.5, high: 2.5, low: 1.4, close: 1.5, volume: 1),
                CandleData(time: 4, open: 2.4, high: 3.0, low: 2.0, close: 2.4, volume: 1),
                CandleData(time: 5, open: 2.1, high: 2.7, low: 1.9, close: 2.1, volume: 1),
                CandleData(time: 6, open: 3, high: 3.2, low: 2.8, close: 3, volume: 1)
            ],
            meta: .empty
        )
        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: MarketCatalogSnapshot(
                    exchange: .upbit,
                    markets: [CoinCatalog.coin(symbol: "BTC")],
                    supportedIntervalsBySymbol: ["BTC": ["1h"]],
                    meta: .empty
                )
            ],
            tickerSnapshots: [
                .upbit: MarketTickerSnapshot(
                    exchange: .upbit,
                    tickers: [
                        "BTC": TickerData(
                            price: 2,
                            change: 1,
                            volume: 100,
                            high24: 3,
                            low24: 1,
                            sparkline: [1, 2],
                            hasServerSparkline: true
                        )
                    ],
                    meta: .empty
                )
            ],
            candleSnapshotsByKey: [
                "upbit:BTC:1h": candleSnapshot
            ],
            candleDelaysByExchange: [.upbit: 180_000_000]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            guard let row = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
                return false
            }
            return row.sparkline.count >= 2
        }

        guard let initialRow = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
            return XCTFail("Expected initial BTC market row")
        }
        XCTAssertTrue(
            initialRow.sparklinePayload.detailLevel == .retainedCoarse ||
                initialRow.sparklinePayload.detailLevel == .liveDetailed
        )

        if initialRow.sparklinePayload.detailLevel == .retainedCoarse {
            await waitUntil(timeoutNanoseconds: 2_000_000_000) {
                vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.sparkline.count == 6
            }

            guard let refinedRow = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
                return XCTFail("Expected refined BTC market row")
            }
            XCTAssertEqual(refinedRow.sparklinePayload.detailLevel, .liveDetailed)
            XCTAssertGreaterThan(refinedRow.graphRenderVersion, initialRow.graphRenderVersion)
            XCTAssertGreaterThan(refinedRow.graphPathVersion, initialRow.graphPathVersion)
        } else {
            XCTAssertEqual(initialRow.sparklinePayload.detailLevel, .liveDetailed)
            XCTAssertEqual(initialRow.sparkline.count, 6)
        }
        XCTAssertEqual(repository.fetchedCandles.first?.symbol, "BTC")
    }

    @MainActor
    func testRefinedSparklineDoesNotRevertToCoarseStreamPatch() async {
        let publicWebSocketService = ManualPublicWebSocketService()
        let candleSnapshot = CandleSnapshot(
            exchange: .upbit,
            symbol: "BTC",
            interval: "1h",
            candles: [
                CandleData(time: 1, open: 1, high: 2, low: 1, close: 1, volume: 1),
                CandleData(time: 2, open: 2, high: 3, low: 2, close: 2, volume: 1),
                CandleData(time: 3, open: 1.5, high: 2.5, low: 1.4, close: 1.5, volume: 1),
                CandleData(time: 4, open: 2.4, high: 3.0, low: 2.0, close: 2.4, volume: 1),
                CandleData(time: 5, open: 2.1, high: 2.7, low: 1.9, close: 2.1, volume: 1),
                CandleData(time: 6, open: 3, high: 3.2, low: 2.8, close: 3, volume: 1)
            ],
            meta: .empty
        )
        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: MarketCatalogSnapshot(
                    exchange: .upbit,
                    markets: [CoinCatalog.coin(symbol: "BTC")],
                    supportedIntervalsBySymbol: ["BTC": ["1h"]],
                    meta: .empty
                )
            ],
            tickerSnapshots: [
                .upbit: MarketTickerSnapshot(
                    exchange: .upbit,
                    tickers: [
                        "BTC": TickerData(
                            price: 2,
                            change: 1,
                            volume: 100,
                            high24: 3,
                            low24: 1,
                            sparkline: [1, 2],
                            hasServerSparkline: true
                        )
                    ],
                    meta: .empty
                )
            ],
            candleSnapshotsByKey: [
                "upbit:BTC:1h": candleSnapshot
            ]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: publicWebSocketService,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.sparklinePayload.detailLevel == .liveDetailed
        }

        guard let refinedRow = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
            return XCTFail("Expected refined BTC market row")
        }
        publicWebSocketService.emitTicker(
            TickerStreamPayload(
                symbol: "BTC",
                exchange: Exchange.upbit.rawValue,
                ticker: TickerData(
                    price: 3.1,
                    change: 1.1,
                    volume: 120,
                    high24: 3.2,
                    low24: 1,
                    sparkline: [],
                    hasServerSparkline: false,
                    timestamp: Date(),
                    delivery: .live
                )
            )
        )
        await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            vm.displayedMarketRows.first(where: { $0.symbol == "BTC" })?.sparkline.last == 3.1
        }

        guard let livePatchedRow = vm.displayedMarketRows.first(where: { $0.symbol == "BTC" }) else {
            return XCTFail("Expected live patched BTC row")
        }
        XCTAssertEqual(livePatchedRow.sparklinePayload.detailLevel, .liveDetailed)
        XCTAssertGreaterThanOrEqual(livePatchedRow.sparkline.count, refinedRow.sparkline.count)
        XCTAssertNotEqual(livePatchedRow.sparklinePayload.detailLevel, .liveCoarse)
    }

    @MainActor
    func testVisibleSparklineRequestIsPrioritizedBeforeOffscreenWarmup() async {
        let coins = (1...18).map { index in
            CoinCatalog.coin(symbol: "C\(index)", isTradable: true, isKimchiComparable: index <= 4)
        }
        let tickerSnapshot = MarketTickerSnapshot(
            exchange: .upbit,
            tickers: Dictionary(uniqueKeysWithValues: coins.map { coin in
                (
                    coin.symbol,
                    TickerData(
                        price: 1_000,
                        change: 1,
                        volume: 1_000,
                        high24: 1_100,
                        low24: 900,
                        sparkline: [990, 1_000],
                        hasServerSparkline: true
                    )
                )
            }),
            meta: .empty
        )
        let repository = SpyMarketRepository()
        repository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: coins,
            supportedIntervalsBySymbol: Dictionary(uniqueKeysWithValues: coins.map { ($0.symbol, ["1h"]) }),
            meta: .empty
        )
        repository.tickerSnapshots[.upbit] = tickerSnapshot

        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.count >= 18
        }

        vm.markMarketRowVisible(symbol: "C18", exchange: .upbit)
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            repository.fetchedCandles.contains(where: { $0.symbol == "C18" })
        }

        let firstRequestedSymbols = repository.fetchedCandles.prefix(12).map(\.symbol)
        XCTAssertTrue(firstRequestedSymbols.contains("C18"))
    }

    @MainActor
    func testDuplicateShortSymbolsAcrossExchangesKeepDistinctMarketIdentityState() async {
        let symbols = ["T", "G", "A", "W", "IN", "IP", "BTC", "ETH"]
        let upbitEntries = symbols.map { symbol in
            (marketId: "upbit-\(symbol)", symbol: symbol, imageURL: "https://assets.example.com/upbit/\(symbol.lowercased()).png")
        }
        let bithumbEntries = symbols.map { symbol in
            (marketId: "bithumb-\(symbol)", symbol: symbol, imageURL: "https://assets.example.com/bithumb/\(symbol.lowercased()).png")
        }
        let korbitEntries = symbols.map { symbol in
            (marketId: "korbit-\(symbol)", symbol: symbol, imageURL: "https://assets.example.com/korbit/\(symbol.lowercased()).png")
        }

        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: makeCatalogSnapshot(exchange: .upbit, entries: upbitEntries),
                .bithumb: makeCatalogSnapshot(exchange: .bithumb, entries: bithumbEntries),
                .korbit: makeCatalogSnapshot(exchange: .korbit, entries: korbitEntries)
            ],
            tickerSnapshots: [
                .upbit: makeTickerSnapshot(
                    exchange: .upbit,
                    entries: upbitEntries.enumerated().map { index, entry in
                        (
                            marketId: entry.marketId,
                            symbol: entry.symbol,
                            price: Double(100 + index),
                            imageURL: entry.imageURL,
                            sparkline: [Double(99 + index), Double(100 + index)]
                        )
                    }
                ),
                .bithumb: makeTickerSnapshot(
                    exchange: .bithumb,
                    entries: bithumbEntries.enumerated().map { index, entry in
                        (
                            marketId: entry.marketId,
                            symbol: entry.symbol,
                            price: Double(200 + index),
                            imageURL: entry.imageURL,
                            sparkline: [Double(199 + index), Double(200 + index)]
                        )
                    }
                ),
                .korbit: makeTickerSnapshot(
                    exchange: .korbit,
                    entries: korbitEntries.enumerated().map { index, entry in
                        (
                            marketId: entry.marketId,
                            symbol: entry.symbol,
                            price: Double(300 + index),
                            imageURL: entry.imageURL,
                            sparkline: [Double(299 + index), Double(300 + index)]
                        )
                    }
                )
            ]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        let upbitTIdentity = MarketIdentity(exchange: .upbit, marketId: "upbit-T", symbol: "T")
        let bithumbTIdentity = MarketIdentity(exchange: .bithumb, marketId: "bithumb-T", symbol: "T")
        let korbitTIdentity = MarketIdentity(exchange: .korbit, marketId: "korbit-T", symbol: "T")

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            Set(vm.displayedMarketRows.map(\.id))
                == Set(upbitEntries.map { MarketIdentity(exchange: .upbit, marketId: $0.marketId, symbol: $0.symbol).cacheKey })
        }

        XCTAssertEqual(Set(vm.displayedMarketRows.map(\.symbol)), Set(symbols))
        XCTAssertEqual(vm.displayedMarketRows.first(where: { $0.marketIdentity == upbitTIdentity })?.imageURL, "https://assets.example.com/upbit/t.png")

        vm.updateExchange(.bithumb, source: "duplicate_symbol_switch")
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            Set(vm.displayedMarketRows.map(\.id))
                == Set(bithumbEntries.map { MarketIdentity(exchange: .bithumb, marketId: $0.marketId, symbol: $0.symbol).cacheKey })
        }

        XCTAssertEqual(vm.displayedMarketRows.first(where: { $0.marketIdentity == bithumbTIdentity })?.imageURL, "https://assets.example.com/bithumb/t.png")

        vm.updateExchange(.korbit, source: "duplicate_symbol_switch")
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            Set(vm.displayedMarketRows.map(\.id))
                == Set(korbitEntries.map { MarketIdentity(exchange: .korbit, marketId: $0.marketId, symbol: $0.symbol).cacheKey })
        }

        XCTAssertEqual(vm.displayedMarketRows.first(where: { $0.marketIdentity == korbitTIdentity })?.imageURL, "https://assets.example.com/korbit/t.png")
        XCTAssertEqual(
            Set(vm.pricesByMarketIdentity.keys.filter { $0.symbol == "T" }),
            Set([upbitTIdentity, bithumbTIdentity, korbitTIdentity])
        )

        vm.updateExchange(.upbit, source: "duplicate_symbol_return")
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.displayedMarketRows.first(where: { $0.marketIdentity == upbitTIdentity })?.imageURL == "https://assets.example.com/upbit/t.png"
        }

        XCTAssertEqual(vm.displayedMarketRows.first(where: { $0.marketIdentity == upbitTIdentity })?.imageURL, "https://assets.example.com/upbit/t.png")
    }

    func testPublicMarketSubscriptionSetKeepsDuplicateSymbolsDistinctAcrossExchangesAndMarketIDs() {
        let identities = [
            MarketIdentity(exchange: .upbit, marketId: "upbit-T", symbol: "T"),
            MarketIdentity(exchange: .bithumb, marketId: "bithumb-T", symbol: "T"),
            MarketIdentity(exchange: .korbit, marketId: "korbit-T", symbol: "T")
        ]
        let subscriptions: Set<PublicMarketSubscription> = [
            PublicMarketSubscription(channel: .ticker, marketIdentity: identities[0]),
            PublicMarketSubscription(channel: .ticker, marketIdentity: identities[1]),
            PublicMarketSubscription(channel: .ticker, marketIdentity: identities[2]),
            PublicMarketSubscription(channel: .ticker, marketIdentity: identities[0])
        ]

        XCTAssertEqual(subscriptions.count, 3)
        XCTAssertEqual(Set(subscriptions.compactMap(\.marketIdentity)), Set(identities))
    }

    @MainActor
    func testDuplicateSymbolSparklineHydrationAndTickerPatchesStayScopedByMarketIdentity() async {
        let upbitEntry = (marketId: "upbit-T", symbol: "T", imageURL: "https://assets.example.com/upbit/t.png")
        let bithumbEntry = (marketId: "bithumb-T", symbol: "T", imageURL: "https://assets.example.com/bithumb/t.png")
        let upbitIdentity = MarketIdentity(exchange: .upbit, marketId: upbitEntry.marketId, symbol: upbitEntry.symbol)
        let bithumbIdentity = MarketIdentity(exchange: .bithumb, marketId: bithumbEntry.marketId, symbol: bithumbEntry.symbol)
        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: makeCatalogSnapshot(exchange: .upbit, entries: [upbitEntry]),
                .bithumb: makeCatalogSnapshot(exchange: .bithumb, entries: [bithumbEntry])
            ],
            tickerSnapshots: [
                .upbit: makeTickerSnapshot(
                    exchange: .upbit,
                    entries: [(marketId: upbitEntry.marketId, symbol: upbitEntry.symbol, price: 101, imageURL: upbitEntry.imageURL, sparkline: [100, 101])]
                ),
                .bithumb: makeTickerSnapshot(
                    exchange: .bithumb,
                    entries: [(marketId: bithumbEntry.marketId, symbol: bithumbEntry.symbol, price: 201, imageURL: bithumbEntry.imageURL, sparkline: [200, 201])]
                )
            ],
            candleSnapshotsByKey: [
                "upbit:T:1h": makeCandleSnapshot(exchange: .upbit, symbol: "T", closes: [98, 99, 100, 101]),
                "bithumb:T:1h": makeCandleSnapshot(exchange: .bithumb, symbol: "T", closes: [198, 199, 200, 201])
            ]
        )
        let publicWebSocketService = ManualPublicWebSocketService()
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: publicWebSocketService,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.pricesByMarketIdentity[upbitIdentity]?.price == 101
        }

        vm.markMarketRowVisible(marketIdentity: upbitIdentity)
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            repository.fetchedCandles.contains(where: { $0.symbol == "T" && $0.exchange == .upbit })
        }

        vm.updateExchange(.bithumb, source: "duplicate_symbol_hydration")
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.displayedMarketRows.first?.marketIdentity == bithumbIdentity
                && vm.prices["T"]?[Exchange.bithumb.rawValue]?.price == 201
        }

        vm.markMarketRowVisible(marketIdentity: bithumbIdentity)
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            repository.fetchedCandles.contains(where: { $0.symbol == "T" && $0.exchange == .bithumb })
        }

        publicWebSocketService.emitTicker(
            TickerStreamPayload(
                symbol: "T",
                exchange: Exchange.upbit.rawValue,
                ticker: TickerData(
                    price: 999,
                    change: 1.0,
                    volume: 10_000,
                    high24: 1_000,
                    low24: 900,
                    sparkline: [100, 999],
                    sparklinePointCount: 2,
                    hasServerSparkline: true,
                    delivery: .live
                )
            )
        )
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.pricesByMarketIdentity[upbitIdentity]?.price == 999
        }

        XCTAssertEqual(vm.prices["T"]?[Exchange.bithumb.rawValue]?.price, 201)
        XCTAssertEqual(vm.displayedMarketRows.first(where: { $0.marketIdentity == bithumbIdentity })?.marketIdentity, bithumbIdentity)

        publicWebSocketService.emitTicker(
            TickerStreamPayload(
                symbol: "T",
                exchange: Exchange.bithumb.rawValue,
                ticker: TickerData(
                    price: 333,
                    change: 1.0,
                    volume: 10_000,
                    high24: 350,
                    low24: 200,
                    sparkline: [201, 333],
                    sparklinePointCount: 2,
                    hasServerSparkline: true,
                    delivery: .live
                )
            )
        )
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.prices["T"]?[Exchange.bithumb.rawValue]?.price == 333
                && vm.displayedMarketRows.first(where: { $0.marketIdentity == bithumbIdentity })?.sparkline.last == 333
        }

        XCTAssertEqual(
            Set(repository.fetchedCandles.filter { $0.symbol == "T" }.map(\.exchange)),
            Set([.upbit, .bithumb])
        )
    }

    @MainActor
    func testLargeMarketUniverseBuildsDistinctIdentityMapsWithoutDictionaryCollisions() async {
        let symbols = ["T", "G", "A", "W", "IN", "IP", "BTC", "ETH"] + (1...212).map { "C\($0)" }
        let entries = symbols.enumerated().map { index, symbol in
            (
                marketId: "upbit-\(symbol)",
                symbol: symbol,
                imageURL: "https://assets.example.com/upbit/\(index).png"
            )
        }
        let repository = SpyMarketRepository()
        repository.marketCatalogSnapshots[.upbit] = makeCatalogSnapshot(exchange: .upbit, entries: entries)
        repository.tickerSnapshots[.upbit] = makeTickerSnapshot(
            exchange: .upbit,
            entries: entries.enumerated().map { index, entry in
                (
                    marketId: entry.marketId,
                    symbol: entry.symbol,
                    price: Double(1_000 + index),
                    imageURL: entry.imageURL,
                    sparkline: [Double(999 + index), Double(1_000 + index)]
                )
            }
        )

        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 3_000_000_000) {
            vm.displayedMarketRows.count == symbols.count
                && vm.pricesByMarketIdentity.keys.filter { $0.exchange == .upbit }.count == symbols.count
        }

        XCTAssertEqual(vm.displayedMarketRows.count, symbols.count)
        XCTAssertEqual(Set(vm.displayedMarketRows.map(\.id)).count, symbols.count)
        XCTAssertEqual(Set(vm.pricesByMarketIdentity.keys.filter { $0.exchange == .upbit }).count, symbols.count)
    }

    @MainActor
    func testFailedSparklineRefreshKeepsStaleVisibleGraph() async {
        let successSnapshot = CandleSnapshot(
            exchange: .upbit,
            symbol: "BTC",
            interval: "1h",
            candles: [
                CandleData(time: 1, open: 1, high: 2, low: 1, close: 1, volume: 1),
                CandleData(time: 2, open: 2, high: 3, low: 2, close: 2, volume: 1),
                CandleData(time: 3, open: 3, high: 4, low: 3, close: 3, volume: 1),
                CandleData(time: 4, open: 4, high: 5, low: 4, close: 4, volume: 1)
            ],
            meta: ResponseMeta(
                fetchedAt: Date(timeIntervalSinceNow: -120),
                isStale: true,
                warningMessage: nil,
                partialFailureMessage: nil
            )
        )
        let repository = SequencedCandleMarketRepository(
            marketCatalogSnapshot: MarketCatalogSnapshot(
                exchange: .upbit,
                markets: [CoinCatalog.coin(symbol: "BTC")],
                supportedIntervalsBySymbol: ["BTC": ["1h"]],
                meta: .empty
            ),
            tickerSnapshot: MarketTickerSnapshot(
                exchange: .upbit,
                tickers: [
                    "BTC": TickerData(
                        price: 125_000_000,
                        change: 1.2,
                        volume: 100_000_000,
                        high24: 126_000_000,
                        low24: 120_000_000,
                        sparkline: [123_500_000, 125_000_000],
                        hasServerSparkline: true
                    )
                ],
                meta: .empty
            ),
            candleResultsBySymbol: [
                "BTC": [
                    .success(successSnapshot),
                    .failure(NetworkServiceError.httpError(503, "temporarily unavailable", .maintenance))
                ]
            ]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.displayedMarketRows.first?.graphState.keepsVisibleGraph == true
                && vm.displayedMarketRows.first?.sparkline.count == 4
        }

        guard let liveRow = vm.displayedMarketRows.first else {
            return XCTFail("Expected live row")
        }

        try? await Task.sleep(for: .milliseconds(1_400))
        vm.markMarketRowVisible(symbol: "BTC", exchange: .upbit)
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            repository.fetchedCandles.count >= 2
        }
        await Task.yield()

        guard let retainedRow = vm.displayedMarketRows.first else {
            return XCTFail("Expected retained row")
        }
        XCTAssertTrue(retainedRow.graphState.keepsVisibleGraph)
        XCTAssertNotEqual(retainedRow.graphState, .placeholder)
        XCTAssertEqual(retainedRow.sparkline, liveRow.sparkline)
    }

    @MainActor
    func testStaleMarketResponseDoesNotOverwriteLatestExchangeSelection() async {
        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: MarketCatalogSnapshot(exchange: .upbit, markets: [CoinCatalog.coin(symbol: "BTC")], supportedIntervalsBySymbol: ["BTC": ["1m", "1h"]], meta: .empty),
                .bithumb: MarketCatalogSnapshot(exchange: .bithumb, markets: [CoinCatalog.coin(symbol: "ETH")], supportedIntervalsBySymbol: ["ETH": ["1m", "1h"]], meta: .empty),
                .coinone: MarketCatalogSnapshot(exchange: .coinone, markets: [CoinCatalog.coin(symbol: "XRP")], supportedIntervalsBySymbol: ["XRP": ["1m", "1h"]], meta: .empty)
            ],
            tickerSnapshots: [
                .upbit: MarketTickerSnapshot(exchange: .upbit, tickers: ["BTC": TickerData(price: 125_000_000, change: 1.2, volume: 100_000_000, high24: 126_000_000, low24: 120_000_000, sparkline: [123_500_000, 125_000_000], hasServerSparkline: true)], meta: .empty),
                .bithumb: MarketTickerSnapshot(exchange: .bithumb, tickers: ["ETH": TickerData(price: 4_900_000, change: -0.1, volume: 60_000_000, high24: 5_000_000, low24: 4_800_000, sparkline: [4_950_000, 4_900_000], hasServerSparkline: true)], meta: .empty),
                .coinone: MarketTickerSnapshot(exchange: .coinone, tickers: ["XRP": TickerData(price: 790, change: 0.3, volume: 30_000_000, high24: 810, low24: 770, sparkline: [780, 790], hasServerSparkline: true)], meta: .empty)
            ],
            marketDelaysByExchange: [.bithumb: 300_000_000],
            tickerDelaysByExchange: [.bithumb: 300_000_000]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.first?.symbol == "BTC"
        }

        vm.updateExchange(.bithumb, source: "stale_test")
        try? await Task.sleep(for: .milliseconds(60))
        vm.updateExchange(.coinone, source: "stale_test")
        try? await Task.sleep(for: .milliseconds(500))
        await Task.yield()

        XCTAssertEqual(vm.selectedExchange, .coinone)
        XCTAssertEqual(vm.displayedMarketRows.map(\.symbol), ["XRP"])
    }

    @MainActor
    func testColdStartUsesPersistedSnapshotCacheBeforeNetworkRefresh() async {
        let cacheStore = InMemoryMarketSnapshotCacheStore()
        cacheStore.catalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "ETH": ["1m", "1h"]],
            meta: ResponseMeta(
                fetchedAt: Date(timeIntervalSince1970: 1_713_510_000),
                isStale: false,
                warningMessage: nil,
                partialFailureMessage: nil
            )
        )
        cacheStore.tickerSnapshots[.upbit] = MarketTickerSnapshot(
            exchange: .upbit,
            coins: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
            tickers: [
                "BTC": TickerData(
                    price: 123_000_000,
                    change: 0.5,
                    volume: 90_000_000,
                    high24: 124_000_000,
                    low24: 121_000_000,
                    sparkline: [122_500_000, 123_000_000],
                    hasServerSparkline: true
                ),
                "ETH": TickerData(
                    price: 4_800_000,
                    change: -0.2,
                    volume: 45_000_000,
                    high24: 4_900_000,
                    low24: 4_700_000,
                    sparkline: [4_820_000, 4_800_000],
                    hasServerSparkline: true
                )
            ],
            meta: ResponseMeta(
                fetchedAt: Date(timeIntervalSince1970: 1_713_510_000),
                isStale: false,
                warningMessage: nil,
                partialFailureMessage: nil
            )
        )
        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: MarketCatalogSnapshot(
                    exchange: .upbit,
                    markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
                    supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "ETH": ["1m", "1h"]],
                    meta: .empty
                )
            ],
            tickerSnapshots: [
                .upbit: MarketTickerSnapshot(
                    exchange: .upbit,
                    coins: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
                    tickers: [
                        "BTC": TickerData(
                            price: 125_000_000,
                            change: 1.2,
                            volume: 100_000_000,
                            high24: 126_000_000,
                            low24: 120_000_000,
                            sparkline: [123_500_000, 125_000_000],
                            hasServerSparkline: true
                        ),
                        "ETH": TickerData(
                            price: 5_000_000,
                            change: -0.4,
                            volume: 50_000_000,
                            high24: 5_100_000,
                            low24: 4_900_000,
                            sparkline: [5_020_000, 5_000_000],
                            hasServerSparkline: true
                        )
                    ],
                    meta: .empty
                )
            ],
            marketDelaysByExchange: [.upbit: 300_000_000],
            tickerDelaysByExchange: [.upbit: 300_000_000]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            marketSnapshotCacheStore: cacheStore
        )

        XCTAssertEqual(Set(vm.displayedMarketRows.map(\.symbol)), Set(["BTC", "ETH"]))
        XCTAssertEqual(vm.prices["BTC"]?[Exchange.upbit.rawValue]?.price, 123_000_000)
        XCTAssertEqual(vm.marketLoadState.phase, .showingCache)

        vm.onAppear()
        await waitUntil {
            vm.prices["BTC"]?[Exchange.upbit.rawValue]?.price == 125_000_000
        }

        XCTAssertEqual(vm.prices["BTC"]?[Exchange.upbit.rawValue]?.price, 125_000_000)
    }

    @MainActor
    func testTickerSnapshotCanRenderRowsBeforeCatalogArrives() async {
        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: MarketCatalogSnapshot(
                    exchange: .upbit,
                    markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
                    supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "ETH": ["1m", "1h"]],
                    meta: .empty
                )
            ],
            tickerSnapshots: [
                .upbit: MarketTickerSnapshot(
                    exchange: .upbit,
                    coins: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
                    tickers: [
                        "BTC": TickerData(
                            price: 125_000_000,
                            change: 1.2,
                            volume: 100_000_000,
                            high24: 126_000_000,
                            low24: 120_000_000,
                            sparkline: [123_500_000, 125_000_000],
                            hasServerSparkline: true
                        ),
                        "ETH": TickerData(
                            price: 5_000_000,
                            change: -0.4,
                            volume: 50_000_000,
                            high24: 5_100_000,
                            low24: 4_900_000,
                            sparkline: [5_020_000, 5_000_000],
                            hasServerSparkline: true
                        )
                    ],
                    meta: .empty
                )
            ],
            marketDelaysByExchange: [.upbit: 400_000_000]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            Set(vm.displayedMarketRows.map(\.symbol)) == Set(["BTC", "ETH"])
        }

        XCTAssertEqual(Set(vm.displayedMarketRows.map(\.symbol)), Set(["BTC", "ETH"]))
        XCTAssertTrue(vm.displayedMarketRows.allSatisfy { $0.isPricePlaceholder == false })
    }

    @MainActor
    func testChangingExchangeUsesCachedSnapshotImmediatelyWhenAvailable() async {
        let cacheStore = InMemoryMarketSnapshotCacheStore()
        cacheStore.catalogSnapshots[.coinone] = MarketCatalogSnapshot(
            exchange: .coinone,
            markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "XRP")],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "XRP": ["1m", "1h"]],
            meta: ResponseMeta(
                fetchedAt: Date(timeIntervalSince1970: 1_713_510_000),
                isStale: false,
                warningMessage: nil,
                partialFailureMessage: nil
            )
        )
        cacheStore.tickerSnapshots[.coinone] = MarketTickerSnapshot(
            exchange: .coinone,
            coins: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "XRP")],
            tickers: [
                "BTC": TickerData(
                    price: 124_500_000,
                    change: 0.9,
                    volume: 98_000_000,
                    high24: 125_000_000,
                    low24: 123_000_000,
                    sparkline: [123_800_000, 124_500_000],
                    hasServerSparkline: true
                ),
                "XRP": TickerData(
                    price: 800,
                    change: 0.2,
                    volume: 40_000_000,
                    high24: 820,
                    low24: 780,
                    sparkline: [790, 800],
                    hasServerSparkline: true
                )
            ],
            meta: ResponseMeta(
                fetchedAt: Date(timeIntervalSince1970: 1_713_510_000),
                isStale: false,
                warningMessage: nil,
                partialFailureMessage: nil
            )
        )
        let repository = DelayedMarketRepository(
            marketCatalogSnapshots: [
                .upbit: MarketCatalogSnapshot(
                    exchange: .upbit,
                    markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
                    supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "ETH": ["1m", "1h"]],
                    meta: .empty
                ),
                .coinone: MarketCatalogSnapshot(
                    exchange: .coinone,
                    markets: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "XRP")],
                    supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "XRP": ["1m", "1h"]],
                    meta: .empty
                )
            ],
            tickerSnapshots: [
                .upbit: MarketTickerSnapshot(
                    exchange: .upbit,
                    coins: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "ETH")],
                    tickers: [
                        "BTC": TickerData(price: 125_000_000, change: 1.2, volume: 100_000_000, high24: 126_000_000, low24: 120_000_000, sparkline: [123_500_000, 125_000_000], hasServerSparkline: true),
                        "ETH": TickerData(price: 5_000_000, change: -0.4, volume: 50_000_000, high24: 5_100_000, low24: 4_900_000, sparkline: [5_020_000, 5_000_000], hasServerSparkline: true)
                    ],
                    meta: .empty
                ),
                .coinone: MarketTickerSnapshot(
                    exchange: .coinone,
                    coins: [CoinCatalog.coin(symbol: "BTC"), CoinCatalog.coin(symbol: "XRP")],
                    tickers: [
                        "BTC": TickerData(price: 124_600_000, change: 1.0, volume: 99_000_000, high24: 125_100_000, low24: 123_100_000, sparkline: [123_900_000, 124_600_000], hasServerSparkline: true),
                        "XRP": TickerData(price: 810, change: 0.3, volume: 41_000_000, high24: 830, low24: 790, sparkline: [800, 810], hasServerSparkline: true)
                    ],
                    meta: .empty
                )
            ],
            marketDelaysByExchange: [.coinone: 300_000_000],
            tickerDelaysByExchange: [.coinone: 300_000_000]
        )
        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService(),
            marketSnapshotCacheStore: cacheStore
        )

        vm.onAppear()
        await waitUntil {
            Set(vm.displayedMarketRows.map(\.symbol)) == Set(["BTC", "ETH"])
        }

        vm.updateExchange(.coinone, source: "cache_switch")
        await Task.yield()

        XCTAssertEqual(Set(vm.displayedMarketRows.map(\.id)), Set([
            MarketIdentity(exchange: .coinone, symbol: "BTC").cacheKey,
            MarketIdentity(exchange: .coinone, symbol: "XRP").cacheKey
        ]))
        XCTAssertNil(vm.marketTransitionMessage)
        XCTAssertEqual(vm.marketLoadState.phase, .showingCache)
    }

    @MainActor
    func testPublicWebSocketFailureShowsPollingFallbackStatusMessage() async {
        let publicWebSocketService = ManualPublicWebSocketService()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: publicWebSocketService,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.isEmpty == false
        }

        publicWebSocketService.emitState(.failed("서버 주소를 확인할 수 없어요. 현재 앱 환경 설정을 확인해주세요."))
        await Task.yield()

        XCTAssertEqual(vm.marketStatusViewState.refreshMode, .pollingFallback)
        XCTAssertNil(vm.marketStatusViewState.message)
        XCTAssertTrue(vm.marketStatusViewState.badges.contains(where: { $0.title == "약간 지연" }))
    }

    @MainActor
    func testKimchiTabUsesSnapshotModeAndClearsPublicSubscriptions() async {
        let publicWebSocketService = RecordingPublicWebSocketService()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: publicWebSocketService,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            publicWebSocketService.lastSubscriptions.isEmpty == false
                && Set(publicWebSocketService.lastSubscriptions.compactMap(\.symbol)) == Set(["BTC", "ETH"])
                && Set(publicWebSocketService.lastSubscriptions.compactMap(\.exchange)) == Set([Exchange.upbit.rawValue])
        }

        vm.setActiveTab(.kimchi)
        await waitUntil {
            publicWebSocketService.lastSubscriptions.isEmpty
                && vm.kimchiStatusViewState.refreshMode == .snapshot
        }

        XCTAssertTrue(publicWebSocketService.lastSubscriptions.isEmpty)
        XCTAssertEqual(vm.kimchiStatusViewState.refreshMode, .snapshot)
    }

    @MainActor
    func testRepeatedChartLoadSkipsDuplicateSnapshotRequestsForSameContext() async {
        let marketRepository = SpyMarketRepository()
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: RecordingPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.contains(where: { $0.symbol == "BTC" })
        }

        vm.selectedCoin = CoinCatalog.coin(symbol: "BTC")
        vm.setActiveTab(.chart)
        await waitUntil {
            !marketRepository.fetchedCandles.isEmpty
                && !marketRepository.fetchedOrderbooks.isEmpty
                && !marketRepository.fetchedTrades.isEmpty
        }

        marketRepository.resetFetchHistory()

        await vm.loadChartData(forceRefresh: false, reason: "repeat_chart_context")

        XCTAssertTrue(marketRepository.fetchedCandles.isEmpty)
        XCTAssertTrue(marketRepository.fetchedOrderbooks.isEmpty)
        XCTAssertTrue(marketRepository.fetchedTrades.isEmpty)
    }

    @MainActor
    func testChartTradesMoveCurrentOneMinuteCandle() async {
        let marketRepository = SpyMarketRepository()
        let publicWebSocketService = ManualPublicWebSocketService()
        let now = Date()
        let previousBucket = Int(now.timeIntervalSince1970) / 60 * 60 - 60
        marketRepository.candleSnapshot = CandleSnapshot(
            exchange: .upbit,
            symbol: "BTC",
            interval: "1m",
            candles: [
                CandleData(
                    time: previousBucket,
                    open: 124_000_000,
                    high: 125_000_000,
                    low: 123_500_000,
                    close: 124_800_000,
                    volume: 12
                )
            ],
            meta: .empty
        )

        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: publicWebSocketService,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.chartPeriod = "1m"
        vm.onAppear()
        await waitUntil {
            vm.displayedMarketRows.contains(where: { $0.symbol == "BTC" })
        }

        vm.selectedCoin = CoinCatalog.coin(symbol: "BTC")
        vm.setActiveTab(.chart)
        await waitUntil {
            vm.candles.count >= 2
        }

        let liveTrade = PublicTrade(
            id: "live-trade-1",
            price: 126_100_000,
            quantity: 0.25,
            side: "buy",
            executedAt: "12:00:01",
            executedDate: now
        )
        publicWebSocketService.emitTrades(
            TradesStreamPayload(
                symbol: "BTC",
                exchange: Exchange.upbit.rawValue,
                trades: [liveTrade]
            )
        )

        await waitUntil {
            vm.candles.last?.close == 126_100_000
                && (vm.candles.last?.volume ?? 0) >= 1
        }

        XCTAssertEqual(vm.candles.last?.close, 126_100_000)
        XCTAssertGreaterThanOrEqual(vm.candles.last?.volume ?? 0, 1)
        XCTAssertEqual(vm.candles.count, 2)
    }

    @MainActor
    func testKimchiUsesFirstPaintComparableSymbolsBeforeFullHydration() async {
        let marketRepository = SpyMarketRepository()
        let comparableMarkets = (1...14).map { index in
            CoinCatalog.coin(symbol: "C\(index)", isTradable: true, isKimchiComparable: true)
        }
        marketRepository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: comparableMarkets,
            supportedIntervalsBySymbol: Dictionary(uniqueKeysWithValues: comparableMarkets.map { ($0.symbol, ["1m"]) }),
            meta: .empty
        )

        let kimchiRepository = SpyKimchiPremiumRepository()
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: kimchiRepository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.setActiveTab(.kimchi)
        await waitUntil {
            kimchiRepository.requestedSymbols.count >= 1
                && vm.representativeKimchiRows.isEmpty == false
        }

        XCTAssertEqual(kimchiRepository.requestedSymbols.first?.count, 5)
        XCTAssertFalse(vm.representativeKimchiRows.isEmpty)
        XCTAssertNotEqual(vm.kimchiPresentationState.representativeRowsState.phase, .loading)

        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            kimchiRepository.requestedSymbols.count >= 2
        }

        let requestedSymbolUnion = Set(kimchiRepository.requestedSymbols.flatMap { $0 })
        XCTAssertEqual(requestedSymbolUnion.count, 14)
    }

    @MainActor
    func testKimchiSelectionUpdatesSelectedExchangeAndRequestsScopedSymbols() async {
        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [
                CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true),
                CoinCatalog.coin(symbol: "ETH", isTradable: true, isKimchiComparable: false)
            ],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "ETH": ["1m", "1h"]],
            meta: .empty
        )
        marketRepository.marketCatalogSnapshots[.bithumb] = MarketCatalogSnapshot(
            exchange: .bithumb,
            markets: [
                CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true),
                CoinCatalog.coin(symbol: "XRP", isTradable: true, isKimchiComparable: false)
            ],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"], "XRP": ["1m", "1h"]],
            meta: .empty
        )
        let kimchiRepository = SpyKimchiPremiumRepository()
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: kimchiRepository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.setActiveTab(.kimchi)
        await waitUntil {
            kimchiRepository.requestedSymbols.count == 1
        }

        XCTAssertEqual(kimchiRepository.requestedSymbols.count, 1)
        XCTAssertEqual(kimchiRepository.requestedExchanges.last, .upbit)
        XCTAssertEqual(kimchiRepository.requestedSymbols.first, ["BTC"])

        vm.updateSelectedDomesticKimchiExchange(.bithumb, source: "test")
        await waitUntil {
            kimchiRepository.requestedSymbols.count == 2
                && vm.selectedExchange == .bithumb
        }

        XCTAssertEqual(vm.selectedExchange, .bithumb)
        XCTAssertEqual(kimchiRepository.requestedSymbols.count, 2)
        XCTAssertEqual(kimchiRepository.requestedExchanges.last, .bithumb)
        XCTAssertEqual(kimchiRepository.requestedSymbols.last, ["BTC"])
        guard case .loaded(let selectedRows) = vm.kimchiPremiumState else {
            return XCTFail("Expected selected kimchi rows")
        }
        XCTAssertEqual(selectedRows.first?.cells.first?.exchange, .bithumb)
    }

    @MainActor
    func testKimchiSameExchangeRefreshKeepsReadyHeaderState() async {
        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true)],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"]],
            meta: .empty
        )

        let repository = DelayedKimchiPremiumRepository(
            snapshotsByExchange: [
                .upbit: KimchiPremiumSnapshot(
                    referenceExchange: .binance,
                    rows: [
                        KimchiPremiumRow(
                            id: "btc-upbit",
                            symbol: "BTC",
                            exchange: .upbit,
                            sourceExchange: .upbit,
                            domesticPrice: 150_000_000,
                            referenceExchangePrice: 100_000,
                            premiumPercent: 3.2,
                            krwConvertedReference: 145_000_000,
                            usdKrwRate: 1450,
                            timestamp: Date(),
                            sourceExchangeTimestamp: Date(),
                            referenceTimestamp: Date(),
                            isStale: false,
                            staleReason: nil
                        )
                    ],
                    fetchedAt: Date(),
                    isStale: false,
                    warningMessage: nil,
                    partialFailureMessage: nil,
                    failedSymbols: []
                )
            ],
            delaysByExchange: [.upbit: 300_000_000]
        )
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: repository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.setActiveTab(.kimchi)
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.kimchiHeaderState.badgeState == .ready
                && vm.representativeKimchiRows.isEmpty == false
        }

        Task {
            await vm.refreshKimchiPremium(forceRefresh: true, reason: "same_exchange_header_refresh")
        }

        try? await Task.sleep(for: .milliseconds(80))
        await Task.yield()

        XCTAssertEqual(vm.kimchiHeaderState.badgeState, .ready)
        XCTAssertNotEqual(vm.kimchiHeaderState.copyState, .representativeLoading)
        XCTAssertFalse(vm.representativeKimchiRows.isEmpty)
        XCTAssertEqual(vm.kimchiPresentationState.selectedExchange, .upbit)
    }

    @MainActor
    func testKimchiExchangeRevisitUsesCachedPresentationWithoutLoadingHeader() async {
        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true)],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"]],
            meta: .empty
        )
        marketRepository.marketCatalogSnapshots[.bithumb] = MarketCatalogSnapshot(
            exchange: .bithumb,
            markets: [CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true)],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"]],
            meta: .empty
        )

        let repository = DelayedKimchiPremiumRepository(
            snapshotsByExchange: [
                .upbit: KimchiPremiumSnapshot(
                    referenceExchange: .binance,
                    rows: [
                        KimchiPremiumRow(
                            id: "btc-upbit",
                            symbol: "BTC",
                            exchange: .upbit,
                            sourceExchange: .upbit,
                            domesticPrice: 150_000_000,
                            referenceExchangePrice: 100_000,
                            premiumPercent: 3.2,
                            krwConvertedReference: 145_000_000,
                            usdKrwRate: 1450,
                            timestamp: Date(),
                            sourceExchangeTimestamp: Date(),
                            referenceTimestamp: Date(),
                            isStale: false,
                            staleReason: nil
                        )
                    ],
                    fetchedAt: Date(),
                    isStale: false,
                    warningMessage: nil,
                    partialFailureMessage: nil,
                    failedSymbols: []
                ),
                .bithumb: KimchiPremiumSnapshot(
                    referenceExchange: .binance,
                    rows: [
                        KimchiPremiumRow(
                            id: "btc-bithumb",
                            symbol: "BTC",
                            exchange: .bithumb,
                            sourceExchange: .bithumb,
                            domesticPrice: 149_500_000,
                            referenceExchangePrice: 100_000,
                            premiumPercent: 3.0,
                            krwConvertedReference: 145_000_000,
                            usdKrwRate: 1450,
                            timestamp: Date(),
                            sourceExchangeTimestamp: Date(),
                            referenceTimestamp: Date(),
                            isStale: false,
                            staleReason: nil
                        )
                    ],
                    fetchedAt: Date(),
                    isStale: false,
                    warningMessage: nil,
                    partialFailureMessage: nil,
                    failedSymbols: []
                )
            ]
        )
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: repository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.setActiveTab(.kimchi)
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.selectedExchange == .upbit
                && vm.kimchiHeaderState.badgeState == .ready
                && vm.representativeKimchiRows.isEmpty == false
        }

        vm.updateSelectedDomesticKimchiExchange(.bithumb, source: "prime_bithumb_cache")
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.selectedExchange == .bithumb
                && vm.kimchiHeaderState.badgeState == .ready
                && vm.representativeKimchiRows.first?.cells.first?.exchange == .bithumb
        }

        vm.updateSelectedDomesticKimchiExchange(.upbit, source: "return_upbit")
        await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.selectedExchange == .upbit
                && vm.kimchiHeaderState.badgeState == .ready
                && vm.representativeKimchiRows.first?.cells.first?.exchange == .upbit
        }

        repository.delaysByExchange[.bithumb] = 300_000_000
        vm.updateSelectedDomesticKimchiExchange(.bithumb, source: "cache_revisit")
        XCTAssertNotEqual(vm.kimchiHeaderState.badgeState, .syncing)
        XCTAssertNotEqual(vm.kimchiHeaderState.copyState, .representativeLoading)
        try? await Task.sleep(for: .milliseconds(80))
        await Task.yield()

        XCTAssertEqual(vm.selectedExchange, .bithumb)
        XCTAssertEqual(vm.kimchiHeaderState.badgeState, .ready)
        XCTAssertNotEqual(vm.kimchiHeaderState.copyState, .representativeLoading)
        XCTAssertFalse(vm.representativeKimchiRows.isEmpty)
        XCTAssertEqual(vm.representativeKimchiRows.first?.cells.first?.exchange, .bithumb)
        XCTAssertNil(vm.kimchiTransitionMessage)
    }

    @MainActor
    func testKimchiSwitchShowsShellRowsUntilNextSnapshotArrives() async {
        let marketRepository = SpyMarketRepository()
        marketRepository.marketCatalogSnapshots[.upbit] = MarketCatalogSnapshot(
            exchange: .upbit,
            markets: [CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true)],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"]],
            meta: .empty
        )
        marketRepository.marketCatalogSnapshots[.bithumb] = MarketCatalogSnapshot(
            exchange: .bithumb,
            markets: [CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true)],
            supportedIntervalsBySymbol: ["BTC": ["1m", "1h"]],
            meta: .empty
        )
        let delayedRepository = DelayedKimchiPremiumRepository(
            snapshotsByExchange: [
                .upbit: KimchiPremiumSnapshot(
                    referenceExchange: .binance,
                    rows: [KimchiPremiumRow(id: "btc-upbit", symbol: "BTC", exchange: .upbit, sourceExchange: .upbit, domesticPrice: 150_000_000, referenceExchangePrice: 100_000, premiumPercent: 3.2, krwConvertedReference: 145_000_000, usdKrwRate: 1450, timestamp: Date(), sourceExchangeTimestamp: Date(), referenceTimestamp: Date(), isStale: false, staleReason: nil)],
                    fetchedAt: Date(),
                    isStale: false,
                    warningMessage: nil,
                    partialFailureMessage: nil,
                    failedSymbols: []
                ),
                .bithumb: KimchiPremiumSnapshot(
                    referenceExchange: .binance,
                    rows: [KimchiPremiumRow(id: "btc-bithumb", symbol: "BTC", exchange: .bithumb, sourceExchange: .bithumb, domesticPrice: 149_500_000, referenceExchangePrice: 100_000, premiumPercent: 3.0, krwConvertedReference: 145_000_000, usdKrwRate: 1450, timestamp: Date(), sourceExchangeTimestamp: Date(), referenceTimestamp: Date(), isStale: false, staleReason: nil)],
                    fetchedAt: Date(),
                    isStale: false,
                    warningMessage: nil,
                    partialFailureMessage: nil,
                    failedSymbols: []
                )
            ],
            delaysByExchange: [.bithumb: 300_000_000]
        )
        let vm = CryptoViewModel(
            marketRepository: marketRepository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: delayedRepository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.setActiveTab(.kimchi)
        await waitUntil {
            vm.kimchiPremiumState.value?.first?.cells.first?.exchange == .upbit
        }

        vm.updateSelectedDomesticKimchiExchange(.bithumb, source: "kimchi_switch")
        try? await Task.sleep(for: .milliseconds(120))
        await Task.yield()

        XCTAssertEqual(vm.selectedExchange, .bithumb)
        XCTAssertEqual(vm.kimchiPresentationState.selectedExchange, .bithumb)
        XCTAssertFalse(vm.kimchiPresentationState.representativeRowsState.rows.isEmpty)
        XCTAssertTrue(vm.kimchiPresentationState.representativeRowsState.rows.allSatisfy { $0.status == .loading })
        XCTAssertTrue(vm.kimchiPresentationState.listRowsState.rows.allSatisfy { $0.status == .loading })
        XCTAssertEqual(vm.kimchiPresentationState.transitionState.phase, .exchangeChanged)
        XCTAssertFalse(vm.kimchiPresentationState.sameExchangeStaleReuse)
        XCTAssertFalse(vm.kimchiPresentationState.crossExchangeStaleReuseAllowed)
        XCTAssertTrue(vm.kimchiTransitionMessage?.contains("준비 중") == true)
        guard case .loaded(let shellRows) = vm.kimchiPremiumState else {
            return XCTFail("Expected kimchi state to keep shell rows during exchange change")
        }
        XCTAssertEqual(shellRows.first?.status, .loading)

        await waitUntil {
            vm.kimchiPremiumState.value?.first?.cells.first?.exchange == .bithumb
                && vm.kimchiPremiumState.value?.first?.status != .loading
        }

        XCTAssertEqual(vm.kimchiPresentationState.transitionState.phase, .partial)
        XCTAssertNil(vm.kimchiTransitionMessage)
    }

    @MainActor
    func testKimchiIgnoresStaleResponseWhenExchangeChanges() async {
        let delayedRepository = DelayedKimchiPremiumRepository(
            snapshotsByExchange: [
                .upbit: KimchiPremiumSnapshot(
                    referenceExchange: .binance,
                    rows: [
                        KimchiPremiumRow(
                            id: "btc-upbit",
                            symbol: "BTC",
                            exchange: .upbit,
                            sourceExchange: .upbit,
                            domesticPrice: 150_000_000,
                            referenceExchangePrice: 100_000,
                            premiumPercent: 3.2,
                            krwConvertedReference: 145_000_000,
                            usdKrwRate: 1450,
                            timestamp: Date(),
                            sourceExchangeTimestamp: Date(),
                            referenceTimestamp: Date(),
                            isStale: false,
                            staleReason: nil
                        )
                    ],
                    fetchedAt: Date(),
                    isStale: false,
                    warningMessage: nil,
                    partialFailureMessage: nil,
                    failedSymbols: []
                ),
                .bithumb: KimchiPremiumSnapshot(
                    referenceExchange: .binance,
                    rows: [
                        KimchiPremiumRow(
                            id: "btc-bithumb",
                            symbol: "BTC",
                            exchange: .bithumb,
                            sourceExchange: .bithumb,
                            domesticPrice: 149_500_000,
                            referenceExchangePrice: 100_000,
                            premiumPercent: 3.0,
                            krwConvertedReference: 145_000_000,
                            usdKrwRate: 1450,
                            timestamp: Date(),
                            sourceExchangeTimestamp: Date(),
                            referenceTimestamp: Date(),
                            isStale: false,
                            staleReason: nil
                        )
                    ],
                    fetchedAt: Date(),
                    isStale: false,
                    warningMessage: nil,
                    partialFailureMessage: nil,
                    failedSymbols: []
                )
            ],
            delaysByExchange: [.upbit: 300_000_000]
        )
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: delayedRepository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.setActiveTab(.kimchi)
        await Task.yield()

        Task {
            await vm.loadKimchiPremium(forceRefresh: true, reason: "stale_upbit")
        }
        await Task.yield()

        vm.updateSelectedDomesticKimchiExchange(.bithumb, source: "stale_test")
        try? await Task.sleep(for: .milliseconds(500))
        await Task.yield()

        XCTAssertEqual(vm.selectedExchange, .bithumb)
        guard case .loaded(let rows) = vm.kimchiPremiumState else {
            return XCTFail("Expected bithumb kimchi rows")
        }
        XCTAssertEqual(rows.first?.cells.first?.exchange, .bithumb)
    }

    @MainActor
    func testKimchiMapsRawBackendMessageToUserFriendlyCopy() async {
        let repository = FailingKimchiPremiumRepository(
            error: NetworkServiceError.httpError(400, "symbols query parameter is required", .unknown)
        )
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: repository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        await vm.loadKimchiPremium(forceRefresh: true, reason: "raw_error_mapping")
        await waitUntil {
            vm.kimchiStatusViewState.message == "데이터를 불러오지 못했어요. 잠시 후 다시 시도해주세요."
        }

        XCTAssertEqual(vm.kimchiStatusViewState.message, "데이터를 불러오지 못했어요. 잠시 후 다시 시도해주세요.")
    }

    @MainActor
    func testKimchiPartialRowsSettleToUnavailableAfterTimeout() async {
        var kimchiRepository = StubKimchiPremiumRepository()
        kimchiRepository.snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                KimchiPremiumRow(
                    id: "btc-upbit",
                    symbol: "BTC",
                    exchange: .upbit,
                    sourceExchange: .upbit,
                    domesticPrice: nil,
                    referenceExchangePrice: 100_000,
                    premiumPercent: nil,
                    krwConvertedReference: 145_000_000,
                    usdKrwRate: 1450,
                    timestamp: Date(),
                    sourceExchangeTimestamp: nil,
                    referenceTimestamp: Date(),
                    isStale: false,
                    staleReason: nil
                )
            ],
            fetchedAt: Date(),
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil,
            failedSymbols: []
        )

        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: kimchiRepository,
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        await vm.loadKimchiPremium(forceRefresh: true, reason: "test_partial_settle")
        await Task.yield()

        guard case .loaded(let initialRows) = vm.kimchiPremiumState else {
            return XCTFail("Expected initial kimchi rows")
        }
        XCTAssertEqual(initialRows.first?.status, .loading)

        await waitUntil(timeoutNanoseconds: 3_000_000_000) {
            vm.kimchiPremiumState.value?.first?.status == .unavailable
        }

        guard case .loaded(let settledRows) = vm.kimchiPremiumState else {
            return XCTFail("Expected settled kimchi rows")
        }
        XCTAssertEqual(settledRows.first?.status, .unavailable)
        XCTAssertEqual(settledRows.first?.cells.first?.status, .unavailable)
    }

    @MainActor
    func testChartCandleFailureKeepsLastSuccessfulCandles() async {
        let firstBucket = Int(Date().timeIntervalSince1970) / 3600 * 3600 - 3600
        let successfulSnapshot = CandleSnapshot(
            exchange: .korbit,
            symbol: "BTC",
            interval: "1h",
            candles: [
                CandleData(time: firstBucket, open: 100, high: 120, low: 90, close: 110, volume: 10),
                CandleData(time: firstBucket + 3600, open: 110, high: 130, low: 100, close: 125, volume: 12)
            ],
            meta: .empty
        )
        let repository = SequencedCandleMarketRepository(
            marketCatalogSnapshot: MarketCatalogSnapshot(
                exchange: .korbit,
                markets: [CoinCatalog.coin(symbol: "BTC", exchange: .korbit)],
                supportedIntervalsBySymbol: ["BTC": ["1h"]],
                meta: .empty
            ),
            tickerSnapshot: MarketTickerSnapshot(
                exchange: .korbit,
                tickers: [
                    "BTC": TickerData(
                        price: 125,
                        change: 1.2,
                        volume: 1000,
                        high24: 130,
                        low24: 90
                    )
                ],
                meta: .empty
            ),
            candleResultsBySymbol: [
                "BTC": [
                    .success(successfulSnapshot),
                    .failure(NetworkServiceError.httpError(503, "korbit candles are temporarily unavailable", .maintenance))
                ]
            ]
        )

        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.updateExchange(.korbit, source: "test")
        vm.selectedCoin = CoinCatalog.coin(symbol: "BTC", exchange: .korbit)
        vm.chartPeriod = "1h"

        await vm.loadChartData(forceRefresh: true, reason: "first_success")
        XCTAssertEqual(vm.candles.count, 2)

        await vm.loadChartData(forceRefresh: true, reason: "second_failure")

        XCTAssertEqual(vm.candles.count, 2)
        XCTAssertEqual(vm.candlesState.warningMessage, "최신 차트 데이터를 불러오지 못했어요. 마지막 데이터를 표시 중입니다.")
        guard case .staleCache = vm.candlesState else {
            return XCTFail("Expected stale candle cache after Korbit candle failure")
        }
    }

    @MainActor
    func testChartOrderbookFailureKeepsLastSuccessfulOrderbook() async {
        let firstBucket = Int(Date().timeIntervalSince1970) / 3600 * 3600 - 3600
        let candleSnapshot = CandleSnapshot(
            exchange: .korbit,
            symbol: "BTC",
            interval: "1h",
            candles: [
                CandleData(time: firstBucket, open: 100, high: 120, low: 90, close: 110, volume: 10)
            ],
            meta: .empty
        )
        let orderbook = OrderbookData(
            asks: [OrderbookEntry(price: 126, qty: 1.5)],
            bids: [OrderbookEntry(price: 125, qty: 2.0)]
        )
        let repository = SequencedCandleMarketRepository(
            marketCatalogSnapshot: MarketCatalogSnapshot(
                exchange: .korbit,
                markets: [CoinCatalog.coin(symbol: "BTC", exchange: .korbit)],
                supportedIntervalsBySymbol: ["BTC": ["1h"]],
                meta: .empty
            ),
            tickerSnapshot: MarketTickerSnapshot(
                exchange: .korbit,
                tickers: [
                    "BTC": TickerData(price: 125, change: 1.2, volume: 1000, high24: 130, low24: 90)
                ],
                meta: .empty
            ),
            candleResultsBySymbol: [
                "BTC": [
                    .success(candleSnapshot),
                    .success(candleSnapshot)
                ]
            ],
            orderbookResultsBySymbol: [
                "BTC": [
                    .success(OrderbookSnapshot(exchange: .korbit, symbol: "BTC", orderbook: orderbook, meta: .empty)),
                    .failure(NetworkServiceError.httpError(503, "korbit orderbook is temporarily unavailable", .maintenance))
                ]
            ]
        )

        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.updateExchange(.korbit, source: "test")
        vm.selectedCoin = CoinCatalog.coin(symbol: "BTC", exchange: .korbit)
        vm.chartPeriod = "1h"

        await vm.loadChartData(forceRefresh: true, reason: "first_success")
        XCTAssertEqual(vm.orderbookState.value?.bids.first?.price, 125)

        await vm.loadChartData(forceRefresh: true, reason: "second_failure")

        XCTAssertEqual(vm.orderbookState.value?.bids.first?.price, 125)
        XCTAssertEqual(vm.orderbookState.warningMessage, "최신 호가 데이터를 불러오지 못했어요. 마지막 데이터를 표시 중입니다.")
        guard case .staleCache = vm.orderbookState else {
            return XCTFail("Expected stale orderbook cache after Korbit orderbook failure")
        }
        guard case .loaded = vm.candleChartState else {
            return XCTFail("Expected candle section to remain independently loaded")
        }
    }

    @MainActor
    func testChartTradesEmptyUsesIndependentEmptyState() async {
        let firstBucket = Int(Date().timeIntervalSince1970) / 3600 * 3600 - 3600
        let candleSnapshot = CandleSnapshot(
            exchange: .korbit,
            symbol: "BTC",
            interval: "1h",
            candles: [
                CandleData(time: firstBucket, open: 100, high: 120, low: 90, close: 110, volume: 10)
            ],
            meta: .empty
        )
        let repository = SequencedCandleMarketRepository(
            marketCatalogSnapshot: MarketCatalogSnapshot(
                exchange: .korbit,
                markets: [CoinCatalog.coin(symbol: "BTC", exchange: .korbit)],
                supportedIntervalsBySymbol: ["BTC": ["1h"]],
                meta: .empty
            ),
            tickerSnapshot: MarketTickerSnapshot(
                exchange: .korbit,
                tickers: [
                    "BTC": TickerData(price: 125, change: 1.2, volume: 1000, high24: 130, low24: 90)
                ],
                meta: .empty
            ),
            candleResultsBySymbol: [
                "BTC": [.success(candleSnapshot)]
            ],
            tradeResultsBySymbol: [
                "BTC": [
                    .success(PublicTradesSnapshot(exchange: .korbit, symbol: "BTC", trades: [], meta: .empty))
                ]
            ]
        )

        let vm = CryptoViewModel(
            marketRepository: repository,
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        vm.updateExchange(.korbit, source: "test")
        vm.selectedCoin = CoinCatalog.coin(symbol: "BTC", exchange: .korbit)
        vm.chartPeriod = "1h"

        await vm.loadChartData(forceRefresh: true, reason: "trades_empty")

        XCTAssertTrue(vm.recentTrades.isEmpty)
        guard case .empty = vm.recentTradesState else {
            return XCTFail("Expected independent empty state for trades")
        }
        guard case .loaded = vm.candleChartState else {
            return XCTFail("Expected candle section to remain loaded when trades are empty")
        }
    }
}
