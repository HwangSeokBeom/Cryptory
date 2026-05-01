import XCTest
@testable import Cryptory

final class PublicContentRepositoryTests: XCTestCase {
    private func makeRepository() -> LivePublicContentRepository {
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
        return LivePublicContentRepository(client: client)
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

        let snapshot = try await repository.fetchNews(category: nil, symbol: nil, cursor: nil, limit: 40)

        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/news"])
        XCTAssertTrue(snapshot.items.isEmpty)
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

        XCTAssertEqual(URLProtocolSpy.requestedPaths, ["/market/trends"])
        XCTAssertNil(trends.totalMarketCap)
        XCTAssertEqual(trends.totalVolume24h, 81_609_000_000)
        XCTAssertTrue(trends.marketCapVolumeSeries.isEmpty)
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
