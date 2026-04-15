import XCTest
@testable import Cryptory

final class CryptoryTests: XCTestCase {

    func testTabAccessPolicyMatchesRequirements() {
        XCTAssertEqual(Tab.market.accessRequirement, .publicAccess)
        XCTAssertEqual(Tab.chart.accessRequirement, .publicAccess)
        XCTAssertEqual(Tab.kimchi.accessRequirement, .publicAccess)
        XCTAssertEqual(Tab.portfolio.accessRequirement, .authenticatedRequired)
        XCTAssertEqual(Tab.trade.accessRequirement, .authenticatedRequired)
    }

    func testLiveConfigurationUsesUnifiedPublicAndPrivatePrefixes() {
        let configuration = APIConfiguration.live

        [configuration.loginPath, configuration.tickersPath, configuration.candlesPath, configuration.orderbookPath, configuration.tradesPath]
            .forEach { path in
                XCTAssertTrue(path.hasPrefix(APIConfiguration.publicPrefix), "Expected public prefix for \(path)")
            }

        [configuration.portfolioPath, configuration.ordersPath, configuration.exchangeConnectionsPath]
            .forEach { path in
                XCTAssertTrue(path.hasPrefix(APIConfiguration.privatePrefix), "Expected private prefix for \(path)")
                XCTAssertFalse(path.contains("/me/"), "Legacy private path should be removed: \(path)")
            }
    }

    func testAuthenticatedRequestBuilderBlocksGuestBeforeDispatchForAllPrivatePaths() throws {
        let client = APIClient(configuration: APIConfiguration(
            baseURL: "https://example.com",
            loginPath: "/api/v1/public/auth/login",
            tickersPath: "/api/v1/public/markets/tickers",
            candlesPath: "/api/v1/public/markets/candles",
            orderbookPath: "/api/v1/public/markets/orderbook",
            tradesPath: "/api/v1/public/markets/trades",
            portfolioPath: "/api/v1/private/portfolio",
            ordersPath: "/api/v1/private/orders",
            exchangeConnectionsPath: "/api/v1/private/exchange-connections",
            exchangeConnectionsCreateEnabled: false,
            exchangeConnectionsDeleteEnabled: false
        ))

        for path in [
            client.configuration.portfolioPath,
            client.configuration.ordersPath,
            client.configuration.exchangeConnectionsPath,
            client.configuration.exchangeConnectionPath(id: "connection-1")
        ] {
            XCTAssertThrowsError(
                try client.makeRequest(
                    path: path,
                    accessRequirement: .authenticatedRequired
                )
            ) { error in
                guard case NetworkServiceError.authenticationRequired = error else {
                    return XCTFail("Expected authenticationRequired, got \(error)")
                }
            }
        }
    }

    func testAuthenticatedRequestJSONDoesNotHitNetworkWithoutToken() async {
        URLProtocolSpy.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)

        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/api/v1/public/auth/login",
                tickersPath: "/api/v1/public/markets/tickers",
                candlesPath: "/api/v1/public/markets/candles",
                orderbookPath: "/api/v1/public/markets/orderbook",
                tradesPath: "/api/v1/public/markets/trades",
                portfolioPath: "/api/v1/private/portfolio",
                ordersPath: "/api/v1/private/orders",
                exchangeConnectionsPath: "/api/v1/private/exchange-connections",
                exchangeConnectionsCreateEnabled: false,
                exchangeConnectionsDeleteEnabled: false
            ),
            session: session
        )

        do {
            _ = try await client.requestJSON(
                path: "/api/v1/private/orders",
                accessRequirement: .authenticatedRequired
            )
            XCTFail("Expected authenticationRequired")
        } catch {
            guard case NetworkServiceError.authenticationRequired = error else {
                return XCTFail("Expected authenticationRequired, got \(error)")
            }
        }

        XCTAssertEqual(URLProtocolSpy.requestCount, 0)
    }

    @MainActor
    func testGuestProtectedLoadsDoNotCallAccountService() async {
        let accountService = SpyAccountService()
        let vm = CryptoViewModel(
            publicService: DummyPublicMarketService(),
            accountService: accountService,
            authService: StubAuthenticationService(),
            webSocketService: NoOpWebSocketService()
        )

        await vm.loadPortfolio()
        await vm.loadOrders()
        await vm.loadExchangeConnections()

        XCTAssertEqual(accountService.fetchPortfolioCount, 0)
        XCTAssertEqual(accountService.fetchOrdersCount, 0)
        XCTAssertEqual(accountService.fetchExchangeConnectionsCount, 0)
        XCTAssertFalse(vm.isAuthenticated)
    }

    @MainActor
    func testLoginOnPortfolioGateReturnsToPortfolioAndLoadsAuthenticatedData() async {
        let accountService = SpyAccountService()
        let vm = CryptoViewModel(
            publicService: DummyPublicMarketService(),
            accountService: accountService,
            authService: StubAuthenticationService(),
            webSocketService: NoOpWebSocketService()
        )

        vm.setActiveTab(.portfolio)
        vm.presentLogin(for: .portfolio)
        vm.loginEmail = "user@example.com"
        vm.loginPassword = "password"

        await vm.submitLogin()

        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertEqual(accountService.fetchExchangeConnectionsCount, 1)
        XCTAssertEqual(accountService.fetchPortfolioCount, 1)
        XCTAssertEqual(vm.activeAuthGate, nil)
    }

    @MainActor
    func testLoginOnTradeGateReturnsToTradeAndLoadsOrders() async {
        let accountService = SpyAccountService()
        let vm = CryptoViewModel(
            publicService: DummyPublicMarketService(),
            accountService: accountService,
            authService: StubAuthenticationService(),
            webSocketService: NoOpWebSocketService()
        )

        vm.setActiveTab(.trade)
        vm.presentLogin(for: .trade)
        vm.loginEmail = "user@example.com"
        vm.loginPassword = "password"

        await vm.submitLogin()

        XCTAssertEqual(vm.activeTab, .trade)
        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertEqual(accountService.fetchExchangeConnectionsCount, 1)
        XCTAssertEqual(accountService.fetchOrdersCount, 1)
        XCTAssertEqual(vm.activeAuthGate, nil)
    }

    @MainActor
    func testLoginForExchangeConnectionsReopensSheetAfterAuthentication() async {
        let accountService = SpyAccountService()
        let vm = CryptoViewModel(
            publicService: DummyPublicMarketService(),
            accountService: accountService,
            authService: StubAuthenticationService(),
            webSocketService: NoOpWebSocketService()
        )

        vm.presentLogin(for: .exchangeConnections)
        vm.loginEmail = "user@example.com"
        vm.loginPassword = "password"

        await vm.submitLogin()

        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertTrue(vm.isExchangeConnectionsPresented)
        XCTAssertEqual(accountService.fetchExchangeConnectionsCount, 1)
    }

    func testMarketWebSocketTickerParserMatchesContract() {
        let message = """
        {
          "type": "ticker",
          "exchange": "upbit",
          "symbol": "BTC",
          "data": {
            "price": 125000000,
            "changePercent": 1.25,
            "volume24h": 123456789,
            "high24": 126000000,
            "low24": 120000000
          }
        }
        """

        guard case .some(.ticker(let payload)) = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("Expected ticker payload")
        }

        XCTAssertEqual(payload.exchange, "upbit")
        XCTAssertEqual(payload.symbol, "BTC")
        XCTAssertEqual(payload.ticker.price, 125000000)
        XCTAssertEqual(payload.ticker.change, 1.25)
        XCTAssertEqual(payload.ticker.volume, 123456789)
        XCTAssertEqual(payload.ticker.high24, 126000000)
        XCTAssertEqual(payload.ticker.low24, 120000000)
    }

    func testMarketWebSocketOrderbookParserMatchesContract() {
        let message = """
        {
          "type": "orderbook",
          "exchange": "bithumb",
          "symbol": "ETH",
          "data": {
            "asks": [
              { "price": 4500000, "quantity": 0.52 }
            ],
            "bids": [
              { "price": 4499000, "quantity": 0.71 }
            ]
          }
        }
        """

        guard case .some(.orderbook(let payload)) = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("Expected orderbook payload")
        }

        XCTAssertEqual(payload.exchange, "bithumb")
        XCTAssertEqual(payload.symbol, "ETH")
        XCTAssertEqual(payload.orderbook.asks.first?.price, 4500000)
        XCTAssertEqual(payload.orderbook.asks.first?.qty, 0.52)
        XCTAssertEqual(payload.orderbook.bids.first?.price, 4499000)
        XCTAssertEqual(payload.orderbook.bids.first?.qty, 0.71)
    }

    func testMarketWebSocketTradesParserMatchesContract() {
        let message = """
        {
          "type": "trades",
          "exchange": "coinone",
          "symbol": "XRP",
          "data": {
            "trades": [
              {
                "id": "trade-1",
                "price": 820,
                "quantity": 1200,
                "side": "buy",
                "executedAt": 1713182400000
              }
            ]
          }
        }
        """

        guard case .some(.trades(let payload)) = MarketWebSocketMessageParser.parse(message) else {
            return XCTFail("Expected trades payload")
        }

        XCTAssertEqual(payload.exchange, "coinone")
        XCTAssertEqual(payload.symbol, "XRP")
        XCTAssertEqual(payload.trades.first?.id, "trade-1")
        XCTAssertEqual(payload.trades.first?.price, 820)
        XCTAssertEqual(payload.trades.first?.quantity, 1200)
        XCTAssertEqual(payload.trades.first?.side, "buy")
    }
}

private struct DummyPublicMarketService: PublicMarketDataServiceProtocol {
    func fetchTickers(exchange: Exchange) async throws -> [String : TickerData] { [:] }
    func fetchCandles(symbol: String, exchange: Exchange, period: String) async throws -> [CandleData] { [] }
    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookData {
        OrderbookData(asks: [], bids: [])
    }
    func fetchTrades(symbol: String, exchange: Exchange) async throws -> [PublicTrade] { [] }
}

private final class SpyAccountService: AccountServiceProtocol {
    let exchangeConnectionCRUDCapability = ExchangeConnectionCRUDCapability.readOnly
    private(set) var fetchPortfolioCount = 0
    private(set) var fetchOrdersCount = 0
    private(set) var fetchExchangeConnectionsCount = 0

    func fetchPortfolio(session: AuthSession, exchange: Exchange) async throws -> PortfolioSnapshot {
        fetchPortfolioCount += 1
        return PortfolioSnapshot(cash: 0, holdings: [])
    }

    func fetchOrders(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> [OrderRecord] {
        fetchOrdersCount += 1
        return []
    }

    func fetchExchangeConnections(session: AuthSession) async throws -> [ExchangeConnection] {
        fetchExchangeConnectionsCount += 1
        return [
            ExchangeConnection(
                id: "upbit",
                exchange: .upbit,
                permission: .tradeEnabled,
                nickname: "업비트",
                isActive: true,
                updatedAt: nil
            )
        ]
    }

    func submitOrder(session: AuthSession, request: OrderSubmissionRequest) async throws {}

    func createExchangeConnection(session: AuthSession, request: ExchangeConnectionCreateRequest) async throws -> ExchangeConnection {
        throw NetworkServiceError.httpError(405, "Not used in tests")
    }

    func deleteExchangeConnection(session: AuthSession, connectionID: String) async throws {}
}

private struct StubAuthenticationService: AuthenticationServiceProtocol {
    func signIn(email: String, password: String) async throws -> AuthSession {
        AuthSession(
            accessToken: "token",
            refreshToken: nil,
            userID: "user-1",
            email: email
        )
    }
}

private final class NoOpWebSocketService: PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?

    func connect() {
        onConnectionStateChange?(.connected)
    }

    func disconnect() {}

    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {}
}

private final class URLProtocolSpy: URLProtocol {
    static var requestCount = 0

    static func reset() {
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
