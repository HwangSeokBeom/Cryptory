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
}
