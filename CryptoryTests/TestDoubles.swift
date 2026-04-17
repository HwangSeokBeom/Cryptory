import XCTest
@testable import Cryptory

struct StubMarketRepository: MarketRepositoryProtocol {
    var marketCatalogSnapshot = MarketCatalogSnapshot(exchange: .upbit, markets: [CoinCatalog.coin(symbol: "BTC")], supportedIntervalsBySymbol: ["BTC": ["1m", "1h", "1d"]], meta: .empty)
    var tickerSnapshot = MarketTickerSnapshot(exchange: .upbit, tickers: ["BTC": TickerData(price: 125_000_000, change: 1.2, volume: 100_000_000, high24: 126_000_000, low24: 120_000_000)], meta: .empty)
    var orderbookSnapshot = OrderbookSnapshot(exchange: .upbit, symbol: "BTC", orderbook: OrderbookData(asks: [], bids: []), meta: .empty)
    var publicTradesSnapshot = PublicTradesSnapshot(exchange: .upbit, symbol: "BTC", trades: [], meta: .empty)
    var candleSnapshot = CandleSnapshot(exchange: .upbit, symbol: "BTC", interval: "1h", candles: [], meta: .empty)

    func fetchMarkets(exchange: Exchange) async throws -> MarketCatalogSnapshot { marketCatalogSnapshot }
    func fetchTickers(exchange: Exchange) async throws -> MarketTickerSnapshot { tickerSnapshot }
    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookSnapshot { orderbookSnapshot }
    func fetchTrades(symbol: String, exchange: Exchange) async throws -> PublicTradesSnapshot { publicTradesSnapshot }
    func fetchCandles(symbol: String, exchange: Exchange, interval: String) async throws -> CandleSnapshot { candleSnapshot }
}

final class SpyTradingRepository: TradingRepositoryProtocol {
    private(set) var fetchChanceCount = 0
    private(set) var fetchOpenOrdersCount = 0
    private(set) var fetchFillsCount = 0
    private(set) var fetchOrderDetailCount = 0
    private(set) var createOrderCount = 0
    private(set) var cancelOrderCount = 0

    var chance = TradingChance(
        exchange: .upbit,
        symbol: "BTC",
        supportedOrderTypes: [.limit, .market],
        minimumOrderAmount: 5_000,
        maximumOrderAmount: nil,
        priceUnit: 1_000,
        quantityPrecision: 6,
        bidBalance: 1_000_000,
        askBalance: 0.25,
        feeRate: 0.0005,
        warningMessage: nil
    )
    var openOrdersSnapshot = OrderRecordsSnapshot(exchange: .upbit, orders: [], meta: .empty)
    var fillsSnapshot = TradeFillsSnapshot(exchange: .upbit, fills: [], meta: .empty)
    var orderDetail = OrderRecord(
        id: "order-1",
        symbol: "BTC",
        side: "buy",
        orderType: .limit,
        price: 125_000_000,
        averageExecutedPrice: nil,
        qty: 0.01,
        executedQuantity: 0,
        remainingQuantity: 0.01,
        total: 1_250_000,
        time: "12:00:00",
        createdAt: Date(),
        exchange: "업비트",
        status: "wait",
        canCancel: true
    )

    func fetchChance(session: AuthSession, exchange: Exchange, symbol: String) async throws -> TradingChance {
        fetchChanceCount += 1
        return chance
    }

    func createOrder(session: AuthSession, request: TradingOrderCreateRequest) async throws -> OrderRecord {
        createOrderCount += 1
        return orderDetail
    }

    func cancelOrder(session: AuthSession, exchange: Exchange, orderID: String) async throws {
        cancelOrderCount += 1
    }

    func fetchOrderDetail(session: AuthSession, exchange: Exchange, orderID: String) async throws -> OrderRecord {
        fetchOrderDetailCount += 1
        return orderDetail
    }

    func fetchOpenOrders(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> OrderRecordsSnapshot {
        fetchOpenOrdersCount += 1
        return openOrdersSnapshot
    }

    func fetchFills(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> TradeFillsSnapshot {
        fetchFillsCount += 1
        return fillsSnapshot
    }
}

final class SpyPortfolioRepository: PortfolioRepositoryProtocol {
    private(set) var fetchSummaryCount = 0
    private(set) var fetchHistoryCount = 0

    var summary = PortfolioSnapshot(
        exchange: .upbit,
        totalAsset: 10_000_000,
        availableAsset: 7_500_000,
        lockedAsset: 2_500_000,
        cash: 1_000_000,
        holdings: [
            Holding(
                symbol: "BTC",
                totalQuantity: 0.1,
                availableQuantity: 0.08,
                lockedQuantity: 0.02,
                averageBuyPrice: 120_000_000,
                evaluationAmount: 12_500_000,
                profitLoss: 500_000,
                profitLossRate: 4.0
            )
        ],
        fetchedAt: Date(),
        isStale: false,
        partialFailureMessage: nil
    )
    var historySnapshot = PortfolioHistorySnapshot(exchange: .upbit, items: [], meta: .empty)

    func fetchSummary(session: AuthSession, exchange: Exchange) async throws -> PortfolioSnapshot {
        fetchSummaryCount += 1
        return summary
    }

    func fetchHistory(session: AuthSession, exchange: Exchange) async throws -> PortfolioHistorySnapshot {
        fetchHistoryCount += 1
        return historySnapshot
    }
}

final class SpyExchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol {
    var crudCapability = ExchangeConnectionCRUDCapability(canCreate: true, canDelete: true, canUpdate: true)
    private(set) var fetchConnectionsCount = 0
    private(set) var createConnectionCount = 0
    private(set) var updateConnectionCount = 0
    private(set) var deleteConnectionCount = 0

    var snapshot = ExchangeConnectionsSnapshot(
        connections: [
            ExchangeConnection(
                id: "upbit-1",
                exchange: .upbit,
                permission: .tradeEnabled,
                nickname: "업비트 메인",
                isActive: true,
                status: .connected,
                statusMessage: nil,
                maskedCredentialSummary: "acc***12",
                lastValidatedAt: Date(),
                updatedAt: Date()
            )
        ],
        meta: .empty
    )

    func fetchConnections(session: AuthSession) async throws -> ExchangeConnectionsSnapshot {
        fetchConnectionsCount += 1
        return snapshot
    }

    func createConnection(session: AuthSession, request: ExchangeConnectionUpsertRequest) async throws -> ExchangeConnection {
        createConnectionCount += 1
        return snapshot.connections[0]
    }

    func updateConnection(session: AuthSession, request: ExchangeConnectionUpdateRequest) async throws -> ExchangeConnection {
        updateConnectionCount += 1
        return snapshot.connections[0]
    }

    func deleteConnection(session: AuthSession, connectionID: String) async throws {
        deleteConnectionCount += 1
    }
}

struct StubKimchiPremiumRepository: KimchiPremiumRepositoryProtocol {
    var snapshot = KimchiPremiumSnapshot(
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
        warningMessage: nil
    )

    func fetchSnapshot(symbols: [String]?) async throws -> KimchiPremiumSnapshot { snapshot }
}

struct StubAuthenticationService: AuthenticationServiceProtocol {
    func signIn(email: String, password: String) async throws -> AuthSession {
        AuthSession(accessToken: "token", refreshToken: nil, userID: "user-1", email: email)
    }
}

final class NoOpPublicWebSocketService: PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?
    var onCandlesReceived: ((CandleStreamPayload) -> Void)?

    func connect() {
        Task { @MainActor [onConnectionStateChange] in
            onConnectionStateChange?(.connected)
        }
    }

    func disconnect() {}
    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {}
}

final class ManualPublicWebSocketService: PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?
    var onCandlesReceived: ((CandleStreamPayload) -> Void)?

    func connect() {}
    func disconnect() {}
    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {}

    func emitState(_ state: PublicWebSocketConnectionState) {
        onConnectionStateChange?(state)
    }
}

final class NoOpPrivateWebSocketService: PrivateWebSocketServicing {
    var onConnectionStateChange: ((PrivateWebSocketConnectionState) -> Void)?
    var onOrderReceived: ((OrderStreamPayload) -> Void)?
    var onFillReceived: ((FillStreamPayload) -> Void)?

    func connect(accessToken: String) {
        Task { @MainActor [onConnectionStateChange] in
            onConnectionStateChange?(.connected)
        }
    }

    func disconnect() {}
    func updateSubscriptions(_ subscriptions: Set<PrivateTradingSubscription>) {}
}

final class URLProtocolSpy: URLProtocol {
    static var requestCount = 0

    static func reset() {
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
