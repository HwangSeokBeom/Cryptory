import Foundation

struct CryptoNewsItem: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let summary: String
    let body: String?
    let source: String
    let publishedAt: Date?
    let relatedSymbols: [String]
    let originalURL: URL?
    let thumbnailURL: URL?

    var dateGroupText: String {
        guard let publishedAt else { return "날짜 미확인" }
        return Self.dateFormatter.string(from: publishedAt)
    }

    var timeText: String {
        guard let publishedAt else { return "--:--" }
        return Self.timeFormatter.string(from: publishedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

struct CoinDetailInfo: Equatable {
    let symbol: String
    let displaySymbol: String?
    let name: String?
    let logoURL: URL?
    let provider: String?
    let providerId: String?
    let rank: Int?
    let marketCap: Double?
    let circulatingSupply: Double?
    let maxSupply: Double?
    let totalSupply: Double?
    let currentPrice: Double?
    let priceCurrency: String?
    let high24h: Double?
    let low24h: Double?
    let allTimeHigh: Double?
    let allTimeLow: Double?
    let volume24h: Double?
    let tradeValue24h: Double?
    let marketCapChange24h: Double?
    let marketAsOf: Date?
    let priceChangePercentages: [CoinPriceChangePeriod: Double]
    let description: String?
    let officialURL: URL?
    let explorerURL: URL?
    let dataProvider: String?
    let metadataSource: String?
    let marketSource: String?
    let fallbackUsed: Bool

    var communityURL: URL? { explorerURL }

    var nullMarketFieldCount: Int {
        [
            currentPrice, high24h, low24h, volume24h, tradeValue24h, marketCap,
            circulatingSupply, totalSupply, maxSupply, allTimeHigh, allTimeLow
        ].filter { $0 == nil }.count
    }
}

enum CoinPriceChangePeriod: String, CaseIterable, Equatable, Hashable {
    case h24
    case d7
    case d14
    case d30
    case d60
    case d200
    case y1

    var title: String {
        switch self {
        case .h24: return "24시간"
        case .d7: return "7일"
        case .d14: return "14일"
        case .d30: return "30일"
        case .d60: return "60일"
        case .d200: return "200일"
        case .y1: return "1년"
        }
    }
}

enum CoinAnalysisTimeframe: String, CaseIterable, Identifiable, Equatable {
    case m1 = "1m"
    case m5 = "5m"
    case m15 = "15m"
    case m30 = "30m"
    case h1 = "1h"
    case h2 = "2h"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .m1: return "1분"
        case .m5: return "5분"
        case .m15: return "15분"
        case .m30: return "30분"
        case .h1: return "1시간"
        case .h2: return "2시간"
        }
    }
}

enum CoinAnalysisSummaryLabel: String, Equatable {
    case strongBearish = "하락 우세"
    case bearish = "하락 신호"
    case neutral = "중립"
    case bullish = "상승 신호"
    case strongBullish = "상승 우세"
    case reference = "시장 참고 신호"

    init(serverValue: String?) {
        let normalized = serverValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""
        switch normalized {
        case "strong_bearish", "strong bearish", "강한 하락 신호":
            self = .strongBearish
        case "bearish", "하락 신호":
            self = .bearish
        case "bullish", "상승 신호":
            self = .bullish
        case "strong_bullish", "strong bullish", "강한 상승 신호":
            self = .strongBullish
        case "reference", "market_reference", "시장 참고 신호":
            self = .reference
        default:
            self = .neutral
        }
    }
}

struct CoinAnalysisIndicator: Identifiable, Equatable {
    let id: String
    let name: String
    let valueText: String
    let description: String?
    let label: CoinAnalysisSummaryLabel
}

struct CoinAnalysisSnapshot: Equatable {
    let symbol: String
    let timeframe: CoinAnalysisTimeframe
    let status: String?
    let summaryLabel: CoinAnalysisSummaryLabel
    let bearishCount: Int
    let neutralCount: Int
    let bullishCount: Int
    let score: Double
    let indicators: [CoinAnalysisIndicator]
    let disclaimer: String
    let dataProvider: String?
    let fallbackUsed: Bool
    let asOf: Date?

    static let defaultDisclaimer = "이 분석은 최근 시장 데이터 기반 참고 정보이며, 투자 조언이나 거래 신호가 아닙니다."

    static func ruleBased(
        symbol: String,
        timeframe: CoinAnalysisTimeframe,
        candles: [CandleData],
        ticker: TickerData?
    ) -> CoinAnalysisSnapshot {
        guard candles.count >= 2 else {
            return CoinAnalysisSnapshot(
                symbol: symbol,
                timeframe: timeframe,
                status: "insufficient_data",
                summaryLabel: .neutral,
                bearishCount: 0,
                neutralCount: 3,
                bullishCount: 0,
                score: 0,
                indicators: [
                    CoinAnalysisIndicator(id: "fallback-price", name: "최근 가격 변화", valueText: "데이터 부족", description: "최근 캔들 데이터가 부족합니다.", label: .neutral),
                    CoinAnalysisIndicator(id: "fallback-ma", name: "이동평균 비교", valueText: "데이터 부족", description: "이동평균 계산에 필요한 데이터가 아직 충분하지 않습니다.", label: .neutral),
                    CoinAnalysisIndicator(id: "fallback-volume", name: "거래대금 흐름", valueText: "데이터 부족", description: "최근 거래대금 흐름을 확인할 데이터가 부족합니다.", label: .neutral)
                ],
                disclaimer: defaultDisclaimer,
                dataProvider: "Market candles",
                fallbackUsed: true,
                asOf: nil
            )
        }

        let orderedCandles = candles.sorted { $0.time < $1.time }
        let latest = orderedCandles.last!
        let previous = orderedCandles[orderedCandles.count - 2]
        let recentChange = previous.close == 0 ? 0 : ((latest.close - previous.close) / previous.close) * 100
        let shortAverage = orderedCandles.suffix(min(5, orderedCandles.count)).map(\.close).average
        let longAverage = orderedCandles.suffix(min(20, orderedCandles.count)).map(\.close).average
        let tickerChange = ticker?.change ?? recentChange

        var indicators: [CoinAnalysisIndicator] = []
        indicators.append(
            CoinAnalysisIndicator(
                id: "recent-change",
                name: "최근 캔들 변화율",
                valueText: String(format: "%+.2f%%", recentChange),
                description: "최근 캔들의 종가 변화를 비교한 참고 지표입니다.",
                label: Self.label(for: recentChange, strongThreshold: 2.4, threshold: 0.4)
            )
        )
        indicators.append(
            CoinAnalysisIndicator(
                id: "moving-average",
                name: "단순 이동평균 비교",
                valueText: shortAverage >= longAverage ? "단기 평균 우위" : "장기 평균 우위",
                description: "단기 평균과 장기 평균의 상대 위치를 비교합니다.",
                label: abs(shortAverage - longAverage) / max(longAverage, 1) > 0.015
                    ? (shortAverage > longAverage ? .bullish : .bearish)
                    : .neutral
            )
        )
        indicators.append(
            CoinAnalysisIndicator(
                id: "ticker-change",
                name: "24시간 가격 흐름",
                valueText: String(format: "%+.2f%%", tickerChange),
                description: "최근 24시간 가격 흐름을 참고 지표로 표시합니다.",
                label: Self.label(for: tickerChange, strongThreshold: 5, threshold: 1)
            )
        )

        let bearishCount = indicators.filter { $0.label == .bearish || $0.label == .strongBearish }.count
        let bullishCount = indicators.filter { $0.label == .bullish || $0.label == .strongBullish }.count
        let neutralCount = indicators.count - bearishCount - bullishCount
        let score = Double(bullishCount - bearishCount) / Double(max(indicators.count, 1))
        let summary = Self.summaryLabel(score: score)

        return CoinAnalysisSnapshot(
            symbol: symbol,
            timeframe: timeframe,
            status: nil,
            summaryLabel: summary,
            bearishCount: bearishCount,
            neutralCount: neutralCount,
            bullishCount: bullishCount,
            score: score,
            indicators: indicators,
            disclaimer: defaultDisclaimer,
            dataProvider: "Market candles",
            fallbackUsed: true,
            asOf: nil
        )
    }

    private static func label(for value: Double, strongThreshold: Double, threshold: Double) -> CoinAnalysisSummaryLabel {
        if value <= -strongThreshold { return .strongBearish }
        if value <= -threshold { return .bearish }
        if value >= strongThreshold { return .strongBullish }
        if value >= threshold { return .bullish }
        return .neutral
    }

    private static func summaryLabel(score: Double) -> CoinAnalysisSummaryLabel {
        if score <= -0.67 { return .strongBearish }
        if score < -0.1 { return .bearish }
        if score >= 0.67 { return .strongBullish }
        if score > 0.1 { return .bullish }
        return .neutral
    }
}

enum CoinDetailTab: String, CaseIterable, Identifiable, Equatable {
    case info
    case chart
    case analysis
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: return "정보"
        case .chart: return "차트"
        case .analysis: return "분석"
        case .community: return "토론"
        }
    }
}

struct CoinCommunityPost: Identifiable, Equatable {
    let id: String
    let authorName: String
    let avatarURL: URL?
    let createdAt: Date?
    let content: String
    let symbol: String
    let tags: [String]
    let likeCount: Int
    let commentCount: Int
    let isFollowing: Bool
    let badge: String?

    var timeAgoText: String {
        guard let createdAt else { return "시간 미확인" }
        let seconds = max(Date().timeIntervalSince(createdAt), 0)
        if seconds < 60 { return "방금 전" }
        if seconds < 3_600 { return "\(Int(seconds / 60))분 전" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))시간 전" }
        return "\(Int(seconds / 86_400))일 전"
    }
}

enum CoinCommunityFilter: String, CaseIterable, Identifiable {
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "전체"
        }
    }
}

struct CoinVoteSnapshot: Equatable {
    let bullishCount: Int
    let bearishCount: Int
    let totalCount: Int
    let myVote: String?

    var participantCount: Int { totalCount }
}

struct CoinCommunitySnapshot: Equatable {
    let posts: [CoinCommunityPost]
    let vote: CoinVoteSnapshot
    let nextCursor: String?

    init(posts: [CoinCommunityPost], vote: CoinVoteSnapshot, nextCursor: String? = nil) {
        self.posts = posts
        self.vote = vote
        self.nextCursor = nextCursor
    }
}

struct MarketTrendPoint: Identifiable, Equatable {
    let id: String
    let date: Date?
    let marketCap: Double?
    let volume: Double?
}

struct BitcoinHalvingCountdown: Equatable {
    let targetDate: Date?
    let days: Int?
    let hours: Int?
    let minutes: Int?
    let seconds: Int?
}

struct MarketPollSnapshot: Equatable {
    let bullishCount: Int
    let bearishCount: Int
    let totalCount: Int
}

struct MarketMover: Identifiable, Equatable {
    let id: String
    let symbol: String
    let name: String?
    let price: Double?
    let changePercent24h: Double?
    let volume24h: Double?
}

struct MarketMoversSnapshot: Equatable {
    let topGainers: [MarketMover]
    let topLosers: [MarketMover]
    let topVolume: [MarketMover]
}

struct MarketThemeSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String?
    let marketCap: Double?
    let volume24h: Double?
    let changePercent24h: Double?
}

struct MarketTrendsSnapshot: Equatable {
    let totalMarketCap: Double?
    let totalMarketCapChange24h: Double?
    let totalVolume24h: Double?
    let btcDominance: Double?
    let ethDominance: Double?
    let fearGreedIndex: Int?
    let altcoinIndex: Int?
    let btcLongShortRatio: Double?
    let marketPoll: MarketPollSnapshot?
    let movers: MarketMoversSnapshot
    let marketCapVolumeSeries: [MarketTrendPoint]
    let bitcoinHalvingCountdown: BitcoinHalvingCountdown?
    let latestHeadline: String?
    let dataProvider: String?
    let fallbackUsed: Bool
    let asOf: Date?
}

private extension Array where Element == Double {
    var average: Double {
        guard isEmpty == false else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
