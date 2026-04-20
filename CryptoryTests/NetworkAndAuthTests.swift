import XCTest
@testable import Cryptory

final class NetworkAndAuthTests: XCTestCase {

    func testTabAccessPolicyMatchesRequirements() {
        XCTAssertEqual(Tab.market.accessRequirement, .publicAccess)
        XCTAssertEqual(Tab.chart.accessRequirement, .publicAccess)
        XCTAssertEqual(Tab.kimchi.accessRequirement, .publicAccess)
        XCTAssertEqual(Tab.portfolio.accessRequirement, .authenticatedRequired)
        XCTAssertEqual(Tab.trade.accessRequirement, .authenticatedRequired)
    }

    func testLiveConfigurationUsesResponsibilityBasedPaths() {
        let configuration = APIConfiguration.live

        XCTAssertEqual(configuration.marketMarketsPath, "/market/markets")
        XCTAssertEqual(configuration.marketTickersPath, "/market/tickers")
        XCTAssertEqual(configuration.marketOrderbookPath, "/market/orderbook")
        XCTAssertEqual(configuration.marketTradesPath, "/market/trades")
        XCTAssertEqual(configuration.marketCandlesPath, "/market/candles")
        XCTAssertEqual(configuration.tradingChancePath, "/trading/chance")
        XCTAssertEqual(configuration.tradingOrdersPath, "/trading/orders")
        XCTAssertEqual(configuration.tradingOpenOrdersPath, "/trading/open-orders")
        XCTAssertEqual(configuration.tradingFillsPath, "/trading/fills")
        XCTAssertEqual(configuration.portfolioSummaryPath, "/portfolio/summary")
        XCTAssertEqual(configuration.portfolioHistoryPath, "/portfolio/history")
        XCTAssertEqual(configuration.kimchiPremiumPath, "/kimchi-premium")
        XCTAssertEqual(configuration.exchangeConnectionsPath, "/exchange-connections")
    }

    func testRuntimeConfigurationDefaultsToLocalForDebugBuilds() {
        let configuration = AppRuntimeConfiguration.resolve(
            environment: [:],
            buildConfiguration: .debug
        )

        XCTAssertEqual(configuration.environment, .local)
        XCTAssertEqual(configuration.restBaseURL.absoluteString, "http://127.0.0.1:3002")
        XCTAssertEqual(configuration.publicMarketWebSocketURL.absoluteString, "ws://127.0.0.1:3002/ws/market")
        XCTAssertEqual(configuration.privateTradingWebSocketURL.absoluteString, "ws://127.0.0.1:3002/ws/trading")
    }

    func testRuntimeConfigurationSupportsLocalHostOverrideForDeviceTesting() {
        let configuration = AppRuntimeConfiguration.resolve(
            environment: [
                "CRYPTORY_APP_ENV": "local",
                "CRYPTORY_LOCAL_SERVER_HOST": "192.168.0.24",
                "CRYPTORY_LOCAL_SERVER_PORT": "3002"
            ],
            buildConfiguration: .debug
        )

        XCTAssertEqual(configuration.restBaseURL.absoluteString, "http://192.168.0.24:3002")
        XCTAssertEqual(configuration.publicMarketWebSocketURL.absoluteString, "ws://192.168.0.24:3002/ws/market")
    }

    func testTransportFailureMapperMarksCannotFindHostAsNonRetryable() {
        let failure = TransportFailureMapper.map(URLError(.cannotFindHost))

        XCTAssertEqual(failure.category, .connectivity)
        XCTAssertFalse(failure.shouldRetry)
        XCTAssertEqual(failure.message, "서버 주소를 확인할 수 없어요. 현재 앱 환경 설정을 확인해주세요.")
    }

    func testAuthenticatedRequestBuilderBlocksGuestBeforeDispatchForAllPrivatePaths() throws {
        let client = APIClient(configuration: APIConfiguration(
            baseURL: "https://example.com",
            loginPath: "/auth/login",
            marketMarketsPath: "/market/markets",
            marketTickersPath: "/market/tickers",
            marketOrderbookPath: "/market/orderbook",
            marketTradesPath: "/market/trades",
            marketCandlesPath: "/market/candles",
            tradingChancePath: "/trading/chance",
            tradingOrdersPath: "/trading/orders",
            tradingOpenOrdersPath: "/trading/open-orders",
            tradingFillsPath: "/trading/fills",
            portfolioSummaryPath: "/portfolio/summary",
            portfolioHistoryPath: "/portfolio/history",
            kimchiPremiumPath: "/kimchi-premium",
            exchangeConnectionsPath: "/exchange-connections",
            exchangeConnectionsCreateEnabled: true,
            exchangeConnectionsUpdateEnabled: true,
            exchangeConnectionsDeleteEnabled: true
        ))

        for path in [
            client.configuration.tradingChancePath,
            client.configuration.tradingOrdersPath,
            client.configuration.portfolioSummaryPath,
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
                loginPath: "/auth/login",
                marketMarketsPath: "/market/markets",
                marketTickersPath: "/market/tickers",
                marketOrderbookPath: "/market/orderbook",
                marketTradesPath: "/market/trades",
                marketCandlesPath: "/market/candles",
                tradingChancePath: "/trading/chance",
                tradingOrdersPath: "/trading/orders",
                tradingOpenOrdersPath: "/trading/open-orders",
                tradingFillsPath: "/trading/fills",
                portfolioSummaryPath: "/portfolio/summary",
                portfolioHistoryPath: "/portfolio/history",
                kimchiPremiumPath: "/kimchi-premium",
                exchangeConnectionsPath: "/exchange-connections",
                exchangeConnectionsCreateEnabled: true,
                exchangeConnectionsUpdateEnabled: true,
                exchangeConnectionsDeleteEnabled: true
            ),
            session: session
        )

        do {
            _ = try await client.requestJSON(
                path: "/trading/orders",
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

    func testCoinoneTickerParsingNormalizesTargetCurrencySymbol() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": [
                {
                  "target_currency": "btc",
                  "quote_currency": "krw",
                  "last": "124500000",
                  "change_rate": "0.012",
                  "target_volume": "10.5",
                  "high": "125000000",
                  "low": "123000000",
                  "sparkline": ["123800000", "124500000"],
                  "sparklinePointCount": 2
                }
              ]
            }
            """.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/auth/login",
                marketMarketsPath: "/market/markets",
                marketTickersPath: "/market/tickers",
                marketOrderbookPath: "/market/orderbook",
                marketTradesPath: "/market/trades",
                marketCandlesPath: "/market/candles",
                tradingChancePath: "/trading/chance",
                tradingOrdersPath: "/trading/orders",
                tradingOpenOrdersPath: "/trading/open-orders",
                tradingFillsPath: "/trading/fills",
                portfolioSummaryPath: "/portfolio/summary",
                portfolioHistoryPath: "/portfolio/history",
                kimchiPremiumPath: "/kimchi-premium",
                exchangeConnectionsPath: "/exchange-connections",
                exchangeConnectionsCreateEnabled: true,
                exchangeConnectionsUpdateEnabled: true,
                exchangeConnectionsDeleteEnabled: true
            ),
            session: session
        )
        let repository = LiveMarketRepository(client: client)

        let snapshot = try await repository.fetchTickers(exchange: .coinone)

        XCTAssertEqual(snapshot.tickers["BTC"]?.price, 124_500_000)
        XCTAssertEqual(snapshot.tickers["BTC"]?.change, 1.2)
        XCTAssertEqual(snapshot.tickers["BTC"]?.volume, 10.5)
        XCTAssertEqual(snapshot.tickers["BTC"]?.sparkline, [123_800_000, 124_500_000])
        XCTAssertEqual(snapshot.tickers["BTC"]?.sparklinePointCount, 2)
        XCTAssertEqual(snapshot.tickers["BTC"]?.hasServerSparkline, true)
    }

    func testTickerParsingSupportsAssetImageURL() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": [
                {
                  "symbol": "BTC",
                  "assetImageUrl": "https://assets.coingecko.com/coins/images/1/large/bitcoin.png",
                  "canonicalAssetKey": "bitcoin",
                  "price": "124500000",
                  "changePercent": "1.2",
                  "volume24h": "10.5",
                  "high24": "125000000",
                  "low24": "123000000",
                  "sparkline": ["123800000", "124500000"],
                  "sparklinePointCount": 2
                }
              ]
            }
            """.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/auth/login",
                marketMarketsPath: "/market/markets",
                marketTickersPath: "/market/tickers",
                marketOrderbookPath: "/market/orderbook",
                marketTradesPath: "/market/trades",
                marketCandlesPath: "/market/candles",
                tradingChancePath: "/trading/chance",
                tradingOrdersPath: "/trading/orders",
                tradingOpenOrdersPath: "/trading/open-orders",
                tradingFillsPath: "/trading/fills",
                portfolioSummaryPath: "/portfolio/summary",
                portfolioHistoryPath: "/portfolio/history",
                kimchiPremiumPath: "/kimchi-premium",
                exchangeConnectionsPath: "/exchange-connections",
                exchangeConnectionsCreateEnabled: true,
                exchangeConnectionsUpdateEnabled: true,
                exchangeConnectionsDeleteEnabled: true
            ),
            session: session
        )
        let repository = LiveMarketRepository(client: client)

        let snapshot = try await repository.fetchTickers(exchange: .coinone)

        XCTAssertEqual(snapshot.coins.first?.symbol, "BTC")
        XCTAssertEqual(
            snapshot.coins.first?.imageURL,
            "https://assets.coingecko.com/coins/images/1/large/bitcoin.png"
        )
    }

    func testMarketCatalogParsingSupportsNestedItemsPayload() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": {
                "items": [
                  {
                    "symbol": "BTC",
                    "displayName": "비트코인",
                    "supportedIntervals": ["1m", "1h"],
                    "tradable": true,
                    "kimchiComparable": true
                  },
                  {
                    "symbol": "ETH",
                    "displayName": "이더리움",
                    "supportedIntervals": ["1m", "1h", "1d"],
                    "tradable": false,
                    "kimchiComparable": false
                  }
                ]
              }
            }
            """.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/auth/login",
                marketMarketsPath: "/market/markets",
                marketTickersPath: "/market/tickers",
                marketOrderbookPath: "/market/orderbook",
                marketTradesPath: "/market/trades",
                marketCandlesPath: "/market/candles",
                tradingChancePath: "/trading/chance",
                tradingOrdersPath: "/trading/orders",
                tradingOpenOrdersPath: "/trading/open-orders",
                tradingFillsPath: "/trading/fills",
                portfolioSummaryPath: "/portfolio/summary",
                portfolioHistoryPath: "/portfolio/history",
                kimchiPremiumPath: "/kimchi-premium",
                exchangeConnectionsPath: "/exchange-connections",
                exchangeConnectionsCreateEnabled: true,
                exchangeConnectionsUpdateEnabled: true,
                exchangeConnectionsDeleteEnabled: true
            ),
            session: session
        )
        let repository = LiveMarketRepository(client: client)

        let snapshot = try await repository.fetchMarkets(exchange: .upbit)

        XCTAssertEqual(snapshot.markets.map(\.symbol), ["BTC", "ETH"])
        XCTAssertEqual(snapshot.supportedIntervalsBySymbol["ETH"], ["1m", "1h", "1d"])
        XCTAssertEqual(snapshot.markets.first?.isTradable, true)
        XCTAssertEqual(snapshot.markets.last?.isTradable, false)
        XCTAssertEqual(snapshot.markets.last?.isKimchiComparable, false)
    }

    func testFetchTradesPrefersCreatedAtWhenTimestampIsZero() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": [
                {
                  "id": "trade-1",
                  "price": 125000000,
                  "quantity": 0.015,
                  "side": "buy",
                  "timestamp": 0,
                  "createdAt": "2024-04-15T12:34:56Z"
                }
              ]
            }
            """.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/auth/login",
                marketMarketsPath: "/market/markets",
                marketTickersPath: "/market/tickers",
                marketOrderbookPath: "/market/orderbook",
                marketTradesPath: "/market/trades",
                marketCandlesPath: "/market/candles",
                tradingChancePath: "/trading/chance",
                tradingOrdersPath: "/trading/orders",
                tradingOpenOrdersPath: "/trading/open-orders",
                tradingFillsPath: "/trading/fills",
                portfolioSummaryPath: "/portfolio/summary",
                portfolioHistoryPath: "/portfolio/history",
                kimchiPremiumPath: "/kimchi-premium",
                exchangeConnectionsPath: "/exchange-connections",
                exchangeConnectionsCreateEnabled: true,
                exchangeConnectionsUpdateEnabled: true,
                exchangeConnectionsDeleteEnabled: true
            ),
            session: session
        )
        let repository = LiveMarketRepository(client: client)

        let snapshot = try await repository.fetchTrades(symbol: "BTC", exchange: .upbit)
        let expectedDisplay = TradeTimestampParser.parse(
            candidates: [
                ("timestamp", 0),
                ("createdAt", "2024-04-15T12:34:56Z")
            ],
            logContext: "test_trade"
        ).displayText

        XCTAssertEqual(snapshot.trades.first?.id, "trade-1")
        XCTAssertEqual(snapshot.trades.first?.executedAt, expectedDisplay)
        XCTAssertNotEqual(snapshot.trades.first?.executedAt, "09:00:00")
    }

    func testMarketCatalogFiltersUnsupportedAndExcludedSymbols() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": {
                "items": [
                  { "symbol": "BTC", "displayName": "비트코인", "tradable": true },
                  { "symbol": "ETH", "displayName": "이더리움", "tradable": true },
                  { "symbol": "XRP", "displayName": "리플", "tradable": true }
                ],
                "supportedSymbols": ["BTC", "ETH"],
                "capabilityExcludedSymbols": ["ETH"]
              }
            }
            """.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/auth/login",
                marketMarketsPath: "/market/markets",
                marketTickersPath: "/market/tickers",
                marketOrderbookPath: "/market/orderbook",
                marketTradesPath: "/market/trades",
                marketCandlesPath: "/market/candles",
                tradingChancePath: "/trading/chance",
                tradingOrdersPath: "/trading/orders",
                tradingOpenOrdersPath: "/trading/open-orders",
                tradingFillsPath: "/trading/fills",
                portfolioSummaryPath: "/portfolio/summary",
                portfolioHistoryPath: "/portfolio/history",
                kimchiPremiumPath: "/kimchi-premium",
                exchangeConnectionsPath: "/exchange-connections",
                exchangeConnectionsCreateEnabled: true,
                exchangeConnectionsUpdateEnabled: true,
                exchangeConnectionsDeleteEnabled: true
            ),
            session: session
        )
        let repository = LiveMarketRepository(client: client)

        let snapshot = try await repository.fetchMarkets(exchange: .upbit)

        XCTAssertEqual(snapshot.markets.map(\.symbol), ["BTC"])
        XCTAssertEqual(Set(snapshot.filteredSymbols), Set(["ETH", "XRP"]))
    }

    func testTickerSnapshotUsesAuthoritativeListedSymbolsAndAsOf() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "asOf": "2026-04-19T12:34:56Z",
              "data": {
                "items": [
                  {
                    "symbol": "BTC",
                    "displayName": "비트코인",
                    "price": 125000000,
                    "changeRate": 0.012,
                    "volume24h": 100000000,
                    "sparkline": [123000000, 125000000]
                  },
                  {
                    "symbol": "DOGE",
                    "displayName": "도지코인",
                    "price": 250,
                    "changeRate": 0.05,
                    "volume24h": 1200000,
                    "sparkline": [200, 250]
                  }
                ],
                "supportedSymbols": ["BTC"]
              }
            }
            """.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/auth/login",
                marketMarketsPath: "/market/markets",
                marketTickersPath: "/market/tickers",
                marketOrderbookPath: "/market/orderbook",
                marketTradesPath: "/market/trades",
                marketCandlesPath: "/market/candles",
                tradingChancePath: "/trading/chance",
                tradingOrdersPath: "/trading/orders",
                tradingOpenOrdersPath: "/trading/open-orders",
                tradingFillsPath: "/trading/fills",
                portfolioSummaryPath: "/portfolio/summary",
                portfolioHistoryPath: "/portfolio/history",
                kimchiPremiumPath: "/kimchi-premium",
                exchangeConnectionsPath: "/exchange-connections",
                exchangeConnectionsCreateEnabled: true,
                exchangeConnectionsUpdateEnabled: true,
                exchangeConnectionsDeleteEnabled: true
            ),
            session: session
        )
        let repository = LiveMarketRepository(client: client)

        let snapshot = try await repository.fetchTickers(exchange: .upbit)

        XCTAssertEqual(snapshot.coins.map(\.symbol), ["BTC"])
        XCTAssertEqual(Set(snapshot.tickers.keys), Set(["BTC"]))
        XCTAssertEqual(snapshot.filteredSymbols, ["DOGE"])
        XCTAssertEqual(snapshot.meta.fetchedAt, ISO8601DateFormatter().date(from: "2026-04-19T12:34:56Z"))
    }

    func testKimchiPremiumRequestIncludesExchangeAndSymbolsQuery() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": {
                "rows": []
              }
            }
            """.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/auth/login",
                marketMarketsPath: "/market/markets",
                marketTickersPath: "/market/tickers",
                marketOrderbookPath: "/market/orderbook",
                marketTradesPath: "/market/trades",
                marketCandlesPath: "/market/candles",
                tradingChancePath: "/trading/chance",
                tradingOrdersPath: "/trading/orders",
                tradingOpenOrdersPath: "/trading/open-orders",
                tradingFillsPath: "/trading/fills",
                portfolioSummaryPath: "/portfolio/summary",
                portfolioHistoryPath: "/portfolio/history",
                kimchiPremiumPath: "/kimchi-premium",
                exchangeConnectionsPath: "/exchange-connections",
                exchangeConnectionsCreateEnabled: true,
                exchangeConnectionsUpdateEnabled: true,
                exchangeConnectionsDeleteEnabled: true
            ),
            session: session
        )
        let repository = LiveKimchiPremiumRepository(client: client)

        _ = try await repository.fetchSnapshot(exchange: .upbit, symbols: ["BTC", "ETH", "XRP"])

        let url = try XCTUnwrap(URLProtocolSpy.lastRequest?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.absoluteString, "https://example.com/kimchi-premium?exchange=upbit&symbols=BTC,ETH,XRP")
        XCTAssertEqual(queryItems["exchange"], "upbit")
        XCTAssertEqual(queryItems["symbols"], "BTC,ETH,XRP")
    }

    func testKimchiPremiumParsingUsesCanonicalSymbolWhenAvailable() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": {
                "rows": [
                  {
                    "canonicalSymbol": "btc",
                    "exchange": "upbit",
                    "sourceExchange": "upbit",
                    "domesticPrice": 150000000,
                    "referenceExchangePrice": 100000,
                    "krwConvertedReference": 145000000,
                    "freshnessState": "reference_price_delayed",
                    "freshnessReason": "기준가 반영 지연",
                    "updatedAt": "2026-04-19T10:00:00Z"
                  },
                  {
                    "market": "KRW-ETH",
                    "exchange": "upbit",
                    "domesticPrice": 5000000,
                    "referenceExchangePrice": 3200,
                    "krwConvertedReference": 4800000
                  }
                ]
              }
            }
            """.utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/auth/login",
                marketMarketsPath: "/market/markets",
                marketTickersPath: "/market/tickers",
                marketOrderbookPath: "/market/orderbook",
                marketTradesPath: "/market/trades",
                marketCandlesPath: "/market/candles",
                tradingChancePath: "/trading/chance",
                tradingOrdersPath: "/trading/orders",
                tradingOpenOrdersPath: "/trading/open-orders",
                tradingFillsPath: "/trading/fills",
                portfolioSummaryPath: "/portfolio/summary",
                portfolioHistoryPath: "/portfolio/history",
                kimchiPremiumPath: "/kimchi-premium",
                exchangeConnectionsPath: "/exchange-connections",
                exchangeConnectionsCreateEnabled: true,
                exchangeConnectionsUpdateEnabled: true,
                exchangeConnectionsDeleteEnabled: true
            ),
            session: session
        )
        let repository = LiveKimchiPremiumRepository(client: client)

        let snapshot = try await repository.fetchSnapshot(exchange: .upbit, symbols: ["BTC", "ETH"])

        XCTAssertEqual(snapshot.rows.map(\.symbol), ["BTC", "ETH"])
        XCTAssertEqual(snapshot.rows.first?.sourceExchange, .upbit)
        XCTAssertEqual(snapshot.rows.first?.freshnessState, .referencePriceDelayed)
        XCTAssertEqual(snapshot.rows.first?.freshnessReason, "기준가 반영 지연")
        XCTAssertNotNil(snapshot.rows.first?.updatedAt)
    }
}
