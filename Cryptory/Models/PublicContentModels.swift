import Foundation

struct CryptoNewsItem: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let summary: String
    let body: String?
    let originalTitle: String
    let originalSummary: String?
    let translatedTitle: String?
    let translatedSummary: String?
    let source: String
    let provider: String?
    let publishedAt: Date?
    let relatedSymbols: [String]
    let tags: [String]
    let originalURL: URL?
    let thumbnailURL: URL?
    let originalLanguage: String?
    let renderLanguage: String
    let translationState: TranslationState
    let titleFallbackUsed: Bool
    let summaryFallbackUsed: Bool
    let relevanceScore: Double?

    init(
        id: String,
        title: String,
        summary: String,
        body: String?,
        originalTitle: String? = nil,
        originalSummary: String? = nil,
        translatedTitle: String? = nil,
        translatedSummary: String? = nil,
        source: String,
        provider: String? = nil,
        publishedAt: Date?,
        relatedSymbols: [String],
        tags: [String] = [],
        originalURL: URL?,
        thumbnailURL: URL?,
        originalLanguage: String? = nil,
        renderLanguage: String = "ko",
        translationState: TranslationState? = nil,
        titleFallbackUsed: Bool = false,
        summaryFallbackUsed: Bool = false,
        relevanceScore: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.body = body
        self.originalTitle = originalTitle ?? title
        self.originalSummary = originalSummary ?? (summary.isEmpty ? nil : summary)
        self.translatedTitle = translatedTitle
        self.translatedSummary = translatedSummary
        self.source = source
        self.provider = provider
        self.publishedAt = publishedAt
        self.relatedSymbols = relatedSymbols
        self.tags = tags
        self.originalURL = originalURL
        self.thumbnailURL = thumbnailURL
        self.originalLanguage = originalLanguage
        self.renderLanguage = renderLanguage
        self.translationState = translationState ?? (titleFallbackUsed || summaryFallbackUsed ? .originalOnly : .translated)
        self.titleFallbackUsed = titleFallbackUsed
        self.summaryFallbackUsed = summaryFallbackUsed
        self.relevanceScore = relevanceScore
    }

    var dateGroupText: String {
        guard let publishedAt else { return "날짜 미확인" }
        return Self.dateFormatter.string(from: publishedAt)
    }

    var timeText: String {
        guard let publishedAt else { return "--:--" }
        let calendar = Calendar(identifier: .gregorian)
        if calendar.isDateInToday(publishedAt) {
            return Self.timeFormatter.string(from: publishedAt)
        }
        if calendar.isDateInYesterday(publishedAt)
            || Date().timeIntervalSince(publishedAt) < 60 * 60 * 24 * 7 {
            return Self.recentFormatter.string(from: publishedAt)
        }
        return Self.dateFormatter.string(from: publishedAt)
    }

    var translationStatusText: String? {
        translationState.badgeText
    }

    var hasTranslation: Bool {
        translatedTitle?.trimmedNonEmpty != nil || translatedSummary?.trimmedNonEmpty != nil
    }

    func textVariant(showOriginal: Bool) -> (title: String, summary: String) {
        if showOriginal {
            return (originalTitle, originalSummary ?? summary)
        }
        return (translatedTitle ?? title, translatedSummary ?? summary)
    }

    func replacingTranslated(title: String?, summary: String?, state: TranslationState = .translated) -> CryptoNewsItem {
        let translatedTitle = title ?? self.translatedTitle
        let translatedSummary = summary ?? self.translatedSummary
        return CryptoNewsItem(
            id: id,
            title: translatedTitle ?? self.title,
            summary: translatedSummary ?? self.summary,
            body: body,
            originalTitle: originalTitle,
            originalSummary: originalSummary,
            translatedTitle: translatedTitle,
            translatedSummary: translatedSummary,
            source: source,
            provider: provider,
            publishedAt: publishedAt,
            relatedSymbols: relatedSymbols,
            tags: tags,
            originalURL: originalURL,
            thumbnailURL: thumbnailURL,
            originalLanguage: originalLanguage,
            renderLanguage: translatedTitle != nil || translatedSummary != nil ? "ko" : renderLanguage,
            translationState: translatedTitle != nil || translatedSummary != nil ? state : .failed,
            titleFallbackUsed: translatedTitle == nil && titleFallbackUsed,
            summaryFallbackUsed: translatedSummary == nil && summaryFallbackUsed,
            relevanceScore: relevanceScore
        )
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

    private static let recentFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter
    }()
}

struct NewsFeedViewState: Equatable {
    let selectedDate: Date
    let requestDateString: String
    let selectedSort: ContentSortOrder
    let isCoinScoped: Bool
    let symbol: String?
    let coinName: String?
    let items: [CryptoNewsItem]
    let emptyReason: String?
    let source: String?
    let cacheHit: Bool?
    let providerStatus: String?
    let latestFallbackDate: Date?
    let availableDates: [Date]

    static func initial(selectedDate: Date = Date(), selectedSort: ContentSortOrder = .latest, isCoinScoped: Bool = false, symbol: String? = nil, coinName: String? = nil) -> NewsFeedViewState {
        NewsFeedViewState(
            selectedDate: selectedDate,
            requestDateString: LivePublicContentRepository.apiDateString(selectedDate),
            selectedSort: selectedSort,
            isCoinScoped: isCoinScoped,
            symbol: symbol,
            coinName: coinName,
            items: [],
            emptyReason: nil,
            source: nil,
            cacheHit: nil,
            providerStatus: nil,
            latestFallbackDate: nil,
            availableDates: []
        )
    }

    func preparing(date: Date, sort: ContentSortOrder, symbol: String? = nil, coinName: String? = nil, isCoinScoped: Bool? = nil) -> NewsFeedViewState {
        NewsFeedViewState(
            selectedDate: date,
            requestDateString: LivePublicContentRepository.apiDateString(date),
            selectedSort: sort,
            isCoinScoped: isCoinScoped ?? self.isCoinScoped,
            symbol: symbol ?? self.symbol,
            coinName: coinName ?? self.coinName,
            items: [],
            emptyReason: nil,
            source: nil,
            cacheHit: nil,
            providerStatus: nil,
            latestFallbackDate: nil,
            availableDates: []
        )
    }

    func resolved(items: [CryptoNewsItem], meta: ResponseMeta, emptyReason: String?) -> NewsFeedViewState {
        NewsFeedViewState(
            selectedDate: selectedDate,
            requestDateString: requestDateString,
            selectedSort: selectedSort,
            isCoinScoped: isCoinScoped,
            symbol: symbol,
            coinName: coinName,
            items: items,
            emptyReason: items.isEmpty ? emptyReason : nil,
            source: meta.source,
            cacheHit: meta.cacheHit,
            providerStatus: meta.providerStatus,
            latestFallbackDate: meta.latestFallbackDate,
            availableDates: meta.availableDates ?? []
        )
    }
}

enum MarketTrendRange: String, CaseIterable, Identifiable, Equatable {
    case d7 = "7d"
    case d30 = "30d"
    case d90 = "90d"
    case y1 = "1y"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .d7: return "7일"
        case .d30: return "30일"
        case .d90: return "90일"
        case .y1: return "1년"
        }
    }
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
    let originalDescription: String?
    let translatedDescription: String?
    let descriptionRenderLanguage: String
    let descriptionFallbackNotice: String?
    let descriptionTranslationState: TranslationState

    init(
        symbol: String,
        displaySymbol: String?,
        name: String?,
        logoURL: URL?,
        provider: String?,
        providerId: String?,
        rank: Int?,
        marketCap: Double?,
        circulatingSupply: Double?,
        maxSupply: Double?,
        totalSupply: Double?,
        currentPrice: Double?,
        priceCurrency: String?,
        high24h: Double?,
        low24h: Double?,
        allTimeHigh: Double?,
        allTimeLow: Double?,
        volume24h: Double?,
        tradeValue24h: Double?,
        marketCapChange24h: Double?,
        marketAsOf: Date?,
        priceChangePercentages: [CoinPriceChangePeriod: Double],
        description: String?,
        officialURL: URL?,
        explorerURL: URL?,
        dataProvider: String?,
        metadataSource: String?,
        marketSource: String?,
        fallbackUsed: Bool,
        originalDescription: String? = nil,
        translatedDescription: String? = nil,
        descriptionRenderLanguage: String = "unknown",
        descriptionFallbackNotice: String? = nil,
        descriptionTranslationState: TranslationState? = nil
    ) {
        self.symbol = symbol
        self.displaySymbol = displaySymbol
        self.name = name
        self.logoURL = logoURL
        self.provider = provider
        self.providerId = providerId
        self.rank = rank
        self.marketCap = marketCap
        self.circulatingSupply = circulatingSupply
        self.maxSupply = maxSupply
        self.totalSupply = totalSupply
        self.currentPrice = currentPrice
        self.priceCurrency = priceCurrency
        self.high24h = high24h
        self.low24h = low24h
        self.allTimeHigh = allTimeHigh
        self.allTimeLow = allTimeLow
        self.volume24h = volume24h
        self.tradeValue24h = tradeValue24h
        self.marketCapChange24h = marketCapChange24h
        self.marketAsOf = marketAsOf
        self.priceChangePercentages = priceChangePercentages
        self.description = description
        self.officialURL = officialURL
        self.explorerURL = explorerURL
        self.dataProvider = dataProvider
        self.metadataSource = metadataSource
        self.marketSource = marketSource
        self.fallbackUsed = fallbackUsed
        self.originalDescription = originalDescription ?? description
        self.translatedDescription = translatedDescription
        self.descriptionRenderLanguage = descriptionRenderLanguage
        self.descriptionFallbackNotice = descriptionFallbackNotice
        self.descriptionTranslationState = descriptionTranslationState ?? (descriptionRenderLanguage == "ko" ? .translated : (description == nil ? .notRequested : .originalOnly))
    }

    var communityURL: URL? { explorerURL }

    var nullMarketFieldCount: Int {
        [
            currentPrice, high24h, low24h, volume24h, tradeValue24h, marketCap,
            circulatingSupply, totalSupply, maxSupply, allTimeHigh, allTimeLow
        ].filter { $0 == nil }.count
    }

    var availablePriceChangePeriods: [CoinPriceChangePeriod] {
        CoinPriceChangePeriod.allCases.filter { priceChangePercentages[$0] != nil }
    }

    var hasOnly24hPriceChange: Bool {
        availablePriceChangePeriods == [.h24]
    }

    func replacingDescription(_ description: String?, language: String, notice: String?, translationState: TranslationState? = nil) -> CoinDetailInfo {
        CoinDetailInfo(
            symbol: symbol,
            displaySymbol: displaySymbol,
            name: name,
            logoURL: logoURL,
            provider: provider,
            providerId: providerId,
            rank: rank,
            marketCap: marketCap,
            circulatingSupply: circulatingSupply,
            maxSupply: maxSupply,
            totalSupply: totalSupply,
            currentPrice: currentPrice,
            priceCurrency: priceCurrency,
            high24h: high24h,
            low24h: low24h,
            allTimeHigh: allTimeHigh,
            allTimeLow: allTimeLow,
            volume24h: volume24h,
            tradeValue24h: tradeValue24h,
            marketCapChange24h: marketCapChange24h,
            marketAsOf: marketAsOf,
            priceChangePercentages: priceChangePercentages,
            description: description,
            officialURL: officialURL,
            explorerURL: explorerURL,
            dataProvider: dataProvider,
            metadataSource: metadataSource,
            marketSource: marketSource,
            fallbackUsed: fallbackUsed,
            originalDescription: originalDescription,
            translatedDescription: language == "ko" ? description : translatedDescription,
            descriptionRenderLanguage: language,
            descriptionFallbackNotice: notice,
            descriptionTranslationState: translationState ?? (language == "ko" ? .translated : .originalOnly)
        )
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
    case news

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: return "정보"
        case .chart: return "차트"
        case .analysis: return "분석"
        case .community: return "토론"
        case .news: return "뉴스"
        }
    }
}

struct CoinCommunityPost: Identifiable, Equatable {
    let id: String
    let authorId: String?
    let authorName: String
    let avatarURL: URL?
    let createdAt: Date?
    let content: String
    let symbol: String
    let tags: [String]
    let likeCount: Int
    let commentCount: Int
    let isLiked: Bool
    let isFollowing: Bool
    let isOwnPost: Bool
    let badge: String?

    init(
        id: String,
        authorId: String? = nil,
        authorName: String,
        avatarURL: URL?,
        createdAt: Date?,
        content: String,
        symbol: String,
        tags: [String],
        likeCount: Int,
        commentCount: Int,
        isLiked: Bool = false,
        isFollowing: Bool,
        isOwnPost: Bool = false,
        badge: String?
    ) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.content = content
        self.symbol = symbol
        self.tags = tags
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.isLiked = isLiked
        self.isFollowing = isFollowing
        self.isOwnPost = isOwnPost
        self.badge = badge
    }

    var timeAgoText: String {
        guard let createdAt else { return "시간 미확인" }
        let seconds = max(Date().timeIntervalSince(createdAt), 0)
        if seconds < 60 { return "방금 전" }
        if seconds < 3_600 { return "\(Int(seconds / 60))분 전" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))시간 전" }
        return "\(Int(seconds / 86_400))일 전"
    }
}

enum UserDisplayNamePolicy {
    struct Resolution: Equatable {
        let primaryName: String
        let subtitle: String?
        let source: String
        let isPrivateRelay: Bool
    }

    static func resolve(
        displayName: String?,
        nickname: String?,
        profileName: String? = nil,
        emailMasked: String?,
        email: String?,
        fallback: String = "사용자"
    ) -> Resolution {
        let displayName = displayName?.trimmedNonEmpty
        let nickname = nickname?.trimmedNonEmpty
        let profileName = profileName?.trimmedNonEmpty
        let emailMasked = emailMasked?.trimmedNonEmpty
        let email = email?.trimmedNonEmpty
        let isPrivateRelay = [displayName, nickname, profileName, email]
            .compactMap { $0 }
            .contains(where: isPrivateRelayEmail)

        let candidates: [(String, String?)] = [
            ("displayName", displayName.flatMap { isPrivateRelayEmail($0) ? nil : $0 }),
            ("nickname", nickname.flatMap { isPrivateRelayEmail($0) ? nil : $0 }),
            ("profileName", profileName.flatMap { isPrivateRelayEmail($0) ? nil : $0 }),
            ("emailMasked", emailMasked.flatMap { isPrivateRelayEmail($0) ? nil : $0 })
        ]
        if let selected = candidates.first(where: { $0.1?.isEmpty == false }),
           let value = selected.1 {
            return Resolution(
                primaryName: value,
                subtitle: selected.0 == "emailMasked" ? nil : emailMasked,
                source: selected.0,
                isPrivateRelay: isPrivateRelay
            )
        }

        if let email, isPrivateRelay == false {
            return Resolution(
                primaryName: maskedEmailLocalPart(email),
                subtitle: nil,
                source: "maskedEmail",
                isPrivateRelay: false
            )
        }

        return Resolution(
            primaryName: isPrivateRelay ? "Apple 사용자" : fallback,
            subtitle: emailMasked ?? (isPrivateRelay ? maskedEmailLocalPart(email ?? "") : nil),
            source: isPrivateRelay ? "privateRelayFallback" : "fallback",
            isPrivateRelay: isPrivateRelay
        )
    }

    static func isPrivateRelayEmail(_ value: String) -> Bool {
        value.lowercased().contains("privaterelay.appleid.com")
    }

    static func maskedEmailLocalPart(_ value: String) -> String {
        let parts = value.split(separator: "@", maxSplits: 1).map(String.init)
        guard let local = parts.first, local.isEmpty == false else { return "사용자" }
        let domain = parts.count > 1 ? parts[1] : nil
        let prefix = String(local.prefix(2))
        let suffix = local.count > 4 ? String(local.suffix(2)) : ""
        let masked = suffix.isEmpty ? "\(prefix)***" : "\(prefix)***\(suffix)"
        return domain.map { "\(masked)@\($0)" } ?? masked
    }
}

struct CoinCommunityComment: Identifiable, Equatable {
    let id: String
    let authorId: String?
    let content: String
    let authorName: String
    let createdAt: Date?
    let isOwnComment: Bool

    init(
        id: String,
        authorId: String? = nil,
        content: String,
        authorName: String,
        createdAt: Date?,
        isOwnComment: Bool = false
    ) {
        self.id = id
        self.authorId = authorId
        self.content = content
        self.authorName = authorName
        self.createdAt = createdAt
        self.isOwnComment = isOwnComment
    }

    var timeAgoText: String {
        guard let createdAt else { return "시간 미확인" }
        let seconds = max(Date().timeIntervalSince(createdAt), 0)
        if seconds < 60 { return "방금 전" }
        if seconds < 3_600 { return "\(Int(seconds / 60))분 전" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))시간 전" }
        return "\(Int(seconds / 86_400))일 전"
    }
}

struct CoinCommunityCommentsSnapshot: Equatable {
    let comments: [CoinCommunityComment]
    let commentCount: Int

    func sorted(sort: String) -> CoinCommunityCommentsSnapshot {
        let sortedComments: [CoinCommunityComment]
        switch sort.lowercased() {
        case "oldest", "asc":
            sortedComments = comments.sorted { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
        default:
            sortedComments = comments.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
        return CoinCommunityCommentsSnapshot(comments: sortedComments, commentCount: commentCount)
    }
}

struct CoinCommunityLikeResult: Equatable {
    let itemId: String
    let likeCount: Int
    let isLiked: Bool
}

struct UserFollowResult: Equatable {
    let userId: String
    let isFollowing: Bool
}

enum CommunityReportTargetType: String, CaseIterable, Equatable {
    case post
    case comment
    case user
    case news
}

enum CommunityReportReason: String, CaseIterable, Identifiable, Equatable {
    case spam
    case harassment
    case sexual
    case scam
    case privacy
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: return "스팸/광고"
        case .harassment: return "혐오/괴롭힘"
        case .sexual: return "음란/부적절한 콘텐츠"
        case .scam: return "사기/투자 유도"
        case .privacy: return "개인정보 노출"
        case .other: return "기타"
        }
    }
}

struct CommunityReportResult: Equatable {
    let targetType: CommunityReportTargetType
    let targetId: String
    let message: String?
    let hidden: Bool
}

struct BlockedUser: Identifiable, Equatable {
    let id: String
    let displayName: String?
    let blockedAt: Date?
}

struct UserRelationship: Equatable {
    let userId: String
    let isFollowing: Bool
    let isFollower: Bool
    let isBlocked: Bool
    let isMe: Bool
}

struct UserListSnapshot: Equatable {
    let users: [BlockedUser]
    let nextCursor: String?
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
    let bullishRatio: Double?
    let bearishRatio: Double?
    let myVote: String?
    let scope: String?
    let key: String?
    let source: String?
    let updatedAt: Date?
    let hasServerCounts: Bool

    init(
        bullishCount: Int,
        bearishCount: Int,
        totalCount: Int,
        bullishRatio: Double? = nil,
        bearishRatio: Double? = nil,
        myVote: String?,
        scope: String? = nil,
        key: String? = nil,
        source: String? = nil,
        updatedAt: Date? = nil,
        hasServerCounts: Bool = true
    ) {
        self.bullishCount = bullishCount
        self.bearishCount = bearishCount
        self.totalCount = totalCount
        self.bullishRatio = bullishRatio
        self.bearishRatio = bearishRatio
        self.myVote = myVote
        self.scope = scope
        self.key = key
        self.source = source
        self.updatedAt = updatedAt
        self.hasServerCounts = hasServerCounts
    }

    var participantCount: Int { totalCount }

    var bullishDisplayRatio: Double {
        if let bullishRatio { return bullishRatio }
        guard totalCount > 0 else { return 0 }
        return Double(bullishCount) / Double(totalCount)
    }

    var bearishDisplayRatio: Double {
        if let bearishRatio { return bearishRatio }
        guard totalCount > 0 else { return 0 }
        return Double(bearishCount) / Double(totalCount)
    }
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

struct CoinCommunityMutationResult: Equatable {
    let post: CoinCommunityPost?
    let snapshot: CoinCommunitySnapshot?
    let message: String?

    init(post: CoinCommunityPost?, snapshot: CoinCommunitySnapshot? = nil, message: String? = nil) {
        self.post = post
        self.snapshot = snapshot
        self.message = message
    }
}

struct MarketTrendPoint: Identifiable, Equatable {
    let id: String
    let date: Date?
    let marketCap: Double?
    let volume: Double?
    let btcDominance: Double?
    let ethDominance: Double?
    let fearGreedIndex: Double?

    init(
        id: String,
        date: Date?,
        marketCap: Double?,
        volume: Double?,
        btcDominance: Double? = nil,
        ethDominance: Double? = nil,
        fearGreedIndex: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.marketCap = marketCap
        self.volume = volume
        self.btcDominance = btcDominance
        self.ethDominance = ethDominance
        self.fearGreedIndex = fearGreedIndex
    }
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
    let bullishRatio: Double?
    let bearishRatio: Double?
    let myVote: String?
    let scope: String?
    let key: String?
    let source: String?
    let updatedAt: Date?
    let hasServerCounts: Bool

    init(
        bullishCount: Int,
        bearishCount: Int,
        totalCount: Int,
        bullishRatio: Double? = nil,
        bearishRatio: Double? = nil,
        myVote: String? = nil,
        scope: String? = "market",
        key: String? = "global",
        source: String? = nil,
        updatedAt: Date? = nil,
        hasServerCounts: Bool = true
    ) {
        self.bullishCount = bullishCount
        self.bearishCount = bearishCount
        self.totalCount = totalCount
        self.bullishRatio = bullishRatio
        self.bearishRatio = bearishRatio
        self.myVote = myVote
        self.scope = scope
        self.key = key
        self.source = source
        self.updatedAt = updatedAt
        self.hasServerCounts = hasServerCounts
    }

    var participantCount: Int { totalCount }

    var bullishDisplayRatio: Double {
        if let bullishRatio { return bullishRatio }
        guard totalCount > 0 else { return 0 }
        return Double(bullishCount) / Double(totalCount)
    }

    var bearishDisplayRatio: Double {
        if let bearishRatio { return bearishRatio }
        guard totalCount > 0 else { return 0 }
        return Double(bearishCount) / Double(totalCount)
    }

    static let empty = MarketPollSnapshot(
        bullishCount: 0,
        bearishCount: 0,
        totalCount: 0,
        hasServerCounts: false
    )
}

struct MarketEventSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String?
    let date: Date?
    let importance: String?
    let source: String?
    let url: URL?
}

struct MarketNewsSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String?
    let originalTitle: String
    let originalSummary: String?
    let translatedTitle: String?
    let translatedSummary: String?
    let source: String?
    let publishedAt: Date?
    let renderLanguage: String
    let translationState: TranslationState
    let fallbackUsed: Bool

    init(
        id: String,
        title: String,
        summary: String?,
        originalTitle: String? = nil,
        originalSummary: String? = nil,
        translatedTitle: String? = nil,
        translatedSummary: String? = nil,
        source: String?,
        publishedAt: Date?,
        renderLanguage: String = "ko",
        translationState: TranslationState? = nil,
        fallbackUsed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.originalTitle = originalTitle ?? title
        self.originalSummary = originalSummary ?? summary
        self.translatedTitle = translatedTitle
        self.translatedSummary = translatedSummary
        self.source = source
        self.publishedAt = publishedAt
        self.renderLanguage = renderLanguage
        self.translationState = translationState ?? (fallbackUsed ? .originalOnly : .translated)
        self.fallbackUsed = fallbackUsed
    }

    func replacingTranslated(title: String?, summary: String?) -> MarketNewsSummary {
        MarketNewsSummary(
            id: id,
            title: title ?? self.title,
            summary: summary ?? self.summary,
            originalTitle: originalTitle,
            originalSummary: originalSummary,
            translatedTitle: title ?? translatedTitle,
            translatedSummary: summary ?? translatedSummary,
            source: source,
            publishedAt: publishedAt,
            renderLanguage: title != nil || summary != nil ? "ko" : renderLanguage,
            translationState: title != nil || summary != nil ? .translated : .failed,
            fallbackUsed: title == nil && summary == nil && fallbackUsed
        )
    }
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
    let range: String?
    let currency: String?
    let events: [MarketEventSnapshot]
    let topNews: [MarketNewsSummary]
    let bitcoinHalvingCountdown: BitcoinHalvingCountdown?
    let latestHeadline: String?
    let summaryDescription: String?
    let eventsEmptyReason: String?
    let unavailableReasons: [String]
    let dataProvider: String?
    let fallbackUsed: Bool
    let asOf: Date?

    init(
        totalMarketCap: Double?,
        totalMarketCapChange24h: Double?,
        totalVolume24h: Double?,
        btcDominance: Double?,
        ethDominance: Double?,
        fearGreedIndex: Int?,
        altcoinIndex: Int?,
        btcLongShortRatio: Double?,
        marketPoll: MarketPollSnapshot?,
        movers: MarketMoversSnapshot,
        marketCapVolumeSeries: [MarketTrendPoint],
        range: String? = nil,
        currency: String? = nil,
        events: [MarketEventSnapshot] = [],
        topNews: [MarketNewsSummary] = [],
        bitcoinHalvingCountdown: BitcoinHalvingCountdown?,
        latestHeadline: String?,
        summaryDescription: String? = nil,
        eventsEmptyReason: String? = nil,
        unavailableReasons: [String] = [],
        dataProvider: String?,
        fallbackUsed: Bool,
        asOf: Date?
    ) {
        self.totalMarketCap = totalMarketCap
        self.totalMarketCapChange24h = totalMarketCapChange24h
        self.totalVolume24h = totalVolume24h
        self.btcDominance = btcDominance
        self.ethDominance = ethDominance
        self.fearGreedIndex = fearGreedIndex
        self.altcoinIndex = altcoinIndex
        self.btcLongShortRatio = btcLongShortRatio
        self.marketPoll = marketPoll
        self.movers = movers
        self.marketCapVolumeSeries = marketCapVolumeSeries
        self.range = range
        self.currency = currency
        self.events = events
        self.topNews = topNews
        self.bitcoinHalvingCountdown = bitcoinHalvingCountdown
        self.latestHeadline = latestHeadline
        self.summaryDescription = summaryDescription
        self.eventsEmptyReason = eventsEmptyReason
        self.unavailableReasons = unavailableReasons
        self.dataProvider = dataProvider
        self.fallbackUsed = fallbackUsed
        self.asOf = asOf
    }

    var latestTrendSections: [LatestTrendSection] {
        var sections: [LatestTrendSection] = [.headline, .fearGreedMood]
        if marketPoll != nil {
            sections.append(.marketPoll)
        }
        if movers.topGainers.isEmpty == false || movers.topLosers.isEmpty == false || movers.topVolume.isEmpty == false {
            sections.append(.topMovers)
        }
        sections.append(.eventInsights)
        return sections
    }

    var marketDataDashboardSections: [MarketDataDashboardSection] {
        [.metrics, .trendChart, .metadata, .disclaimer]
    }

    func replacingSummary(headline: String?, description: String?, topNews: [MarketNewsSummary]) -> MarketTrendsSnapshot {
        MarketTrendsSnapshot(
            totalMarketCap: totalMarketCap,
            totalMarketCapChange24h: totalMarketCapChange24h,
            totalVolume24h: totalVolume24h,
            btcDominance: btcDominance,
            ethDominance: ethDominance,
            fearGreedIndex: fearGreedIndex,
            altcoinIndex: altcoinIndex,
            btcLongShortRatio: btcLongShortRatio,
            marketPoll: marketPoll,
            movers: movers,
            marketCapVolumeSeries: marketCapVolumeSeries,
            range: range,
            currency: currency,
            events: events,
            topNews: topNews,
            bitcoinHalvingCountdown: bitcoinHalvingCountdown,
            latestHeadline: headline,
            summaryDescription: description,
            eventsEmptyReason: eventsEmptyReason,
            unavailableReasons: unavailableReasons,
            dataProvider: dataProvider,
            fallbackUsed: fallbackUsed,
            asOf: asOf
        )
    }

    func replacingMarketTrendSeries(
        _ series: [MarketTrendPoint],
        range: String?,
        currency: String?,
        dataProvider: String?,
        asOf: Date?
    ) -> MarketTrendsSnapshot {
        MarketTrendsSnapshot(
            totalMarketCap: totalMarketCap ?? series.last?.marketCap,
            totalMarketCapChange24h: totalMarketCapChange24h,
            totalVolume24h: totalVolume24h ?? series.last?.volume,
            btcDominance: btcDominance ?? series.last?.btcDominance,
            ethDominance: ethDominance ?? series.last?.ethDominance,
            fearGreedIndex: fearGreedIndex,
            altcoinIndex: altcoinIndex,
            btcLongShortRatio: btcLongShortRatio,
            marketPoll: marketPoll,
            movers: movers,
            marketCapVolumeSeries: series,
            range: range,
            currency: currency,
            events: events,
            topNews: topNews,
            bitcoinHalvingCountdown: bitcoinHalvingCountdown,
            latestHeadline: latestHeadline,
            summaryDescription: summaryDescription,
            eventsEmptyReason: eventsEmptyReason,
            unavailableReasons: unavailableReasons,
            dataProvider: dataProvider,
            fallbackUsed: fallbackUsed,
            asOf: asOf
        )
    }
}

enum LatestTrendSection: Equatable {
    case headline
    case fearGreedMood
    case marketPoll
    case topMovers
    case eventInsights
    case seriesPlaceholder
}

enum MarketDataDashboardSection: Equatable {
    case metrics
    case trendChart
    case metadata
    case disclaimer
}

private extension Array where Element == Double {
    var average: Double {
        guard isEmpty == false else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

extension Array where Element == MarketTrendPoint {
    var hasRenderableMarketTrend: Bool {
        let metricCounts = [
            compactMap(\.marketCap).count,
            compactMap(\.volume).count,
            compactMap(\.btcDominance).count,
            compactMap(\.ethDominance).count
        ]
        return metricCounts.contains { $0 >= 3 }
    }
}
