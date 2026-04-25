import XCTest
@testable import Cryptory

final class NetworkAndAuthTests: XCTestCase {
    private func makeAPIConfiguration(baseURL: String = "https://example.com") -> APIConfiguration {
        APIConfiguration(
            baseURL: baseURL,
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
        )
    }

    private func makeAuthenticationService(baseURL: String = "https://example.com") -> LiveAuthenticationService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolSpy.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: makeAPIConfiguration(baseURL: baseURL),
            session: session
        )
        return LiveAuthenticationService(client: client)
    }

    private func lastRequestBody() throws -> JSONObject {
        let bodyData = try XCTUnwrap(URLProtocolSpy.lastRequestBody)
        let body = try JSONSerialization.jsonObject(with: bodyData)
        return try XCTUnwrap(body as? JSONObject)
    }

    func testTabAccessPolicyMatchesRequirements() {
        XCTAssertEqual(Tab.market.accessRequirement, .publicAccess)
        XCTAssertEqual(Tab.chart.accessRequirement, .publicAccess)
        XCTAssertEqual(Tab.kimchi.accessRequirement, .publicAccess)
        XCTAssertEqual(Tab.portfolio.accessRequirement, .authenticatedRequired)
        XCTAssertEqual(Tab.trade.accessRequirement, .authenticatedRequired)
    }

    func testLiveConfigurationUsesResponsibilityBasedPaths() {
        let configuration = APIConfiguration.live

        XCTAssertEqual(configuration.loginPath, "/api/v1/auth/login")
        XCTAssertEqual(configuration.registerPath, "/api/v1/auth/register")
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

    func testSocialAuthConfigurationUsesContractPaths() throws {
        let devRuntime = AppRuntimeConfiguration.resolve(
            environment: ["APP_ENV": "Dev"],
            buildConfiguration: .debug
        )
        let prodRuntime = AppRuntimeConfiguration.resolve(
            environment: ["APP_ENV": "Prod"],
            buildConfiguration: .release
        )
        let devConfiguration = APIConfiguration.resolve(
            environment: ["APP_ENV": "Dev"],
            buildConfiguration: .debug
        )
        let prodConfiguration = APIConfiguration.resolve(
            environment: ["APP_ENV": "Prod"],
            buildConfiguration: .release
        )

        XCTAssertEqual(devRuntime.restBaseURL.absoluteString, "http://127.0.0.1:3002")
        XCTAssertEqual(prodRuntime.restBaseURL.absoluteString, "http://crytory.duckdns.org")
        XCTAssertEqual(devConfiguration.googleLoginPath, "/api/v1/auth/social/google")
        XCTAssertEqual(devConfiguration.appleLoginPath, "/api/v1/auth/social/apple")
        XCTAssertEqual(prodConfiguration.googleLoginPath, "/api/v1/auth/social/google")
        XCTAssertEqual(prodConfiguration.appleLoginPath, "/api/v1/auth/social/apple")

        let devClient = APIClient(configuration: devConfiguration)
        let prodClient = APIClient(configuration: prodConfiguration)
        XCTAssertEqual(
            try devClient.makeRequest(path: devConfiguration.googleLoginPath, method: "POST", accessRequirement: .publicAccess).url?.absoluteString,
            "http://127.0.0.1:3002/api/v1/auth/social/google"
        )
        XCTAssertEqual(
            try devClient.makeRequest(path: devConfiguration.appleLoginPath, method: "POST", accessRequirement: .publicAccess).url?.absoluteString,
            "http://127.0.0.1:3002/api/v1/auth/social/apple"
        )
        XCTAssertEqual(
            try prodClient.makeRequest(path: prodConfiguration.googleLoginPath, method: "POST", accessRequirement: .publicAccess).url?.absoluteString,
            "http://crytory.duckdns.org/api/v1/auth/social/google"
        )
        XCTAssertEqual(
            try prodClient.makeRequest(path: prodConfiguration.appleLoginPath, method: "POST", accessRequirement: .publicAccess).url?.absoluteString,
            "http://crytory.duckdns.org/api/v1/auth/social/apple"
        )
    }

    func testSocialAuthPathsIgnoreLegacyPathOverrides() {
        let configuration = APIConfiguration.resolve(
            environment: [
                "APP_ENV": "Dev",
                "CRYPTORY_GOOGLE_LOGIN_PATH": "/api/v1/auth/" + "google",
                "CRYPTORY_APPLE_LOGIN_PATH": "/api/v1/auth/" + "apple"
            ],
            buildConfiguration: .debug
        )

        XCTAssertEqual(configuration.googleLoginPath, "/api/v1/auth/social/google")
        XCTAssertEqual(configuration.appleLoginPath, "/api/v1/auth/social/apple")
    }

    func testRuntimeConfigurationStripsPathFromRESTBaseURL() {
        let configuration = AppRuntimeConfiguration.resolve(
            environment: [
                "APP_ENV": "Dev",
                "API_BASE_URL": "http://127.0.0.1:3002/api/v1"
            ],
            buildConfiguration: .debug
        )

        XCTAssertEqual(configuration.restBaseURL.absoluteString, "http://127.0.0.1:3002")
    }

    func testRuntimeConfigurationDefaultsToDevelopmentForDebugBuilds() {
        let configuration = AppRuntimeConfiguration.resolve(
            environment: [:],
            buildConfiguration: .debug
        )

        XCTAssertEqual(configuration.environment, .development)
        XCTAssertEqual(configuration.restBaseURL.absoluteString, "http://127.0.0.1:3002")
        XCTAssertEqual(configuration.webBaseURL.absoluteString, "http://127.0.0.1:3002")
        XCTAssertEqual(configuration.publicMarketWebSocketURL.absoluteString, "ws://127.0.0.1:3002/ws/market")
        XCTAssertEqual(configuration.privateTradingWebSocketURL.absoluteString, "ws://127.0.0.1:3002/ws/trading")
    }

    func testRuntimeConfigurationDefaultsToProductionForReleaseBuilds() {
        let configuration = AppRuntimeConfiguration.resolve(
            environment: [:],
            buildConfiguration: .release
        )

        XCTAssertEqual(configuration.environment, .production)
        XCTAssertEqual(configuration.restBaseURL.absoluteString, "http://crytory.duckdns.org")
        XCTAssertEqual(configuration.webBaseURL.absoluteString, "http://crytory.duckdns.org")
        XCTAssertEqual(configuration.publicMarketWebSocketURL.absoluteString, "ws://crytory.duckdns.org/ws/market")
        XCTAssertEqual(configuration.privateTradingWebSocketURL.absoluteString, "ws://crytory.duckdns.org/ws/trading")
    }

    func testRuntimeConfigurationSupportsLocalHostOverrideForDeviceTesting() {
        let configuration = AppRuntimeConfiguration.resolve(
            environment: [
                "APP_ENV": "Dev",
                "LOCAL_SERVER_HOST": "192.168.0.24",
                "LOCAL_SERVER_PORT": "3002"
            ],
            buildConfiguration: .debug
        )

        XCTAssertEqual(configuration.environment, .development)
        XCTAssertEqual(configuration.restBaseURL.absoluteString, "http://192.168.0.24:3002")
        XCTAssertEqual(configuration.publicMarketWebSocketURL.absoluteString, "ws://192.168.0.24:3002/ws/market")
    }

    func testGoogleSocialLoginUsesSocialPathAndContractBody() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": {
                "accessToken": "access-token",
                "refreshToken": "refresh-token",
                "tokenType": "Bearer",
                "expiresIn": 3600,
                "refreshTokenExpiresAt": "2026-05-01T00:00:00Z",
                "sessionId": "session-1",
                "user": {
                  "id": "user-1",
                  "email": "user@example.com"
                }
              }
            }
            """.utf8
        )
        let service = makeAuthenticationService()

        let session = try await service.signInWithGoogle(
            request: GoogleSocialLoginRequest(
                idToken: "google-id-token",
                accessToken: "google-access-token",
                email: "user@example.com",
                displayName: "Test User",
                deviceID: "device-1"
            )
        )
        let body = try lastRequestBody()

        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.path, "/api/v1/auth/social/google")
        XCTAssertEqual(body["idToken"] as? String, "google-id-token")
        XCTAssertEqual(body["accessToken"] as? String, "google-access-token")
        XCTAssertNil(body["credential"])
        XCTAssertEqual(session.accessToken, "access-token")
        XCTAssertEqual(session.refreshToken, "refresh-token")
        XCTAssertEqual(session.tokenType, "Bearer")
        XCTAssertEqual(session.expiresIn, 3600)
        XCTAssertEqual(session.refreshTokenExpiresAt, "2026-05-01T00:00:00Z")
        XCTAssertEqual(session.sessionID, "session-1")
        XCTAssertEqual(session.userID, "user-1")
        XCTAssertEqual(session.email, "user@example.com")
    }

    func testAppleSocialLoginUsesSocialPathAndContractBody() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": {
                "accessToken": "access-token",
                "refreshToken": "refresh-token",
                "user": {
                  "id": "user-1",
                  "email": "apple@example.com"
                }
              }
            }
            """.utf8
        )
        let service = makeAuthenticationService()

        _ = try await service.signInWithApple(
            request: AppleSocialLoginRequest(
                identityToken: "apple-identity-token",
                authorizationCode: "apple-auth-code",
                userIdentifier: "apple-user",
                email: "apple@example.com",
                fullName: "Apple User",
                givenName: "Apple",
                familyName: "User",
                deviceID: "device-1"
            )
        )
        let body = try lastRequestBody()

        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.path, "/api/v1/auth/social/apple")
        XCTAssertEqual(body["identityToken"] as? String, "apple-identity-token")
        XCTAssertEqual(body["authorizationCode"] as? String, "apple-auth-code")
        XCTAssertEqual(body["fullName"] as? String, "Apple User")
        XCTAssertEqual(body["email"] as? String, "apple@example.com")
        XCTAssertNil(body["idToken"])
    }

    func testSignUpUsesServerAuthRegisterPathAndParsesNestedUserResponse() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "user": {
                  "id": "user-1",
                  "email": "new@example.com",
                  "nickname": "newbie",
                  "authProvider": "email"
                },
                "token": "access-token"
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
            session: session
        )
        let service = LiveAuthenticationService(client: client)

        let sessionResult = try await service.signUp(
            request: SignUpRequest(
                email: "new@example.com",
                password: "abc12345",
                passwordConfirm: "abc12345",
                nickname: "newbie",
                acceptedTerms: true
            )
        )

        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.path, "/api/v1/auth/register")
        XCTAssertEqual(URLProtocolSpy.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(sessionResult.accessToken, "access-token")
        XCTAssertEqual(sessionResult.userID, "user-1")
        XCTAssertEqual(sessionResult.email, "new@example.com")
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

    func testTickerParsingHonorsHasImageFlag() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": [
                {
                  "symbol": "XRP",
                  "hasImage": false,
                  "assetImageUrl": "https://assets.example.com/xrp.png",
                  "price": "790",
                  "changePercent": "0.3",
                  "volume24h": "30000000",
                  "high24": "810",
                  "low24": "770",
                  "sparkline": ["780", "790"],
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
        let coin = try XCTUnwrap(snapshot.coins.first)

        XCTAssertEqual(coin.symbol, "XRP")
        XCTAssertEqual(coin.hasImage, false)
        XCTAssertNil(coin.iconURL)
        XCTAssertEqual(coin.displayMetadata?.iconURL, "https://assets.example.com/xrp.png")
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

    func testMarketCatalogParsingUsesCanonicalMetadataForDisplayAndImages() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "data": {
                "items": [
                  {
                    "symbol": "C",
                    "marketId": "btc_krw",
                    "baseAsset": "btc",
                    "quoteAsset": "krw",
                    "displaySymbol": "btc",
                    "displayName": "비트코인",
                    "englishName": "Bitcoin",
                    "iconUrl": "https://assets.example.com/btc.png",
                    "isChartAvailable": false,
                    "isOrderBookAvailable": true,
                    "isTradesAvailable": true,
                    "unavailableReason": "korbit candles are temporarily unavailable"
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

        let snapshot = try await repository.fetchMarkets(exchange: .korbit)
        let coin = try XCTUnwrap(snapshot.markets.first)

        XCTAssertEqual(coin.symbol, "BTC")
        XCTAssertEqual(coin.canonicalSymbol, "BTC")
        XCTAssertEqual(coin.displaySymbol, "BTC")
        XCTAssertEqual(coin.name, "비트코인")
        XCTAssertEqual(coin.iconURL, "https://assets.example.com/btc.png")
        XCTAssertEqual(coin.displayMetadata?.marketId, "btc_krw")
        XCTAssertEqual(coin.displayMetadata?.baseAsset, "BTC")
        XCTAssertEqual(coin.displayMetadata?.quoteAsset, "KRW")
        XCTAssertEqual(coin.displayMetadata?.isChartAvailable, false)
    }
}
