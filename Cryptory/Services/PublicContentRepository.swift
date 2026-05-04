import Foundation

struct NewsSnapshot: Equatable {
    let items: [CryptoNewsItem]
    let meta: ResponseMeta
}

struct CoinNewsRequestContext: Equatable {
    let market: String?
    let coinName: String?
    let providerId: String?
    let keywords: [String]

    init(market: String? = nil, coinName: String? = nil, providerId: String? = nil, keywords: [String] = []) {
        self.market = market?.trimmedNonEmpty
        self.coinName = coinName?.trimmedNonEmpty
        self.providerId = providerId?.trimmedNonEmpty
        self.keywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .removingDuplicates()
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}

protocol PublicContentRepositoryProtocol {
    func fetchNews(category: String?, symbol: String?, date: Date?, sort: String, cursor: String?, limit: Int) async throws -> NewsSnapshot
    func fetchCoinNews(symbol: String, context: CoinNewsRequestContext?, date: Date?, sort: String, cursor: String?, limit: Int) async throws -> NewsSnapshot
    func fetchCoinInfo(symbol: String) async throws -> CoinDetailInfo
    func fetchCoinAnalysis(symbol: String, timeframe: CoinAnalysisTimeframe) async throws -> CoinAnalysisSnapshot
    func fetchCoinCommunity(symbol: String, sort: String, filter: CoinCommunityFilter, cursor: String?, limit: Int) async throws -> CoinCommunitySnapshot
    func createCoinCommunityPost(symbol: String, content: String, session: AuthSession) async throws -> CoinCommunityMutationResult
    func setCoinCommunityLike(symbol: String, itemId: String, isLiked: Bool, session: AuthSession) async throws -> CoinCommunityLikeResult
    func fetchCoinCommunityComments(symbol: String, itemId: String, sort: String, session: AuthSession?) async throws -> CoinCommunityCommentsSnapshot
    func createCoinCommunityComment(symbol: String, itemId: String, content: String, session: AuthSession) async throws -> CoinCommunityCommentsSnapshot
    func setUserFollow(userId: String, isFollowing: Bool, session: AuthSession) async throws -> UserFollowResult
    func fetchUserRelationship(userId: String, session: AuthSession) async throws -> UserRelationship
    func fetchFollowing(userId: String?, session: AuthSession) async throws -> UserListSnapshot
    func fetchFollowers(userId: String, session: AuthSession) async throws -> UserListSnapshot
    func reportCommunityTarget(targetType: CommunityReportTargetType, targetId: String, reason: CommunityReportReason, description: String?, session: AuthSession) async throws -> CommunityReportResult
    func blockUser(userId: String, session: AuthSession) async throws -> BlockedUser
    func unblockUser(userId: String, session: AuthSession) async throws
    func fetchBlockedUsers(session: AuthSession) async throws -> [BlockedUser]
    func voteCoin(symbol: String, direction: String, session: AuthSession) async throws -> CoinVoteSnapshot
    func voteMarketSentiment(direction: String, session: AuthSession) async throws -> MarketPollSnapshot
    func fetchMarketTrends(range: String, interval: String, currency: String) async throws -> MarketTrendsSnapshot
    func fetchMarketThemes() async throws -> [MarketThemeSnapshot]
}

final class LivePublicContentRepository: PublicContentRepositoryProtocol {
    private let client: APIClient
    private let translationUseCase: TranslationUseCase

    init(client: APIClient = APIClient(), translationUseCase: TranslationUseCase? = nil) {
        self.client = client
        self.translationUseCase = translationUseCase ?? TranslationUseCase()
    }

    func fetchNews(category: String?, symbol: String?, date: Date?, sort: String = "latest", cursor: String?, limit: Int) async throws -> NewsSnapshot {
        let normalizedSort = Self.normalizedSort(sort)
        let requestDate = date.map(Self.apiDateString) ?? "nil"
        AppLogger.debug(.network, "[NewsAPI] request tab=main date=\(requestDate) sort=\(normalizedSort)")
        AppLogger.debug(.network, "[NewsAPI] request date=\(requestDate) symbol=\(symbol.map(Self.normalizedSymbol) ?? "all") sort=\(normalizedSort) endpoint=/news cursor=\(cursor ?? "nil") limit=\(limit)")
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "sort", value: normalizedSort),
            URLQueryItem(name: "orderBy", value: "publishedAt"),
            URLQueryItem(name: "direction", value: normalizedSort == "oldest" ? "asc" : "desc")
        ]
        if let category, category.isEmpty == false {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let symbol, symbol.isEmpty == false {
                queryItems.append(URLQueryItem(name: "symbol", value: Self.normalizedSymbol(symbol)))
        }
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let date {
            queryItems.append(URLQueryItem(name: "date", value: Self.apiDateString(date)))
        }

        let json = try await requestPublicJSON(
            endpoint: .news,
            queryItems: queryItems
        )
        let container = try PublicContentParser.splitPayload(json, endpoint: .news, decodeTarget: "NewsEnvelope")
        let array = PublicContentParser.unwrapArray(container.payload) ?? []
        let items = array.compactMap { ($0 as? JSONObject).flatMap(PublicContentParser.newsItem) }
        let translatedItems = await translatedNewsItemsIfNeeded(Self.sortedNewsItems(items, sort: normalizedSort), context: "market_news", symbol: symbol.map(Self.normalizedSymbol))
        let externalCount = translatedItems.filter { ($0.provider ?? $0.source).lowercased().contains("cryptory") == false }.count
        let fallbackCount = translatedItems.count - externalCount
        let providerSummary = Dictionary(grouping: translatedItems, by: { $0.provider ?? $0.source })
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
        AppLogger.debug(.network, "[News] loaded category=\(category ?? "all") symbol=\(symbol.map(Self.normalizedSymbol) ?? "all") itemCount=\(items.count)")
        AppLogger.debug(.network, "[MarketNewsResponse] status=decoded itemCount=\(translatedItems.count) provider=\(providerSummary.isEmpty ? "none" : providerSummary) externalCount=\(externalCount) fallbackCount=\(fallbackCount)")
        let emptyReason = translatedItems.isEmpty ? Self.newsEmptyReason(meta: container.meta, itemCount: items.count, filteredCount: translatedItems.count, isCoinScoped: false) : "none"
        AppLogger.debug(.network, "[NewsAPI] response date=\(requestDate) count=\(translatedItems.count) source=\(providerSummary.isEmpty ? container.meta.source ?? "none" : providerSummary) reason=\(emptyReason)")
        AppLogger.debug(.network, "[NewsAPI] response count=\(translatedItems.count) source=\(providerSummary.isEmpty ? container.meta.source ?? "none" : providerSummary) cacheHit=\(Self.cacheHitLogValue(container.meta)) reason=\(emptyReason)")
        if translatedItems.isEmpty {
            AppLogger.debug(.network, "WARN [NewsAPI] empty reason=\(emptyReason) providerStatus=\(container.meta.providerStatus ?? "unknown")")
        }
        AppLogger.debug(.network, "[MarketNewsRender] itemCount=\(translatedItems.count) hasImages=\(translatedItems.contains { $0.thumbnailURL != nil }) translatedCount=\(translatedItems.filter { $0.renderLanguage == "ko" }.count) providerSummary=\(providerSummary)")
        if translatedItems.count <= 3 && fallbackCount == translatedItems.count {
            AppLogger.debug(.network, "[NewsProviderState] provider=cryptory_research configured=false externalAvailable=false fallbackUsed=true reason=fallback_only_or_provider_empty")
        }
        return NewsSnapshot(
            items: translatedItems,
            meta: container.meta
        )
    }

    func fetchCoinNews(symbol: String, context: CoinNewsRequestContext? = nil, date: Date?, sort: String = "latest", cursor: String?, limit: Int) async throws -> NewsSnapshot {
        let normalized = Self.normalizedSymbol(symbol)
        let normalizedSort = Self.normalizedSort(sort)
        let requestDate = date.map(Self.apiDateString) ?? "nil"
        let endpoint: PublicContentEndpoint = .coinNews(normalized)
        var queryItems = [
            URLQueryItem(name: "symbol", value: normalized),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "sort", value: normalizedSort),
            URLQueryItem(name: "orderBy", value: "publishedAt"),
            URLQueryItem(name: "direction", value: normalizedSort == "oldest" ? "asc" : "desc")
        ]
        if let market = context?.market {
            queryItems.append(URLQueryItem(name: "market", value: market))
        }
        if let coinName = context?.coinName {
            queryItems.append(URLQueryItem(name: "coinName", value: coinName))
        }
        if let providerId = context?.providerId {
            queryItems.append(URLQueryItem(name: "providerId", value: providerId))
        }
        if let keywords = context?.keywords, keywords.isEmpty == false {
            queryItems.append(URLQueryItem(name: "keywords", value: keywords.joined(separator: ",")))
        }
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let date {
            queryItems.append(URLQueryItem(name: "date", value: Self.apiDateString(date)))
        }
        AppLogger.debug(.network, "[CoinNewsAPI] symbol=\(normalized) path=\(endpoint.canonicalRootPath) status=dispatch")
        AppLogger.debug(.network, "DEBUG [CoinNews] request symbol=\(normalized) coinName=\(context?.coinName ?? "nil") providerId=\(context?.providerId ?? "nil") date=\(requestDate) sort=\(normalizedSort)")
        AppLogger.debug(.network, "[CoinNewsRequest] symbol=\(normalized) endpoint=\(endpoint.canonicalRootPath) date=\(requestDate) sort=\(normalizedSort) market=\(context?.market ?? "nil") keywords=\(context?.keywords.joined(separator: "|") ?? "nil")")
        do {
            let json = try await requestPublicJSON(
                endpoint: endpoint,
                queryItems: queryItems,
                symbol: normalized
            )
            let container = try PublicContentParser.splitPayload(json, endpoint: endpoint, decodeTarget: "CoinNewsEnvelope")
            let dictionary = container.payload as? JSONObject
            let payloadSymbol = dictionary?.string(["symbol"])?.uppercased() ?? normalized
            let scope = dictionary?.string(["scope"]) ?? "coin"
            let array = PublicContentParser.unwrapArray(container.payload) ?? []
            let items = array.compactMap { ($0 as? JSONObject).flatMap(PublicContentParser.newsItem) }
            let translatedItems = await translatedNewsItemsIfNeeded(Self.sortedNewsItems(items, sort: normalizedSort), context: "coin_news", symbol: normalized)
            AppLogger.debug(.network, "[CoinNewsDecode] itemCount=\(items.count) scope=\(scope) symbol=\(payloadSymbol)")
            let providerSummary = Dictionary(grouping: translatedItems, by: { $0.provider ?? $0.source })
                .map { "\($0.key):\($0.value.count)" }
                .sorted()
                .joined(separator: ",")
            let translatedCount = translatedItems.filter { $0.renderLanguage == "ko" }.count
            let emptyReason = translatedItems.isEmpty ? Self.newsEmptyReason(meta: container.meta, itemCount: items.count, filteredCount: translatedItems.count, isCoinScoped: true) : "none"
            AppLogger.debug(.network, "[CoinNewsResponse] symbol=\(normalized) status=decoded itemCount=\(translatedItems.count) provider=\(providerSummary.isEmpty ? "none" : providerSummary) updatedAt=\(container.meta.fetchedAt.map(String.init(describing:)) ?? "nil")")
            AppLogger.debug(.network, "DEBUG [CoinNews] response count=\(translatedItems.count) filtered=\(translatedItems.count) source=\(providerSummary.isEmpty ? container.meta.source ?? "unknown" : providerSummary) cacheHit=\(Self.cacheHitLogValue(container.meta)) reason=\(emptyReason)")
            AppLogger.debug(.network, "[CoinNewsFilter] symbol=\(normalized) selectedDate=\(requestDate) serverItemCount=\(items.count) localFilteredCount=\(translatedItems.count) reason=server_scope_trusted provider=\(providerSummary.isEmpty ? "unknown" : providerSummary)")
            AppLogger.debug(.network, "[CoinNewsRender] symbol=\(normalized) itemCount=\(translatedItems.count) translatedCount=\(translatedCount) fallbackCount=\(translatedItems.count - translatedCount)")
            if translatedItems.isEmpty {
                AppLogger.debug(.network, "WARN [CoinNews] empty reason=\(emptyReason) providerStatus=\(container.meta.providerStatus ?? "unknown")")
                AppLogger.debug(.network, "[CoinNewsEmpty] symbol=\(normalized) selectedDate=\(requestDate) responseItemCount=\(items.count) filteredItemCount=\(translatedItems.count) emptyReason=\(emptyReason) provider=\(providerSummary.isEmpty ? "unknown" : providerSummary) sourceStatus=decoded")
            }
            return NewsSnapshot(items: translatedItems, meta: container.meta)
        } catch let error as NetworkServiceError where error.isNotFound {
            AppLogger.debug(.network, "[CoinNewsAPI] symbol=\(normalized) path=\(endpoint.canonicalRootPath) status=404 fallback=marketNewsLocalFilter")
            AppLogger.debug(.network, "[APIFallback] feature=coinNews primaryEndpoint=\(endpoint.canonicalRootPath) fallbackEndpoint=/news reason=404")
            let marketSnapshot = try await fetchNews(category: nil, symbol: nil, date: date, sort: normalizedSort, cursor: cursor, limit: limit)
            let filteredItems = marketSnapshot.items.filter { item in
                item.relatedSymbols.map(Self.normalizedSymbol).contains(normalized)
                    || item.tags.map(Self.normalizedSymbol).contains(normalized)
                    || context?.keywords.contains(where: { keyword in
                        let haystack = "\(item.originalTitle) \(item.originalSummary ?? "") \(item.title) \(item.summary)".localizedLowercase
                        return haystack.contains(keyword.localizedLowercase)
                    }) == true
            }
            AppLogger.debug(.network, "[CoinNewsDecode] itemCount=\(filteredItems.count) scope=localFilter symbol=\(normalized)")
            let sorted = Self.sortedNewsItems(filteredItems, sort: normalizedSort)
            let emptyReason = sorted.isEmpty ? Self.newsEmptyReason(meta: marketSnapshot.meta, itemCount: marketSnapshot.items.count, filteredCount: sorted.count, isCoinScoped: true) : "none"
            AppLogger.debug(.network, "DEBUG [CoinNews] response count=\(marketSnapshot.items.count) filtered=\(sorted.count) source=\(marketSnapshot.meta.source ?? "marketNewsLocalFilter") cacheHit=\(Self.cacheHitLogValue(marketSnapshot.meta)) reason=\(emptyReason)")
            if sorted.isEmpty {
                AppLogger.debug(.network, "WARN [CoinNews] empty reason=\(emptyReason) providerStatus=\(marketSnapshot.meta.providerStatus ?? "unknown")")
            }
            AppLogger.debug(.network, "[CoinNewsFilter] symbol=\(normalized) selectedDate=\(requestDate) serverItemCount=\(marketSnapshot.items.count) localFilteredCount=\(sorted.count) reason=primary_404")
            return NewsSnapshot(items: sorted, meta: marketSnapshot.meta)
        }
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
        var info = PublicContentParser.coinInfo(dictionary: dictionary, fallbackSymbol: normalized)
        if info.descriptionRenderLanguage == "en",
           let description = info.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           description.isEmpty == false {
            AppLogger.debug(.network, "[CoinInfoDescription] symbol=\(normalized) hasPlainTextKo=false hasKo=false hasTranslatedDescription=false hasEn=true selectedSource=en")
            AppLogger.debug(.network, "[CoinDescriptionTranslation] symbol=\(normalized) source=english usedServerKo=false usedTranslateEndpoint=true fallbackUsed=false status=dispatch")
            let translated = await translationUseCase.translateOne(
                id: "coin_\(normalized)_description",
                text: description,
                sourceLanguage: "en",
                targetLanguage: "ko",
                context: "coin_description",
                symbol: normalized
            )
            if let translatedText = translated.translatedText?.trimmedNonEmpty {
                info = info.replacingDescription(translatedText, language: "ko", notice: nil, translationState: translated.state)
                AppLogger.debug(.network, "[CoinDescriptionTranslation] symbol=\(normalized) source=translateEndpoint usedServerKo=false usedTranslateEndpoint=true fallbackUsed=false status=success")
            } else {
                info = info.replacingDescription(description, language: "en", notice: "번역 실패 · 원문 표시 중", translationState: .failed)
                AppLogger.debug(.network, "[CoinDescriptionTranslation] symbol=\(normalized) source=english usedServerKo=false usedTranslateEndpoint=true fallbackUsed=true status=fallback_original")
            }
        } else {
            AppLogger.debug(.network, "[CoinDescriptionTranslation] symbol=\(normalized) source=\(info.descriptionRenderLanguage) usedServerKo=\(info.descriptionRenderLanguage == "ko") usedTranslateEndpoint=false fallbackUsed=\(info.descriptionFallbackNotice != nil) status=resolved")
        }
        logDecodeSuccess(endpoint: endpoint, target: "CoinInfo", symbol: info.symbol)
        AppLogger.debug(.network, "[CoinInfo] symbol=\(info.symbol) source=\(info.dataProvider ?? "unknown") hasDescriptionKo=\(info.descriptionRenderLanguage == "ko") hasDescriptionEn=\(info.descriptionRenderLanguage == "en" || info.description != nil) renderLanguage=\(info.descriptionRenderLanguage)")
        AppLogger.debug(.network, "[CoinInfoDescriptionRender] symbol=\(info.symbol) language=\(info.descriptionRenderLanguage) isFallback=\(info.descriptionFallbackNotice != nil) textLength=\(info.description?.count ?? 0)")
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

    func createCoinCommunityPost(symbol: String, content: String, session: AuthSession) async throws -> CoinCommunityMutationResult {
        let normalized = Self.normalizedSymbol(symbol)
        AppLogger.debug(.network, "[CommunityPost] begin symbol=\(normalized) inputLength=\(content.count)")
        let endpoint: PublicContentEndpoint = .coinCommunity(normalized)
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            method: "POST",
            body: ["content": content],
            symbol: normalized,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: "createCommunity"
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CoinCommunityPost")
        guard let result = PublicContentParser.communityPostMutation(payload: payload, fallbackSymbol: normalized) else {
            logDecodeFailure(
                endpoint: endpoint,
                target: "CoinCommunityPost",
                path: "data|data.item|data.post|data.items[0]",
                error: "expected post object or community snapshot",
                rawPreview: PublicContentParser.rawPreview(payload)
            )
            throw NetworkServiceError.parsingFailed("커뮤니티 작성 응답을 해석하지 못했어요.")
        }
        logDecodeSuccess(endpoint: endpoint, target: "CoinCommunityPost", symbol: result.post?.symbol ?? normalized)
        AppLogger.debug(
            .network,
            "[CommunityPost] success symbol=\(normalized) inputLength=\(content.count) postId=\(result.post?.id ?? "nil") snapshotItems=\(result.snapshot?.posts.count ?? -1)"
        )
        return result
    }

    func setCoinCommunityLike(symbol: String, itemId: String, isLiked: Bool, session: AuthSession) async throws -> CoinCommunityLikeResult {
        let normalized = Self.normalizedSymbol(symbol)
        let endpoint: PublicContentEndpoint = .coinCommunityLike(normalized, itemId)
        let method = isLiked ? "POST" : "DELETE"
        AppLogger.debug(.network, "[CommunityLike] itemId=\(itemId) symbol=\(normalized) action=\(method) status=dispatch")
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            method: method,
            symbol: normalized,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: "communityLike"
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CommunityLike")
        let result = PublicContentParser.likeResult(payload: payload, fallbackItemId: itemId, fallbackIsLiked: isLiked)
        AppLogger.debug(.network, "[CommunityLike] itemId=\(result.itemId) symbol=\(normalized) action=\(method) after=\(result.likeCount) status=success")
        return result
    }

    func fetchCoinCommunityComments(symbol: String, itemId: String, sort: String = "latest", session: AuthSession?) async throws -> CoinCommunityCommentsSnapshot {
        let normalized = Self.normalizedSymbol(symbol)
        let endpoint: PublicContentEndpoint = .coinCommunityComments(normalized, itemId)
        let normalizedSort = Self.normalizedSort(sort)
        AppLogger.debug(.network, "[CommunityComment] itemId=\(itemId) action=fetch sort=\(normalizedSort) status=dispatch")
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            queryItems: [
                URLQueryItem(name: "sort", value: normalizedSort),
                URLQueryItem(name: "orderBy", value: "createdAt"),
                URLQueryItem(name: "direction", value: normalizedSort == "oldest" ? "asc" : "desc")
            ],
            symbol: normalized,
            accessRequirement: session == nil ? .publicAccess : .authenticatedRequired,
            accessToken: session?.accessToken,
            logEndpointName: "communityComments"
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CommunityComments")
        let snapshot = PublicContentParser.commentsSnapshot(payload: payload).sorted(sort: normalizedSort)
        AppLogger.debug(.network, "[CommunityComment] itemId=\(itemId) action=fetch status=success commentCount=\(snapshot.commentCount)")
        return snapshot
    }

    func createCoinCommunityComment(symbol: String, itemId: String, content: String, session: AuthSession) async throws -> CoinCommunityCommentsSnapshot {
        let normalized = Self.normalizedSymbol(symbol)
        let endpoint: PublicContentEndpoint = .coinCommunityComments(normalized, itemId)
        AppLogger.debug(.network, "[CommunityComment] itemId=\(itemId) action=create status=dispatch")
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            method: "POST",
            body: ["content": content],
            symbol: normalized,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: "createCommunityComment"
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CommunityComment")
        let snapshot = PublicContentParser.commentsSnapshot(payload: payload)
        AppLogger.debug(.network, "[CommunityComment] itemId=\(itemId) action=create status=success commentCount=\(snapshot.commentCount)")
        return snapshot
    }

    func setUserFollow(userId: String, isFollowing: Bool, session: AuthSession) async throws -> UserFollowResult {
        let endpoint: PublicContentEndpoint = .userFollow(userId)
        let method = isFollowing ? "POST" : "DELETE"
        AppLogger.debug(.network, "[UserFollow] targetUserId=\(userId) action=\(method) status=dispatch")
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            method: method,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: "userFollow"
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "UserFollow")
        let result = PublicContentParser.followResult(payload: payload, fallbackUserId: userId, fallbackIsFollowing: isFollowing)
        AppLogger.debug(.network, "[UserFollow] targetUserId=\(result.userId) action=\(method) status=success")
        return result
    }

    func fetchUserRelationship(userId: String, session: AuthSession) async throws -> UserRelationship {
        let endpoint: PublicContentEndpoint = .userRelationship(userId)
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: "userRelationship"
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "UserRelationship")
        let result = PublicContentParser.userRelationship(payload: payload, fallbackUserId: userId)
        AppLogger.debug(.network, "[UserRelationship] targetUserId=\(result.userId) following=\(result.isFollowing) follower=\(result.isFollower) blocked=\(result.isBlocked)")
        return result
    }

    func fetchFollowing(userId: String?, session: AuthSession) async throws -> UserListSnapshot {
        try await fetchUserList(endpoint: .following(userId), session: session, logName: "following")
    }

    func fetchFollowers(userId: String, session: AuthSession) async throws -> UserListSnapshot {
        try await fetchUserList(endpoint: .followers(userId), session: session, logName: "followers")
    }

    private func fetchUserList(endpoint: PublicContentEndpoint, session: AuthSession, logName: String) async throws -> UserListSnapshot {
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: logName
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "UserList")
        return PublicContentParser.userList(payload: payload)
    }

    func reportCommunityTarget(
        targetType: CommunityReportTargetType,
        targetId: String,
        reason: CommunityReportReason,
        description: String?,
        session: AuthSession
    ) async throws -> CommunityReportResult {
        let endpoint: PublicContentEndpoint = .communityReports
        var body: JSONObject = [
            "targetType": targetType.rawValue,
            "targetId": targetId,
            "reason": reason.rawValue
        ]
        if let trimmedDescription = description?.trimmedNonEmpty {
            body["description"] = trimmedDescription
        }
        AppLogger.debug(.network, "[CommunityReport] targetType=\(targetType.rawValue) targetId=\(targetId) reason=\(reason.rawValue) status=dispatch")
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            method: "POST",
            body: body,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: "communityReport"
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CommunityReport")
        let result = PublicContentParser.reportResult(payload: payload, fallbackType: targetType, fallbackTargetId: targetId)
        AppLogger.debug(.network, "[CommunityReport] targetType=\(result.targetType.rawValue) targetId=\(result.targetId) status=success hidden=\(result.hidden)")
        return result
    }

    func blockUser(userId: String, session: AuthSession) async throws -> BlockedUser {
        let endpoint: PublicContentEndpoint = .communityBlocks
        AppLogger.debug(.network, "[CommunityBlock] targetUserId=\(userId) action=block status=dispatch")
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            method: "POST",
            body: ["blockedUserId": userId],
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: "communityBlock"
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CommunityBlock")
        let blocked = PublicContentParser.blockedUser(payload: payload, fallbackUserId: userId)
        AppLogger.debug(.network, "[CommunityBlock] targetUserId=\(blocked.id) action=block status=success")
        return blocked
    }

    func unblockUser(userId: String, session: AuthSession) async throws {
        let endpoint: PublicContentEndpoint = .communityBlockUser(userId)
        _ = try await requestPublicJSON(
            endpoint: endpoint,
            method: "DELETE",
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: "communityUnblock"
        )
        AppLogger.debug(.network, "[CommunityBlock] targetUserId=\(userId) action=unblock status=success")
    }

    func fetchBlockedUsers(session: AuthSession) async throws -> [BlockedUser] {
        let endpoint: PublicContentEndpoint = .communityBlocks
        let json = try await requestPublicJSON(
            endpoint: endpoint,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken,
            logEndpointName: "communityBlocks"
        )
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CommunityBlocks")
        let users = PublicContentParser.userList(payload: payload).users
        AppLogger.debug(.network, "[CommunityBlock] action=fetch count=\(users.count) status=success")
        return users
    }

    func voteCoin(symbol: String, direction: String, session: AuthSession) async throws -> CoinVoteSnapshot {
        let normalized = Self.normalizedSymbol(symbol)
        AppLogger.debug(.network, "[PublicContentAPI] symbol normalized raw=\(symbol) normalized=\(normalized)")
        let endpoint: PublicContentEndpoint = .coinSentiment(normalized)
        let json: Any
        do {
            json = try await requestPublicJSON(
                endpoint: endpoint,
                method: "POST",
                body: ["direction": direction],
                symbol: normalized,
                accessRequirement: .authenticatedRequired,
                accessToken: session.accessToken,
                logEndpointName: "voteCoinSentiment"
            )
        } catch let error as NetworkServiceError where error.isNotFound {
            AppLogger.debug(.network, "[SentimentAPI] scope=coin key=\(normalized) method=POST status=404 fallback=/votes")
            json = try await requestPublicJSON(
                endpoint: .coinVotes(normalized),
                method: "POST",
                body: ["direction": direction],
                symbol: normalized,
                accessRequirement: .authenticatedRequired,
                accessToken: session.accessToken,
                logEndpointName: "voteCoin"
            )
        }
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "CoinVote")
        guard let dictionary = payload as? JSONObject else {
            logDecodeFailure(endpoint: endpoint, target: "CoinVote", path: "data", error: "expected object")
            throw NetworkServiceError.parsingFailed("투표 응답을 해석하지 못했어요.")
        }
        logDecodeSuccess(endpoint: endpoint, target: "CoinVote", symbol: normalized)
        let vote = PublicContentParser.vote(dictionary: dictionary, fallbackScope: "coin", fallbackKey: normalized)
        AppLogger.debug(
            .network,
            "[SentimentState] scope=coin key=\(normalized) participants=\(vote.totalCount) bullishRatio=\(vote.bullishDisplayRatio) bearishRatio=\(vote.bearishDisplayRatio) myVote=\(vote.myVote ?? "nil")"
        )
        return vote
    }

    func voteMarketSentiment(direction: String, session: AuthSession) async throws -> MarketPollSnapshot {
        let endpoint: PublicContentEndpoint = .marketSentiment
        let json: Any
        do {
            json = try await requestPublicJSON(
                endpoint: endpoint,
                method: "POST",
                body: ["direction": direction],
                accessRequirement: .authenticatedRequired,
                accessToken: session.accessToken,
                logEndpointName: "voteMarketSentiment"
            )
        } catch let error as NetworkServiceError where error.isNotFound {
            AppLogger.debug(.network, "[SentimentAPI] scope=market key=global method=POST status=404 fallback=/market/votes")
            json = try await requestPublicJSON(
                endpoint: .marketVotes,
                method: "POST",
                body: ["scope": "market", "key": "global", "direction": direction],
                accessRequirement: .authenticatedRequired,
                accessToken: session.accessToken,
                logEndpointName: "voteMarketSentiment"
            )
        }
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "MarketVote")
        guard let dictionary = payload as? JSONObject else {
            logDecodeFailure(endpoint: endpoint, target: "MarketVote", path: "data", error: "expected object", rawPreview: PublicContentParser.rawPreview(payload))
            throw NetworkServiceError.parsingFailed("시장 투표 응답을 해석하지 못했어요.")
        }
        let poll = PublicContentParser.marketPoll(dictionary: dictionary)
        logDecodeSuccess(endpoint: endpoint, target: "MarketVote", symbol: nil)
        AppLogger.debug(
            .network,
            "[SentimentState] scope=market key=global participants=\(poll.totalCount) bullishRatio=\(poll.bullishDisplayRatio) bearishRatio=\(poll.bearishDisplayRatio) myVote=\(poll.myVote ?? "nil")"
        )
        return poll
    }

    func fetchMarketTrends(range: String = "30d", interval: String = "daily", currency: String = "KRW") async throws -> MarketTrendsSnapshot {
        AppLogger.debug(.network, "DEBUG [MarketTrend] request range=\(range) interval=\(interval) currency=\(currency)")
        AppLogger.debug(.network, "[NewsOverviewRequest] endpoint=/news/overview")
        var endpoint: PublicContentEndpoint = .newsOverview
        let json: Any
        let trendQueryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "currency", value: currency)
        ]
        do {
            json = try await requestPublicJSON(endpoint: .newsOverview, queryItems: trendQueryItems)
        } catch let error as NetworkServiceError where error.isNotFound {
            AppLogger.debug(.network, "[APIFallback] feature=newsOverview primaryEndpoint=/news/overview fallbackEndpoint=/market/trends reason=404")
            endpoint = .marketTrends
            json = try await requestPublicJSON(endpoint: .marketTrends, queryItems: trendQueryItems)
        }
        let payload = try PublicContentParser.unwrapPayload(json, endpoint: endpoint, decodeTarget: "MarketTrends")
        guard let dictionary = payload as? JSONObject else {
            logDecodeFailure(endpoint: endpoint, target: "MarketTrends", path: "data", error: "expected object")
            throw NetworkServiceError.parsingFailed("시장 데이터 응답을 해석하지 못했어요.")
        }
        var snapshot = PublicContentParser.marketTrends(dictionary: dictionary)
        snapshot = await translatedMarketTrendsIfNeeded(snapshot)
        logDecodeSuccess(endpoint: endpoint, target: "MarketTrends", symbol: nil)
        AppLogger.debug(
            .network,
            "[MarketDataAPI] response status=decoded range=\(snapshot.range ?? "nil") pointCount=\(snapshot.marketCapVolumeSeries.count) source=\(snapshot.dataProvider ?? "unknown") updatedAt=\(snapshot.asOf.map(String.init(describing:)) ?? "nil")"
        )
        AppLogger.debug(.network, "DEBUG [MarketTrend] response points=\(snapshot.marketCapVolumeSeries.count) source=\(snapshot.dataProvider ?? "unknown") cacheHit=unknown")
        Self.logMarketTrendQuality(snapshot.marketCapVolumeSeries)
        AppLogger.debug(.network, "[NewsOverviewResponse] status=decoded summaryAvailable=\(snapshot.summaryDescription?.isEmpty == false || snapshot.latestHeadline?.isEmpty == false) moodAvailable=\(snapshot.fearGreedIndex != nil) topNewsCount=\(snapshot.topNews.count) provider=\(snapshot.dataProvider ?? "unknown") source=\(endpoint.name)")
        AppLogger.debug(.network, "[NewsOverviewSectionState] summary=\(snapshot.summaryDescription?.isEmpty == false || snapshot.latestHeadline?.isEmpty == false) mood=\(snapshot.fearGreedIndex != nil) sentiment=\(snapshot.marketPoll != nil) topNews=\(snapshot.topNews.isEmpty == false)")
        return snapshot
    }

    private func translatedMarketTrendsIfNeeded(_ snapshot: MarketTrendsSnapshot) async -> MarketTrendsSnapshot {
        var requests: [TranslationRequestItem] = []
        if let headline = snapshot.latestHeadline?.trimmedNonEmpty, !Self.looksKorean(headline) {
            requests.append(TranslationRequestItem(id: "market_summary_headline", text: headline, sourceLanguage: "en"))
        }
        if let description = snapshot.summaryDescription?.trimmedNonEmpty, !Self.looksKorean(description) {
            requests.append(TranslationRequestItem(id: "market_summary_description", text: description, sourceLanguage: "en"))
        }
        for item in snapshot.topNews where item.fallbackUsed {
            requests.append(TranslationRequestItem(id: "\(item.id)_summary_title", text: item.originalTitle, sourceLanguage: "en"))
            if let summary = item.originalSummary?.trimmedNonEmpty {
                requests.append(TranslationRequestItem(id: "\(item.id)_summary_body", text: summary, sourceLanguage: "en"))
            }
        }
        guard requests.isEmpty == false else { return snapshot }
        let translations = await translationUseCase.translate(items: requests, context: "market_news_summary", symbol: nil)
        let topNews = snapshot.topNews.map { item in
            item.replacingTranslated(
                title: translations["\(item.id)_summary_title"]?.translatedText,
                summary: translations["\(item.id)_summary_body"]?.translatedText
            )
        }
        return snapshot.replacingSummary(
            headline: translations["market_summary_headline"]?.translatedText ?? snapshot.latestHeadline,
            description: translations["market_summary_description"]?.translatedText ?? snapshot.summaryDescription,
            topNews: topNews
        )
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
        symbol: String? = nil,
        accessRequirement: RequestAccessRequirement = .publicAccess,
        accessToken: String? = nil,
        logEndpointName: String? = nil
    ) async throws -> Any {
        let endpointName = logEndpointName ?? endpoint.name
        do {
            return try await client.requestPublicContentJSONWithDebugLog(
                path: endpoint.canonicalRootPath,
                method: method,
                queryItems: queryItems,
                body: body,
                endpoint: endpointName,
                canonical: true,
                decodeTarget: endpoint.decodeTarget,
                normalizedSymbol: symbol,
                accessRequirement: accessRequirement,
                accessToken: accessToken
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
                endpoint: endpointName,
                canonical: false,
                decodeTarget: endpoint.decodeTarget,
                normalizedSymbol: symbol,
                accessRequirement: accessRequirement,
                accessToken: accessToken
            )
        }
    }

    private func translatedNewsItemsIfNeeded(_ items: [CryptoNewsItem], context: String, symbol: String?) async -> [CryptoNewsItem] {
        var requestItems: [TranslationRequestItem] = []
        for item in items {
            if item.titleFallbackUsed {
                requestItems.append(TranslationRequestItem(id: "\(item.id)_title", text: item.originalTitle, sourceLanguage: item.originalLanguage ?? "en"))
            }
            if item.summaryFallbackUsed, item.summary.isEmpty == false {
                requestItems.append(TranslationRequestItem(id: "\(item.id)_summary", text: item.originalSummary ?? item.summary, sourceLanguage: item.originalLanguage ?? "en"))
            }
        }
        let translations = await translationUseCase.translate(items: requestItems, context: context, symbol: symbol)
        return items.map { item in
            let title = translations["\(item.id)_title"]?.translatedText
            let summary = translations["\(item.id)_summary"]?.translatedText
            if title != nil || summary != nil {
                let nextItem = item.replacingTranslated(title: title, summary: summary)
                AppLogger.debug(.network, "[NewsTranslation] id=\(item.id) hasKo=true fallbackUsed=false")
                return nextItem
            }
            let needsTranslation = item.titleFallbackUsed || item.summaryFallbackUsed
            AppLogger.debug(.network, "[NewsTranslation] id=\(item.id) hasKo=\(!needsTranslation) fallbackUsed=\(needsTranslation)")
            return needsTranslation ? item.replacingTranslated(title: nil, summary: nil, state: .failed) : item
        }
    }

    private func logDecodeSuccess(endpoint: PublicContentEndpoint, target: String, symbol: String?) {
        AppLogger.debug(.network, "[PublicContentAPI] decode success endpoint=\(endpoint.name)\(symbol.map { " symbol=\($0)" } ?? "") target=\(target)")
    }

    private func logDecodeFailure(endpoint: PublicContentEndpoint, target: String, path: String, error: String, rawPreview: String? = nil) {
        AppLogger.debug(.network, "[PublicContentAPI] decode failed endpoint=\(endpoint.name) target=\(target) path=\(path) error=\(error)\(rawPreview.map { " rawPreview=\($0)" } ?? "")")
        if endpoint.name == "coinCommunity" {
            AppLogger.debug(.network, "[CommunityDecode] failure codingPath=\(path) rawPreview=\(rawPreview ?? "nil") error=\(error)")
        }
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

    private static func normalizedSort(_ sort: String) -> String {
        switch sort.lowercased() {
        case "oldest", "asc":
            return "oldest"
        case "popular":
            return "popular"
        default:
            return "latest"
        }
    }

    private static func sortedNewsItems(_ items: [CryptoNewsItem], sort: String) -> [CryptoNewsItem] {
        switch normalizedSort(sort) {
        case "oldest":
            return items.sorted { ($0.publishedAt ?? .distantFuture) < ($1.publishedAt ?? .distantFuture) }
        default:
            return items.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        }
    }

    private static func newsEmptyReason(meta: ResponseMeta, itemCount: Int, filteredCount: Int, isCoinScoped: Bool) -> String {
        if let emptyReason = meta.emptyReason?.trimmedNonEmpty {
            return emptyReason
        }
        if itemCount > 0 && filteredCount == 0 {
            return isCoinScoped ? "no_related_news" : "relevance_filter_empty"
        }
        if let message = meta.partialFailureMessage?.lowercased() ?? meta.warningMessage?.lowercased() {
            if message.contains("limit") || message.contains("rate") {
                return "provider_limit"
            }
            if message.contains("provider") || message.contains("source") {
                return "provider_error"
            }
            if message.contains("cache") {
                return "cache_empty"
            }
        }
        return isCoinScoped ? "date_no_news" : "date_no_news"
    }

    static func apiDateString(_ date: Date) -> String {
        apiDateFormatter.string(from: date)
    }

    private static func cacheHitLogValue(_ meta: ResponseMeta) -> String {
        if let cacheHit = meta.cacheHit {
            return cacheHit ? "true" : "false"
        }
        return meta.isStale ? "stale" : "unknown"
    }

    private static func logMarketTrendQuality(_ series: [MarketTrendPoint]) {
        let metrics: [(name: String, values: [Double])] = [
            ("marketCap", series.compactMap(\.marketCap)),
            ("volume", series.compactMap(\.volume)),
            ("btcDominance", series.compactMap(\.btcDominance)),
            ("ethDominance", series.compactMap(\.ethDominance))
        ]
        for metric in metrics {
            let nonNil = metric.values.count
            guard nonNil >= 3,
                  let minValue = metric.values.min(),
                  let maxValue = metric.values.max() else {
                AppLogger.debug(.network, "WARN [MarketTrend] insufficientPoints metric=\(metric.name) nonNil=\(nonNil)")
                continue
            }
            let variation = maxValue == minValue ? 0 : (maxValue - minValue) / max(abs(minValue), abs(maxValue), 1)
            AppLogger.debug(.network, "DEBUG [MarketTrend] metric=\(metric.name) nonNil=\(nonNil) min=\(minValue) max=\(maxValue) variation=\(variation)")
            if minValue == maxValue {
                AppLogger.debug(.network, "WARN [MarketTrend] flatGraph metric=\(metric.name) reason=all_values_equal")
            } else if variation < 0.001 {
                AppLogger.debug(.network, "WARN [MarketTrend] flatGraph metric=\(metric.name) reason=variation_under_0_1_percent")
            }
            if nonNil < 7 {
                AppLogger.debug(.network, "WARN [MarketTrend] insufficientPoints metric=\(metric.name) nonNil=\(nonNil)")
            }
        }
    }

    private static func looksKorean(_ text: String) -> Bool {
        text.range(of: #"[가-힣]"#, options: .regularExpression) != nil
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    fileprivate enum PublicContentEndpoint {
        case news
        case newsOverview
        case newsDetail(String)
        case coinNews(String)
        case coinInfo(String)
        case coinAnalysis(String)
        case coinCommunity(String)
        case coinCommunityLike(String, String)
        case coinCommunityComments(String, String)
        case userFollow(String)
        case userRelationship(String)
        case following(String?)
        case followers(String)
        case communityReports
        case communityBlocks
        case communityBlockUser(String)
        case coinVotes(String)
        case coinSentiment(String)
        case marketVotes
        case marketSentiment
        case marketTrends
        case marketThemes

        var name: String {
            switch self {
            case .news: return "news"
            case .newsOverview: return "newsOverview"
            case .newsDetail: return "newsDetail"
            case .coinNews: return "coinNews"
            case .coinInfo: return "coinInfo"
            case .coinAnalysis: return "coinAnalysis"
            case .coinCommunity: return "coinCommunity"
            case .coinCommunityLike: return "coinCommunityLike"
            case .coinCommunityComments: return "coinCommunityComments"
            case .userFollow: return "userFollow"
            case .userRelationship: return "userRelationship"
            case .following: return "following"
            case .followers: return "followers"
            case .communityReports: return "communityReports"
            case .communityBlocks: return "communityBlocks"
            case .communityBlockUser: return "communityBlockUser"
            case .coinVotes: return "coinVotes"
            case .coinSentiment: return "coinSentiment"
            case .marketVotes: return "marketVotes"
            case .marketSentiment: return "marketSentiment"
            case .marketTrends: return "marketTrends"
            case .marketThemes: return "marketThemes"
            }
        }

        var decodeTarget: String {
            switch self {
            case .news, .newsDetail: return "NewsEnvelope"
            case .newsOverview: return "NewsOverviewEnvelope"
            case .coinNews: return "CoinNewsEnvelope"
            case .coinInfo: return "CoinInfoEnvelope"
            case .coinAnalysis: return "CoinAnalysisEnvelope"
            case .coinCommunity: return "CoinCommunityEnvelope"
            case .coinCommunityLike: return "CommunityLikeEnvelope"
            case .coinCommunityComments: return "CommunityCommentsEnvelope"
            case .userFollow: return "UserFollowEnvelope"
            case .userRelationship: return "UserRelationshipEnvelope"
            case .following, .followers: return "UserListEnvelope"
            case .communityReports: return "CommunityReportEnvelope"
            case .communityBlocks, .communityBlockUser: return "CommunityBlocksEnvelope"
            case .coinVotes, .coinSentiment: return "CoinVoteEnvelope"
            case .marketVotes, .marketSentiment: return "MarketVoteEnvelope"
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
            case .newsOverview:
                return "\(prefix)/news/overview"
            case .newsDetail(let id):
                return "\(prefix)/news/\(LivePublicContentRepository.pathComponent(id))"
            case .coinNews(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/news"
            case .coinInfo(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/info"
            case .coinAnalysis(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/analysis"
            case .coinCommunity(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/community"
            case .coinCommunityLike(let symbol, let itemId):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/community/\(LivePublicContentRepository.pathComponent(itemId))/like"
            case .coinCommunityComments(let symbol, let itemId):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/community/\(LivePublicContentRepository.pathComponent(itemId))/comments"
            case .userFollow(let userId):
                return "\(prefix)/users/\(LivePublicContentRepository.pathComponent(userId))/follow"
            case .userRelationship(let userId):
                return "\(prefix)/users/\(LivePublicContentRepository.pathComponent(userId))/relationship"
            case .following(let userId):
                if let userId {
                    return "\(prefix)/users/\(LivePublicContentRepository.pathComponent(userId))/following"
                }
                return "\(prefix)/users/me/following"
            case .followers(let userId):
                return "\(prefix)/users/\(LivePublicContentRepository.pathComponent(userId))/followers"
            case .communityReports:
                return "\(prefix)/community/reports"
            case .communityBlocks:
                return "\(prefix)/community/blocks"
            case .communityBlockUser(let userId):
                return "\(prefix)/community/blocks/\(LivePublicContentRepository.pathComponent(userId))"
            case .coinVotes(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/votes"
            case .coinSentiment(let symbol):
                return "\(prefix)/coins/\(LivePublicContentRepository.pathComponent(symbol))/sentiment"
            case .marketVotes:
                return "\(prefix)/market/votes"
            case .marketSentiment:
                return "\(prefix)/market/sentiment"
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
        let metaDictionary = dictionary["meta"] as? JSONObject ?? dictionary["metadata"] as? JSONObject ?? [:]
        let sourceDictionary = dictionary["source"] as? JSONObject ?? metaDictionary["source"] as? JSONObject ?? [:]
        return (
            payload,
            ResponseMeta(
                fetchedAt: parseDate(dictionary["asOf"] ?? dictionary["fetchedAt"] ?? dictionary["timestamp"]),
                isStale: dictionary.bool(["stale", "isStale"]) ?? false,
                warningMessage: dictionary.string(["warningMessage", "message"]) ?? metaDictionary.string(["warningMessage", "message"]),
                partialFailureMessage: dictionary.string(["partialFailureMessage", "partialError"]) ?? metaDictionary.string(["partialFailureMessage", "partialError"]),
                source: sourceDictionary.string(["primary", "provider", "name"]) ?? dictionary.string(["source", "provider", "dataProvider"]) ?? metaDictionary.string(["source", "provider"]),
                cacheHit: dictionary.bool(["cacheHit", "cache_hit"]) ?? metaDictionary.bool(["cacheHit", "cache_hit"]),
                emptyReason: dictionary.string(["emptyReason", "empty_reason", "reason"]) ?? metaDictionary.string(["emptyReason", "empty_reason", "reason"]),
                providerStatus: dictionary.string(["providerStatus", "provider_status", "status"]) ?? metaDictionary.string(["providerStatus", "provider_status", "status"]),
                latestFallbackDate: parseDate(dictionary["latestFallbackDate"] ?? dictionary["latest_fallback_date"] ?? metaDictionary["latestFallbackDate"] ?? metaDictionary["latest_fallback_date"]),
                availableDates: parseDateArray(dictionary["availableDates"] ?? dictionary["available_dates"] ?? metaDictionary["availableDates"] ?? metaDictionary["available_dates"])
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
        let titleResolution = localizedText(
            dictionary: dictionary,
            koKeys: ["titleKo", "title_ko", "translatedTitle", "translated_title"],
            localizedKeys: ["localizedTitle", "localized_title"],
            fallbackKeys: ["title", "headline"]
        )
        guard let title = titleResolution.text else { return nil }
        let summaryResolution = localizedText(
            dictionary: dictionary,
            koKeys: ["summaryKo", "summary_ko", "translatedSummary", "translated_summary"],
            localizedKeys: ["localizedSummary", "localized_summary"],
            fallbackKeys: ["summary", "description", "excerpt"]
        )
        let id = dictionary.string(["id", "newsId", "news_id"]) ?? UUID().uuidString
        let item = CryptoNewsItem(
            id: id,
            title: title,
            summary: summaryResolution.text ?? "",
            body: cleanHTML(dictionary.string(["bodyKo", "body_ko", "translatedBody", "translated_body"]) ?? dictionary.string(["body", "content"])),
            originalTitle: cleanHTML(dictionary.string(["originalTitle", "original_title", "title", "headline"])) ?? title,
            originalSummary: cleanHTML(dictionary.string(["originalSummary", "original_summary", "summary", "description", "excerpt"])),
            translatedTitle: titleResolution.fallbackUsed ? nil : title,
            translatedSummary: summaryResolution.fallbackUsed ? nil : summaryResolution.text,
            source: dictionary.string(["sourceName", "source_name", "publisher", "domain", "source"]) ?? dictionary.string(["provider"]) ?? "Unknown",
            provider: dictionary.string(["provider", "providerName", "provider_name"]),
            publishedAt: parseDate(dictionary["publishedAt"] ?? dictionary["published_at"] ?? dictionary["createdAt"] ?? dictionary["timestamp"]),
            relatedSymbols: dictionary.stringArray(["relatedSymbols", "related_symbols", "symbols", "coins", "assets"]).map { LivePublicContentRepository.normalizedSymbol($0) },
            tags: dictionary.stringArray(["tags", "keywords", "categories"]),
            originalURL: url(dictionary.string(["originalUrl", "originalURL", "url", "link"])),
            thumbnailURL: url(dictionary.string(["thumbnailUrl", "thumbnailURL", "imageUrl", "imageURL"])),
            originalLanguage: dictionary.string(["originalLanguage", "original_language", "language"]) ?? titleResolution.language,
            renderLanguage: titleResolution.language ?? summaryResolution.language ?? "unknown",
            translationState: titleResolution.fallbackUsed || summaryResolution.fallbackUsed ? .originalOnly : .translated,
            titleFallbackUsed: titleResolution.fallbackUsed,
            summaryFallbackUsed: summaryResolution.fallbackUsed,
            relevanceScore: dictionary.double(["relevanceScore", "relevance_score"])
        )
        AppLogger.debug(.network, "[NewsTranslation] id=\(id) hasTitleKo=\(!titleResolution.fallbackUsed) hasSummaryKo=\(!(summaryResolution.text ?? "").isEmpty && !summaryResolution.fallbackUsed) renderLanguage=\(item.renderLanguage) fallbackUsed=\(item.titleFallbackUsed || item.summaryFallbackUsed)")
        return item
    }

    static func coinInfo(dictionary: JSONObject, fallbackSymbol: String) -> CoinDetailInfo {
        let market = dictionary["market"] as? JSONObject ?? [:]
        let source = dictionary["source"] as? JSONObject ?? [:]
        var changes: [CoinPriceChangePeriod: Double] = [:]
        changes[.h24] = normalizePercent(market.double(["priceChangePercent24h", "price_change_percent_24h"]) ?? dictionary.double(["priceChangePercent24h", "price_change_percent_24h", "priceChangePercentage24h", "price_change_percentage_24h", "change24h"]))
        changes[.d7] = normalizePercent(market.double(["priceChangePercent7d", "price_change_percent_7d"]) ?? dictionary.double(["priceChangePercent7d", "price_change_percent_7d", "priceChangePercentage7d", "price_change_percentage_7d", "change7d"]))
        changes[.d14] = normalizePercent(market.double(["priceChangePercent14d", "price_change_percent_14d"]) ?? dictionary.double(["priceChangePercent14d", "price_change_percent_14d", "priceChangePercentage14d", "price_change_percentage_14d", "change14d"]))
        changes[.d30] = normalizePercent(market.double(["priceChangePercent30d", "price_change_percent_30d"]) ?? dictionary.double(["priceChangePercent30d", "price_change_percent_30d", "priceChangePercentage30d", "price_change_percentage_30d", "change30d"]))
        changes[.d60] = normalizePercent(market.double(["priceChangePercent60d", "price_change_percent_60d"]) ?? dictionary.double(["priceChangePercent60d", "price_change_percent_60d", "priceChangePercentage60d", "price_change_percentage_60d", "change60d"]))
        changes[.d200] = normalizePercent(market.double(["priceChangePercent200d", "price_change_percent_200d"]) ?? dictionary.double(["priceChangePercent200d", "price_change_percent_200d", "priceChangePercentage200d", "price_change_percentage_200d", "change200d"]))
        changes[.y1] = normalizePercent(market.double(["priceChangePercent1y", "price_change_percent_1y"]) ?? dictionary.double(["priceChangePercent1y", "price_change_percent_1y", "priceChangePercentage1y", "price_change_percentage_1y", "change1y"]))

        let resolvedSymbol = dictionary.string(["symbol"])?.uppercased() ?? fallbackSymbol.uppercased()
        let descriptionResolution = coinDescription(dictionary: dictionary)
        let descriptionDictionary = dictionary["description"] as? JSONObject
        let hasPlainTextKo = [
            descriptionDictionary?.string(["plainTextKo", "plain_text_ko"]),
            dictionary.string(["plainTextKo", "plain_text_ko"])
        ].contains { cleanHTML($0)?.trimmedNonEmpty != nil }
        let hasKo = [
            descriptionDictionary?.string(["ko"]),
            (dictionary["localization"] as? JSONObject)?.string(["ko"]),
            dictionary.string(["descriptionKo", "description_ko"])
        ].contains { cleanHTML($0)?.trimmedNonEmpty != nil }
        let hasTranslatedDescription = cleanHTML(dictionary.string(["translatedDescription", "translated_description"]))?.trimmedNonEmpty != nil
        let hasEn = cleanHTML(
            descriptionDictionary?.string(["plainTextEn", "plain_text_en", "en"])
                ?? dictionary.string(["plainTextEn", "plain_text_en", "descriptionEn", "description_en", "rawDescription", "raw_description", "description"])
        )?.trimmedNonEmpty != nil
        AppLogger.debug(.network, "[CoinInfoDescription] symbol=\(resolvedSymbol) hasPlainTextKo=\(hasPlainTextKo) hasKo=\(hasKo) hasTranslatedDescription=\(hasTranslatedDescription) hasEn=\(hasEn) selectedSource=\(descriptionResolution.language)")
        let info = CoinDetailInfo(
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
            description: descriptionResolution.text,
            officialURL: url(dictionary.string(["homepageUrl", "homepage_url", "officialUrl", "officialURL", "homepage", "website"])),
            explorerURL: url(dictionary.string(["explorerUrl", "explorer_url", "communityUrl", "communityURL"])),
            dataProvider: source.string(["market", "metadata"]) ?? dictionary.string(["dataProvider", "provider"]) ?? "CoinGecko",
            metadataSource: source.string(["metadata"]),
            marketSource: source.string(["market"]),
            fallbackUsed: source.bool(["fallbackUsed", "fallback_used"]) ?? dictionary.bool(["fallbackUsed", "fallback_used"]) ?? false,
            originalDescription: descriptionResolution.language == "ko" ? nil : descriptionResolution.text,
            translatedDescription: descriptionResolution.language == "ko" ? descriptionResolution.text : nil,
            descriptionRenderLanguage: descriptionResolution.language,
            descriptionFallbackNotice: descriptionResolution.notice,
            descriptionTranslationState: descriptionResolution.language == "ko" ? .translated : (descriptionResolution.text == nil ? .notRequested : .originalOnly)
        )
        AppLogger.debug(.network, "[CoinInfoDecode] success codingPath=data rawPreview=\(rawPreview(dictionary, limit: 1000))")
        return info
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
            let itemsContainer = dictionary["items"] ?? dictionary["posts"] ?? dictionary["rows"] ?? dictionary["results"] ?? dictionary["list"]
            let posts = (unwrapArray(itemsContainer) ?? [])
                .compactMap { ($0 as? JSONObject).flatMap { communityPost(dictionary: $0, fallbackSymbol: fallbackSymbol) } }
            let voteDictionary = (dictionary["vote"] as? JSONObject)
                ?? (dictionary["coinVote"] as? JSONObject)
                ?? (dictionary["sentiment"] as? JSONObject)
                ?? dictionary
            AppLogger.debug(
                .network,
                "[CommunityDecode] success codingPath=data bodyShape=\(bodyShape(dictionary)) itemCount=\(posts.count)"
            )
            return CoinCommunitySnapshot(
                posts: posts,
                vote: vote(dictionary: voteDictionary, fallbackScope: "coin", fallbackKey: fallbackSymbol),
                nextCursor: dictionary.string(["nextCursor", "next_cursor", "cursor"])
            )
        }
        let posts = (unwrapArray(payload) ?? [])
            .compactMap { ($0 as? JSONObject).flatMap { communityPost(dictionary: $0, fallbackSymbol: fallbackSymbol) } }
        AppLogger.debug(.network, "[CommunityDecode] success codingPath=data[] bodyShape=array itemCount=\(posts.count)")
        return CoinCommunitySnapshot(
            posts: posts,
            vote: CoinVoteSnapshot(
                bullishCount: 0,
                bearishCount: 0,
                totalCount: 0,
                myVote: nil,
                scope: "coin",
                key: fallbackSymbol,
                hasServerCounts: false
            )
        )
    }

    static func communityPostMutation(payload: Any, fallbackSymbol: String) -> CoinCommunityMutationResult? {
        if let dictionary = payload as? JSONObject {
            if let post = communityPost(dictionary: dictionary, fallbackSymbol: fallbackSymbol) {
                return CoinCommunityMutationResult(post: post, message: dictionary.string(["message"]))
            }

            for key in ["item", "post", "community", "communityPost", "community_post", "createdPost", "created_post"] {
                if let nested = dictionary[key] as? JSONObject,
                   let post = communityPost(dictionary: nested, fallbackSymbol: fallbackSymbol) {
                    return CoinCommunityMutationResult(post: post, message: dictionary.string(["message"]))
                }
            }

            let snapshot = communitySnapshot(payload: dictionary, fallbackSymbol: fallbackSymbol)
            if snapshot.posts.isEmpty == false || dictionary.int(["itemCount", "item_count"]) != nil {
                return CoinCommunityMutationResult(post: snapshot.posts.first, snapshot: snapshot, message: dictionary.string(["message"]))
            }

            if dictionary.bool(["success"]) == true || dictionary.string(["status"])?.lowercased() == "created" {
                return CoinCommunityMutationResult(post: nil, snapshot: nil, message: dictionary.string(["message"]))
            }
        }

        if let array = unwrapArray(payload), array.isEmpty == false {
            let posts = array.compactMap { ($0 as? JSONObject).flatMap { communityPost(dictionary: $0, fallbackSymbol: fallbackSymbol) } }
            if posts.isEmpty == false {
                return CoinCommunityMutationResult(
                    post: posts.first,
                    snapshot: CoinCommunitySnapshot(
                        posts: posts,
                        vote: CoinVoteSnapshot(
                            bullishCount: 0,
                            bearishCount: 0,
                            totalCount: 0,
                            myVote: nil,
                            scope: "coin",
                            key: fallbackSymbol,
                            hasServerCounts: false
                        )
                    )
                )
            }
        }

        return nil
    }

    static func communityPost(dictionary: JSONObject, fallbackSymbol: String) -> CoinCommunityPost? {
        let author = dictionary["author"] as? JSONObject ?? dictionary["user"] as? JSONObject ?? [:]
        guard let content = dictionary.string(["content", "body", "message"]) else { return nil }
        let itemId = dictionary.string(["id", "postId", "post_id"]) ?? UUID().uuidString
        let authorResolution = authorDisplayName(author: author, dictionary: dictionary, fallback: "사용자")
        AppLogger.debug(
            .network,
            "[CommunityAuthorRender] itemId=\(itemId) selectedName=\(authorResolution.primaryName) isPrivateRelay=\(authorResolution.isPrivateRelay) hasFollowState=\(dictionary.bool(["isFollowing", "is_following"]) != nil)"
        )
        return CoinCommunityPost(
            id: itemId,
            authorId: author.string(["id", "userId", "user_id"]) ?? dictionary.string(["authorId", "author_id", "userId", "user_id"]),
            authorName: authorResolution.primaryName,
            avatarURL: url(author.string(["avatarUrl", "avatarURL", "imageUrl", "imageURL"]) ?? dictionary.string(["avatarUrl", "avatarURL"])),
            createdAt: parseDate(dictionary["createdAt"] ?? dictionary["created_at"] ?? dictionary["timestamp"]),
            content: content,
            symbol: dictionary.string(["symbol"])?.uppercased() ?? fallbackSymbol.uppercased(),
            tags: dictionary.stringArray(["tags"]).map { $0.replacingOccurrences(of: "거래 인증", with: "활동 인증") },
            likeCount: dictionary.int(["likeCount", "like_count", "likes"]) ?? 0,
            commentCount: dictionary.int(["commentCount", "comment_count", "comments"]) ?? 0,
            isLiked: dictionary.bool(["isLiked", "is_liked"]) ?? (dictionary.string(["myReaction", "my_reaction"]) == "like"),
            isFollowing: dictionary.bool(["isFollowing", "is_following"]) ?? false,
            isOwnPost: dictionary.bool(["isOwnPost", "is_own_post", "isMine", "is_mine"]) ?? false,
            badge: dictionary.string(["badge"])?.replacingOccurrences(of: "거래 인증", with: "활동 인증")
        )
    }

    static func likeResult(payload: Any, fallbackItemId: String, fallbackIsLiked: Bool) -> CoinCommunityLikeResult {
        let dictionary = payload as? JSONObject ?? [:]
        return CoinCommunityLikeResult(
            itemId: dictionary.string(["itemId", "item_id", "postId", "post_id", "id"]) ?? fallbackItemId,
            likeCount: dictionary.int(["likeCount", "like_count", "likes"]) ?? 0,
            isLiked: dictionary.bool(["isLiked", "is_liked"]) ?? ((dictionary.string(["myReaction", "my_reaction"]) == "like") || fallbackIsLiked)
        )
    }

    static func commentsSnapshot(payload: Any) -> CoinCommunityCommentsSnapshot {
        let dictionary = payload as? JSONObject ?? [:]
        let array = unwrapArray(payload) ?? unwrapArray(dictionary["comments"] ?? dictionary["items"]) ?? []
        let comments = array.enumerated().compactMap { index, item -> CoinCommunityComment? in
            guard let item = item as? JSONObject else { return nil }
            let author = item["author"] as? JSONObject ?? item["user"] as? JSONObject ?? [:]
            guard let content = item.string(["content", "body", "message"]) else { return nil }
            let authorResolution = authorDisplayName(author: author, dictionary: item, fallback: "사용자")
            return CoinCommunityComment(
                id: item.string(["id", "commentId", "comment_id"]) ?? "comment-\(index)",
                authorId: author.string(["id", "userId", "user_id"]) ?? item.string(["authorId", "author_id", "userId", "user_id"]),
                content: content,
                authorName: authorResolution.primaryName,
                createdAt: parseDate(item["createdAt"] ?? item["created_at"] ?? item["timestamp"]),
                isOwnComment: item.bool(["isOwnComment", "is_own_comment", "isMine", "is_mine"]) ?? false
            )
        }
        return CoinCommunityCommentsSnapshot(
            comments: comments,
            commentCount: dictionary.int(["commentCount", "comment_count", "totalCount", "total_count", "count"]) ?? comments.count
        )
    }

    static func followResult(payload: Any, fallbackUserId: String, fallbackIsFollowing: Bool) -> UserFollowResult {
        let dictionary = payload as? JSONObject ?? [:]
        return UserFollowResult(
            userId: dictionary.string(["userId", "user_id", "targetUserId", "target_user_id", "id"]) ?? fallbackUserId,
            isFollowing: dictionary.bool(["isFollowing", "is_following", "following"]) ?? fallbackIsFollowing
        )
    }

    static func userRelationship(payload: Any, fallbackUserId: String) -> UserRelationship {
        let dictionary = payload as? JSONObject ?? [:]
        let relationship = dictionary["relationship"] as? JSONObject ?? dictionary
        return UserRelationship(
            userId: relationship.string(["userId", "user_id", "targetUserId", "target_user_id", "id"]) ?? fallbackUserId,
            isFollowing: relationship.bool(["isFollowing", "is_following", "following"]) ?? false,
            isFollower: relationship.bool(["isFollower", "is_follower", "followsMe", "follows_me"]) ?? false,
            isBlocked: relationship.bool(["isBlocked", "is_blocked", "blocked"]) ?? false,
            isMe: relationship.bool(["isMe", "is_me", "own"]) ?? false
        )
    }

    static func userList(payload: Any) -> UserListSnapshot {
        let dictionary = payload as? JSONObject ?? [:]
        let array = unwrapArray(payload) ?? unwrapArray(dictionary["users"] ?? dictionary["items"] ?? dictionary["blockedUsers"] ?? dictionary["blocked_users"]) ?? []
        let users = array.enumerated().compactMap { index, item -> BlockedUser? in
            guard let item = item as? JSONObject else { return nil }
            let user = item["user"] as? JSONObject ?? item["blockedUser"] as? JSONObject ?? item
            let id = user.string(["id", "userId", "user_id", "blockedUserId", "blocked_user_id"])
                ?? item.string(["id", "userId", "user_id", "blockedUserId", "blocked_user_id"])
                ?? "user-\(index)"
            return BlockedUser(
                id: id,
                displayName: user.string(["displayName", "display_name", "nickname", "name"])
                    ?? item.string(["displayName", "display_name", "nickname", "name"]),
                blockedAt: parseDate(item["blockedAt"] ?? item["blocked_at"] ?? item["createdAt"] ?? item["created_at"])
            )
        }
        return UserListSnapshot(users: users, nextCursor: dictionary.string(["nextCursor", "next_cursor", "cursor"]))
    }

    static func reportResult(payload: Any, fallbackType: CommunityReportTargetType, fallbackTargetId: String) -> CommunityReportResult {
        let dictionary = payload as? JSONObject ?? [:]
        let data = dictionary["report"] as? JSONObject ?? dictionary
        let type = CommunityReportTargetType(rawValue: data.string(["targetType", "target_type"]) ?? fallbackType.rawValue) ?? fallbackType
        return CommunityReportResult(
            targetType: type,
            targetId: data.string(["targetId", "target_id", "id"]) ?? fallbackTargetId,
            message: dictionary.string(["message"]) ?? data.string(["message"]),
            hidden: data.bool(["hidden", "isHidden", "is_hidden"]) ?? true
        )
    }

    static func blockedUser(payload: Any, fallbackUserId: String) -> BlockedUser {
        let dictionary = payload as? JSONObject ?? [:]
        let user = dictionary["blockedUser"] as? JSONObject ?? dictionary["user"] as? JSONObject ?? dictionary
        return BlockedUser(
            id: user.string(["id", "userId", "user_id", "blockedUserId", "blocked_user_id"]) ?? fallbackUserId,
            displayName: user.string(["displayName", "display_name", "nickname", "name"]),
            blockedAt: parseDate(user["blockedAt"] ?? user["blocked_at"] ?? dictionary["blockedAt"] ?? dictionary["blocked_at"])
        )
    }

    private static func authorDisplayName(author: JSONObject, dictionary: JSONObject, fallback: String) -> UserDisplayNamePolicy.Resolution {
        let email = author.string(["email"]) ?? dictionary.string(["email", "authorEmail", "author_email"])
        let emailMasked = author.string(["emailMasked", "email_masked", "maskedEmail", "masked_email"])
            ?? dictionary.string(["emailMasked", "email_masked", "maskedEmail", "masked_email"])
        let resolution = UserDisplayNamePolicy.resolve(
            displayName: author.string(["displayName", "display_name"])
                ?? dictionary.string(["displayName", "display_name"]),
            nickname: author.string(["nickname"])
                ?? dictionary.string(["nickname"]),
            profileName: author.string(["profileName", "profile_name", "name"])
                ?? dictionary.string(["profileName", "profile_name", "authorName", "author_name"]),
            emailMasked: emailMasked,
            email: email,
            fallback: fallback
        )
        AppLogger.debug(
            .network,
            "[UserDisplayName] source=\(resolution.source) displayNameExists=\((author.string(["displayName", "display_name"]) ?? dictionary.string(["displayName", "display_name"])) != nil) nicknameExists=\((author.string(["nickname"]) ?? dictionary.string(["nickname"])) != nil) emailMaskedExists=\(emailMasked != nil) isPrivateRelay=\(resolution.isPrivateRelay) selectedName=\(resolution.primaryName)"
        )
        return resolution
    }

    static func vote(dictionary: JSONObject, fallbackScope: String?, fallbackKey: String?) -> CoinVoteSnapshot {
        let bullish = dictionary.int(["bullishCount", "bullish_count", "upCount", "up_count"])
        let bearish = dictionary.int(["bearishCount", "bearish_count", "downCount", "down_count"])
        let total = dictionary.int(["participantCount", "participant_count", "totalParticipants", "total_participants", "totalCount", "total_count", "participants"])
        let bullishRatio = normalizeRatio(dictionary.double(["bullishRatio", "bullish_ratio", "bullishPercentage", "bullish_percentage", "upRatio", "up_ratio"]))
        let bearishRatio = normalizeRatio(dictionary.double(["bearishRatio", "bearish_ratio", "bearishPercentage", "bearish_percentage", "downRatio", "down_ratio"]))
        let hasServerCounts = bullish != nil || bearish != nil || total != nil || bullishRatio != nil || bearishRatio != nil
        return CoinVoteSnapshot(
            bullishCount: bullish ?? 0,
            bearishCount: bearish ?? 0,
            totalCount: total ?? (bullish ?? 0) + (bearish ?? 0),
            bullishRatio: bullishRatio,
            bearishRatio: bearishRatio,
            myVote: normalizedVote(dictionary.string(["myVote", "my_vote", "vote", "direction"])),
            scope: dictionary.string(["scope", "sourceScope"]) ?? fallbackScope,
            key: dictionary.string(["key", "symbol", "targetKey"]) ?? fallbackKey,
            source: dictionary.string(["source", "provider"]),
            updatedAt: parseDate(dictionary["updatedAt"] ?? dictionary["updated_at"] ?? dictionary["asOf"] ?? dictionary["as_of"]),
            hasServerCounts: hasServerCounts
        )
    }

    static func marketPoll(dictionary: JSONObject) -> MarketPollSnapshot {
        let bullish = dictionary.int(["bullishCount", "bullish_count", "upCount", "up_count"])
        let bearish = dictionary.int(["bearishCount", "bearish_count", "downCount", "down_count"])
        let total = dictionary.int(["participantCount", "participant_count", "totalParticipants", "total_participants", "totalCount", "total_count", "participants"])
        let bullishRatio = normalizeRatio(dictionary.double(["bullishRatio", "bullish_ratio", "bullishPercentage", "bullish_percentage", "upRatio", "up_ratio"]))
        let bearishRatio = normalizeRatio(dictionary.double(["bearishRatio", "bearish_ratio", "bearishPercentage", "bearish_percentage", "downRatio", "down_ratio"]))
        let hasServerCounts = bullish != nil || bearish != nil || total != nil || bullishRatio != nil || bearishRatio != nil
        return MarketPollSnapshot(
            bullishCount: bullish ?? 0,
            bearishCount: bearish ?? 0,
            totalCount: total ?? (bullish ?? 0) + (bearish ?? 0),
            bullishRatio: bullishRatio,
            bearishRatio: bearishRatio,
            myVote: normalizedVote(dictionary.string(["myVote", "my_vote", "vote", "direction"])),
            scope: dictionary.string(["scope", "sourceScope"]) ?? "market",
            key: dictionary.string(["key", "targetKey"]) ?? "global",
            source: dictionary.string(["source", "provider"]),
            updatedAt: parseDate(dictionary["updatedAt"] ?? dictionary["updated_at"] ?? dictionary["asOf"] ?? dictionary["as_of"]),
            hasServerCounts: hasServerCounts
        )
    }

    static func marketTrends(dictionary: JSONObject) -> MarketTrendsSnapshot {
        let summary = dictionary["summary"] as? JSONObject ?? [:]
        let mood = dictionary["mood"] as? JSONObject ?? dictionary["marketSentiment"] as? JSONObject ?? [:]
        let seriesDictionary = dictionary["series"] as? JSONObject ?? [:]
        let source = dictionary["source"] as? JSONObject ?? [:]
        let moversDictionary = dictionary["movers"] as? JSONObject ?? [:]
        let series = marketTrendSeries(dictionary: dictionary, seriesDictionary: seriesDictionary)
        if summary.bool(["available"]) == false {
            AppLogger.debug(.network, "[NewsOverviewSectionState] summary=false reason=\(summary.string(["reason", "emptyReason", "empty_reason"]) ?? "available_false")")
        }
        if mood.bool(["available"]) == false {
            AppLogger.debug(.network, "[NewsOverviewSectionState] mood=false reason=\(mood.string(["reason", "emptyReason", "empty_reason"]) ?? "available_false")")
        }
        let halvingDictionary = dictionary["bitcoinHalvingCountdown"] as? JSONObject
        let pollDictionary = (dictionary["marketPoll"] as? JSONObject)
            ?? (dictionary["sentiment"] as? JSONObject)
            ?? (dictionary["vote"] as? JSONObject)
        let events = marketEvents(dictionary["events"] ?? dictionary["majorEvents"] ?? dictionary["major_events"])
        let topNews = marketNewsSummaries(dictionary["topNews"] ?? dictionary["newsSummary"] ?? dictionary["news_summary"] ?? dictionary["headlines"])
        let unavailableReasons = [
            dictionary.stringArray(["unavailableReasons", "unavailable_reasons"]),
            summary.stringArray(["unavailableReasons", "unavailable_reasons"]),
            seriesDictionary.stringArray(["unavailableReasons", "unavailable_reasons"])
        ].flatMap { $0 }
        let snapshot = MarketTrendsSnapshot(
            totalMarketCap: summary.double(["totalMarketCap", "total_market_cap"]) ?? dictionary.double(["totalMarketCap", "total_market_cap"]),
            totalMarketCapChange24h: normalizePercent(dictionary.double(["totalMarketCapChange24h", "total_market_cap_change_24h"])),
            totalVolume24h: summary.double(["volume24h", "totalVolume24h", "total_volume_24h", "totalVolume", "total_volume"]) ?? dictionary.double(["totalVolume24h", "total_volume_24h", "volume24h", "totalVolume", "total_volume"]),
            btcDominance: normalizePercent(summary.double(["btcDominance", "btc_dominance"]) ?? dictionary.double(["btcDominance", "btc_dominance"])),
            ethDominance: normalizePercent(summary.double(["ethDominance", "eth_dominance"]) ?? dictionary.double(["ethDominance", "eth_dominance"])),
            fearGreedIndex: mood.int(["score", "fearGreedIndex", "fear_greed_index"]) ?? summary.int(["fearGreedIndex", "fear_greed_index"]) ?? dictionary.int(["fearGreedIndex", "fear_greed_index"]),
            altcoinIndex: summary.int(["altcoinIndex", "altcoin_index"]) ?? dictionary.int(["altcoinIndex", "altcoin_index"]),
            btcLongShortRatio: normalizePercent(dictionary.double(["btcLongShortRatio", "btc_long_short_ratio"])),
            marketPoll: pollDictionary.map(marketPoll),
            movers: MarketMoversSnapshot(
                topGainers: marketMovers(moversDictionary["topGainers"] ?? moversDictionary["top_gainers"]),
                topLosers: marketMovers(moversDictionary["topLosers"] ?? moversDictionary["top_losers"]),
                topVolume: marketMovers(moversDictionary["topVolume"] ?? moversDictionary["top_volume"])
            ),
            marketCapVolumeSeries: series,
            range: dictionary.string(["range"]) ?? seriesDictionary.string(["range"]),
            currency: summary.string(["currency"]) ?? dictionary.string(["currency"]) ?? seriesDictionary.string(["currency"]),
            events: events,
            topNews: topNews,
            bitcoinHalvingCountdown: halvingDictionary.map {
                BitcoinHalvingCountdown(
                    targetDate: parseDate($0["targetDate"]),
                    days: $0.int(["days"]),
                    hours: $0.int(["hours"]),
                    minutes: $0.int(["minutes"]),
                    seconds: $0.int(["seconds"])
                )
            },
            latestHeadline: summary.string(["headline", "title", "titleKo", "title_ko"]) ?? dictionary.string(["latestHeadline", "headline"]),
            summaryDescription: summary.string(["descriptionKo", "description_ko", "translatedDescription", "translated_description", "description", "summary"]) ?? dictionary.string(["summaryDescription", "summary_description"]),
            eventsEmptyReason: (dictionary["eventsState"] as? JSONObject)?.string(["emptyReason", "empty_reason", "reason"]),
            unavailableReasons: unavailableReasons,
            dataProvider: source.string(["primary"]) ?? dictionary.string(["dataProvider", "provider"]),
            fallbackUsed: source.bool(["fallbackUsed", "fallback_used"]) ?? dictionary.bool(["fallbackUsed", "fallback_used"]) ?? false,
            asOf: parseDate(dictionary["asOf"] ?? dictionary["as_of"] ?? dictionary["updatedAt"] ?? dictionary["updated_at"])
        )
        AppLogger.debug(.network, "[MarketDataAPI] dashboard status=decoded source=\(snapshot.dataProvider ?? "unknown") updatedAt=\(snapshot.asOf.map(String.init(describing:)) ?? "nil") availableMetrics=\(marketAvailableMetrics(snapshot).joined(separator: ","))")
        AppLogger.debug(.network, "[MarketTrendAPI] range=\(snapshot.range ?? "nil") pointCount=\(snapshot.marketCapVolumeSeries.count) availability=\(snapshot.marketCapVolumeSeries.isEmpty ? "empty" : "available")")
        AppLogger.debug(.network, "[MarketDataResponse] status=decoded availableMetrics=\(marketAvailableMetrics(snapshot).joined(separator: ",")) unavailableReasons=\(snapshot.unavailableReasons.joined(separator: "|")) source=\(snapshot.dataProvider ?? "unknown") updatedAt=\(snapshot.asOf.map(String.init(describing:)) ?? "nil")")
        AppLogger.debug(.network, "[MarketTrendResponse] range=\(snapshot.range ?? "nil") pointCount=\(snapshot.marketCapVolumeSeries.count) source=\(snapshot.dataProvider ?? "unknown") emptyReason=\(snapshot.marketCapVolumeSeries.isEmpty ? "no_points" : "none") availability=\(snapshot.marketCapVolumeSeries.isEmpty ? "empty" : "available")")
        return snapshot
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
        let unifiedPoints = unwrapArray(seriesDictionary["points"] ?? dictionary["points"] ?? dictionary["trendPoints"] ?? dictionary["trend_points"])
        if let unifiedPoints {
            return unifiedPoints.enumerated().compactMap { index, item -> MarketTrendPoint? in
                guard let item = item as? JSONObject else { return nil }
                let marketCap = item.double(["totalMarketCap", "total_market_cap", "marketCap", "market_cap"])
                let volume = item.double(["totalVolume", "total_volume", "totalVolume24h", "total_volume_24h", "volume", "volume24h"])
                let btcDominance = normalizePercent(item.double(["btcDominance", "btc_dominance"]))
                let ethDominance = normalizePercent(item.double(["ethDominance", "eth_dominance"]))
                let fearGreed = item.double(["fearGreedIndex", "fear_greed_index"])
                guard marketCap != nil || volume != nil || btcDominance != nil || ethDominance != nil || fearGreed != nil else {
                    return nil
                }
                return MarketTrendPoint(
                    id: item.string(["id"]) ?? "trend-\(index)",
                    date: parseDate(item["date"] ?? item["time"] ?? item["timestamp"]),
                    marketCap: marketCap,
                    volume: volume,
                    btcDominance: btcDominance,
                    ethDominance: ethDominance,
                    fearGreedIndex: fearGreed
                )
            }
        }

        let marketCapItems = unwrapArray(seriesDictionary["marketCap"] ?? seriesDictionary["market_cap"])
        let volumeItems = unwrapArray(seriesDictionary["volume"])
        let btcDominanceItems = unwrapArray(seriesDictionary["btcDominance"] ?? seriesDictionary["btc_dominance"])
        let ethDominanceItems = unwrapArray(seriesDictionary["ethDominance"] ?? seriesDictionary["eth_dominance"])
        let fearGreedItems = unwrapArray(seriesDictionary["fearGreedIndex"] ?? seriesDictionary["fear_greed_index"])
        if marketCapItems != nil || volumeItems != nil || btcDominanceItems != nil || ethDominanceItems != nil || fearGreedItems != nil {
            let count = [
                marketCapItems?.count ?? 0,
                volumeItems?.count ?? 0,
                btcDominanceItems?.count ?? 0,
                ethDominanceItems?.count ?? 0,
                fearGreedItems?.count ?? 0
            ].max() ?? 0
            guard count > 0 else { return [] }
            return (0..<count).compactMap { index in
                let marketCapItem = marketCapItems?.indices.contains(index) == true ? marketCapItems?[index] : nil
                let volumeItem = volumeItems?.indices.contains(index) == true ? volumeItems?[index] : nil
                let btcItem = btcDominanceItems?.indices.contains(index) == true ? btcDominanceItems?[index] : nil
                let ethItem = ethDominanceItems?.indices.contains(index) == true ? ethDominanceItems?[index] : nil
                let fearGreedItem = fearGreedItems?.indices.contains(index) == true ? fearGreedItems?[index] : nil
                let marketCapDictionary = marketCapItem as? JSONObject
                let volumeDictionary = volumeItem as? JSONObject
                let btcDictionary = btcItem as? JSONObject
                let ethDictionary = ethItem as? JSONObject
                let fearGreedDictionary = fearGreedItem as? JSONObject
                let marketCap = numericSeriesValue(
                    marketCapItem,
                    keys: ["marketCap", "market_cap", "value", "y"]
                )
                let volume = numericSeriesValue(
                    volumeItem,
                    keys: ["volume", "tradeVolume", "trade_volume", "value", "y"]
                ) ?? marketCapDictionary?.double(["volume", "tradeVolume", "trade_volume"])
                let btcDominance = normalizePercent(numericSeriesValue(btcItem, keys: ["btcDominance", "btc_dominance", "value", "y"]))
                let ethDominance = normalizePercent(numericSeriesValue(ethItem, keys: ["ethDominance", "eth_dominance", "value", "y"]))
                let fearGreed = numericSeriesValue(fearGreedItem, keys: ["fearGreedIndex", "fear_greed_index", "value", "y"])
                guard marketCap != nil || volume != nil || btcDominance != nil || ethDominance != nil || fearGreed != nil else { return nil }
                return MarketTrendPoint(
                    id: marketCapDictionary?.string(["id"]) ?? volumeDictionary?.string(["id"]) ?? btcDictionary?.string(["id"]) ?? "trend-\(index)",
                    date: parseDate(
                        marketCapDictionary?["date"] ?? marketCapDictionary?["time"] ?? marketCapDictionary?["timestamp"]
                            ?? volumeDictionary?["date"] ?? volumeDictionary?["time"] ?? volumeDictionary?["timestamp"]
                            ?? btcDictionary?["date"] ?? btcDictionary?["time"] ?? btcDictionary?["timestamp"]
                            ?? ethDictionary?["date"] ?? ethDictionary?["time"] ?? ethDictionary?["timestamp"]
                            ?? fearGreedDictionary?["date"] ?? fearGreedDictionary?["time"] ?? fearGreedDictionary?["timestamp"]
                    ),
                    marketCap: marketCap,
                    volume: volume,
                    btcDominance: btcDominance,
                    ethDominance: ethDominance,
                    fearGreedIndex: fearGreed
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
                    marketCap: item.double(["totalMarketCap", "total_market_cap", "marketCap", "market_cap"]),
                    volume: item.double(["totalVolume", "total_volume", "volume", "tradeVolume", "trade_volume"]),
                    btcDominance: normalizePercent(item.double(["btcDominance", "btc_dominance"])),
                    ethDominance: normalizePercent(item.double(["ethDominance", "eth_dominance"])),
                    fearGreedIndex: item.double(["fearGreedIndex", "fear_greed_index"])
                )
            }
    }

    private static func marketEvents(_ rawValue: Any?) -> [MarketEventSnapshot] {
        (unwrapArray(rawValue) ?? []).enumerated().compactMap { index, item -> MarketEventSnapshot? in
            guard let dictionary = item as? JSONObject,
                  let title = dictionary.string(["title", "name"]) else {
                return nil
            }
            return MarketEventSnapshot(
                id: dictionary.string(["id"]) ?? "event-\(index)",
                title: title,
                category: dictionary.string(["category", "type"]),
                date: parseDate(dictionary["time"] ?? dictionary["date"] ?? dictionary["timestamp"]),
                importance: dictionary.string(["importance", "priority", "level"]),
                source: dictionary.string(["source", "provider"]),
                url: url(dictionary.string(["url", "link"]))
            )
        }
    }

    private static func marketNewsSummaries(_ rawValue: Any?) -> [MarketNewsSummary] {
        (unwrapArray(rawValue) ?? []).enumerated().compactMap { index, item -> MarketNewsSummary? in
            guard let dictionary = item as? JSONObject else {
                return nil
            }
            let titleResolution = localizedText(
                dictionary: dictionary,
                koKeys: ["titleKo", "title_ko", "translatedTitle", "translated_title"],
                localizedKeys: ["localizedTitle", "localized_title"],
                fallbackKeys: ["title", "headline"]
            )
            guard let title = titleResolution.text else { return nil }
            let summaryResolution = localizedText(
                dictionary: dictionary,
                koKeys: ["summaryKo", "summary_ko", "translatedSummary", "translated_summary"],
                localizedKeys: ["localizedSummary", "localized_summary"],
                fallbackKeys: ["summary", "description", "excerpt"]
            )
            return MarketNewsSummary(
                id: dictionary.string(["id", "newsId", "news_id"]) ?? "market-news-\(index)",
                title: title,
                summary: summaryResolution.text,
                originalTitle: cleanHTML(dictionary.string(["originalTitle", "original_title", "title", "headline"])) ?? title,
                originalSummary: cleanHTML(dictionary.string(["originalSummary", "original_summary", "summary", "description", "excerpt"])),
                translatedTitle: titleResolution.fallbackUsed ? nil : title,
                translatedSummary: summaryResolution.fallbackUsed ? nil : summaryResolution.text,
                source: dictionary.string(["source", "provider"]),
                publishedAt: parseDate(dictionary["publishedAt"] ?? dictionary["published_at"] ?? dictionary["createdAt"] ?? dictionary["timestamp"]),
                renderLanguage: titleResolution.language ?? summaryResolution.language ?? "unknown",
                translationState: titleResolution.fallbackUsed || summaryResolution.fallbackUsed ? .originalOnly : .translated,
                fallbackUsed: titleResolution.fallbackUsed || summaryResolution.fallbackUsed
            )
        }
    }

    private static func coinDescription(dictionary: JSONObject) -> (text: String?, language: String, notice: String?) {
        let descriptionDictionary = dictionary["description"] as? JSONObject
        let localizationDictionary = dictionary["localization"] as? JSONObject
        let plainTextDictionary = dictionary["plainText"] as? JSONObject
            ?? dictionary["plain_text"] as? JSONObject
        let translatedDictionary = dictionary["translatedDescription"] as? JSONObject
            ?? dictionary["translated_description"] as? JSONObject
        let koCandidates = [
            cleanHTML(descriptionDictionary?.string(["plainTextKo", "plain_text_ko"])),
            cleanHTML(plainTextDictionary?.string(["ko"])),
            cleanHTML(dictionary.string(["plainTextKo", "plain_text_ko"])),
            cleanHTML(descriptionDictionary?.string(["ko"])),
            cleanHTML(localizationDictionary?.string(["ko"])),
            cleanHTML(dictionary.string(["descriptionKo", "description_ko"])),
            cleanHTML(translatedDictionary?.string(["ko"])),
            cleanHTML(dictionary.string(["translatedDescription", "translated_description"]))
        ]
        if let ko = koCandidates.compactMap({ $0?.trimmedNonEmpty }).first {
            return (ko, "ko", nil)
        }
        let english = cleanHTML(
            descriptionDictionary?.string(["plainTextEn", "plain_text_en"])
                ?? plainTextDictionary?.string(["en"])
                ?? dictionary.string(["plainTextEn", "plain_text_en"])
                ?? descriptionDictionary?.string(["en"])
                ?? dictionary.string(["descriptionEn", "description_en", "rawDescription", "raw_description", "description"])
        )
        if let english, english.isEmpty == false {
            return (english, "en", "한국어 설명 준비 중 · 원문 제공")
        }
        return (nil, "none", nil)
    }

    private static func localizedText(
        dictionary: JSONObject,
        koKeys: [String],
        localizedKeys: [String],
        fallbackKeys: [String]
    ) -> (text: String?, language: String?, fallbackUsed: Bool) {
        if let ko = cleanHTML(dictionary.string(koKeys)), ko.isEmpty == false {
            return (ko, "ko", false)
        }
        for key in localizedKeys {
            if let localized = dictionary[key] as? JSONObject,
               let ko = cleanHTML(localized.string(["ko"])),
               ko.isEmpty == false {
                return (ko, "ko", false)
            }
        }
        let fallback = cleanHTML(dictionary.string(fallbackKeys))
        if let fallback, looksKorean(fallback) {
            return (fallback, "ko", false)
        }
        return (fallback, fallback == nil ? nil : "en", fallback != nil)
    }

    private static func looksKorean(_ text: String) -> Bool {
        text.range(of: #"[가-힣]"#, options: .regularExpression) != nil
    }

    static func cleanHTML(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        value = value
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p\s*>"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<p[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        value = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func marketAvailableMetrics(_ snapshot: MarketTrendsSnapshot) -> [String] {
        [
            snapshot.totalMarketCap == nil ? nil : "totalMarketCap",
            snapshot.totalVolume24h == nil ? nil : "totalVolume24h",
            snapshot.btcDominance == nil ? nil : "btcDominance",
            snapshot.ethDominance == nil ? nil : "ethDominance",
            snapshot.fearGreedIndex == nil ? nil : "fearGreedIndex",
            snapshot.altcoinIndex == nil ? nil : "altcoinIndex"
        ].compactMap { $0 }
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

    private static func normalizeRatio(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return value > 1 ? value / 100 : value
    }

    private static func normalizePercent(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return abs(value) <= 1 ? value * 100 : value
    }

    private static func normalizedVote(_ value: String?) -> String? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bullish", "up", "rise", "positive", "상승":
            return "bullish"
        case "bearish", "down", "fall", "negative", "하락":
            return "bearish"
        default:
            return value
        }
    }

    static func rawPreview(_ value: Any, limit: Int = 700) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              var string = String(data: data, encoding: .utf8) else {
            return String(describing: value).prefix(limit).description
        }
        if string.count > limit {
            string = String(string.prefix(limit)) + "…"
        }
        return string
    }

    private static func bodyShape(_ dictionary: JSONObject) -> String {
        dictionary.keys.sorted().joined(separator: ",")
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
            return iso8601.date(from: string) ?? dateOnly.date(from: string)
        default:
            return nil
        }
    }

    private static func parseDateArray(_ rawValue: Any?) -> [Date]? {
        guard let values = unwrapArray(rawValue) else { return nil }
        let dates = values.compactMap(parseDate)
        return dates.isEmpty ? nil : dates
    }

    private static let iso8601WithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
