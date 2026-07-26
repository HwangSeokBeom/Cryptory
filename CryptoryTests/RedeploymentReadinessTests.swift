import XCTest
@testable import Cryptory

final class RedeploymentReadinessTests: XCTestCase {
    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        return APIClient(
            configuration: APIConfiguration(
                baseURL: "https://example.com",
                loginPath: "/api/v1/auth/login",
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
            session: URLSession(configuration: configuration)
        )
    }

    private var session: AuthSession {
        AuthSession(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            userID: "user-1",
            email: "user@example.com"
        )
    }

    func testReleaseFlagsCannotEnableTransactionalFeatures() {
        let flags = AppFeatureFlags.resolve(
            environment: [
                "CRYPTORY_ORDER_ENABLED": "true",
                "CRYPTORY_TRADING_ENABLED": "true",
                "CRYPTORY_TRANSFER_ENABLED": "true",
                "CRYPTORY_DEPOSIT_WITHDRAW_ENABLED": "true",
                "CRYPTORY_WALLET_ENABLED": "true",
                "CRYPTORY_PRIVATE_TRADING_API_ENABLED": "true"
            ],
            buildConfiguration: .release,
            appEnvironment: .production
        )

        XCTAssertFalse(flags.isOrderEnabled)
        XCTAssertFalse(flags.isTradingEnabled)
        XCTAssertFalse(flags.isTransferEnabled)
        XCTAssertFalse(flags.isDepositWithdrawEnabled)
        XCTAssertFalse(flags.isWalletEnabled)
        XCTAssertFalse(flags.isPrivateExchangeTradingAPIEnabled)
    }

    func testStaleTradingDeepLinksRemainBlocked() throws {
        for route in [
            "cryptory://trade/BTC",
            "cryptory://orders/open",
            "cryptory://wallet/deposit",
            "https://cryptory.duckdns.org/withdraw?asset=BTC",
            "cryptory://route/%EB%A7%A4%EC%88%98/BTC"
        ] {
            XCTAssertTrue(AppRouteGuard.isTradingRoute(try XCTUnwrap(URL(string: route))), route)
        }

        XCTAssertEqual(
            AppRouteGuard.informationalTab(for: try XCTUnwrap(URL(string: "cryptory://chart/BTC"))),
            .chart
        )
    }

    func testFcmRegistrationUsesCanonicalIOSPlatformAndDeleteHasMinimalBody() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseQueue = [
            (200, Data(#"{"success":true,"data":{"registered":true}}"#.utf8)),
            (200, Data(#"{"success":true,"data":{"deleted":true}}"#.utf8))
        ]
        let registrar = FCMTokenRegistrar(client: makeClient())

        try await registrar.register(token: "fcm-token", session: session)
        let registerBody = try XCTUnwrap(URLProtocolSpy.lastRequestBody)
        let registerJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: registerBody) as? JSONObject
        )
        XCTAssertEqual(registerJSON["platform"] as? String, "IOS")
        XCTAssertEqual(registerJSON["token"] as? String, "fcm-token")

        try await registrar.delete(token: "fcm-token", session: session)
        let deleteBody = try XCTUnwrap(URLProtocolSpy.lastRequestBody)
        let deleteJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: deleteBody) as? JSONObject
        )
        XCTAssertEqual(Set(deleteJSON.keys), ["token"])
    }

    func testPriceAlertCreateUsesServerContractAndParsesCanonicalResponse() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "id": "alert-1",
                "exchange": "upbit",
                "symbol": "BTC",
                "quoteCurrency": "KRW",
                "condition": "BELOW",
                "targetPrice": 100000000,
                "repeatMode": "REPEAT",
                "isActive": true
              }
            }
            """.utf8
        )
        let repository = LivePriceAlertRepository(client: makeClient())
        let draft = PriceAlertDraft(
            alertId: nil,
            exchange: .upbit,
            symbol: "BTC",
            quoteCurrency: .krw,
            currentPrice: 110000000,
            condition: .below,
            targetPriceText: "100000000",
            repeatPolicy: .repeating,
            isActive: true,
            warningMessage: nil
        )

        let alert = try await repository.savePriceAlert(session: session, draft: draft)
        let bodyData = try XCTUnwrap(URLProtocolSpy.lastRequestBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? JSONObject)

        XCTAssertEqual(body["condition"] as? String, "BELOW")
        XCTAssertEqual(body["repeatMode"] as? String, "REPEAT")
        XCTAssertNil(body["repeatPolicy"])
        XCTAssertEqual(alert.condition, .below)
        XCTAssertEqual(alert.repeatPolicy, .repeating)
    }

    func testPriceAlertSupportMatchesServerMarketContract() {
        XCTAssertTrue(PriceAlertSupport.isSupported(exchange: .upbit, quoteCurrency: .krw))
        XCTAssertTrue(PriceAlertSupport.isSupported(exchange: .bithumb, quoteCurrency: .btc))
        XCTAssertFalse(PriceAlertSupport.isSupported(exchange: .coinone, quoteCurrency: .krw))
        XCTAssertFalse(PriceAlertSupport.isSupported(exchange: .binance, quoteCurrency: .usdt))
        XCTAssertFalse(PriceAlertSupport.isSupported(exchange: .upbit, quoteCurrency: .eth))
    }
}
