import XCTest
@testable import Cryptory

final class PublicContentRepositoryTests: XCTestCase {
    private final class FakeTranslationService: ClientTranslationServiceProtocol {
        private(set) var requestedIDs: [String] = []

        func translate(items: [TranslationRequestItem], targetLanguage: String, context: String, symbol: String?) async -> [TranslationResultItem] {
            requestedIDs.append(contentsOf: items.map(\.id))
            return items.map {
                TranslationResultItem(
                    id: $0.id,
                    originalText: $0.text,
                    translatedText: "번역 \($0.text)",
                    sourceLanguage: $0.sourceLanguage,
                    targetLanguage: targetLanguage,
                    provider: "apple_translation",
                    state: .translated
                )
            }
        }
    }

    private func makeRepository(translationUseCase: TranslationUseCase? = nil) -> LivePublicContentRepository {
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
        return LivePublicContentRepository(client: client, translationUseCase: translationUseCase)
    }

    private func queryItems(from url: URL?) -> [String: String] {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    func testCoinInfoUsesRootCanonicalPathAndUnwrapsDataMarket() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "symbol": "DRIFT",
                "displaySymbol": "DRIFT/KRW",
                "name": "Drift",
                "provider": "CoinGecko",
                "providerId": "drift-protocol",
                "homepageUrl": "https://www.drift.trade",
                "market": {
                  "price": 86.8,
                  "priceCurrency": "KRW",
                  "high24h": 91.2,
                  "low24h": 84.0,
                  "tradeValue24h": 81609000000,
                  "marketCap": null,
                  "marketCapRank": 123,
                  "asOf": "2026-05-01T12:24:00Z"
                },
                "source": {
                  "metadata": "coingecko",
                  "market": "upbit",
                  "fallbackUsed": false
                }
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let info = try await repository.fetchCoinInfo(symbol: "KRW-DRIFT")

        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/coins/DRIFT/info"])
        XCTAssertEqual(info.symbol, "DRIFT")
        XCTAssertEqual(info.currentPrice, 86.8)
        XCTAssertEqual(info.tradeValue24h, 81_609_000_000)
        XCTAssertNil(info.marketCap)
        XCTAssertEqual(info.rank, 123)
        XCTAssertFalse(info.fallbackUsed)
    }

    func testORCAKRWSymbolIsNormalizedBeforePathGeneration() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "symbol": "ORCA",
                "displaySymbol": null,
                "market": { "price": 1820.5 },
                "source": { "fallbackUsed": false }
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let info = try await repository.fetchCoinInfo(symbol: " ORCA/KRW ")

        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/coins/ORCA/info"])
        XCTAssertEqual(info.symbol, "ORCA")
        XCTAssertEqual(info.displaySymbol, "ORCA/KRW")
        XCTAssertEqual(info.currentPrice, 1820.5)
        XCTAssertEqual(LivePublicContentRepository.normalizedSymbol("KRW-ORCA"), "ORCA")
        XCTAssertEqual(LivePublicContentRepository.normalizedSymbol("orca"), "ORCA")
    }

    func testNewsDateUsesSeoulCalendarForQuery() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(#"{"success":true,"data":[]}"#.utf8)
        let repository = makeRepository()
        let selectedKSTDate = ISO8601DateFormatter().date(from: "2026-05-02T15:30:00Z")!

        _ = try await repository.fetchNews(category: nil, symbol: nil, date: selectedKSTDate, sort: "latest", cursor: nil, limit: 40)

        XCTAssertEqual(LivePublicContentRepository.apiDateString(selectedKSTDate), "2026-05-03")
        let query = queryItems(from: URLProtocolSpy.lastRequest?.url)
        XCTAssertEqual(query["date"], "2026-05-03")
        XCTAssertEqual(query["sort"], "latest")
    }

    func testCoinNewsRequestIncludesMetadataContext() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(#"{"success":true,"data":{"symbol":"BIO","items":[]}}"#.utf8)
        let repository = makeRepository()

        _ = try await repository.fetchCoinNews(
            symbol: "BIO/KRW",
            context: CoinNewsRequestContext(
                market: "KRW",
                coinName: "BIO Protocol",
                providerId: "bio-protocol",
                keywords: ["BIO Protocol", "BIO token", "DeSci", "bio.xyz"]
            ),
            date: ISO8601DateFormatter().date(from: "2026-05-02T15:30:00Z"),
            sort: "latest",
            cursor: nil,
            limit: 20
        )

        let query = queryItems(from: URLProtocolSpy.lastRequest?.url)
        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/coins/BIO/news"])
        XCTAssertEqual(query["symbol"], "BIO")
        XCTAssertEqual(query["market"], "KRW")
        XCTAssertEqual(query["coinName"], "BIO Protocol")
        XCTAssertEqual(query["providerId"], "bio-protocol")
        XCTAssertEqual(query["keywords"], "BIO Protocol,BIO token,DeSci,bio.xyz")
        XCTAssertEqual(query["date"], "2026-05-03")
        XCTAssertEqual(query["sort"], "latest")
    }

    func testFallbackAliasIsUsedOnlyAfterRoot404() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseQueue = [
            (404, Data(#"{"message":"Cannot GET /coins/DRIFT/info"}"#.utf8)),
            (
                200,
                Data(
                    """
                    {
                      "success": true,
                      "data": {
                        "symbol": "DRIFT",
                        "market": { "price": 86.8 },
                        "source": { "fallbackUsed": true }
                      }
                    }
                    """.utf8
                )
            )
        ]
        let repository = makeRepository()

        let info = try await repository.fetchCoinInfo(symbol: "DRIFT/KRW")

        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/coins/DRIFT/info", "/api/v1/coins/DRIFT/info"])
        XCTAssertEqual(info.currentPrice, 86.8)
        XCTAssertTrue(info.fallbackUsed)
    }

    func testAliasFallbackIsNotUsedForNon404Failures() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseStatusCode = 500
        URLProtocolSpy.responseData = Data(#"{"success":false,"error":{"message":"provider failed"}}"#.utf8)
        let repository = makeRepository()

        do {
            _ = try await repository.fetchCoinInfo(symbol: "DRIFT")
            XCTFail("Expected server error")
        } catch {
            XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/coins/DRIFT/info"])
        }
    }

    func testNewsEmptyListIsDecodedAsEmptySnapshot() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(#"{"success":true,"data":{"items":[]}}"#.utf8)
        let repository = makeRepository()

        let snapshot = try await repository.fetchNews(category: nil, symbol: nil, date: nil, cursor: nil, limit: 40)

        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/news"])
        XCTAssertTrue(snapshot.items.isEmpty)
    }

    func testNewsAPIProviderNewsItemDecodesAndUsesAppleTranslationPipeline() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "items": [
                  {
                    "id": "newsapi-1",
                    "title": "original title",
                    "summary": "original summary",
                    "sourceName": "Reuters",
                    "provider": "newsapi",
                    "publishedAt": "2026-05-03T10:00:00Z",
                    "imageUrl": "https://example.com/news.png",
                    "originalUrl": "https://example.com/news",
                    "symbols": ["BTC"],
                    "tags": ["market"],
                    "language": "en",
                    "relevanceScore": 0.82
                  }
                ]
              }
            }
            """.utf8
        )
        let translationService = FakeTranslationService()
        let repository = makeRepository(
            translationUseCase: TranslationUseCase(
                service: translationService,
                cache: TranslationCache(),
                maxBatchSize: 20
            )
        )

        let snapshot = try await repository.fetchNews(category: nil, symbol: nil, date: nil, cursor: nil, limit: 40)

        XCTAssertEqual(snapshot.items.count, 1)
        let item = try XCTUnwrap(snapshot.items.first)
        XCTAssertEqual(item.source, "Reuters")
        XCTAssertEqual(item.provider, "newsapi")
        XCTAssertEqual(item.title, "번역 original title")
        XCTAssertEqual(item.summary, "번역 original summary")
        XCTAssertEqual(item.originalURL?.absoluteString, "https://example.com/news")
        XCTAssertEqual(item.thumbnailURL?.absoluteString, "https://example.com/news.png")
        XCTAssertEqual(item.relatedSymbols, ["BTC"])
        XCTAssertEqual(Set(translationService.requestedIDs), ["newsapi-1_title", "newsapi-1_summary"])
    }

    func testUnknownNewsProviderDoesNotBreakNewsDecode() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "items": [
                  {
                    "id": "unknown-provider-1",
                    "title": "provider title",
                    "summary": null,
                    "sourceName": "Unknown Wire",
                    "provider": "future_provider",
                    "publishedAt": "2026-05-03T10:00:00Z",
                    "imageUrl": null,
                    "originalUrl": "https://example.com/unknown",
                    "symbols": ["ETH"],
                    "language": "en"
                  }
                ]
              }
            }
            """.utf8
        )
        let translationService = FakeTranslationService()
        let repository = makeRepository(
            translationUseCase: TranslationUseCase(
                service: translationService,
                cache: TranslationCache(),
                maxBatchSize: 20
            )
        )

        let snapshot = try await repository.fetchNews(category: nil, symbol: nil, date: nil, cursor: nil, limit: 40)

        let item = try XCTUnwrap(snapshot.items.first)
        XCTAssertEqual(item.source, "Unknown Wire")
        XCTAssertEqual(item.provider, "future_provider")
        XCTAssertEqual(item.title, "번역 provider title")
        XCTAssertEqual(item.summary, "")
        XCTAssertNil(item.thumbnailURL)
        XCTAssertEqual(translationService.requestedIDs, ["unknown-provider-1_title"])
    }

    func testCommunityEmptyListIsLoadedWithZeroParticipants() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "symbol": "ORCA",
                "vote": {
                  "bullishCount": 0,
                  "bearishCount": 0,
                  "participantCount": 0,
                  "myVote": null
                },
                "items": [],
                "nextCursor": null
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let snapshot = try await repository.fetchCoinCommunity(symbol: "ORCA/KRW", sort: "latest", filter: .all, cursor: nil, limit: 30)

        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/coins/ORCA/community"])
        XCTAssertTrue(snapshot.posts.isEmpty)
        XCTAssertEqual(snapshot.vote.participantCount, 0)
        XCTAssertNil(snapshot.vote.myVote)
    }

    func testCommunityPostAttachesAuthorizationWhenLoggedIn() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseStatusCode = 201
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "id": "community-1",
                "authorName": "tester",
                "content": "좋아요",
                "symbol": "ORCA"
              }
            }
            """.utf8
        )
        let repository = makeRepository()
        let session = AuthSession(accessToken: "access-token-1234", refreshToken: nil, userID: "user-1", email: "user@example.com")

        let result = try await repository.createCoinCommunityPost(symbol: "ORCA/KRW", content: "좋아요", session: session)

        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.path, "/coins/ORCA/community")
        XCTAssertEqual(URLProtocolSpy.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(URLProtocolSpy.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer access-token-1234")
        XCTAssertEqual(result.post?.id, "community-1")
    }

    func testCommunityPostDecodesNestedCreatedItemEnvelope() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseStatusCode = 201
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "item": {
                  "id": "community-nested",
                  "authorName": "tester",
                  "content": "12313",
                  "symbol": "ORCA",
                  "commentCount": 0
                },
                "itemCount": 1,
                "participantCount": 0
              }
            }
            """.utf8
        )
        let repository = makeRepository()
        let session = AuthSession(accessToken: "access-token-1234", refreshToken: nil, userID: "user-1", email: "user@example.com")

        let result = try await repository.createCoinCommunityPost(symbol: "ORCA", content: "12313", session: session)

        XCTAssertEqual(result.post?.id, "community-nested")
        XCTAssertEqual(result.post?.content, "12313")
    }

    func testVotePostAttachesAuthorizationWhenLoggedIn() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "bullishCount": 4,
                "bearishCount": 1,
                "participantCount": 5,
                "myVote": "bullish"
              }
            }
            """.utf8
        )
        let repository = makeRepository()
        let session = AuthSession(accessToken: "vote-token-5678", refreshToken: nil, userID: "user-1", email: "user@example.com")

        let vote = try await repository.voteCoin(symbol: "KRW-ORCA", direction: "bullish", session: session)

        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.path, "/coins/ORCA/sentiment")
        XCTAssertEqual(URLProtocolSpy.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(URLProtocolSpy.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer vote-token-5678")
        XCTAssertEqual(vote.myVote, "bullish")
        XCTAssertTrue(vote.hasServerCounts)
    }

    func testMarketSentimentVoteUsesMarketScopeEndpoint() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "scope": "market",
                "key": "global",
                "bullishCount": 6,
                "bearishCount": 4,
                "totalParticipants": 10,
                "myVote": "bearish"
              }
            }
            """.utf8
        )
        let repository = makeRepository()
        let session = AuthSession(accessToken: "vote-token-5678", refreshToken: nil, userID: "user-1", email: "user@example.com")

        let vote = try await repository.voteMarketSentiment(direction: "bearish", session: session)

        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.path, "/market/sentiment")
        XCTAssertEqual(URLProtocolSpy.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(vote.scope, "market")
        XCTAssertEqual(vote.myVote, "bearish")
    }

    func testPublicContentGetRoutesDoNotAttachAuthorization() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(#"{"success":true,"data":{"items":[]}}"#.utf8)
        let repository = makeRepository()

        _ = try await repository.fetchNews(category: nil, symbol: nil, date: nil, cursor: nil, limit: 40)

        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.path, "/news")
        XCTAssertNil(URLProtocolSpy.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testCommunityPostAccessTokenInvalidMapsToAuthenticationCategory() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseStatusCode = 401
        URLProtocolSpy.responseData = Data(#"{"success":false,"error":"인증이 필요합니다","code":"ACCESS_TOKEN_INVALID"}"#.utf8)
        let repository = makeRepository()
        let session = AuthSession(accessToken: "expired-token", refreshToken: nil, userID: "user-1", email: "user@example.com")

        do {
            _ = try await repository.createCoinCommunityPost(symbol: "ORCA", content: "좋아요", session: session)
            XCTFail("Expected auth error")
        } catch let error as NetworkServiceError {
            XCTAssertEqual(error.errorCategory, .authenticationFailed)
        }
    }

    func testAnalysisTimeframeAndSummaryUnwrap() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "symbol": "DRIFT",
                "timeframe": "1h",
                "summary": {
                  "status": "neutral",
                  "label": "중립",
                  "score": 0,
                  "bullishCount": 1,
                  "bearishCount": 1,
                  "neutralCount": 2
                },
                "indicators": [
                  {
                    "key": "rsi",
                    "label": "RSI",
                    "state": "neutral",
                    "valueText": "데이터 부족",
                    "description": "최근 캔들 데이터가 부족합니다."
                  }
                ],
                "source": { "type": "technical", "fallbackUsed": false }
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let snapshot = try await repository.fetchCoinAnalysis(symbol: "drift", timeframe: .h1)

        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.path, "/coins/DRIFT/analysis")
        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.query, "timeframe=1h")
        XCTAssertEqual(snapshot.summaryLabel, .neutral)
        XCTAssertEqual(snapshot.indicators.first?.name, "RSI")
        XCTAssertEqual(snapshot.indicators.first?.description, "최근 캔들 데이터가 부족합니다.")
    }

    func testAnalysisFallbackPayloadWithEmptyIndicatorsStillLoadsDataInsufficientIndicator() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "symbol": "ORCA",
                "timeframe": "1h",
                "summary": {
                  "status": "neutral",
                  "label": "중립",
                  "score": 0,
                  "bullishCount": 0,
                  "bearishCount": 0,
                  "neutralCount": 1
                },
                "indicators": [],
                "source": { "type": "fallback", "fallbackUsed": true },
                "asOf": "2026-05-01T12:24:00Z"
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let snapshot = try await repository.fetchCoinAnalysis(symbol: "KRW-ORCA", timeframe: .h1)

        XCTAssertEqual(URLProtocolSpy.lastRequest?.url?.path, "/coins/ORCA/analysis")
        XCTAssertEqual(snapshot.summaryLabel, .neutral)
        XCTAssertTrue(snapshot.fallbackUsed)
        XCTAssertEqual(snapshot.indicators.first?.valueText, "데이터 부족")
    }

    func testMarketTrendsEmptySeriesIsNotError() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "summary": {
                  "totalMarketCap": null,
                  "volume24h": 81609000000,
                  "btcDominance": 51.2,
                  "ethDominance": 17.3
                },
                "movers": {
                  "topGainers": [],
                  "topLosers": [],
                  "topVolume": []
                },
                "series": {
                  "marketCap": [],
                  "volume": []
                },
                "source": { "primary": "provider", "fallbackUsed": false }
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let trends = try await repository.fetchMarketTrends()

        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/news/overview"])
        let query = queryItems(from: URLProtocolSpy.lastRequest?.url)
        XCTAssertEqual(query["range"], "30d")
        XCTAssertEqual(query["interval"], "daily")
        XCTAssertEqual(query["currency"], "KRW")
        XCTAssertNil(trends.totalMarketCap)
        XCTAssertEqual(trends.totalVolume24h, 81_609_000_000)
        XCTAssertTrue(trends.marketCapVolumeSeries.isEmpty)
    }

    func testCoinInfoPrefersPlainTextKoDescription() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "symbol": "ORCA",
                "description": {
                  "plainTextKo": "오르카는 솔라나 기반 탈중앙화 거래소입니다.",
                  "plainTextEn": "Orca is a decentralized exchange on Solana."
                },
                "source": { "fallbackUsed": false }
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let info = try await repository.fetchCoinInfo(symbol: "ORCA")

        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/coins/ORCA/info"])
        XCTAssertEqual(info.description, "오르카는 솔라나 기반 탈중앙화 거래소입니다.")
        XCTAssertEqual(info.descriptionRenderLanguage, "ko")
        XCTAssertNil(info.descriptionFallbackNotice)
    }

    func testPrivateRelayEmailIsNotUsedAsPrimaryDisplayName() {
        let result = UserDisplayNamePolicy.resolve(
            displayName: "w9xnwcrq9f@privaterelay.appleid.com",
            nickname: nil,
            profileName: nil,
            emailMasked: "w9***@privaterelay.appleid.com",
            email: "w9xnwcrq9f@privaterelay.appleid.com"
        )

        XCTAssertEqual(result.primaryName, "Apple 사용자")
        XCTAssertEqual(result.subtitle, "w9***@privaterelay.appleid.com")
        XCTAssertTrue(result.isPrivateRelay)
    }

    func testMarketTrendsSeparateMarketCapAndVolumeSeriesAreMerged() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "summary": { "volume24h": 1000 },
                "movers": { "topGainers": [], "topLosers": [], "topVolume": [] },
                "series": {
                  "marketCap": [
                    { "time": "2026-05-01T00:00:00Z", "value": 100 },
                    { "time": "2026-05-01T01:00:00Z", "value": 120 }
                  ],
                  "volume": [
                    { "time": "2026-05-01T00:00:00Z", "value": 10 },
                    { "time": "2026-05-01T01:00:00Z", "value": 12 }
                  ]
                },
                "source": { "primary": "provider", "fallbackUsed": false }
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let trends = try await repository.fetchMarketTrends()

        XCTAssertEqual(trends.marketCapVolumeSeries.count, 2)
        XCTAssertEqual(trends.marketCapVolumeSeries.last?.marketCap, 120)
        XCTAssertEqual(trends.marketCapVolumeSeries.last?.volume, 12)
    }

    func testMarketTrendsUnifiedPointsDecodeAllMetrics() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "range": "7D",
                "currency": "USD",
                "summary": { "volume24h": 1000 },
                "series": {
                  "points": [
                    {
                      "timestamp": "2026-05-01T00:00:00Z",
                      "totalMarketCap": 100,
                      "totalVolume": 10,
                      "btcDominance": 0.58,
                      "ethDominance": 10.3,
                      "fearGreedIndex": 26
                    },
                    {
                      "timestamp": "2026-05-02T00:00:00Z",
                      "totalMarketCap": 120,
                      "totalVolume": 12,
                      "btcDominance": 59,
                      "ethDominance": 10.5,
                      "fearGreedIndex": 28
                    }
                  ]
                },
                "events": [],
                "source": { "primary": "coingecko", "fallbackUsed": false },
                "updatedAt": "2026-05-02T01:00:00Z"
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let trends = try await repository.fetchMarketTrends()

        XCTAssertEqual(trends.range, "7D")
        XCTAssertEqual(trends.currency, "USD")
        XCTAssertEqual(trends.marketCapVolumeSeries.count, 2)
        XCTAssertEqual(trends.marketCapVolumeSeries.first?.btcDominance ?? 0, 58, accuracy: 0.0001)
        XCTAssertEqual(trends.marketCapVolumeSeries.last?.fearGreedIndex, 28)
    }

    func testPeriodChangeOnly24hHidesUnavailableOptionalPeriods() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "symbol": "ORCA",
                "market": {
                  "priceChangePercent24h": 2.5
                }
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let info = try await repository.fetchCoinInfo(symbol: "ORCA")

        XCTAssertEqual(info.availablePriceChangePeriods, [.h24])
        XCTAssertTrue(info.hasOnly24hPriceChange)
    }

    func testPeriodChangeOptionalFieldsRenderWhenPresent() async throws {
        URLProtocolSpy.reset()
        URLProtocolSpy.responseData = Data(
            """
            {
              "success": true,
              "data": {
                "symbol": "ORCA",
                "market": {
                  "priceChangePercent24h": 2.5,
                  "priceChangePercent7d": 4.0,
                  "priceChangePercent14d": 6.0,
                  "priceChangePercent30d": 8.0,
                  "priceChangePercent60d": 10.0,
                  "priceChangePercent200d": 12.0,
                  "priceChangePercent1y": 14.0
                }
              }
            }
            """.utf8
        )
        let repository = makeRepository()

        let info = try await repository.fetchCoinInfo(symbol: "ORCA")

        XCTAssertEqual(info.availablePriceChangePeriods, CoinPriceChangePeriod.allCases)
        XCTAssertEqual(info.priceChangePercentages[.d7], 4.0)
        XCTAssertEqual(info.priceChangePercentages[.y1], 14.0)
    }

    func testLatestTrendsAndMarketDataExposeDistinctSections() {
        let trends = MarketTrendsSnapshot(
            totalMarketCap: 100,
            totalMarketCapChange24h: 2,
            totalVolume24h: 10,
            btcDominance: 50,
            ethDominance: 18,
            fearGreedIndex: 60,
            altcoinIndex: 55,
            btcLongShortRatio: nil,
            marketPoll: MarketPollSnapshot(bullishCount: 2, bearishCount: 1, totalCount: 3),
            movers: MarketMoversSnapshot(
                topGainers: [MarketMover(id: "ORCA", symbol: "ORCA", name: nil, price: nil, changePercent24h: 3, volume24h: nil)],
                topLosers: [],
                topVolume: []
            ),
            marketCapVolumeSeries: [],
            bitcoinHalvingCountdown: nil,
            latestHeadline: "headline",
            dataProvider: "provider",
            fallbackUsed: false,
            asOf: nil
        )

        XCTAssertTrue(trends.latestTrendSections.contains(.headline))
        XCTAssertTrue(trends.latestTrendSections.contains(.fearGreedMood))
        XCTAssertTrue(trends.latestTrendSections.contains(.marketPoll))
        XCTAssertTrue(trends.latestTrendSections.contains(.topMovers))
        XCTAssertFalse(trends.latestTrendSections.contains(.seriesPlaceholder))
        XCTAssertEqual(trends.marketDataDashboardSections, [.metrics, .trendChart, .metadata, .disclaimer])
    }

    func testMarketDataFallbackMessageCanBeMappedSeparatelyFromTrends() {
        let error = NetworkServiceError.httpError(404, "Cannot GET /market/trends", .unknown)

        XCTAssertEqual(
            error.userFacingDescription(fallback: "시장 데이터를 불러오지 못했어요."),
            "시장 데이터를 불러오지 못했어요."
        )
    }

    func testCompactKoreanAmountFormatterKeepsEokAndJoUnits() {
        XCTAssertEqual(PriceFormatter.formatCompactKRWAmount(81_609_000_000), "816.09억")
        XCTAssertEqual(PriceFormatter.formatCompactKRWAmount(1_230_000_000_000), "1.23조")
        XCTAssertEqual(PriceFormatter.formatKRW(1234), "₩1,234")
        XCTAssertEqual(PriceFormatter.formatPercent(2.97), "+2.97%")
        XCTAssertEqual(PriceFormatter.formatPercent(-1.2), "-1.20%")
    }
}
