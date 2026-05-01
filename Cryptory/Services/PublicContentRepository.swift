import Foundation

struct NewsSnapshot: Equatable {
    let items: [CryptoNewsItem]
    let meta: ResponseMeta
}

protocol PublicContentRepositoryProtocol {
    func fetchNews(category: String?, symbol: String?, cursor: String?, limit: Int) async throws -> NewsSnapshot
    func fetchCoinInfo(symbol: String) async throws -> CoinDetailInfo
    func fetchCoinAnalysis(symbol: String, timeframe: CoinAnalysisTimeframe) async throws -> CoinAnalysisSnapshot
    func fetchCoinCommunity(symbol: String, sort: String, filter: CoinCommunityFilter, cursor: String?, limit: Int) async throws -> CoinCommunitySnapshot
    func createCoinCommunityPost(symbol: String, content: String) async throws -> CoinCommunityPost
    func voteCoin(symbol: String, direction: String) async throws -> CoinVoteSnapshot
    func fetchMarketTrends() async throws -> MarketTrendsSnapshot
    func fetchMarketThemes() async throws -> [MarketThemeSnapshot]
}

final class LivePublicContentRepository: PublicContentRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchNews(category: String?, symbol: String?, cursor: String?, limit: Int) async throws -> NewsSnapshot {
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let category, category.isEmpty == false {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let symbol, symbol.isEmpty == false {
                queryItems.append(URLQueryItem(name: "symbol", value: Self.normalizedSymbol(symbol)))
        }
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let json = try await requestPublicJSON(
            endpoint: .news,
            queryItems: queryItems
        )
        let container = try PublicContentParser.splitPayload(json, endpoint: .news, decodeTarget: "NewsEnvelope")
        let array = PublicContentParser.unwrapArray(container.payload) ?? []
        let items = array.compactMap { ($0 as? JSONObject).flatMap(PublicContentParser.newsItem) }
        AppLogger.debug(.network, "[News] loaded category=\(category ?? "all") symbol=\(symbol.map(Self.normalizedSymbol) ?? "all") itemCount=\(items.count)")
        return NewsSnapshot(
            items: items,
            meta: container.meta
        )
    }

    func fetchCoinInfo(symbol: String) async throws -> CoinDetailInfo {
        let normalized = Self.normalizedSymbol(symbol)
        AppLogger.debug(.network, "[PublicContentAPI] symbol normalized raw=\(symbol) normalized=\(normalized)")
        let endpoint: PublicContentEndpoint = .coinInfo(normalized)
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            symbol: normalized
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CoinInfo")
        guard let dictionary = payload as? JSONObject else {
            logDecodeFailure(endpoint: endpoint, target: "CoinInfo", path: "data", error: "expected object")
            throw NetworkServiceError.parsingFailed("코인 정보 응답을 해석하지 못했어요.")
        }
        let info = PublicContentParser.coinInfo(dictionary: dictionary, fallbackSymbol: normalized)
        logDecodeSuccess(endpoint: endpoint, target: "CoinInfo", symbol: info.symbol)
        AppLogger.debug(.network, "[CoinInfo] loaded symbol=\(info.symbol) provider=\(info.dataProvider ?? "unknown") providerId=\(info.providerId ?? "nil") fallbackUsed=\(info.fallbackUsed) nullFieldCount=\(info.nullMarketFieldCount)")
        return info
    }

    func fetchCoinAnalysis(symbol: String, timeframe: CoinAnalysisTimeframe) async throws -> CoinAnalysisSnapshot {
        let normalized = Self.normalizedSymbol(symbol)
        AppLogger.debug(.network, "[PublicContentAPI] symbol normalized raw=\(symbol) normalized=\(normalized)")
        let endpoint: PublicContentEndpoint = .coinAnalysis(normalized)
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            queryItems: [URLQueryItem(name: "timeframe", value: timeframe.rawValue)],
            symbol: normalized
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CoinAnalysis")
        guard let dictionary = payload as? JSONObject else {
            logDecodeFailure(endpoint: endpoint, target: "CoinAnalysis", path: "data", error: "expected object")
            throw NetworkServiceError.parsingFailed("분석 응답을 해석하지 못했어요.")
        }
        let snapshot = PublicContentParser.analysis(dictionary: dictionary, fallbackSymbol: normalized, fallbackTimeframe: timeframe)
        logDecodeSuccess(endpoint: endpoint, target: "CoinAnalysis", symbol: snapshot.symbol)
        AppLogger.debug(.network, "[CoinAnalysis] loaded symbol=\(snapshot.symbol) timeframe=\(snapshot.timeframe.rawValue) status=\(snapshot.status ?? snapshot.summaryLabel.rawValue) fallbackUsed=\(snapshot.fallbackUsed)")
        return snapshot
    }

    func fetchCoinCommunity(
        symbol: String,
        sort: String,
        filter: CoinCommunityFilter,
        cursor: String?,
        limit: Int
    ) async throws -> CoinCommunitySnapshot {
        var queryItems = [
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "filter", value: filter.rawValue),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let normalized = Self.normalizedSymbol(symbol)
        AppLogger.debug(.network, "[PublicContentAPI] symbol normalized raw=\(symbol) normalized=\(normalized)")
        let endpoint: PublicContentEndpoint = .coinCommunity(normalized)
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            queryItems: queryItems,
            symbol: normalized
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CoinCommunity")
        let snapshot = PublicContentParser.communitySnapshot(payload: payload, fallbackSymbol: normalized)
        logDecodeSuccess(endpoint: endpoint, target: "CoinCommunity", symbol: normalized)
        AppLogger.debug(.network, "[Community] loaded symbol=\(normalized) itemCount=\(snapshot.posts.count) participantCount=\(snapshot.vote.participantCount)")
        return snapshot
    }

    func createCoinCommunityPost(symbol: String, content: String) async throws -> CoinCommunityPost {
        let normalized = Self.normalizedSymbol(symbol)
        AppLogger.debug(.network, "[PublicContentAPI] symbol normalized raw=\(symbol) normalized=\(normalized)")
        let endpoint: PublicContentEndpoint = .coinCommunity(normalized)
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            method: "POST",
            body: ["content": content],
            symbol: normalized
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CoinCommunityPost")
        guard let dictionary = payload as? JSONObject,
              let post = PublicContentParser.communityPost(dictionary: dictionary, fallbackSymbol: normalized) else {
            logDecodeFailure(endpoint: endpoint, target: "CoinCommunityPost", path: "data", error: "expected post object")
            throw NetworkServiceError.parsingFailed("커뮤니티 작성 응답을 해석하지 못했어요.")
        }
        logDecodeSuccess(endpoint: endpoint, target: "CoinCommunityPost", symbol: post.symbol)
        return post
    }

    func voteCoin(symbol: String, direction: String) async throws -> CoinVoteSnapshot {
        let normalized = Self.normalizedSymbol(symbol)
        AppLogger.debug(.network, "[PublicContentAPI] symbol normalized raw=\(symbol) normalized=\(normalized)")
        let endpoint: PublicContentEndpoint = .coinVotes(normalized)
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            method: "POST",
            body: ["direction": direction],
            symbol: normalized
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CoinVote")
        guard let dictionary = payload as? JSONObject else {
            logDecodeFailure(endpoint: endpoint, target: "CoinVote", path: "data", error: "expected object")
            throw NetworkServiceError.parsingFailed("투표 응답을 해석하지 못했어요.")
        }
        logDecodeSuccess(endpoint: endpoint, target: "CoinVote", symbol: normalized)
        return PublicContentParser.vote(dictionary: dictionary)
    }

    func fetchMarketTrends() async throws -> MarketTrendsSnapshot {
        let json = try await requestPublicJSON(
            endpoint: .marketTrends
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: .marketTrends, decodeTarget: "MarketTrends")
        guard let dictionary = payload as? JSONObject else {
            logDecodeFailure(endpoint: .marketTrends, target: "MarketTrends", path: "data", error: "expected object")
            throw NetworkServiceError.parsingFailed("시장 데이터 응답을 해석하지 못했어요.")
        }
        let snapshot = PublicContentParser.marketTrends(dictionary: dictionary)
        logDecodeSuccess(endpoint: .marketTrends, target: "MarketTrends", symbol: nil)
        AppLogger.debug(.network, "[MarketTrends] loaded fallbackUsed=\(snapshot.fallbackUsed) hasSeries=\(snapshot.marketCapVolumeSeries.isEmpty == false)")
        return snapshot
    }

    func fetchMarketThemes() async throws -> [MarketThemeSnapshot] {
        let json = try await requestPublicJSON(endpoint: .marketThemes)
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: .marketThemes, decodeTarget: "MarketThemes")
        let items = (PublicContentParser.unwrapArray(payload) ?? [])
            .enumerated()
            .compactMap { index, item -> MarketThemeSnapshot? in
                guard let dictionary = item as? JSONObject else { return nil }
                return PublicContentParser.marketTheme(dictionary: dictionary, index: index)
            }
        let fallbackUsed = (payload as? JSONObject)?.bool(["fallbackUsed", "fallback_used"]) ?? false
        logDecodeSuccess(endpoint: .marketThemes, target: "MarketThemes", symbol: nil)
        AppLogger.debug(.network, "[MarketThemes] loaded itemCount=\(items.count) fallbackUsed=\(fallbackUsed)")
        return items
    }

    private func requestPublicJSON(
        endpoint: PublicContentEndpoint,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: JSONObject? = nil,
        symbol: String? = nil
    ) async throws -> Any {
        do {
            return try await client.requestPublicContentJSONWithDebugLog(
                path: endpoint.canonicalRootPath,
                method: method,
                queryItems: queryItems,
                body: body,
                endpoint: endpoint.name,
                canonical: true,
                decodeTarget: endpoint.decodeTarget,
                normalizedSymbol: symbol
            )
        } catch let error as NetworkServiceError {
            guard error.isNotFound else {
                throw error
            }
            AppLogger.debug(.network, "[PublicContentAPI] fallback reason=root404 alias=\(endpoint.fallbackAliasPath)")
            return try await client.requestPublicContentJSONWithDebugLog(
                path: endpoint.fallbackAliasPath,
                method: method,
                queryItems: queryItems,
                body: body,
                endpoint: endpoint.name,
                canonical: false,
                decodeTarget: endpoint.decodeTarget,
                normalizedSymbol: symbol
            )
        }
    }

    private func logDecodeSuccess(endpoint: PublicContentEndpoint, target: String, symbol: String?) {
        AppLogger.debug(.network, "[PublicContentAPI] decode success endpoint=\(endpoint.name)\(symbol.map { " symbol=\($0)" } ?? "") target=\(target)")
    }

    private func logDecodeFailure(endpoint: PublicContentEndpoint, target: String, path: String, error: String) {
        AppLogger.debug(.network, "[PublicContentAPI] decode failed endpoint=\(endpoint.name) target=\(target) path=\(path) error=\(error)")
    }

    static func normalizedSymbol(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("KRW-") {
            return String(trimmed.dropFirst(4)).uppercased()
        }
        if let base = trimmed.split(separator: "/").first, trimmed.contains("/") {
            return String(base).uppercased()
        }
        return trimmed.uppercased()
    }

    private static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    fileprivate enum PublicContentEndpoint {
        case news
        case newsDetail(String)
        case coinInfo(String)
        case coinAnalysis(String)
        case coinCommunity(String)
        case coinVotes(String)
        case marketTrends
        case marketThemes

        var name: String {
            switch self {
            case .news: return "news"
            case .newsDetail: return "newsDetail"
            case .coinInfo: return "coinInfo"
            case .coinAnalysis: return "coinAnalysis"
            case .coinCommunity: return "coinCommunity"
            case .coinVotes: return "coinVotes"
            case .marketTrends: return "marketTrends"
            case .marketThemes: return "marketThemes"
            }
        }

        var decodeTarget: String {
            switch self {
            case .news, .newsDetail: return "NewsEnvelope"
            case .coinInfo: return "CoinInfoEnvelope"
            case .coinAnalysis: return "CoinAnalysisEnvelope"
            case .coinCommunity: return "CoinCommunityEnvelope"
            case .coinVotes: return "CoinVoteEnvelope"
            case .marketTrends: return "MarketTrendsEnvelope"
            case .marketThemes: return "MarketThemesEnvelope"
            }
        }

        var canonicalRootPath: String { path(prefix: "") }
        var fallbackAliasPath: String { path(prefix: "/api/v1") }

        private func path(prefix: String) -> String {
            switch self {
            case .news:
                return "\(prefix)/news"
            case .newsDetail(let id):
                return "\(prefix)/news/\(LivePublicContentRepository.pathComponent(id))"
            case .coinInfo(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/info"
            case .coinAnalysis(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/analysis"
            case .coinCommunity(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/community"
            case .coinVotes(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/votes"
            case .marketTrends:
                return "\(prefix)/market/trends"
            case .marketThemes:
                return "\(prefix)/market/themes"
            }
        }
    }
}

private enum PublicContentParser {
    static func splitPayload(_ json: Any, endpoint: LivePublicContentRepository.PublicContentEndpoint, decodeTarget: String) throws -> (payload: Any, meta: ResponseMeta) {
        guard let dictionary = json as? JSONObject else {
            return (json, .empty)
        }
        let payload = try unwrapPayload(dictionary, endpoint: endpoint, decodeTarget: decodeTarget)
        return (
            payload,
            ResponseMeta(
                fetchedAt: parseDate(dictionary["asOf"] ?? dictionary["fetchedAt"] ?? dictionary["timestamp"]),
                isStale: dictionary.bool(["stale", "isStale"]) ?? false,
                warningMessage: dictionary.string(["warningMessage", "message"]),
                partialFailureMessage: dictionary.string(["partialFailureMessage", "partialError"])
            )
        )
    }

    static func unwrapPayload(_ json: Any, endpoint: LivePublicContentRepository.PublicContentEndpoint, decodeTarget: String) throws -> Any {
        guard let dictionary = json as? JSONObject else { return json }
        if dictionary.bool(["success"]) == false {
            let errorDictionary = dictionary["error"] as? JSONObject
            let message = errorDictionary?.string(["message", "detail", "description"])
                ?? dictionary.string(["message", "error", "detail"])
                ?? "정보성 API 응답이 실패로 반환됐습니다."
            let code = errorDictionary?.string(["code", "type"])
                ?? dictionary.string(["code", "errorCode", "error_code"])
            let details = errorDictionary?["details"] ?? dictionary["details"]
            AppLogger.debug(
                .network,
                "[PublicContentAPI] decode failed endpoint=\(endpoint.name) target=\(decodeTarget) path=success error=false code=\(code ?? "nil") details=\(details.map(String.init(describing:)) ?? "nil")"
            )
            throw NetworkServiceError.parsingFailed(code.map { "\(message) (\($0))" } ?? message)
        }
        for key in ["data", "result", "payload"] {
            if let value = dictionary[key] {
                if value is NSNull {
                    return [:]
                }
                return value
            }
        }
        return json
    }

    static func unwrapArray(_ value: Any?) -> [Any]? {
        if let array = value as? [Any] {
            return array
        }
        if let dictionary = value as? JSONObject {
            for key in ["items", "posts", "news", "rows", "results", "list"] {
                if let array = dictionary[key] as? [Any] {
                    return array
                }
            }
        }
        return nil
    }

    static func newsItem(dictionary: JSONObject) -> CryptoNewsItem? {
        guard let title = dictionary.string(["title"]) else { return nil }
        let id = dictionary.string(["id", "newsId", "news_id"]) ?? UUID().uuidString
        return CryptoNewsItem(
            id: id,
            title: title,
            summary: dictionary.string(["summary", "description", "excerpt"]) ?? "",
            body: dictionary.string(["body", "content"]),
            source: dictionary.string(["source", "provider"]) ?? "Unknown",
            publishedAt: parseDate(dictionary["publishedAt"] ?? dictionary["published_at"] ?? dictionary["createdAt"] ?? dictionary["timestamp"]),
            relatedSymbols: dictionary.stringArray(["relatedSymbols", "related_symbols", "symbols", "tags"]).map { $0.uppercased() },
            originalURL: url(dictionary.string(["originalUrl", "originalURL", "url", "link"])),
            thumbnailURL: url(dictionary.string(["thumbnailUrl", "thumbnailURL", "imageUrl", "imageURL"]))
        )
    }

    static func coinInfo(dictionary: JSONObject, fallbackSymbol: String) -> CoinDetailInfo {
        let market = dictionary["market"] as? JSONObject ?? [:]
        let source = dictionary["source"] as? JSONObject ?? [:]
        var changes: [CoinPriceChangePeriod: Double] = [:]
        changes[.h24] = normalizePercent(market.double(["priceChangePercent24h", "price_change_percent_24h"]) ?? dictionary.double(["priceChangePercentage24h", "price_change_percentage_24h", "change24h"]))
        changes[.d7] = normalizePercent(dictionary.double(["priceChangePercentage7d", "price_change_percentage_7d", "change7d"]))
        changes[.d14] = normalizePercent(dictionary.double(["priceChangePercentage14d", "price_change_percentage_14d", "change14d"]))
        changes[.d30] = normalizePercent(dictionary.double(["priceChangePercentage30d", "price_change_percentage_30d", "change30d"]))
        changes[.d60] = normalizePercent(dictionary.double(["priceChangePercentage60d", "price_change_percentage_60d", "change60d"]))
        changes[.d200] = normalizePercent(dictionary.double(["priceChangePercentage200d", "price_change_percentage_200d", "change200d"]))
        changes[.y1] = normalizePercent(dictionary.double(["priceChangePercentage1y", "price_change_percentage_1y", "change1y"]))

        let resolvedSymbol = dictionary.string(["symbol"])?.uppercased() ?? fallbackSymbol.uppercased()
        return CoinDetailInfo(
            symbol: resolvedSymbol,
            displaySymbol: dictionary.string(["displaySymbol", "display_symbol"]) ?? "\(resolvedSymbol)/KRW",
            name: dictionary.string(["name", "coinName"]),
            logoURL: url(dictionary.string(["logoUrl", "logoURL", "image", "imageUrl", "iconUrl", "iconURL"])),
            provider: dictionary.string(["provider"]),
            providerId: dictionary.string(["providerId", "provider_id"]),
            rank: market.int(["marketCapRank", "market_cap_rank"]) ?? dictionary.int(["rank", "marketCapRank", "market_cap_rank"]),
            marketCap: market.double(["marketCap", "market_cap"]) ?? dictionary.double(["marketCap", "market_cap"]),
            circulatingSupply: market.double(["circulatingSupply", "circulating_supply"]) ?? dictionary.double(["circulatingSupply", "circulating_supply"]),
            maxSupply: market.double(["maxSupply", "max_supply"]) ?? dictionary.double(["maxSupply", "max_supply"]),
            totalSupply: market.double(["totalSupply", "total_supply"]) ?? dictionary.double(["totalSupply", "total_supply"]),
            currentPrice: market.double(["price", "currentPrice", "current_price"]) ?? dictionary.double(["currentPrice", "current_price", "price"]),
            priceCurrency: market.string(["priceCurrency", "price_currency"]) ?? dictionary.string(["priceCurrency", "currency"]),
            high24h: market.double(["high24h", "high_24h"]) ?? dictionary.double(["high24h", "high_24h"]),
            low24h: market.double(["low24h", "low_24h"]) ?? dictionary.double(["low24h", "low_24h"]),
            allTimeHigh: market.double(["ath", "allTimeHigh", "all_time_high"]) ?? dictionary.double(["allTimeHigh", "ath", "all_time_high"]),
            allTimeLow: market.double(["atl", "allTimeLow", "all_time_low"]) ?? dictionary.double(["allTimeLow", "atl", "all_time_low"]),
            volume24h: market.double(["volume24h", "totalVolume", "total_volume", "tradeVolume24h"]) ?? dictionary.double(["volume24h", "totalVolume", "total_volume", "tradeVolume24h"]),
            tradeValue24h: market.double(["tradeValue24h", "trade_value_24h"]) ?? dictionary.double(["tradeValue24h", "trade_value_24h"]),
            marketCapChange24h: dictionary.double(["marketCapChange24h", "market_cap_change_24h"]),
            marketAsOf: parseDate(market["asOf"] ?? market["as_of"] ?? dictionary["asOf"] ?? dictionary["as_of"]),
            priceChangePercentages: changes,
            description: dictionary.string(["description", "descriptionEn", "description_en"]),
            officialURL: url(dictionary.string(["homepageUrl", "homepage_url", "officialUrl", "officialURL", "homepage", "website"])),
            explorerURL: url(dictionary.string(["explorerUrl", "explorer_url", "communityUrl", "communityURL"])),
            dataProvider: source.string(["market", "metadata"]) ?? dictionary.string(["dataProvider", "provider"]) ?? "CoinGecko",
            metadataSource: source.string(["metadata"]),
            marketSource: source.string(["market"]),
            fallbackUsed: source.bool(["fallbackUsed", "fallback_used"]) ?? dictionary.bool(["fallbackUsed", "fallback_used"]) ?? false
        )
    }

    static func analysis(
        dictionary: JSONObject,
        fallbackSymbol: String,
        fallbackTimeframe: CoinAnalysisTimeframe
    ) -> CoinAnalysisSnapshot {
        let timeframe = CoinAnalysisTimeframe(rawValue: dictionary.string(["timeframe"]) ?? "") ?? fallbackTimeframe
        let summary = dictionary["summary"] as? JSONObject ?? [:]
        let source = dictionary["source"] as? JSONObject ?? [:]
        let indicatorsArray = unwrapArray(dictionary["indicators"]) ?? []
        var indicators = indicatorsArray.enumerated().compactMap { index, item -> CoinAnalysisIndicator? in
            guard let item = item as? JSONObject else { return nil }
            let label = CoinAnalysisSummaryLabel(serverValue: item.string(["state", "label", "signal", "summary"]))
            return CoinAnalysisIndicator(
                id: item.string(["key", "id"]) ?? "indicator-\(index)",
                name: item.string(["label", "name", "title"]) ?? "지표 \(index + 1)",
                valueText: item.string(["valueText", "value_text", "value"]) ?? "-",
                description: item.string(["description"]),
                label: label
            )
        }
        if indicators.isEmpty {
            indicators = [
                CoinAnalysisIndicator(
                    id: "insufficient-data",
                    name: "데이터 부족",
                    valueText: "데이터 부족",
                    description: "분석에 필요한 시장 데이터가 아직 충분하지 않습니다.",
                    label: .neutral
                )
            ]
        }
        let bearish = summary.int(["bearishCount", "bearish_count"]) ?? dictionary.int(["bearishCount", "bearish_count"]) ?? indicators.filter { $0.label == .bearish || $0.label == .strongBearish }.count
        let bullish = summary.int(["bullishCount", "bullish_count"]) ?? dictionary.int(["bullishCount", "bullish_count"]) ?? indicators.filter { $0.label == .bullish || $0.label == .strongBullish }.count
        let neutral = summary.int(["neutralCount", "neutral_count"]) ?? dictionary.int(["neutralCount", "neutral_count"]) ?? max(indicators.count - bearish - bullish, 0)
        return CoinAnalysisSnapshot(
            symbol: dictionary.string(["symbol"])?.uppercased() ?? fallbackSymbol.uppercased(),
            timeframe: timeframe,
            status: summary.string(["status"]),
            summaryLabel: CoinAnalysisSummaryLabel(serverValue: summary.string(["label", "status"]) ?? dictionary.string(["summaryLabel", "summary_label", "label"])),
            bearishCount: bearish,
            neutralCount: neutral,
            bullishCount: bullish,
            score: summary.double(["score"]) ?? dictionary.double(["score"]) ?? 0,
            indicators: indicators,
            disclaimer: dictionary.string(["disclaimer"]) ?? CoinAnalysisSnapshot.defaultDisclaimer,
            dataProvider: source.string(["type"]) ?? dictionary.string(["dataProvider", "provider"]),
            fallbackUsed: source.bool(["fallbackUsed", "fallback_used"]) ?? dictionary.bool(["fallbackUsed", "fallback_used"]) ?? false,
            asOf: parseDate(dictionary["asOf"] ?? dictionary["as_of"])
        )
    }

    static func communitySnapshot(payload: Any, fallbackSymbol: String) -> CoinCommunitySnapshot {
        if let dictionary = payload as? JSONObject {
            let posts = (unwrapArray(dictionary["items"] ?? dictionary["posts"]) ?? [])
                .compactMap { ($0 as? JSONObject).flatMap { communityPost(dictionary: $0, fallbackSymbol: fallbackSymbol) } }
            let voteDictionary = (dictionary["vote"] as? JSONObject) ?? (dictionary["marketPoll"] as? JSONObject) ?? dictionary
            return CoinCommunitySnapshot(posts: posts, vote: vote(dictionary: voteDictionary), nextCursor: dictionary.string(["nextCursor", "next_cursor"]))
        }
        let posts = (unwrapArray(payload) ?? [])
            .compactMap { ($0 as? JSONObject).flatMap { communityPost(dictionary: $0, fallbackSymbol: fallbackSymbol) } }
        return CoinCommunitySnapshot(posts: posts, vote: CoinVoteSnapshot(bullishCount: 0, bearishCount: 0, totalCount: 0, myVote: nil))
    }

    static func communityPost(dictionary: JSONObject, fallbackSymbol: String) -> CoinCommunityPost? {
        guard let content = dictionary.string(["content", "body", "message"]) else { return nil }
        return CoinCommunityPost(
            id: dictionary.string(["id", "postId", "post_id"]) ?? UUID().uuidString,
            authorName: dictionary.string(["authorName", "author_name", "nickname"]) ?? "익명",
            avatarURL: url(dictionary.string(["avatarUrl", "avatarURL"])),
            createdAt: parseDate(dictionary["createdAt"] ?? dictionary["created_at"] ?? dictionary["timestamp"]),
            content: content,
            symbol: dictionary.string(["symbol"])?.uppercased() ?? fallbackSymbol.uppercased(),
            tags: dictionary.stringArray(["tags"]).map { $0.replacingOccurrences(of: "거래 인증", with: "활동 인증") },
            likeCount: dictionary.int(["likeCount", "like_count", "likes"]) ?? 0,
            commentCount: dictionary.int(["commentCount", "comment_count", "comments"]) ?? 0,
            isFollowing: dictionary.bool(["isFollowing", "is_following"]) ?? false,
            badge: dictionary.string(["badge"])?.replacingOccurrences(of: "거래 인증", with: "활동 인증")
        )
    }

    static func vote(dictionary: JSONObject) -> CoinVoteSnapshot {
        let bullish = dictionary.int(["bullishCount", "bullish_count", "upCount"]) ?? 0
        let bearish = dictionary.int(["bearishCount", "bearish_count", "downCount"]) ?? 0
        return CoinVoteSnapshot(
            bullishCount: bullish,
            bearishCount: bearish,
            totalCount: dictionary.int(["participantCount", "participant_count", "totalCount", "total_count", "participants"]) ?? bullish + bearish,
            myVote: dictionary.string(["myVote", "my_vote"])
        )
    }

    static func marketTrends(dictionary: JSONObject) -> MarketTrendsSnapshot {
        let summary = dictionary["summary"] as? JSONObject ?? [:]
        let seriesDictionary = dictionary["series"] as? JSONObject ?? [:]
        let source = dictionary["source"] as? JSONObject ?? [:]
        let moversDictionary = dictionary["movers"] as? JSONObject ?? [:]
        let series = marketTrendSeries(dictionary: dictionary, seriesDictionary: seriesDictionary)
        let halvingDictionary = dictionary["bitcoinHalvingCountdown"] as? JSONObject
        let pollDictionary = dictionary["marketPoll"] as? JSONObject
        return MarketTrendsSnapshot(
            totalMarketCap: summary.double(["totalMarketCap", "total_market_cap"]) ?? dictionary.double(["totalMarketCap", "total_market_cap"]),
            totalMarketCapChange24h: normalizePercent(dictionary.double(["totalMarketCapChange24h", "total_market_cap_change_24h"])),
            totalVolume24h: summary.double(["volume24h", "totalVolume24h", "total_volume_24h", "totalVolume", "total_volume"]) ?? dictionary.double(["totalVolume24h", "total_volume_24h", "volume24h", "totalVolume", "total_volume"]),
            btcDominance: normalizePercent(summary.double(["btcDominance", "btc_dominance"]) ?? dictionary.double(["btcDominance", "btc_dominance"])),
            ethDominance: normalizePercent(summary.double(["ethDominance", "eth_dominance"]) ?? dictionary.double(["ethDominance", "eth_dominance"])),
            fearGreedIndex: summary.int(["fearGreedIndex", "fear_greed_index"]) ?? dictionary.int(["fearGreedIndex", "fear_greed_index"]),
            altcoinIndex: summary.int(["altcoinIndex", "altcoin_index"]) ?? dictionary.int(["altcoinIndex", "altcoin_index"]),
            btcLongShortRatio: normalizePercent(dictionary.double(["btcLongShortRatio", "btc_long_short_ratio"])),
            marketPoll: pollDictionary.map { MarketPollSnapshot(bullishCount: $0.int(["bullishCount"]) ?? 0, bearishCount: $0.int(["bearishCount"]) ?? 0, totalCount: $0.int(["totalCount"]) ?? 0) },
            movers: MarketMoversSnapshot(
                topGainers: marketMovers(moversDictionary["topGainers"] ?? moversDictionary["top_gainers"]),
                topLosers: marketMovers(moversDictionary["topLosers"] ?? moversDictionary["top_losers"]),
                topVolume: marketMovers(moversDictionary["topVolume"] ?? moversDictionary["top_volume"])
            ),
            marketCapVolumeSeries: series,
            bitcoinHalvingCountdown: halvingDictionary.map {
                BitcoinHalvingCountdown(
                    targetDate: parseDate($0["targetDate"]),
                    days: $0.int(["days"]),
                    hours: $0.int(["hours"]),
                    minutes: $0.int(["minutes"]),
                    seconds: $0.int(["seconds"])
                )
            },
            latestHeadline: dictionary.string(["latestHeadline", "headline"]),
            dataProvider: source.string(["primary"]) ?? dictionary.string(["dataProvider", "provider"]),
            fallbackUsed: source.bool(["fallbackUsed", "fallback_used"]) ?? dictionary.bool(["fallbackUsed", "fallback_used"]) ?? false,
            asOf: parseDate(dictionary["asOf"] ?? dictionary["as_of"])
        )
    }

    static func marketTheme(dictionary: JSONObject, index: Int) -> MarketThemeSnapshot? {
        guard let name = dictionary.string(["name", "title"]) else { return nil }
        return MarketThemeSnapshot(
            id: dictionary.string(["id", "key"]) ?? "theme-\(index)",
            name: name,
            summary: dictionary.string(["summary", "description"]),
            marketCap: dictionary.double(["marketCap", "market_cap"]),
            volume24h: dictionary.double(["volume24h", "volume_24h"]),
            changePercent24h: normalizePercent(dictionary.double(["changePercent24h", "change_percent_24h"]))
        )
    }

    private static func marketMovers(_ rawValue: Any?) -> [MarketMover] {
        (unwrapArray(rawValue) ?? []).enumerated().compactMap { index, item -> MarketMover? in
            guard let dictionary = item as? JSONObject,
                  let symbol = dictionary.string(["symbol"]) else {
                return nil
            }
            return MarketMover(
                id: dictionary.string(["id"]) ?? "\(symbol)-\(index)",
                symbol: symbol.uppercased(),
                name: dictionary.string(["name"]),
                price: dictionary.double(["price", "currentPrice", "current_price"]),
                changePercent24h: normalizePercent(dictionary.double(["changePercent24h", "change_percent_24h", "priceChangePercent24h", "price_change_percent_24h"])),
                volume24h: dictionary.double(["volume24h", "volume_24h", "tradeValue24h", "trade_value_24h"])
            )
        }
    }

    private static func marketTrendSeries(dictionary: JSONObject, seriesDictionary: JSONObject) -> [MarketTrendPoint] {
        let marketCapItems = unwrapArray(seriesDictionary["marketCap"] ?? seriesDictionary["market_cap"])
        let volumeItems = unwrapArray(seriesDictionary["volume"])
        if marketCapItems != nil || volumeItems != nil {
            let count = max(marketCapItems?.count ?? 0, volumeItems?.count ?? 0)
            guard count > 0 else { return [] }
            return (0..<count).compactMap { index in
                let marketCapItem = marketCapItems?.indices.contains(index) == true ? marketCapItems?[index] : nil
                let volumeItem = volumeItems?.indices.contains(index) == true ? volumeItems?[index] : nil
                let marketCapDictionary = marketCapItem as? JSONObject
                let volumeDictionary = volumeItem as? JSONObject
                let marketCap = numericSeriesValue(
                    marketCapItem,
                    keys: ["marketCap", "market_cap", "value", "y"]
                )
                let volume = numericSeriesValue(
                    volumeItem,
                    keys: ["volume", "tradeVolume", "trade_volume", "value", "y"]
                ) ?? marketCapDictionary?.double(["volume", "tradeVolume", "trade_volume"])
                guard marketCap != nil || volume != nil else { return nil }
                return MarketTrendPoint(
                    id: marketCapDictionary?.string(["id"]) ?? volumeDictionary?.string(["id"]) ?? "trend-\(index)",
                    date: parseDate(marketCapDictionary?["date"] ?? marketCapDictionary?["time"] ?? marketCapDictionary?["timestamp"] ?? volumeDictionary?["date"] ?? volumeDictionary?["time"] ?? volumeDictionary?["timestamp"]),
                    marketCap: marketCap,
                    volume: volume
                )
            }
        }

        return (unwrapArray(dictionary["marketCapVolumeSeries"] ?? dictionary["series"]) ?? [])
            .enumerated()
            .compactMap { index, item -> MarketTrendPoint? in
                guard let item = item as? JSONObject else { return nil }
                return MarketTrendPoint(
                    id: item.string(["id"]) ?? "trend-\(index)",
                    date: parseDate(item["date"] ?? item["time"] ?? item["timestamp"]),
                    marketCap: item.double(["marketCap", "market_cap"]),
                    volume: item.double(["volume", "tradeVolume", "trade_volume"])
                )
            }
    }

    private static func numericSeriesValue(_ rawValue: Any?, keys: [String]) -> Double? {
        if let number = rawValue as? NSNumber {
            return number.doubleValue
        }
        if let string = rawValue as? String {
            return Double(string.replacingOccurrences(of: ",", with: ""))
        }
        if let dictionary = rawValue as? JSONObject {
            return dictionary.double(keys)
        }
        return nil
    }

    private static func normalizePercent(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return abs(value) <= 1 ? value * 100 : value
    }

    private static func url(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }
        if value.contains("://") {
            return URL(string: value)
        }
        return URL(string: "https://\(value)")
    }

    private static func parseDate(_ rawValue: Any?) -> Date? {
        switch rawValue {
        case let number as NSNumber:
            let timestamp = number.doubleValue > 1_000_000_000_000 ? number.doubleValue / 1000 : number.doubleValue
            return Date(timeIntervalSince1970: timestamp)
        case let string as String:
            if let timestamp = Double(string) {
                let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp
                return Date(timeIntervalSince1970: seconds)
            }
            if let date = iso8601WithFraction.date(from: string) {
                return date
            }
            return iso8601.date(from: string)
        default:
            return nil
        }
    }

    private static let iso8601WithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ keys: [String]) -> String? {
        for key in keys {
            if let value = self[key] as? String, value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return value
            }
            if let value = self[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    func double(_ keys: [String]) -> Double? {
        for key in keys {
            if let value = self[key] as? Double {
                return value
            }
            if let value = self[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = self[key] as? String, let number = Double(value.replacingOccurrences(of: ",", with: "")) {
                return number
            }
        }
        return nil
    }

    func int(_ keys: [String]) -> Int? {
        for key in keys {
            if let value = self[key] as? Int {
                return value
            }
            if let value = self[key] as? NSNumber {
                return value.intValue
            }
            if let value = self[key] as? String, let number = Int(value) {
                return number
            }
        }
        return nil
    }

    func bool(_ keys: [String]) -> Bool? {
        for key in keys {
            if let value = self[key] as? Bool {
                return value
            }
            if let value = self[key] as? NSNumber {
                return value.boolValue
            }
            if let value = self[key] as? String {
                switch value.lowercased() {
                case "true", "1", "yes", "enabled", "active":
                    return true
                case "false", "0", "no", "disabled", "inactive":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }

    func stringArray(_ keys: [String]) -> [String] {
        for key in keys {
            if let array = self[key] as? [String] {
                return array
            }
            if let array = self[key] as? [Any] {
                return array.compactMap { item in
                    if let string = item as? String {
                        return string
                    }
                    if let number = item as? NSNumber {
                        return number.stringValue
                    }
                    return nil
                }
            }
        }
        return []
    }
}
