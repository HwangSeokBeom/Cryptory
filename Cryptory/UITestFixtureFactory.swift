#if DEBUG
import Foundation

enum UITestFixtureFactory {
    @MainActor
    static func makeViewModelIfNeeded() -> CryptoViewModel? {
        guard let scenario = ProcessInfo.processInfo.environment["CRYPTORY_UI_TEST_SCENARIO"] else {
            return nil
        }

        let defaults = makeIsolatedDefaults(scenario: scenario)
        let viewModel = CryptoViewModel(
            marketRepository: UITestMarketRepository(),
            tradingRepository: UITestTradingRepository(),
            portfolioRepository: UITestPortfolioRepository(),
            kimchiPremiumRepository: UITestKimchiPremiumRepository(),
            exchangeConnectionsRepository: UITestExchangeConnectionsRepository(),
            authService: UITestAuthenticationService(),
            publicWebSocketService: UITestPublicWebSocketService(),
            privateWebSocketService: UITestPrivateWebSocketService(),
            marketSnapshotCacheStore: nil,
            userDefaults: defaults
        )

        switch scenario {
        case "kimchi_freshness":
            viewModel.setActiveTab(.kimchi)
        case "chart_settings":
            viewModel.selectCoin(CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true))
        default:
            return nil
        }

        return viewModel
    }

    private static func makeIsolatedDefaults(scenario: String) -> UserDefaults {
        let suiteName = "Cryptory.UITests.\(scenario)"
        let defaults = UserDefaults(suiteName: suiteName)!
        if ProcessInfo.processInfo.environment["CRYPTORY_UI_TEST_RESET_DEFAULTS"] != "0" {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private struct UITestMarketRepository: MarketRepositoryProtocol {
    let marketCandlesEndpointPath = "/market/candles"

    func fetchMarkets(exchange: Exchange) async throws -> MarketCatalogSnapshot {
        let markets = [
            CoinCatalog.coin(symbol: "BTC", isTradable: true, isKimchiComparable: true),
            CoinCatalog.coin(symbol: "ETH", isTradable: true, isKimchiComparable: true)
        ]
        return MarketCatalogSnapshot(
            exchange: exchange,
            markets: markets,
            supportedIntervalsBySymbol: ["BTC": ["1m"], "ETH": ["1m"]],
            meta: .empty
        )
    }

    func fetchTickers(exchange: Exchange) async throws -> MarketTickerSnapshot {
        MarketTickerSnapshot(
            exchange: exchange,
            coins: [
                CoinCatalog.coin(symbol: "BTC"),
                CoinCatalog.coin(symbol: "ETH")
            ],
            tickers: [
                "BTC": TickerData(
                    price: 150_000_000,
                    change: 0.4,
                    volume: 100_000_000,
                    high24: 151_000_000,
                    low24: 149_000_000,
                    sparkline: [149_800_000, 150_000_000],
                    hasServerSparkline: true,
                    timestamp: Date(),
                    sourceExchange: exchange
                ),
                "ETH": TickerData(
                    price: 5_000_000,
                    change: -0.2,
                    volume: 60_000_000,
                    high24: 5_100_000,
                    low24: 4_900_000,
                    sparkline: [5_020_000, 5_000_000],
                    hasServerSparkline: true,
                    timestamp: Date(),
                    sourceExchange: exchange
                )
            ],
            meta: .empty
        )
    }

    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookSnapshot {
        OrderbookSnapshot(
            exchange: exchange,
            symbol: symbol,
            orderbook: OrderbookData(
                asks: [OrderbookEntry(price: 150_200_000, qty: 0.4)],
                bids: [OrderbookEntry(price: 149_900_000, qty: 0.7)]
            ),
            meta: .empty
        )
    }

    func fetchTrades(symbol: String, exchange: Exchange) async throws -> PublicTradesSnapshot {
        PublicTradesSnapshot(exchange: exchange, symbol: symbol, trades: [], meta: .empty)
    }

    func fetchCandles(symbol: String, exchange: Exchange, interval: String) async throws -> CandleSnapshot {
        let baseTime = 1_775_000_000
        let candles = (0..<36).map { index in
            let open = 149_000_000 + Double(index * 42_000)
            let close = open + (index.isMultiple(of: 3) ? -180_000 : 230_000)
            return CandleData(
                time: baseTime + index * 60,
                open: open,
                high: max(open, close) + 310_000,
                low: min(open, close) - 280_000,
                close: close,
                volume: 2_000 + index * 120
            )
        }
        return CandleSnapshot(exchange: exchange, symbol: symbol, interval: interval, candles: candles, meta: .empty)
    }
}

private struct UITestKimchiPremiumRepository: KimchiPremiumRepositoryProtocol {
    func fetchSnapshot(exchange: Exchange, symbols: [String]) async throws -> KimchiPremiumSnapshot {
        let now = Date()
        return KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                KimchiPremiumRow(
                    id: "btc-\(exchange.rawValue)",
                    symbol: "BTC",
                    exchange: exchange,
                    sourceExchange: exchange,
                    domesticPrice: 150_000_000,
                    referenceExchangePrice: 100_000,
                    premiumPercent: 3.2,
                    krwConvertedReference: 145_000_000,
                    usdKrwRate: 1450,
                    timestamp: now,
                    sourceExchangeTimestamp: now,
                    referenceTimestamp: now.addingTimeInterval(-45),
                    isStale: true,
                    staleReason: "기준가 반영이 늦어지고 있어요.",
                    freshnessState: .stale,
                    freshnessReason: "기준가 반영이 늦어지고 있어요.",
                    updatedAt: now
                )
            ],
            fetchedAt: now,
            isStale: true,
            warningMessage: nil,
            partialFailureMessage: "일부 비교 종목이 제외되었어요.",
            failedSymbols: ["ETH"]
        )
    }
}

private struct UITestTradingRepository: TradingRepositoryProtocol {
    func fetchChance(session: AuthSession, exchange: Exchange, symbol: String) async throws -> TradingChance {
        TradingChance(
            exchange: exchange,
            symbol: symbol,
            supportedOrderTypes: [.limit, .market],
            minimumOrderAmount: nil,
            maximumOrderAmount: nil,
            priceUnit: nil,
            quantityPrecision: nil,
            bidBalance: 0,
            askBalance: 0,
            feeRate: nil,
            warningMessage: nil
        )
    }

    func createOrder(session: AuthSession, request: TradingOrderCreateRequest) async throws -> OrderRecord {
        throw NetworkServiceError.parsingFailed("UI 테스트에서는 주문을 지원하지 않아요.")
    }

    func cancelOrder(session: AuthSession, exchange: Exchange, orderID: String) async throws {}

    func fetchOrderDetail(session: AuthSession, exchange: Exchange, orderID: String) async throws -> OrderRecord {
        throw NetworkServiceError.parsingFailed("UI 테스트에서는 주문 상세를 지원하지 않아요.")
    }

    func fetchOpenOrders(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> OrderRecordsSnapshot {
        OrderRecordsSnapshot(exchange: exchange, orders: [], meta: .empty)
    }

    func fetchFills(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> TradeFillsSnapshot {
        TradeFillsSnapshot(exchange: exchange, fills: [], meta: .empty)
    }
}

private struct UITestPortfolioRepository: PortfolioRepositoryProtocol {
    func fetchSummary(session: AuthSession, exchange: Exchange) async throws -> PortfolioSnapshot {
        PortfolioSnapshot(
            exchange: exchange,
            totalAsset: 0,
            availableAsset: 0,
            lockedAsset: 0,
            cash: 0,
            holdings: [],
            fetchedAt: Date(),
            isStale: false,
            partialFailureMessage: nil
        )
    }

    func fetchHistory(session: AuthSession, exchange: Exchange) async throws -> PortfolioHistorySnapshot {
        PortfolioHistorySnapshot(exchange: exchange, items: [], meta: .empty)
    }
}

private struct UITestExchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol {
    let crudCapability = ExchangeConnectionCRUDCapability(canCreate: false, canDelete: false, canUpdate: false)

    func fetchConnections(session: AuthSession) async throws -> ExchangeConnectionsSnapshot {
        ExchangeConnectionsSnapshot(connections: [], meta: .empty)
    }

    func createConnection(session: AuthSession, request: ExchangeConnectionUpsertRequest) async throws -> ExchangeConnection {
        throw NetworkServiceError.parsingFailed("UI 테스트에서는 거래소 연결 생성을 지원하지 않아요.")
    }

    func updateConnection(session: AuthSession, request: ExchangeConnectionUpdateRequest) async throws -> ExchangeConnection {
        throw NetworkServiceError.parsingFailed("UI 테스트에서는 거래소 연결 수정을 지원하지 않아요.")
    }

    func deleteConnection(session: AuthSession, connectionID: String) async throws {}
}

private struct UITestAuthenticationService: AuthenticationServiceProtocol {
    func signIn(email: String, password: String) async throws -> AuthSession {
        AuthSession(accessToken: "ui-test-token", refreshToken: nil, userID: "ui-test", email: email)
    }

    func signUp(request: SignUpRequest) async throws -> AuthSession {
        AuthSession(accessToken: "ui-test-token", refreshToken: nil, userID: "ui-test", email: request.email)
    }

    func signInWithGoogle(request: GoogleSocialLoginRequest) async throws -> AuthSession {
        AuthSession(accessToken: "ui-test-token", refreshToken: nil, userID: "ui-test", email: request.email)
    }

    func signInWithApple(request: AppleSocialLoginRequest) async throws -> AuthSession {
        AuthSession(accessToken: "ui-test-token", refreshToken: nil, userID: "ui-test", email: request.email)
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        AuthSession(accessToken: "ui-test-token-refreshed", refreshToken: refreshToken, userID: "ui-test", email: nil)
    }

    func signOut(session: AuthSession) async throws {}

    func deleteAccount(session: AuthSession) async throws {}
}

private final class UITestPublicWebSocketService: PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?
    var onCandlesReceived: ((CandleStreamPayload) -> Void)?

    func connect() {
        onConnectionStateChange?(.connected)
    }

    func disconnect() {
        onConnectionStateChange?(.disconnected)
    }

    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {}
}

private final class UITestPrivateWebSocketService: PrivateWebSocketServicing {
    var onConnectionStateChange: ((PrivateWebSocketConnectionState) -> Void)?
    var onOrderReceived: ((OrderStreamPayload) -> Void)?
    var onFillReceived: ((FillStreamPayload) -> Void)?

    func connect(accessToken: String) {
        onConnectionStateChange?(.connected)
    }

    func disconnect() {
        onConnectionStateChange?(.disconnected)
    }

    func updateSubscriptions(_ subscriptions: Set<PrivateTradingSubscription>) {}
}
#endif
