import Foundation

typealias JSONObject = [String: Any]

enum RequestAccessRequirement: String {
    case publicAccess = "public"
    case authenticatedRequired = "authenticated"
}

enum NetworkServiceError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, String, RemoteErrorCategory)
    case authenticationRequired
    case transportError(String, RemoteErrorCategory)
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "잘못된 서버 경로입니다: \(path)"
        case .invalidResponse:
            return "서버 응답을 확인할 수 없어요."
        case .httpError(_, let message, _):
            return message
        case .authenticationRequired:
            return "로그인이 필요한 요청이에요."
        case .transportError(let message, _):
            return message
        case .parsingFailed(let message):
            return message
        }
    }

    var errorCategory: RemoteErrorCategory {
        switch self {
        case .httpError(_, _, let category):
            return category
        case .transportError(_, let category):
            return category
        case .authenticationRequired:
            return .authenticationFailed
        default:
            return .unknown
        }
    }
}

struct ResponseMeta: Equatable, Codable {
    let fetchedAt: Date?
    let isStale: Bool
    let warningMessage: String?
    let partialFailureMessage: String?
    let isChartAvailable: Bool?
    let isOrderBookAvailable: Bool?
    let isTradesAvailable: Bool?
    let unavailableReason: String?

    nonisolated init(
        fetchedAt: Date?,
        isStale: Bool,
        warningMessage: String?,
        partialFailureMessage: String?,
        isChartAvailable: Bool? = nil,
        isOrderBookAvailable: Bool? = nil,
        isTradesAvailable: Bool? = nil,
        unavailableReason: String? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.isStale = isStale
        self.warningMessage = warningMessage
        self.partialFailureMessage = partialFailureMessage
        self.isChartAvailable = isChartAvailable
        self.isOrderBookAvailable = isOrderBookAvailable
        self.isTradesAvailable = isTradesAvailable
        self.unavailableReason = unavailableReason
    }

    static let empty = ResponseMeta(
        fetchedAt: nil,
        isStale: false,
        warningMessage: nil,
        partialFailureMessage: nil
    )
}

enum BuildConfiguration: String {
    case debug
    case release

    static var current: BuildConfiguration {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }
}

enum AppEnvironment: String {
    case development = "Dev"
    case production = "Prod"

    static var current: AppEnvironment {
        AppRuntimeConfiguration.live.environment
    }

    static func resolve(
        environment: [String: String],
        buildConfiguration: BuildConfiguration = .current
    ) -> AppEnvironment {
        if let configuredValue = runtimeSetting(
            in: environment,
            keys: "APP_ENV", "CRYPTORY_APP_ENV", "CRYPTORY_ENVIRONMENT"
        ) {
            switch configuredValue.lowercased() {
            case "dev", "development", "local", "debug":
                return .development
            case "production", "prod", "release":
                return .production
            default:
                break
            }
        }

        switch buildConfiguration {
        case .debug:
            return .development
        case .release:
            return .production
        }
    }
}

enum AppConfig {
    static var current: AppRuntimeConfiguration {
        AppRuntimeConfiguration.live
    }
}

struct AppRuntimeConfiguration {
    let environment: AppEnvironment
    let restBaseURL: URL
    let webSocketBaseURL: URL
    let webBaseURL: URL
    let publicMarketWebSocketURL: URL
    let privateTradingWebSocketURL: URL

    static let live: AppRuntimeConfiguration = resolve(
        environment: ProcessInfo.processInfo.environment,
        includeBundleSettings: true
    )

    static func resolve(
        environment: [String: String],
        buildConfiguration: BuildConfiguration = .current,
        includeBundleSettings: Bool = false
    ) -> AppRuntimeConfiguration {
        let values = mergedRuntimeSettings(
            environment: environment,
            includeBundleSettings: includeBundleSettings
        )
        let resolvedEnvironment = AppEnvironment.resolve(
            environment: values,
            buildConfiguration: buildConfiguration
        )
        let publicWebSocketPath = runtimeSetting(
            in: values,
            keys: "PUBLIC_WS_PATH", "CRYPTORY_PUBLIC_WS_PATH"
        ) ?? "/ws/market"
        let privateWebSocketPath = runtimeSetting(
            in: values,
            keys: "PRIVATE_WS_PATH", "CRYPTORY_PRIVATE_WS_PATH"
        ) ?? "/ws/trading"

        let defaultRESTBaseURL = makeDefaultRESTBaseURL(
            for: resolvedEnvironment,
            environment: values
        )
        let restBaseURL = sanitizedURL(
            string: runtimeSetting(in: values, keys: "API_BASE_URL", "CRYPTORY_API_BASE_URL")
                ?? environmentSpecificRESTBaseURLString(for: resolvedEnvironment, environment: values),
            fallback: defaultRESTBaseURL,
            label: "REST base URL"
        )
        let defaultWebSocketBaseURL = deriveWebSocketBaseURL(from: restBaseURL)
        let webSocketBaseURL = sanitizedURL(
            string: runtimeSetting(in: values, keys: "WS_BASE_URL", "CRYPTORY_WS_BASE_URL")
                ?? environmentSpecificWebSocketBaseURLString(for: resolvedEnvironment, environment: values),
            fallback: defaultWebSocketBaseURL,
            label: "WebSocket base URL"
        )
        let webBaseURL = sanitizedURL(
            string: runtimeSetting(in: values, keys: "WEB_BASE_URL", "CRYPTORY_WEB_BASE_URL")
                ?? environmentSpecificWebBaseURLString(for: resolvedEnvironment, environment: values),
            fallback: restBaseURL,
            label: "Web base URL"
        )
        let publicMarketWebSocketURL = sanitizedURL(
            string: runtimeSetting(in: values, keys: "PUBLIC_WS_URL", "CRYPTORY_PUBLIC_WS_URL"),
            fallback: webSocketBaseURL.appendingEndpointPath(publicWebSocketPath),
            label: "Public WebSocket URL"
        )
        let privateTradingWebSocketURL = sanitizedURL(
            string: runtimeSetting(in: values, keys: "PRIVATE_WS_URL", "CRYPTORY_PRIVATE_WS_URL"),
            fallback: webSocketBaseURL.appendingEndpointPath(privateWebSocketPath),
            label: "Private WebSocket URL"
        )

        let configuration = AppRuntimeConfiguration(
            environment: resolvedEnvironment,
            restBaseURL: restBaseURL,
            webSocketBaseURL: webSocketBaseURL,
            webBaseURL: webBaseURL,
            publicMarketWebSocketURL: publicMarketWebSocketURL,
            privateTradingWebSocketURL: privateTradingWebSocketURL
        )

        AppLogger.configuration("Environment -> \(configuration.environment.rawValue)")
        AppLogger.configuration("REST base URL -> \(configuration.restBaseURL.absoluteString)")
        AppLogger.configuration("Web base URL -> \(configuration.webBaseURL.absoluteString)")
        AppLogger.configuration("Public WS URL -> \(configuration.publicMarketWebSocketURL.absoluteString)")
        AppLogger.configuration("Private WS URL -> \(configuration.privateTradingWebSocketURL.absoluteString)")

        return configuration
    }

    private static func makeDefaultRESTBaseURL(
        for environment: AppEnvironment,
        environment values: [String: String]
    ) -> URL {
        let defaultString: String
        switch environment {
        case .development:
            let host = runtimeSetting(
                in: values,
                keys: "LOCAL_SERVER_HOST", "CRYPTORY_LOCAL_SERVER_HOST"
            ) ?? "127.0.0.1"
            let port = runtimeSetting(
                in: values,
                keys: "LOCAL_SERVER_PORT", "CRYPTORY_LOCAL_SERVER_PORT"
            ) ?? "3002"
            defaultString = "http://\(host):\(port)"
        case .production:
            defaultString = runtimeSetting(
                in: values,
                keys: "PROD_API_BASE_URL", "PRODUCTION_API_BASE_URL", "CRYPTORY_PRODUCTION_API_BASE_URL"
            ) ?? "http://crytory.duckdns.org"
        }

        return URL(string: defaultString) ?? URL(string: "http://crytory.duckdns.org")!
    }

    private static func environmentSpecificRESTBaseURLString(
        for environment: AppEnvironment,
        environment values: [String: String]
    ) -> String? {
        switch environment {
        case .development:
            return runtimeSetting(
                in: values,
                keys: "DEV_API_BASE_URL", "DEVELOPMENT_API_BASE_URL", "LOCAL_API_BASE_URL", "CRYPTORY_LOCAL_API_BASE_URL"
            )
        case .production:
            return runtimeSetting(
                in: values,
                keys: "PROD_API_BASE_URL", "PRODUCTION_API_BASE_URL", "CRYPTORY_PRODUCTION_API_BASE_URL"
            )
        }
    }

    private static func environmentSpecificWebSocketBaseURLString(
        for environment: AppEnvironment,
        environment values: [String: String]
    ) -> String? {
        switch environment {
        case .development:
            return runtimeSetting(
                in: values,
                keys: "DEV_WS_BASE_URL", "DEVELOPMENT_WS_BASE_URL", "LOCAL_WS_BASE_URL", "CRYPTORY_LOCAL_WS_BASE_URL"
            )
        case .production:
            return runtimeSetting(
                in: values,
                keys: "PROD_WS_BASE_URL", "PRODUCTION_WS_BASE_URL", "CRYPTORY_PRODUCTION_WS_BASE_URL"
            )
        }
    }

    private static func environmentSpecificWebBaseURLString(
        for environment: AppEnvironment,
        environment values: [String: String]
    ) -> String? {
        switch environment {
        case .development:
            return runtimeSetting(
                in: values,
                keys: "DEV_WEB_BASE_URL", "DEVELOPMENT_WEB_BASE_URL", "LOCAL_WEB_BASE_URL", "CRYPTORY_LOCAL_WEB_BASE_URL"
            )
        case .production:
            return runtimeSetting(
                in: values,
                keys: "PROD_WEB_BASE_URL", "PRODUCTION_WEB_BASE_URL", "CRYPTORY_PRODUCTION_WEB_BASE_URL"
            )
        }
    }

    private static func deriveWebSocketBaseURL(from restBaseURL: URL) -> URL {
        guard var components = URLComponents(url: restBaseURL, resolvingAgainstBaseURL: false) else {
            return restBaseURL
        }

        switch components.scheme {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case nil:
            components.scheme = "wss"
        default:
            break
        }

        return components.url ?? restBaseURL
    }

    private static func sanitizedURL(string: String?, fallback: URL, label: String) -> URL {
        guard let string else { return fallback }
        guard let url = URL(string: string) else {
            AppLogger.debug(.network, "Invalid \(label) -> \(string). Fallback \(fallback.absoluteString)")
            return fallback
        }
        return url
    }
}

private func mergedRuntimeSettings(
    environment: [String: String],
    includeBundleSettings: Bool
) -> [String: String] {
    var values: [String: String] = includeBundleSettings ? bundleRuntimeSettings() : [:]
    values.merge(environment) { _, runtimeValue in runtimeValue }
    return values
}

private func bundleRuntimeSettings() -> [String: String] {
    guard let infoDictionary = Bundle.main.infoDictionary else {
        return [:]
    }

    var values: [String: String] = [:]
    for (key, value) in infoDictionary {
        guard let stringValue = value as? String,
              let resolvedValue = stringValue.trimmedNonEmpty,
              resolvedValue.hasPrefix("$(") == false else {
            continue
        }
        values[key] = resolvedValue
    }
    return values
}

private func runtimeSetting(in values: [String: String], keys: String...) -> String? {
    runtimeSetting(in: values, keys: keys)
}

private func runtimeSetting(in values: [String: String], keys: [String]) -> String? {
    for key in keys {
        if let value = values[key]?.trimmedNonEmpty {
            return value
        }
    }
    return nil
}

struct TransportFailureDetails {
    let message: String
    let category: RemoteErrorCategory
    let shouldRetry: Bool
    let kind: TransportFailureKind
}

enum TransportFailureKind: String {
    case cancelled
    case invalidURL
    case authentication
    case timeout
    case connectivity
    case security
    case unknown
}

private struct ServerErrorDetails {
    let message: String
    let category: RemoteErrorCategory
    let mappedCode: String
}

enum TransportFailureMapper {
    static func map(_ error: Error) -> TransportFailureDetails {
        if error is CancellationError {
            return TransportFailureDetails(
                message: "요청이 취소되었어요.",
                category: .unknown,
                shouldRetry: false,
                kind: .cancelled
            )
        }

        if let networkError = error as? NetworkServiceError {
            return TransportFailureDetails(
                message: networkError.errorDescription ?? "네트워크 요청에 실패했어요.",
                category: networkError.errorCategory,
                shouldRetry: false,
                kind: .unknown
            )
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            switch code {
            case .badURL, .unsupportedURL, .cannotFindHost:
                return TransportFailureDetails(
                    message: "서버 주소를 확인할 수 없어요. 현재 앱 환경 설정을 확인해주세요.",
                    category: .connectivity,
                    shouldRetry: false,
                    kind: .invalidURL
                )
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return TransportFailureDetails(
                    message: "인증에 실패했어요. 다시 로그인해주세요.",
                    category: .authenticationFailed,
                    shouldRetry: false,
                    kind: .authentication
                )
            case .timedOut:
                return TransportFailureDetails(
                    message: "서버 응답이 지연되고 있어요. 잠시 후 다시 시도해주세요.",
                    category: .connectivity,
                    shouldRetry: true,
                    kind: .timeout
                )
            case .cancelled:
                return TransportFailureDetails(
                    message: "요청이 취소되었어요.",
                    category: .unknown,
                    shouldRetry: false,
                    kind: .cancelled
                )
            case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed:
                return TransportFailureDetails(
                    message: "서버에 연결할 수 없어요. 네트워크와 서버 주소를 확인해주세요.",
                    category: .connectivity,
                    shouldRetry: true,
                    kind: .connectivity
                )
            case .secureConnectionFailed,
                 .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .clientCertificateRejected,
                 .clientCertificateRequired:
                return TransportFailureDetails(
                    message: "보안 연결을 확인할 수 없어요. 서버 인증서를 확인해주세요.",
                    category: .connectivity,
                    shouldRetry: false,
                    kind: .security
                )
            default:
                return TransportFailureDetails(
                    message: nsError.localizedDescription,
                    category: .connectivity,
                    shouldRetry: true,
                    kind: .connectivity
                )
            }
        }

        return TransportFailureDetails(
            message: nsError.localizedDescription,
            category: .unknown,
            shouldRetry: true,
            kind: .unknown
        )
    }
}

struct MarketCatalogSnapshot: Codable {
    let exchange: Exchange
    let markets: [CoinInfo]
    let supportedIntervalsBySymbol: [String: [String]]
    let meta: ResponseMeta
    let filteredSymbols: [String]

    init(
        exchange: Exchange,
        markets: [CoinInfo],
        supportedIntervalsBySymbol: [String: [String]],
        meta: ResponseMeta,
        filteredSymbols: [String] = []
    ) {
        self.exchange = exchange
        self.markets = markets
        self.supportedIntervalsBySymbol = supportedIntervalsBySymbol
        self.meta = meta
        self.filteredSymbols = filteredSymbols
    }
}

struct MarketTickerSnapshot: Codable {
    let exchange: Exchange
    let coins: [CoinInfo]
    let tickers: [String: TickerData]
    let meta: ResponseMeta
    let filteredSymbols: [String]

    init(
        exchange: Exchange,
        coins: [CoinInfo] = [],
        tickers: [String: TickerData],
        meta: ResponseMeta,
        filteredSymbols: [String] = []
    ) {
        self.exchange = exchange
        self.coins = coins
        self.tickers = tickers
        self.meta = meta
        self.filteredSymbols = filteredSymbols
    }
}

struct OrderbookSnapshot {
    let exchange: Exchange
    let symbol: String
    let orderbook: OrderbookData
    let meta: ResponseMeta
}

struct PublicTradesSnapshot {
    let exchange: Exchange
    let symbol: String
    let trades: [PublicTrade]
    let meta: ResponseMeta
}

struct CandleSnapshot {
    let exchange: Exchange
    let symbol: String
    let interval: String
    let candles: [CandleData]
    let meta: ResponseMeta
}

struct OrderRecordsSnapshot {
    let exchange: Exchange
    let orders: [OrderRecord]
    let meta: ResponseMeta
}

struct TradeFillsSnapshot {
    let exchange: Exchange
    let fills: [TradeFill]
    let meta: ResponseMeta
}

struct PortfolioHistorySnapshot {
    let exchange: Exchange
    let items: [PortfolioHistoryItem]
    let meta: ResponseMeta
}

struct ExchangeConnectionsSnapshot {
    let connections: [ExchangeConnection]
    let meta: ResponseMeta
}

protocol MarketSnapshotCacheStoring {
    func loadCatalogSnapshot(for exchange: Exchange) -> MarketCatalogSnapshot?
    func saveCatalogSnapshot(_ snapshot: MarketCatalogSnapshot)
    func loadTickerSnapshot(for exchange: Exchange) -> MarketTickerSnapshot?
    func saveTickerSnapshot(_ snapshot: MarketTickerSnapshot)
}

final class UserDefaultsMarketSnapshotCacheStore: MarketSnapshotCacheStoring {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadCatalogSnapshot(for exchange: Exchange) -> MarketCatalogSnapshot? {
        decode(MarketCatalogSnapshot.self, forKey: key(prefix: "market.catalog", exchange: exchange))
    }

    func saveCatalogSnapshot(_ snapshot: MarketCatalogSnapshot) {
        encode(snapshot, forKey: key(prefix: "market.catalog", exchange: snapshot.exchange))
    }

    func loadTickerSnapshot(for exchange: Exchange) -> MarketTickerSnapshot? {
        decode(MarketTickerSnapshot.self, forKey: key(prefix: "market.tickers", exchange: exchange))
    }

    func saveTickerSnapshot(_ snapshot: MarketTickerSnapshot) {
        let sanitizedTickers = snapshot.tickers.mapValues { ticker -> TickerData in
            var sanitizedTicker = ticker
            sanitizedTicker.flash = nil
            sanitizedTicker.delivery = .snapshot
            return sanitizedTicker
        }
        encode(
            MarketTickerSnapshot(
                exchange: snapshot.exchange,
                coins: snapshot.coins,
                tickers: sanitizedTickers,
                meta: snapshot.meta,
                filteredSymbols: snapshot.filteredSymbols
            ),
            forKey: key(prefix: "market.tickers", exchange: snapshot.exchange)
        )
    }

    private func key(prefix: String, exchange: Exchange) -> String {
        "\(prefix).\(exchange.rawValue)"
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}

struct APIConfiguration {
    let baseURL: String
    let loginPath: String
    let registerPath: String
    let refreshPath: String
    let googleLoginPath: String
    let appleLoginPath: String
    let logoutPath: String
    let deleteAccountPath: String
    let marketMarketsPath: String
    let marketTickersPath: String
    let marketOrderbookPath: String
    let marketTradesPath: String
    let marketCandlesPath: String
    let tradingChancePath: String
    let tradingOrdersPath: String
    let tradingOpenOrdersPath: String
    let tradingFillsPath: String
    let portfolioSummaryPath: String
    let portfolioHistoryPath: String
    let kimchiPremiumPath: String
    let exchangeConnectionsPath: String
    let exchangeConnectionsCreateEnabled: Bool
    let exchangeConnectionsUpdateEnabled: Bool
    let exchangeConnectionsDeleteEnabled: Bool

    init(
        baseURL: String,
        loginPath: String,
        registerPath: String = "/api/v1/auth/register",
        refreshPath: String = "/api/v1/auth/refresh",
        googleLoginPath: String = "/api/v1/auth/google",
        appleLoginPath: String = "/api/v1/auth/apple",
        logoutPath: String = "/api/v1/auth/logout",
        deleteAccountPath: String = "/api/v1/auth/me",
        marketMarketsPath: String,
        marketTickersPath: String,
        marketOrderbookPath: String,
        marketTradesPath: String,
        marketCandlesPath: String,
        tradingChancePath: String,
        tradingOrdersPath: String,
        tradingOpenOrdersPath: String,
        tradingFillsPath: String,
        portfolioSummaryPath: String,
        portfolioHistoryPath: String,
        kimchiPremiumPath: String,
        exchangeConnectionsPath: String,
        exchangeConnectionsCreateEnabled: Bool,
        exchangeConnectionsUpdateEnabled: Bool,
        exchangeConnectionsDeleteEnabled: Bool
    ) {
        self.baseURL = baseURL
        self.loginPath = loginPath
        self.registerPath = registerPath
        self.refreshPath = refreshPath
        self.googleLoginPath = googleLoginPath
        self.appleLoginPath = appleLoginPath
        self.logoutPath = logoutPath
        self.deleteAccountPath = deleteAccountPath
        self.marketMarketsPath = marketMarketsPath
        self.marketTickersPath = marketTickersPath
        self.marketOrderbookPath = marketOrderbookPath
        self.marketTradesPath = marketTradesPath
        self.marketCandlesPath = marketCandlesPath
        self.tradingChancePath = tradingChancePath
        self.tradingOrdersPath = tradingOrdersPath
        self.tradingOpenOrdersPath = tradingOpenOrdersPath
        self.tradingFillsPath = tradingFillsPath
        self.portfolioSummaryPath = portfolioSummaryPath
        self.portfolioHistoryPath = portfolioHistoryPath
        self.kimchiPremiumPath = kimchiPremiumPath
        self.exchangeConnectionsPath = exchangeConnectionsPath
        self.exchangeConnectionsCreateEnabled = exchangeConnectionsCreateEnabled
        self.exchangeConnectionsUpdateEnabled = exchangeConnectionsUpdateEnabled
        self.exchangeConnectionsDeleteEnabled = exchangeConnectionsDeleteEnabled
    }

    func exchangeConnectionPath(id: String) -> String {
        "\(exchangeConnectionsPath)/\(id)"
    }

    func tradingOrderDetailPath(exchange: Exchange, orderID: String) -> String {
        "\(tradingOrdersPath)/\(exchange.rawValue)/\(orderID)"
    }

    static let live: APIConfiguration = resolve(
        environment: ProcessInfo.processInfo.environment,
        includeBundleSettings: true
    )

    static func resolve(
        environment: [String: String],
        buildConfiguration: BuildConfiguration = .current,
        includeBundleSettings: Bool = false
    ) -> APIConfiguration {
        let runtimeConfiguration = AppRuntimeConfiguration.resolve(
            environment: environment,
            buildConfiguration: buildConfiguration,
            includeBundleSettings: includeBundleSettings
        )

        return APIConfiguration(
            baseURL: runtimeConfiguration.restBaseURL.absoluteString,
            loginPath: environment["CRYPTORY_LOGIN_PATH"] ?? "/api/v1/auth/login",
            registerPath: environment["CRYPTORY_REGISTER_PATH"] ?? "/api/v1/auth/register",
            refreshPath: environment["CRYPTORY_REFRESH_PATH"] ?? "/api/v1/auth/refresh",
            googleLoginPath: environment["CRYPTORY_GOOGLE_LOGIN_PATH"] ?? "/api/v1/auth/google",
            appleLoginPath: environment["CRYPTORY_APPLE_LOGIN_PATH"] ?? "/api/v1/auth/apple",
            logoutPath: environment["CRYPTORY_LOGOUT_PATH"] ?? "/api/v1/auth/logout",
            deleteAccountPath: environment["CRYPTORY_DELETE_ACCOUNT_PATH"] ?? "/api/v1/auth/me",
            marketMarketsPath: environment["CRYPTORY_MARKET_MARKETS_PATH"] ?? "/market/markets",
            marketTickersPath: environment["CRYPTORY_MARKET_TICKERS_PATH"] ?? "/market/tickers",
            marketOrderbookPath: environment["CRYPTORY_MARKET_ORDERBOOK_PATH"] ?? "/market/orderbook",
            marketTradesPath: environment["CRYPTORY_MARKET_TRADES_PATH"] ?? "/market/trades",
            marketCandlesPath: environment["CRYPTORY_MARKET_CANDLES_PATH"] ?? "/market/candles",
            tradingChancePath: environment["CRYPTORY_TRADING_CHANCE_PATH"] ?? "/trading/chance",
            tradingOrdersPath: environment["CRYPTORY_TRADING_ORDERS_PATH"] ?? "/trading/orders",
            tradingOpenOrdersPath: environment["CRYPTORY_TRADING_OPEN_ORDERS_PATH"] ?? "/trading/open-orders",
            tradingFillsPath: environment["CRYPTORY_TRADING_FILLS_PATH"] ?? "/trading/fills",
            portfolioSummaryPath: environment["CRYPTORY_PORTFOLIO_SUMMARY_PATH"] ?? "/portfolio/summary",
            portfolioHistoryPath: environment["CRYPTORY_PORTFOLIO_HISTORY_PATH"] ?? "/portfolio/history",
            kimchiPremiumPath: environment["CRYPTORY_KIMCHI_PREMIUM_PATH"] ?? "/kimchi-premium",
            exchangeConnectionsPath: environment["CRYPTORY_EXCHANGE_CONNECTIONS_PATH"] ?? "/exchange-connections",
            exchangeConnectionsCreateEnabled: environment["CRYPTORY_EXCHANGE_CONNECTION_CREATE_ENABLED"] != "0",
            exchangeConnectionsUpdateEnabled: environment["CRYPTORY_EXCHANGE_CONNECTION_UPDATE_ENABLED"] != "0",
            exchangeConnectionsDeleteEnabled: environment["CRYPTORY_EXCHANGE_CONNECTION_DELETE_ENABLED"] != "0"
        )
    }
}

struct TradingOrderCreateRequest {
    let symbol: String
    let exchange: Exchange
    let side: OrderSide
    let type: OrderType
    let price: Double?
    let quantity: Double
}

struct SignUpRequest: Equatable {
    let email: String
    let password: String
    let passwordConfirm: String
    let nickname: String
    let acceptedTerms: Bool
}

struct GoogleSocialLoginRequest: Equatable {
    let idToken: String
    let email: String?
    let displayName: String?
    let deviceID: String?
}

struct AppleSocialLoginRequest: Equatable {
    let identityToken: String
    let authorizationCode: String?
    let userIdentifier: String
    let email: String?
    let fullName: String?
    let givenName: String?
    let familyName: String?
    let deviceID: String?
}

protocol AuthenticationServiceProtocol {
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(request: SignUpRequest) async throws -> AuthSession
    func signInWithGoogle(request: GoogleSocialLoginRequest) async throws -> AuthSession
    func signInWithApple(request: AppleSocialLoginRequest) async throws -> AuthSession
    func refreshSession(refreshToken: String) async throws -> AuthSession
    func signOut(session: AuthSession) async throws
    func deleteAccount(session: AuthSession) async throws
}

protocol MarketRepositoryProtocol {
    var marketCandlesEndpointPath: String { get }

    func fetchMarkets(exchange: Exchange) async throws -> MarketCatalogSnapshot
    func fetchTickers(exchange: Exchange) async throws -> MarketTickerSnapshot
    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookSnapshot
    func fetchTrades(symbol: String, exchange: Exchange) async throws -> PublicTradesSnapshot
    func fetchCandles(symbol: String, exchange: Exchange, interval: String) async throws -> CandleSnapshot
}

protocol TradingRepositoryProtocol {
    func fetchChance(session: AuthSession, exchange: Exchange, symbol: String) async throws -> TradingChance
    func createOrder(session: AuthSession, request: TradingOrderCreateRequest) async throws -> OrderRecord
    func cancelOrder(session: AuthSession, exchange: Exchange, orderID: String) async throws
    func fetchOrderDetail(session: AuthSession, exchange: Exchange, orderID: String) async throws -> OrderRecord
    func fetchOpenOrders(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> OrderRecordsSnapshot
    func fetchFills(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> TradeFillsSnapshot
}

protocol PortfolioRepositoryProtocol {
    func fetchSummary(session: AuthSession, exchange: Exchange) async throws -> PortfolioSnapshot
    func fetchHistory(session: AuthSession, exchange: Exchange) async throws -> PortfolioHistorySnapshot
}

protocol KimchiPremiumRepositoryProtocol {
    func fetchSnapshot(exchange: Exchange, symbols: [String]) async throws -> KimchiPremiumSnapshot
}

protocol ExchangeConnectionsRepositoryProtocol {
    var crudCapability: ExchangeConnectionCRUDCapability { get }

    func fetchConnections(session: AuthSession) async throws -> ExchangeConnectionsSnapshot
    func createConnection(session: AuthSession, request: ExchangeConnectionUpsertRequest) async throws -> ExchangeConnection
    func updateConnection(session: AuthSession, request: ExchangeConnectionUpdateRequest) async throws -> ExchangeConnection
    func deleteConnection(session: AuthSession, connectionID: String) async throws
}

final class APIClient {
    let configuration: APIConfiguration
    private let session: URLSession

    init(configuration: APIConfiguration = .live, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: JSONObject? = nil,
        accessRequirement: RequestAccessRequirement,
        accessToken: String? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(string: configuration.baseURL) else {
            throw NetworkServiceError.invalidURL(configuration.baseURL)
        }

        components.path = normalizedPath(basePath: components.path, endpointPath: path)
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw NetworkServiceError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        switch accessRequirement {
        case .publicAccess:
            AppLogger.debug(.network, "Public request -> \(method) \(url.absoluteString)")
        case .authenticatedRequired:
            guard let accessToken, !accessToken.isEmpty else {
                AppLogger.debug(.auth, "Blocked authenticated request before dispatch -> \(method) \(url.absoluteString)")
                throw NetworkServiceError.authenticationRequired
            }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            AppLogger.debug(.network, "Authenticated request -> \(method) \(url.absoluteString)")
        }

        return request
    }

    func requestJSON(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: JSONObject? = nil,
        accessRequirement: RequestAccessRequirement,
        accessToken: String? = nil
    ) async throws -> Any {
        let request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            accessRequirement: accessRequirement,
            accessToken: accessToken
        )

        if let body {
            AppLogger.debug(
                .network,
                "Request body -> route=\(path) body=\(maskedDebugJSONString(body))"
            )
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let failure = TransportFailureMapper.map(error)
            AppLogger.debug(
                .network,
                "Transport error <- route=\(path) url=\(request.url?.absoluteString ?? path) kind=\(failure.kind.rawValue) category=\(failure.category) message=\(failure.message)"
            )
            throw NetworkServiceError.transportError(failure.message, failure.category)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let parsedError = parseServerError(from: data, statusCode: httpResponse.statusCode)
            AppLogger.debug(
                .network,
                "HTTP error <- route=\(path) status=\(httpResponse.statusCode) mappedCode=\(parsedError.mappedCode) category=\(parsedError.category) url=\(request.url?.absoluteString ?? path)"
            )
            if httpResponse.statusCode == 404 {
                AppLogger.debug(
                    .network,
                    "Endpoint not found <- configuredPath=\(path) baseURL=\(configuration.baseURL). Check server route prefix."
                )
            }
            throw NetworkServiceError.httpError(httpResponse.statusCode, parsedError.message, parsedError.category)
        }

        if data.isEmpty {
            return [:]
        }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            AppLogger.debug(
                .network,
                "Decode failure <- route=\(path) url=\(request.url?.absoluteString ?? path) bytes=\(data.count)"
            )
            throw NetworkServiceError.parsingFailed("서버 응답 형식을 해석하지 못했어요.")
        }
    }

    private func normalizedPath(basePath: String, endpointPath: String) -> String {
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let normalizedEndpoint = endpointPath.hasPrefix("/") ? endpointPath : "/\(endpointPath)"
        return "\(trimmedBase)\(normalizedEndpoint)"
    }

    private func parseServerError(from data: Data, statusCode: Int) -> ServerErrorDetails {
        if let json = try? JSONSerialization.jsonObject(with: data) as? JSONObject {
            let candidates = serverErrorDictionaries(from: json)
            let message = candidates
                .compactMap { $0.string(["message", "error", "detail", "description"]) }
                .first
                ?? "서버 요청에 실패했어요. (\(statusCode))"
            let code = candidates
                .compactMap { $0.string(["code", "errorCode", "type", "error_type"]) }
                .first?
                .lowercased()
            let category = responseErrorCategory(statusCode: statusCode, code: code)
            return ServerErrorDetails(
                message: message,
                category: category,
                mappedCode: mappedServerErrorCode(statusCode: statusCode, code: code)
            )
        }

        let message = String(data: data, encoding: .utf8) ?? "서버 요청에 실패했어요. (\(statusCode))"
        return ServerErrorDetails(
            message: message,
            category: responseErrorCategory(statusCode: statusCode, code: nil),
            mappedCode: mappedServerErrorCode(statusCode: statusCode, code: nil)
        )
    }

    private func responseErrorCategory(statusCode: Int, code: String?) -> RemoteErrorCategory {
        if statusCode == 401 || code == "authentication_failed" {
            return .authenticationFailed
        }
        if statusCode == 403 || code == "permission_denied" {
            return .permissionDenied
        }
        if statusCode == 429 || code == "rate_limited" {
            return .rateLimited
        }
        if statusCode == 503
            || code == "maintenance"
            || code == "market_data_unsupported"
            || code == "unsupported_market_data" {
            return .maintenance
        }
        if code == "stale_data" {
            return .staleData
        }
        if statusCode >= 500 {
            return .connectivity
        }
        return .unknown
    }

    private func mappedServerErrorCode(statusCode: Int, code: String?) -> String {
        if let code = code?.trimmedNonEmpty {
            return code
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
        }

        switch statusCode {
        case 400:
            return "bad_request"
        case 401:
            return "authentication_failed"
        case 403:
            return "permission_denied"
        case 409:
            return "duplicate_account"
        case 429:
            return "rate_limited"
        case 500...599:
            return "server_error"
        default:
            return "unknown"
        }
    }

    private func serverErrorDictionaries(from json: JSONObject) -> [JSONObject] {
        let directData = json["data"] as? JSONObject
        let directError = json["error"] as? JSONObject
        let nestedDataError = directData?["error"] as? JSONObject

        return [json, directData, directError, nestedDataError].compactMap { $0 }
    }
}

final class LiveAuthenticationService: AuthenticationServiceProtocol {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let json = try await client.requestJSON(
            path: client.configuration.loginPath,
            method: "POST",
            body: [
                "email": email,
                "password": password
            ],
            accessRequirement: .publicAccess
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject else {
            throw NetworkServiceError.parsingFailed("로그인 응답을 확인할 수 없어요.")
        }

        return try parseAuthSession(
            from: dictionary,
            fallbackEmail: email,
            context: "로그인"
        )
    }

    func signUp(request: SignUpRequest) async throws -> AuthSession {
        let body: JSONObject = [
            "email": request.email,
            "password": request.password,
            "nickname": request.nickname
        ]

        let json = try await client.requestJSON(
            path: client.configuration.registerPath,
            method: "POST",
            body: body,
            accessRequirement: .publicAccess
        )

        let payload = unwrapPayload(json)
        if let dictionary = payload as? JSONObject,
           let session = try? parseAuthSession(
            from: dictionary,
            fallbackEmail: request.email,
            context: "회원가입"
           ) {
            return session
        }

        return try await signIn(email: request.email, password: request.password)
    }

    func signInWithGoogle(request: GoogleSocialLoginRequest) async throws -> AuthSession {
        var body: JSONObject = [
            "idToken": request.idToken
        ]
        body["credential"] = request.idToken
        if let email = request.email?.trimmedNonEmpty {
            body["email"] = email
        }
        if let displayName = request.displayName?.trimmedNonEmpty {
            body["displayName"] = displayName
        }
        if let deviceID = request.deviceID?.trimmedNonEmpty {
            body["deviceId"] = deviceID
        }

        let json = try await client.requestJSON(
            path: client.configuration.googleLoginPath,
            method: "POST",
            body: body,
            accessRequirement: .publicAccess
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject else {
            throw NetworkServiceError.parsingFailed("구글 로그인 응답을 확인할 수 없어요.")
        }

        return try parseAuthSession(
            from: dictionary,
            fallbackEmail: request.email,
            context: "구글 로그인"
        )
    }

    func signInWithApple(request: AppleSocialLoginRequest) async throws -> AuthSession {
        var body: JSONObject = [
            "identityToken": request.identityToken,
            "idToken": request.identityToken,
            "userIdentifier": request.userIdentifier
        ]
        if let authorizationCode = request.authorizationCode?.trimmedNonEmpty {
            body["authorizationCode"] = authorizationCode
        }
        if let email = request.email?.trimmedNonEmpty {
            body["email"] = email
        }
        if let fullName = request.fullName?.trimmedNonEmpty {
            body["fullName"] = fullName
        }
        if let givenName = request.givenName?.trimmedNonEmpty {
            body["givenName"] = givenName
        }
        if let familyName = request.familyName?.trimmedNonEmpty {
            body["familyName"] = familyName
        }
        if let deviceID = request.deviceID?.trimmedNonEmpty {
            body["deviceId"] = deviceID
        }

        let json = try await client.requestJSON(
            path: client.configuration.appleLoginPath,
            method: "POST",
            body: body,
            accessRequirement: .publicAccess
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject else {
            throw NetworkServiceError.parsingFailed("애플 로그인 응답을 확인할 수 없어요.")
        }

        return try parseAuthSession(
            from: dictionary,
            fallbackEmail: request.email,
            context: "애플 로그인"
        )
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        let json = try await client.requestJSON(
            path: client.configuration.refreshPath,
            method: "POST",
            body: [
                "refreshToken": refreshToken
            ],
            accessRequirement: .publicAccess
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject else {
            throw NetworkServiceError.parsingFailed("세션 갱신 응답을 확인할 수 없어요.")
        }

        return try parseAuthSession(
            from: dictionary,
            fallbackEmail: nil,
            context: "세션 갱신"
        )
    }

    func signOut(session: AuthSession) async throws {
        let body: JSONObject?
        if let refreshToken = session.refreshToken?.trimmedNonEmpty {
            body = ["refreshToken": refreshToken]
        } else {
            body = nil
        }

        _ = try await client.requestJSON(
            path: client.configuration.logoutPath,
            method: "POST",
            body: body,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
    }

    func deleteAccount(session: AuthSession) async throws {
        _ = try await client.requestJSON(
            path: client.configuration.deleteAccountPath,
            method: "DELETE",
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
    }

    private func parseAuthSession(
        from dictionary: JSONObject,
        fallbackEmail: String?,
        context: String
    ) throws -> AuthSession {
        guard let accessToken = dictionary.string(["accessToken", "access_token", "token"]) else {
            throw NetworkServiceError.parsingFailed("\(context) 토큰이 응답에 없어요.")
        }
        let user = dictionary["user"] as? JSONObject

        return AuthSession(
            accessToken: accessToken,
            refreshToken: dictionary.string(["refreshToken", "refresh_token"]),
            userID: dictionary.string(["userId", "user_id", "id"]) ?? user?.string(["userId", "user_id", "id"]),
            email: dictionary.string(["email"]) ?? user?.string(["email"]) ?? fallbackEmail
        )
    }
}

final class LiveMarketRepository: MarketRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    var marketCandlesEndpointPath: String {
        client.configuration.marketCandlesPath
    }

    func fetchMarkets(exchange: Exchange) async throws -> MarketCatalogSnapshot {
        let json = try await client.requestJSON(
            path: client.configuration.marketMarketsPath,
            queryItems: [URLQueryItem(name: "exchange", value: exchange.rawValue)],
            accessRequirement: .publicAccess
        )

        let container = splitPayload(json)
        let payload = container.payload
        let array: [Any]
        if let directArray = unwrapArray(payload) {
            array = directArray
        } else if let dictionary = payload as? JSONObject {
            array = unwrapArray(dictionary["items"] ?? dictionary["markets"] ?? dictionary["symbols"]) ?? []
        } else {
            array = []
        }
        var markets: [CoinInfo] = []
        var intervalsBySymbol: [String: [String]] = [:]
        var seenSymbols = Set<String>()

        for item in array {
            guard let dictionary = item as? JSONObject else { continue }
            guard let dto = MarketInfoDTO(dictionary: dictionary, exchange: exchange) else { continue }
            guard seenSymbols.insert(dto.coinInfo.symbol).inserted else { continue }
            markets.append(dto.coinInfo)
            intervalsBySymbol[dto.coinInfo.symbol] = dto.supportedIntervals
        }

        let resolvedUniverse = resolveMarketUniverse(
            parsedCoins: markets,
            payload: payload,
            exchange: exchange
        )

        return MarketCatalogSnapshot(
            exchange: exchange,
            markets: resolvedUniverse.coins,
            supportedIntervalsBySymbol: intervalsBySymbol,
            meta: container.meta,
            filteredSymbols: resolvedUniverse.filteredSymbols
        )
    }

    func fetchTickers(exchange: Exchange) async throws -> MarketTickerSnapshot {
        let json = try await client.requestJSON(
            path: client.configuration.marketTickersPath,
            queryItems: [URLQueryItem(name: "exchange", value: exchange.rawValue)],
            accessRequirement: .publicAccess
        )

        let container = splitPayload(json)
        if exchange == .coinone {
            AppLogger.debug(
                .network,
                "Coinone ticker payload -> \(debugJSONString(container.payload))"
            )
        }
        var tickers: [String: TickerData] = [:]
        var coins: [CoinInfo] = []
        var seenSymbols = Set<String>()

        if let array = unwrapArray(container.payload) {
            for item in array {
                guard let dictionary = item as? JSONObject else { continue }
                guard let dto = MarketTickerDTO(dictionary: dictionary, exchange: exchange) else { continue }
                tickers[dto.symbol] = dto.entity(meta: container.meta)
                if seenSymbols.insert(dto.coinInfo.symbol).inserted {
                    coins.append(dto.coinInfo)
                }
            }
        } else if let dictionary = container.payload as? JSONObject {
            if let nestedArray = unwrapArray(dictionary["items"] ?? dictionary["tickers"]) {
                for item in nestedArray {
                    guard let tickerDictionary = item as? JSONObject else { continue }
                    guard let dto = MarketTickerDTO(dictionary: tickerDictionary, exchange: exchange) else { continue }
                    tickers[dto.symbol] = dto.entity(meta: container.meta)
                    if seenSymbols.insert(dto.coinInfo.symbol).inserted {
                        coins.append(dto.coinInfo)
                    }
                }
            } else {
                for (symbol, rawValue) in dictionary {
                    guard let tickerDictionary = rawValue as? JSONObject else { continue }
                    guard let dto = MarketTickerDTO(dictionary: tickerDictionary.merging(["symbol": symbol as Any], uniquingKeysWith: { left, _ in left }), exchange: exchange) else { continue }
                    tickers[dto.symbol] = dto.entity(meta: container.meta)
                    if seenSymbols.insert(dto.coinInfo.symbol).inserted {
                        coins.append(dto.coinInfo)
                    }
                }
            }
        }

        let resolvedUniverse = resolveMarketUniverse(
            parsedCoins: coins,
            payload: container.payload,
            exchange: exchange
        )
        let allowedSymbols = Set(resolvedUniverse.coins.map(\.symbol))
        let filteredTickers: [String: TickerData]
        if allowedSymbols.isEmpty {
            filteredTickers = tickers
        } else {
            filteredTickers = tickers.filter { allowedSymbols.contains($0.key) }
        }

        if exchange == .coinone {
            AppLogger.debug(.network, "Coinone ticker parsed count -> \(filteredTickers.count)")
        }
        return MarketTickerSnapshot(
            exchange: exchange,
            coins: resolvedUniverse.coins,
            tickers: filteredTickers,
            meta: container.meta,
            filteredSymbols: resolvedUniverse.filteredSymbols
        )
    }

    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookSnapshot {
        let json = try await client.requestJSON(
            path: client.configuration.marketOrderbookPath,
            queryItems: [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "exchange", value: exchange.rawValue)
            ],
            accessRequirement: .publicAccess
        )

        let container = splitPayload(json)
        guard let dictionary = container.payload as? JSONObject else {
            throw NetworkServiceError.parsingFailed("호가 응답을 해석하지 못했어요.")
        }

        guard let dto = OrderbookDTO(dictionary: dictionary) else {
            throw NetworkServiceError.parsingFailed("호가 데이터가 비어 있어요.")
        }

        return OrderbookSnapshot(
            exchange: exchange,
            symbol: symbol,
            orderbook: dto.entity(meta: container.meta),
            meta: container.meta
        )
    }

    func fetchTrades(symbol: String, exchange: Exchange) async throws -> PublicTradesSnapshot {
        let json = try await client.requestJSON(
            path: client.configuration.marketTradesPath,
            queryItems: [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "exchange", value: exchange.rawValue)
            ],
            accessRequirement: .publicAccess
        )

        let container = splitPayload(json)
        let array = unwrapArray(container.payload) ?? []
        let trades = array.compactMap { item -> PublicTrade? in
            guard let dictionary = item as? JSONObject, let dto = PublicTradeDTO(dictionary: dictionary) else {
                return nil
            }
            return dto.entity
        }

        return PublicTradesSnapshot(exchange: exchange, symbol: symbol, trades: trades, meta: container.meta)
    }

    func fetchCandles(symbol: String, exchange: Exchange, interval: String) async throws -> CandleSnapshot {
        let startedAt = Date()
        AppLogger.debug(
            .network,
            "[ChartPipeline] exchange=\(exchange.rawValue) symbol=\(symbol) interval=\(interval.uppercased()) phase=request_dispatch endpoint=\(client.configuration.marketCandlesPath)"
        )
        let json = try await client.requestJSON(
            path: client.configuration.marketCandlesPath,
            queryItems: [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "exchange", value: exchange.rawValue),
                URLQueryItem(name: "interval", value: interval)
            ],
            accessRequirement: .publicAccess
        )

        let container = splitPayload(json)
        let array = unwrapArray(container.payload) ?? []
        let candles = array.compactMap { item -> CandleData? in
            guard let dictionary = item as? JSONObject, let dto = CandleDTO(dictionary: dictionary) else {
                return nil
            }
            return dto.entity
        }
        .sorted { $0.time < $1.time }

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        if candles.isEmpty {
            AppLogger.debug(
                .network,
                "[ChartPipeline] exchange=\(exchange.rawValue) symbol=\(symbol) interval=\(interval.uppercased()) phase=response_empty elapsedMs=\(elapsedMs)"
            )
        } else {
            AppLogger.debug(
                .network,
                "[ChartPipeline] exchange=\(exchange.rawValue) symbol=\(symbol) interval=\(interval.uppercased()) phase=response_success candles=\(candles.count) elapsedMs=\(elapsedMs)"
            )
        }

        return CandleSnapshot(
            exchange: exchange,
            symbol: symbol,
            interval: interval,
            candles: candles,
            meta: container.meta
        )
    }
}

final class LiveTradingRepository: TradingRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchChance(session: AuthSession, exchange: Exchange, symbol: String) async throws -> TradingChance {
        let json = try await client.requestJSON(
            path: client.configuration.tradingChancePath,
            queryItems: [
                URLQueryItem(name: "exchange", value: exchange.rawValue),
                URLQueryItem(name: "symbol", value: symbol)
            ],
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject, let dto = TradingChanceDTO(dictionary: dictionary, exchange: exchange, symbol: symbol) else {
            throw NetworkServiceError.parsingFailed("주문 가능 정보를 해석하지 못했어요.")
        }

        return dto.entity
    }

    func createOrder(session: AuthSession, request: TradingOrderCreateRequest) async throws -> OrderRecord {
        var body: JSONObject = [
            "symbol": request.symbol,
            "exchange": request.exchange.rawValue,
            "side": request.side.rawValue,
            "type": request.type.rawValue,
            "quantity": request.quantity
        ]
        if let price = request.price {
            body["price"] = price
        }

        let json = try await client.requestJSON(
            path: client.configuration.tradingOrdersPath,
            method: "POST",
            body: body,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject, let dto = TradingOrderDTO(dictionary: dictionary, exchange: request.exchange) else {
            throw NetworkServiceError.parsingFailed("주문 생성 응답을 해석하지 못했어요.")
        }

        return dto.entity
    }

    func cancelOrder(session: AuthSession, exchange: Exchange, orderID: String) async throws {
        _ = try await client.requestJSON(
            path: client.configuration.tradingOrderDetailPath(exchange: exchange, orderID: orderID),
            method: "DELETE",
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
    }

    func fetchOrderDetail(session: AuthSession, exchange: Exchange, orderID: String) async throws -> OrderRecord {
        let json = try await client.requestJSON(
            path: client.configuration.tradingOrderDetailPath(exchange: exchange, orderID: orderID),
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject, let dto = TradingOrderDTO(dictionary: dictionary, exchange: exchange) else {
            throw NetworkServiceError.parsingFailed("주문 상세 응답을 해석하지 못했어요.")
        }

        return dto.entity
    }

    func fetchOpenOrders(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> OrderRecordsSnapshot {
        var queryItems = [URLQueryItem(name: "exchange", value: exchange.rawValue)]
        if let symbol, !symbol.isEmpty {
            queryItems.append(URLQueryItem(name: "symbol", value: symbol))
        }

        let json = try await client.requestJSON(
            path: client.configuration.tradingOpenOrdersPath,
            queryItems: queryItems,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        return try parseOrderRecordsSnapshot(json: json, exchange: exchange)
    }

    func fetchFills(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> TradeFillsSnapshot {
        var queryItems = [URLQueryItem(name: "exchange", value: exchange.rawValue)]
        if let symbol, !symbol.isEmpty {
            queryItems.append(URLQueryItem(name: "symbol", value: symbol))
        }

        let json = try await client.requestJSON(
            path: client.configuration.tradingFillsPath,
            queryItems: queryItems,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let container = splitPayload(json)
        let array = unwrapArray(container.payload) ?? []
        let fills = array.compactMap { item -> TradeFill? in
            guard let dictionary = item as? JSONObject, let dto = TradingFillDTO(dictionary: dictionary, exchange: exchange) else {
                return nil
            }
            return dto.entity
        }

        return TradeFillsSnapshot(exchange: exchange, fills: fills, meta: container.meta)
    }

    private func parseOrderRecordsSnapshot(json: Any, exchange: Exchange) throws -> OrderRecordsSnapshot {
        let container = splitPayload(json)
        let array = unwrapArray(container.payload) ?? []
        let orders = array.compactMap { item -> OrderRecord? in
            guard let dictionary = item as? JSONObject, let dto = TradingOrderDTO(dictionary: dictionary, exchange: exchange) else {
                return nil
            }
            return dto.entity
        }

        return OrderRecordsSnapshot(exchange: exchange, orders: orders, meta: container.meta)
    }
}

final class LivePortfolioRepository: PortfolioRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchSummary(session: AuthSession, exchange: Exchange) async throws -> PortfolioSnapshot {
        let json = try await client.requestJSON(
            path: client.configuration.portfolioSummaryPath,
            queryItems: [URLQueryItem(name: "exchange", value: exchange.rawValue)],
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let container = splitPayload(json)
        guard let dictionary = container.payload as? JSONObject, let dto = PortfolioSummaryDTO(dictionary: dictionary, exchange: exchange, meta: container.meta) else {
            throw NetworkServiceError.parsingFailed("포트폴리오 응답을 해석하지 못했어요.")
        }

        return dto.entity
    }

    func fetchHistory(session: AuthSession, exchange: Exchange) async throws -> PortfolioHistorySnapshot {
        let json = try await client.requestJSON(
            path: client.configuration.portfolioHistoryPath,
            queryItems: [URLQueryItem(name: "exchange", value: exchange.rawValue)],
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let container = splitPayload(json)
        let array = unwrapArray(container.payload) ?? []
        let items = array.compactMap { item -> PortfolioHistoryItem? in
            guard let dictionary = item as? JSONObject, let dto = PortfolioHistoryItemDTO(dictionary: dictionary, exchange: exchange) else {
                return nil
            }
            return dto.entity
        }

        return PortfolioHistorySnapshot(exchange: exchange, items: items, meta: container.meta)
    }
}

final class LiveKimchiPremiumRepository: KimchiPremiumRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchSnapshot(exchange: Exchange, symbols: [String]) async throws -> KimchiPremiumSnapshot {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "exchange", value: exchange.rawValue),
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))
        ]

        let json = try await client.requestJSON(
            path: client.configuration.kimchiPremiumPath,
            queryItems: queryItems,
            accessRequirement: .publicAccess
        )

        let container = splitPayload(json)
        let payload = container.payload

        let rows: [KimchiPremiumRow]
        if let array = unwrapArray(payload) {
            rows = array.compactMap { item -> KimchiPremiumRow? in
                guard let dictionary = item as? JSONObject, let dto = KimchiPremiumRowDTO(dictionary: dictionary) else {
                    return nil
                }
                return dto.entity
            }
        } else if let dictionary = payload as? JSONObject, let items = unwrapArray(dictionary["rows"] ?? dictionary["items"]) {
            rows = items.compactMap { item -> KimchiPremiumRow? in
                guard let rowDictionary = item as? JSONObject, let dto = KimchiPremiumRowDTO(dictionary: rowDictionary) else {
                    return nil
                }
                return dto.entity
            }
        } else {
            rows = []
        }

        let referenceExchangeRawValue = (payload as? JSONObject)?.string(["referenceExchange", "reference_exchange"]) ?? Exchange.binance.rawValue
        let referenceExchange = Exchange(rawValue: referenceExchangeRawValue.lowercased()) ?? .binance
        let payloadDictionary = payload as? JSONObject
        let failedSymbols = Set(
            (payloadDictionary?.stringArray(["failedSymbols", "unsupportedSymbols", "excludedSymbols"]) ?? []).map { $0.uppercased() }
            + ((payloadDictionary?["partialFailures"] as? [Any]) ?? []).compactMap { item -> String? in
                if let dictionary = item as? JSONObject {
                    return dictionary.string(["symbol", "asset", "market"])?.uppercased()
                }
                if let symbol = item as? String {
                    return symbol.uppercased()
                }
                return nil
            }
        ).sorted()
        let partialFailureMessage = container.meta.partialFailureMessage
            ?? payloadDictionary?.string(["partialFailureMessage", "partialError", "partial_error"])
            ?? (failedSymbols.isEmpty ? nil : "일부 비교 종목이 제외되었어요.")

        return KimchiPremiumSnapshot(
            referenceExchange: referenceExchange,
            rows: rows,
            fetchedAt: container.meta.fetchedAt,
            isStale: container.meta.isStale,
            warningMessage: container.meta.warningMessage,
            partialFailureMessage: partialFailureMessage,
            failedSymbols: failedSymbols
        )
    }
}

final class LiveExchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol {
    private let client: APIClient

    var crudCapability: ExchangeConnectionCRUDCapability {
        ExchangeConnectionCRUDCapability(
            canCreate: client.configuration.exchangeConnectionsCreateEnabled,
            canDelete: client.configuration.exchangeConnectionsDeleteEnabled,
            canUpdate: client.configuration.exchangeConnectionsUpdateEnabled
        )
    }

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchConnections(session: AuthSession) async throws -> ExchangeConnectionsSnapshot {
        let json = try await client.requestJSON(
            path: client.configuration.exchangeConnectionsPath,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let container = splitPayload(json)
        let array = unwrapArray(container.payload) ?? []
        let connections = array.compactMap { item -> ExchangeConnection? in
            guard let dictionary = item as? JSONObject, let dto = ExchangeConnectionDTO(dictionary: dictionary) else {
                return nil
            }
            return dto.entity
        }

        return ExchangeConnectionsSnapshot(connections: connections, meta: container.meta)
    }

    func createConnection(session: AuthSession, request: ExchangeConnectionUpsertRequest) async throws -> ExchangeConnection {
        guard crudCapability.canCreate else {
            throw NetworkServiceError.httpError(405, "거래소 연결 생성 API가 아직 활성화되지 않았어요.", .unknown)
        }

        AppLogger.debug(
            .auth,
            "Create exchange connection -> exchange=\(request.exchange.rawValue), metadata={\(AppLogger.sanitizedMetadata(request.credentials.mapKeys(\.requestKey)))}"
        )

        let json = try await client.requestJSON(
            path: client.configuration.exchangeConnectionsPath,
            method: "POST",
            body: exchangeConnectionBody(request: request),
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject, let dto = ExchangeConnectionDTO(dictionary: dictionary) else {
            throw NetworkServiceError.parsingFailed("생성된 거래소 연결 응답을 해석하지 못했어요.")
        }
        return dto.entity
    }

    func updateConnection(session: AuthSession, request: ExchangeConnectionUpdateRequest) async throws -> ExchangeConnection {
        guard crudCapability.canUpdate else {
            throw NetworkServiceError.httpError(405, "거래소 연결 수정 API가 아직 활성화되지 않았어요.", .unknown)
        }

        AppLogger.debug(
            .auth,
            "Update exchange connection -> id=\(request.id), metadata={\(AppLogger.sanitizedMetadata(request.credentials.mapKeys(\.requestKey)))}"
        )

        let json = try await client.requestJSON(
            path: client.configuration.exchangeConnectionPath(id: request.id),
            method: "PATCH",
            body: exchangeConnectionBody(request: request),
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject, let dto = ExchangeConnectionDTO(dictionary: dictionary) else {
            throw NetworkServiceError.parsingFailed("수정된 거래소 연결 응답을 해석하지 못했어요.")
        }
        return dto.entity
    }

    func deleteConnection(session: AuthSession, connectionID: String) async throws {
        guard crudCapability.canDelete else {
            throw NetworkServiceError.httpError(405, "거래소 연결 삭제 API가 아직 활성화되지 않았어요.", .unknown)
        }

        _ = try await client.requestJSON(
            path: client.configuration.exchangeConnectionPath(id: connectionID),
            method: "DELETE",
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
    }

    private func exchangeConnectionBody(request: ExchangeConnectionUpsertRequest) -> JSONObject {
        var body: JSONObject = [
            "exchange": request.exchange.rawValue,
            "permission": request.permission.rawValue,
            "credentials": request.credentials.mapKeys(\.requestKey)
        ]
        if let nickname = request.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
            body["nickname"] = nickname
        }
        return body
    }

    private func exchangeConnectionBody(request: ExchangeConnectionUpdateRequest) -> JSONObject {
        var body: JSONObject = [:]
        if let permission = request.permission {
            body["permission"] = permission.rawValue
        }
        if let nickname = request.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
            body["nickname"] = nickname
        }
        if !request.credentials.isEmpty {
            body["credentials"] = request.credentials.mapKeys(\.requestKey)
        }
        return body
    }
}

private struct MarketInfoDTO {
    let coinInfo: CoinInfo
    let supportedIntervals: [String]

    init?(dictionary: JSONObject, exchange: Exchange) {
        guard let rawSymbol = marketRawSymbol(from: dictionary) else {
            return nil
        }

        let displayName = dictionary.string(["displayName", "name", "koreanName"])
        let englishName = dictionary.string(["displayNameEn", "englishName"])
        let imageURL = marketImageURL(from: dictionary)
        let hasImage = marketHasImage(from: dictionary)
        let canonicalAssetKey = marketCanonicalAssetKey(from: dictionary)
        let metadata = marketDisplayMetadata(
            from: dictionary,
            exchange: exchange,
            rawSymbol: rawSymbol,
            displayName: displayName,
            englishName: englishName,
            imageURL: imageURL,
            hasImage: hasImage,
            localAssetName: canonicalAssetKey
        )
        let symbol = metadata.canonicalSymbol
        let isTradable = dictionary.bool([
            "tradable",
            "isTradable",
            "tradeable",
            "enabled",
            "isActive"
        ]) ?? true
        let isKimchiComparable = dictionary.bool([
            "kimchiComparable",
            "kimchi_comparable",
            "isKimchiComparable",
            "supportsKimchiPremium",
            "comparable"
        ]) ?? (exchange.isDomestic && exchange.supportsKimchiPremium && isTradable)

        self.coinInfo = CoinCatalog.coin(
            symbol: symbol,
            exchange: exchange,
            marketId: metadata.marketId,
            baseAsset: metadata.baseAsset,
            quoteAsset: metadata.quoteAsset,
            canonicalSymbol: metadata.canonicalSymbol,
            displaySymbol: metadata.displaySymbol,
            displayName: displayName,
            englishName: englishName,
            imageURL: imageURL,
            hasImage: hasImage,
            localAssetName: metadata.localAssetName,
            isChartAvailable: metadata.isChartAvailable,
            isOrderBookAvailable: metadata.isOrderBookAvailable,
            isTradesAvailable: metadata.isTradesAvailable,
            unavailableReason: metadata.unavailableReason,
            isTradable: isTradable,
            isKimchiComparable: isKimchiComparable
        )
        AppLogger.debug(
            .network,
            "[ImageDebug] symbol=\(symbol) action=url_received value=\(imageURL ?? "<nil>") hasImage=\(String(describing: hasImage)) canonicalAssetKey=\(canonicalAssetKey ?? "<nil>")"
        )
        self.supportedIntervals = dictionary.stringArray(["supportedIntervals", "intervals", "chartIntervals"]).map { $0.lowercased() }
    }
}

private struct ResolvedMarketUniverse {
    let coins: [CoinInfo]
    let filteredSymbols: [String]
}

private struct MarketUniverseHints {
    let listedCoins: [CoinInfo]
    let listedSymbols: [String]
    let supportedSymbols: Set<String>
    let excludedSymbols: Set<String>
}

private struct MarketTickerDTO {
    let symbol: String
    let coinInfo: CoinInfo
    let price: Double
    let changePercent: Double
    let volume24h: Double
    let high24: Double
    let low24: Double
    let sparkline: [Double]
    let sparklinePointCount: Int?
    let timestamp: Date?
    let isStale: Bool
    let sourceExchange: Exchange

    init?(dictionary: JSONObject, exchange: Exchange) {
        guard let rawSymbol = marketRawSymbol(from: dictionary) else {
            return nil
        }
        guard let price = dictionary.double([
            "price",
            "lastPrice",
            "tradePrice",
            "closing_price",
            "last",
            "close",
            "close_price"
        ]) else {
            return nil
        }

        let displayName = dictionary.string(["displayName", "name", "koreanName", "assetName"])
        let englishName = dictionary.string(["displayNameEn", "englishName", "nameEn"])
        let imageURL = marketImageURL(from: dictionary)
        let hasImage = marketHasImage(from: dictionary)
        let canonicalAssetKey = marketCanonicalAssetKey(from: dictionary)
        let metadata = marketDisplayMetadata(
            from: dictionary,
            exchange: exchange,
            rawSymbol: rawSymbol,
            displayName: displayName,
            englishName: englishName,
            imageURL: imageURL,
            hasImage: hasImage,
            localAssetName: canonicalAssetKey
        )
        let symbol = metadata.canonicalSymbol
        self.symbol = symbol
        let isTradable = dictionary.bool([
            "tradable",
            "isTradable",
            "tradeable",
            "enabled",
            "isActive"
        ]) ?? true
        let isKimchiComparable = dictionary.bool([
            "kimchiComparable",
            "kimchi_comparable",
            "isKimchiComparable",
            "supportsKimchiPremium",
            "comparable"
        ]) ?? (exchange.isDomestic && exchange.supportsKimchiPremium && isTradable)
        self.coinInfo = CoinCatalog.coin(
            symbol: symbol,
            exchange: exchange,
            marketId: metadata.marketId,
            baseAsset: metadata.baseAsset,
            quoteAsset: metadata.quoteAsset,
            canonicalSymbol: metadata.canonicalSymbol,
            displaySymbol: metadata.displaySymbol,
            displayName: displayName,
            englishName: englishName,
            imageURL: imageURL,
            hasImage: hasImage,
            localAssetName: metadata.localAssetName,
            isChartAvailable: metadata.isChartAvailable,
            isOrderBookAvailable: metadata.isOrderBookAvailable,
            isTradesAvailable: metadata.isTradesAvailable,
            unavailableReason: metadata.unavailableReason,
            isTradable: isTradable,
            isKimchiComparable: isKimchiComparable
        )
        AppLogger.debug(
            .network,
            "[ImageDebug] symbol=\(symbol) action=url_received value=\(imageURL ?? "<nil>") hasImage=\(String(describing: hasImage)) canonicalAssetKey=\(canonicalAssetKey ?? "<nil>")"
        )
        self.price = price
        let rawChangePercent = dictionary.double([
            "changePercent",
            "change24h",
            "signed_change_rate",
            "changeRate",
            "change_rate",
            "change"
        ]) ?? 0
        self.changePercent = abs(rawChangePercent) <= 1 ? rawChangePercent * 100 : rawChangePercent
        self.volume24h = dictionary.double([
            "volume24h",
            "quoteVolume",
            "acc_trade_price_24h",
            "volume",
            "target_volume",
            "quote_volume"
        ]) ?? 0
        self.high24 = dictionary.double(["high24", "highPrice", "high_price", "high", "high_price_24h"]) ?? price
        self.low24 = dictionary.double(["low24", "lowPrice", "low_price", "low", "low_price_24h"]) ?? price
        self.sparkline = parseSparklinePoints(from: dictionary)
        self.sparklinePointCount = parseSparklinePointCount(from: dictionary)
        self.timestamp = parseDateValue(dictionary["timestamp"] ?? dictionary["time"] ?? dictionary["updatedAt"])
        self.isStale = dictionary.bool(["stale", "isStale"]) ?? false
        self.sourceExchange = Exchange(rawValue: (dictionary.string(["sourceExchange", "exchange"]) ?? exchange.rawValue).lowercased()) ?? exchange
    }

    func entity(meta: ResponseMeta) -> TickerData {
        TickerData(
            price: price,
            change: changePercent,
            volume: volume24h,
            high24: high24,
            low24: low24,
            sparkline: sparkline,
            sparklinePointCount: sparklinePointCount,
            hasServerSparkline: sparkline.count >= 2,
            timestamp: timestamp ?? meta.fetchedAt,
            isStale: isStale || meta.isStale,
            sourceExchange: sourceExchange,
            delivery: .snapshot
        )
    }
}

private func resolveMarketUniverse(
    parsedCoins: [CoinInfo],
    payload: Any,
    exchange: Exchange
) -> ResolvedMarketUniverse {
    let hints = marketUniverseHints(from: payload, exchange: exchange)
    let baseCoins: [CoinInfo]

    if !hints.listedCoins.isEmpty {
        baseCoins = deduplicatedCoins(hints.listedCoins, exchange: exchange)
    } else if !hints.listedSymbols.isEmpty {
        let parsedCoinsBySymbol = deduplicatedCoins(parsedCoins, exchange: exchange)
            .reduce(into: [String: CoinInfo]()) { partialResult, coin in
                if let existing = partialResult[coin.symbol] {
                    partialResult[coin.symbol] = existing.merged(with: coin)
                } else {
                    partialResult[coin.symbol] = coin
                }
            }
        baseCoins = hints.listedSymbols.map { symbol in
            parsedCoinsBySymbol[symbol] ?? CoinCatalog.coin(symbol: symbol)
        }
    } else {
        baseCoins = deduplicatedCoins(parsedCoins, exchange: exchange)
    }

    let filteredSymbols = deduplicatedSymbols(
        baseCoins.compactMap { coin -> String? in
            let isUnsupported = hints.supportedSymbols.isEmpty == false && hints.supportedSymbols.contains(coin.symbol) == false
            let isExcluded = hints.excludedSymbols.contains(coin.symbol)
            return (isUnsupported || isExcluded) ? coin.symbol : nil
        }
    )

    let filteredCoins = baseCoins.filter { coin in
        (hints.supportedSymbols.isEmpty || hints.supportedSymbols.contains(coin.symbol))
            && hints.excludedSymbols.contains(coin.symbol) == false
    }

    return ResolvedMarketUniverse(
        coins: filteredCoins,
        filteredSymbols: filteredSymbols
    )
}

private func marketUniverseHints(from payload: Any, exchange: Exchange) -> MarketUniverseHints {
    guard let dictionary = payload as? JSONObject else {
        return MarketUniverseHints(
            listedCoins: [],
            listedSymbols: [],
            supportedSymbols: [],
            excludedSymbols: []
        )
    }

    let listedCoins = parseCoinInfoArray(
        from: dictionary["listedItems"]
            ?? dictionary["listedMarkets"]
            ?? dictionary["marketListings"]
            ?? dictionary["listings"],
        exchange: exchange
    )
    let listedSymbols = deduplicatedSymbols(
        dictionary.stringArray([
            "listedSymbols",
            "canonicalListedSymbols",
            "marketSymbols"
        ]).map(normalizeMarketSymbol)
    )
    let supportedSymbols = Set(
        dictionary.stringArray([
            "supportedSymbols",
            "supported_symbols",
            "symbols"
        ]).map(normalizeMarketSymbol)
    )
    let excludedSymbols = Set(
        dictionary.stringArray([
            "capabilityExcludedSymbols",
            "excludedSymbols",
            "unsupportedSymbols",
            "unsupported_symbols"
        ]).map(normalizeMarketSymbol)
    )

    return MarketUniverseHints(
        listedCoins: listedCoins,
        listedSymbols: listedSymbols,
        supportedSymbols: supportedSymbols,
        excludedSymbols: excludedSymbols
    )
}

private func parseCoinInfoArray(from rawValue: Any?, exchange: Exchange) -> [CoinInfo] {
    let array = unwrapArray(rawValue) ?? []
    return deduplicatedCoins(
        array.compactMap { item -> CoinInfo? in
            if let symbol = item as? String {
                return CoinCatalog.coin(symbol: symbol)
            }

            guard let dictionary = item as? JSONObject else {
                return nil
            }

            return MarketInfoDTO(dictionary: dictionary, exchange: exchange)?.coinInfo
                ?? MarketTickerDTO(dictionary: dictionary, exchange: exchange)?.coinInfo
        },
        exchange: exchange
    )
}

private func deduplicatedCoins(_ coins: [CoinInfo], exchange: Exchange) -> [CoinInfo] {
    var mergedCoinsByMarketIdentity = [MarketIdentity: CoinInfo]()
    var orderedMarketIdentities = [MarketIdentity]()

    for coin in coins {
        let marketIdentity = coin.marketIdentity(exchange: exchange)
        if let existing = mergedCoinsByMarketIdentity[marketIdentity] {
            mergedCoinsByMarketIdentity[marketIdentity] = existing.merged(with: coin)
        } else {
            mergedCoinsByMarketIdentity[marketIdentity] = coin
            orderedMarketIdentities.append(marketIdentity)
        }
    }

    return orderedMarketIdentities.compactMap { mergedCoinsByMarketIdentity[$0] }
}

private func deduplicatedSymbols(_ symbols: [String]) -> [String] {
    var seenSymbols = Set<String>()
    return symbols.filter { symbol in
        seenSymbols.insert(symbol).inserted
    }
}

private func marketImageURL(from dictionary: JSONObject) -> String? {
    let directValue = dictionary.string([
        "assetImageUrl",
        "assetImageURL",
        "asset_image_url",
        "coinGeckoImageUrl",
        "coingeckoImageUrl",
        "coingecko_image_url",
        "imageUrl",
        "imageURL",
        "image_url",
        "iconUrl",
        "iconURL",
        "icon_url",
        "logoUrl",
        "logoURL",
        "logo_url",
        "thumbnail",
        "thumb",
        "image"
    ])

    let nestedAssetValue = (dictionary["asset"] as? JSONObject)?.string([
        "assetImageUrl",
        "assetImageURL",
        "asset_image_url",
        "imageUrl",
        "imageURL",
        "image_url",
        "iconUrl",
        "iconURL",
        "icon_url",
        "logoUrl",
        "logoURL",
        "logo_url"
    ])

    let nestedMetadataValue = (dictionary["metadata"] as? JSONObject)?.string([
        "assetImageUrl",
        "assetImageURL",
        "asset_image_url",
        "imageUrl",
        "imageURL",
        "image_url",
        "iconUrl",
        "iconURL",
        "icon_url",
        "logoUrl",
        "logoURL",
        "logo_url"
    ])

    return normalizedMarketImageURLString(
        directValue ?? nestedAssetValue ?? nestedMetadataValue
    )
}

private func marketCanonicalAssetKey(from dictionary: JSONObject) -> String? {
    let directValue = dictionary.string([
        "canonicalAssetKey",
        "canonical_asset_key",
        "assetKey",
        "asset_key",
        "coingeckoId",
        "coinGeckoId",
        "coingecko_id"
    ])
    let nestedValue = (dictionary["asset"] as? JSONObject)?.string([
        "canonicalAssetKey",
        "canonical_asset_key",
        "assetKey",
        "asset_key",
        "coingeckoId",
        "coinGeckoId",
        "coingecko_id"
    ])

    let value = (directValue ?? nestedValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let value, !value.isEmpty {
        return value
    }
    return nil
}

private func marketRawSymbol(from dictionary: JSONObject) -> String? {
    dictionary.string([
        "canonicalSymbol",
        "canonical_symbol",
        "displaySymbol",
        "display_symbol",
        "ticker",
        "symbol",
        "marketId",
        "market_id",
        "market",
        "code",
        "baseAsset",
        "base_asset",
        "baseCurrency",
        "base_currency",
        "asset",
        "currency",
        "target_currency",
        "targetCurrency"
    ])
}

private func marketId(from dictionary: JSONObject) -> String? {
    dictionary.string([
        "marketId",
        "market_id",
        "market",
        "code",
        "pair",
        "pairCode",
        "pair_code"
    ])
}

private func marketBaseAsset(from dictionary: JSONObject) -> String? {
    dictionary.string([
        "baseAsset",
        "base_asset",
        "baseCurrency",
        "base_currency",
        "target_currency",
        "targetCurrency",
        "asset",
        "currency"
    ]) ?? (dictionary["asset"] as? JSONObject)?.string([
        "symbol",
        "code",
        "baseAsset",
        "base_asset"
    ])
}

private func marketQuoteAsset(from dictionary: JSONObject) -> String? {
    dictionary.string([
        "quoteAsset",
        "quote_asset",
        "quoteCurrency",
        "quote_currency",
        "marketCurrency",
        "market_currency",
        "paymentCurrency",
        "payment_currency"
    ])
}

private func marketCanonicalSymbol(from dictionary: JSONObject) -> String? {
    dictionary.string([
        "canonicalSymbol",
        "canonical_symbol",
        "canonicalAsset",
        "canonical_asset"
    ])
}

private func marketDisplaySymbol(from dictionary: JSONObject) -> String? {
    dictionary.string([
        "displaySymbol",
        "display_symbol",
        "ticker",
        "symbol"
    ])
}

private func marketDisplayMetadata(
    from dictionary: JSONObject,
    exchange: Exchange,
    rawSymbol: String,
    displayName: String?,
    englishName: String?,
    imageURL: String?,
    hasImage: Bool?,
    localAssetName: String?
) -> CoinDisplayMetadata {
    let resolvedCanonicalSymbol = marketCanonicalSymbol(from: dictionary)
        ?? SymbolNormalization.canonicalAlias(for: assetKeyOrLocalAssetName(localAssetName))
    return CoinDisplayMetadata(
        exchange: exchange,
        rawSymbol: rawSymbol,
        marketId: marketId(from: dictionary),
        baseAsset: marketBaseAsset(from: dictionary),
        quoteAsset: marketQuoteAsset(from: dictionary),
        canonicalSymbol: resolvedCanonicalSymbol,
        displaySymbol: marketDisplaySymbol(from: dictionary),
        koreanName: displayName,
        englishName: englishName,
        iconURL: imageURL,
        hasImage: hasImage,
        localAssetName: localAssetName,
        isChartAvailable: dictionary.bool(["isChartAvailable", "chartAvailable", "supportsChart"]),
        isOrderBookAvailable: dictionary.bool(["isOrderBookAvailable", "orderBookAvailable", "orderbookAvailable", "supportsOrderBook", "supportsOrderbook"]),
        isTradesAvailable: dictionary.bool(["isTradesAvailable", "tradesAvailable", "supportsTrades"]),
        unavailableReason: dictionary.string(["unavailableReason", "unavailable_reason", "reason", "statusMessage"])
    )
}

private func assetKeyOrLocalAssetName(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    if value.hasPrefix("coin.") {
        return String(value.dropFirst("coin.".count))
    }
    return value
}

private func marketHasImage(from dictionary: JSONObject) -> Bool? {
    let keys = [
        "hasImage",
        "has_image",
        "hasIcon",
        "has_icon",
        "imageAvailable",
        "image_available",
        "isImageAvailable",
        "iconAvailable",
        "icon_available",
        "isIconAvailable"
    ]

    return dictionary.bool(keys)
        ?? (dictionary["asset"] as? JSONObject)?.bool(keys)
        ?? (dictionary["metadata"] as? JSONObject)?.bool(keys)
}

private func normalizedMarketImageURLString(_ rawValue: String?) -> String? {
    guard var normalizedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !normalizedValue.isEmpty else {
        return nil
    }

    if normalizedValue.hasPrefix("//") {
        normalizedValue = "https:\(normalizedValue)"
    } else if normalizedValue.contains("://") == false,
              normalizedValue.hasPrefix("www.") || normalizedValue.contains("assets.coingecko.com") {
        normalizedValue = "https://\(normalizedValue)"
    }

    if let components = URLComponents(string: normalizedValue),
       components.scheme != nil,
       components.host != nil {
        return components.string
    }

    let allowedCharacters = CharacterSet.urlFragmentAllowed
    if let encodedValue = normalizedValue.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
       let components = URLComponents(string: encodedValue),
       components.scheme != nil,
       components.host != nil {
        return components.string
    }

    return nil
}

private struct OrderbookDTO {
    let asks: [OrderbookEntry]
    let bids: [OrderbookEntry]
    let timestamp: Date?
    let isStale: Bool

    init?(dictionary: JSONObject) {
        let parsedAsks = parseOrderbookEntries(dictionary["asks"] ?? dictionary["sell"], isBid: false)
        let parsedBids = parseOrderbookEntries(dictionary["bids"] ?? dictionary["buy"], isBid: true)

        if parsedAsks.isEmpty && parsedBids.isEmpty, let units = unwrapArray(dictionary["orderbook_units"]) {
            self.asks = units.compactMap { item -> OrderbookEntry? in
                guard let unit = item as? JSONObject else { return nil }
                guard
                    let price = unit.double(["ask_price", "askPrice"]),
                    let quantity = unit.double(["ask_size", "askSize"])
                else {
                    return nil
                }
                return OrderbookEntry(price: price, qty: quantity)
            }
            self.bids = units.compactMap { item -> OrderbookEntry? in
                guard let unit = item as? JSONObject else { return nil }
                guard
                    let price = unit.double(["bid_price", "bidPrice"]),
                    let quantity = unit.double(["bid_size", "bidSize"])
                else {
                    return nil
                }
                return OrderbookEntry(price: price, qty: quantity)
            }
        } else {
            self.asks = parsedAsks
            self.bids = parsedBids
        }

        guard !asks.isEmpty || !bids.isEmpty else {
            return nil
        }

        self.timestamp = parseDateValue(dictionary["timestamp"] ?? dictionary["updatedAt"])
        self.isStale = dictionary.bool(["stale", "isStale"]) ?? false
    }

    func entity(meta: ResponseMeta) -> OrderbookData {
        OrderbookData(asks: asks, bids: bids, timestamp: timestamp ?? meta.fetchedAt, isStale: isStale || meta.isStale)
    }
}

private struct PublicTradeDTO {
    let entity: PublicTrade

    init?(dictionary: JSONObject) {
        guard let price = dictionary.double(["price", "tradePrice", "trade_price"]) else {
            return nil
        }

        let tradeTime = TradeTimestampParser.parse(
            candidates: [
                ("executedAt", dictionary["executedAt"]),
                ("tradeTimestamp", dictionary["tradeTimestamp"] ?? dictionary["trade_timestamp"]),
                ("createdAt", dictionary["createdAt"] ?? dictionary["created_at"]),
                ("timestamp", dictionary["timestamp"]),
                ("time", dictionary["time"])
            ],
            logContext: "rest_public_trade"
        )
        self.entity = PublicTrade(
            id: dictionary.string(["id", "tradeId", "trade_id"]) ?? UUID().uuidString,
            price: price,
            quantity: dictionary.double(["quantity", "qty", "volume", "size"]) ?? 0,
            side: dictionary.string(["side", "askBid", "ask_bid"]) ?? "buy",
            executedAt: tradeTime.displayText,
            executedDate: tradeTime.date
        )
    }
}

private struct CandleDTO {
    let entity: CandleData

    init?(dictionary: JSONObject) {
        guard
            let open = dictionary.double(["open", "openingPrice", "opening_price"]),
            let high = dictionary.double(["high", "highPrice", "high_price"]),
            let low = dictionary.double(["low", "lowPrice", "low_price"]),
            let close = dictionary.double(["close", "tradePrice", "trade_price"])
        else {
            return nil
        }

        let timestamp = parseDateValue(dictionary["timestamp"] ?? dictionary["time"] ?? dictionary["candleDateTimeKst"] ?? dictionary["candle_date_time_utc"])
        self.entity = CandleData(
            time: Int((timestamp ?? Date()).timeIntervalSince1970),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: dictionary.int(["volume", "candleAccTradeVolume", "candle_acc_trade_volume"]) ?? 0
        )
    }
}

private struct TradingChanceDTO {
    let entity: TradingChance

    init?(dictionary: JSONObject, exchange: Exchange, symbol: String) {
        let supportedOrderTypes = dictionary.stringArray(["supportedOrderTypes", "orderTypes", "supported_types"])
            .compactMap { OrderType(rawValue: $0.lowercased()) }
        self.entity = TradingChance(
            exchange: exchange,
            symbol: symbol,
            supportedOrderTypes: supportedOrderTypes.isEmpty ? [.limit, .market] : supportedOrderTypes,
            minimumOrderAmount: dictionary.double(["minimumOrderAmount", "minTotal", "min_amount"]),
            maximumOrderAmount: dictionary.double(["maximumOrderAmount", "maxTotal", "max_amount"]),
            priceUnit: dictionary.double(["priceUnit", "tickSize", "price_unit"]),
            quantityPrecision: dictionary.int(["quantityPrecision", "volumePrecision", "qtyPrecision"]),
            bidBalance: dictionary.double(["bidBalance", "buyingBalance", "availableAskQuoteAmount", "cashBalance"]) ?? 0,
            askBalance: dictionary.double(["askBalance", "availableBaseAmount", "availableBidBaseAmount", "assetBalance"]) ?? 0,
            feeRate: dictionary.double(["feeRate", "makerFeeRate", "fee"]),
            warningMessage: dictionary.string(["warningMessage", "message"])
        )
    }
}

private struct TradingOrderDTO {
    let entity: OrderRecord

    init?(dictionary: JSONObject, exchange: Exchange) {
        let price = dictionary.double(["price", "limitPrice", "avgPrice", "avg_price"]) ?? 0
        let quantity = dictionary.double(["quantity", "qty", "volume"]) ?? 0
        let executedQuantity = dictionary.double(["executedQuantity", "filledQuantity", "executed_volume"]) ?? 0
        let remainingQuantity = dictionary.double(["remainingQuantity", "remainingVolume", "remaining_qty"]) ?? max(quantity - executedQuantity, 0)
        let createdAt = parseDateValue(dictionary["createdAt"] ?? dictionary["created_at"] ?? dictionary["timestamp"] ?? dictionary["time"])
        let rawOrderType = dictionary.string(["orderType", "type", "ordType"])?.lowercased() ?? OrderType.limit.rawValue

        self.entity = OrderRecord(
            id: dictionary.string(["id", "orderId", "order_id", "uuid"]) ?? UUID().uuidString,
            symbol: dictionary.string(["symbol", "market", "asset"])?.uppercased() ?? "-",
            side: dictionary.string(["side"]) ?? "buy",
            orderType: OrderType(rawValue: rawOrderType) ?? .limit,
            price: price,
            averageExecutedPrice: dictionary.double(["averageExecutedPrice", "avgExecutedPrice", "avg_price"]),
            qty: quantity,
            executedQuantity: executedQuantity,
            remainingQuantity: remainingQuantity,
            total: dictionary.double(["total", "notional"]) ?? price * quantity,
            time: formatTimestamp(createdAt),
            createdAt: createdAt,
            exchange: dictionary.string(["exchange"]) ?? exchange.displayName,
            status: dictionary.string(["status", "state"]) ?? "unknown",
            canCancel: dictionary.bool(["canCancel", "cancelable", "isCancelable"]) ?? (remainingQuantity > 0)
        )
    }
}

private struct TradingFillDTO {
    let entity: TradeFill

    init?(dictionary: JSONObject, exchange: Exchange) {
        guard let price = dictionary.double(["price", "executedPrice", "trade_price"]) else {
            return nil
        }

        let executedAt = parseDateValue(dictionary["executedAt"] ?? dictionary["time"] ?? dictionary["timestamp"])
        self.entity = TradeFill(
            id: dictionary.string(["id", "fillId", "tradeId"]) ?? UUID().uuidString,
            orderID: dictionary.string(["orderId", "order_id"]) ?? "-",
            symbol: dictionary.string(["symbol", "market", "asset"])?.uppercased() ?? "-",
            side: dictionary.string(["side"]) ?? "buy",
            price: price,
            quantity: dictionary.double(["quantity", "qty", "volume"]) ?? 0,
            fee: dictionary.double(["fee", "paidFee", "fee_amount"]) ?? 0,
            executedAtText: formatTimestamp(executedAt),
            executedAt: executedAt,
            exchange: exchange
        )
    }
}

private struct PortfolioSummaryDTO {
    let entity: PortfolioSnapshot

    init?(dictionary: JSONObject, exchange: Exchange, meta: ResponseMeta) {
        let holdingsArray = unwrapArray(dictionary["holdings"] ?? dictionary["assets"] ?? dictionary["balances"]) ?? []
        let holdings = holdingsArray.compactMap { item -> Holding? in
            guard let holdingDictionary = item as? JSONObject else {
                return nil
            }

            guard let symbol = holdingDictionary.string(["symbol", "asset", "currency"]) else {
                return nil
            }

            let totalQuantity = holdingDictionary.double(["totalQuantity", "total", "balance", "qty", "quantity"]) ?? 0
            let availableQuantity = holdingDictionary.double(["availableQuantity", "available", "free"]) ?? totalQuantity
            let lockedQuantity = holdingDictionary.double(["lockedQuantity", "locked", "hold"]) ?? max(totalQuantity - availableQuantity, 0)
            let averageBuyPrice = holdingDictionary.double(["averageBuyPrice", "avgPrice", "avg_buy_price"]) ?? 0
            let evaluationAmount = holdingDictionary.double(["evaluationAmount", "evaluation", "marketValue"]) ?? 0
            let profitLoss = holdingDictionary.double(["profitLoss", "pnl"]) ?? 0
            let rawProfitLossRate = holdingDictionary.double(["profitLossRate", "pnlRate"]) ?? 0
            let normalizedProfitLossRate = abs(rawProfitLossRate) <= 1 ? rawProfitLossRate * 100 : rawProfitLossRate

            return Holding(
                symbol: symbol.uppercased(),
                totalQuantity: totalQuantity,
                availableQuantity: availableQuantity,
                lockedQuantity: lockedQuantity,
                averageBuyPrice: averageBuyPrice,
                evaluationAmount: evaluationAmount,
                profitLoss: profitLoss,
                profitLossRate: normalizedProfitLossRate
            )
        }

        self.entity = PortfolioSnapshot(
            exchange: exchange,
            totalAsset: dictionary.double(["totalAsset", "totalEvaluationAmount", "total_asset"]) ?? holdings.reduce(0) { $0 + $1.evaluationAmount },
            availableAsset: dictionary.double(["availableAsset", "availableEvaluationAmount", "available_asset"]) ?? holdings.reduce(0) { $0 + ($1.availableQuantity * $1.averageBuyPrice) },
            lockedAsset: dictionary.double(["lockedAsset", "lockedEvaluationAmount", "locked_asset"]) ?? holdings.reduce(0) { $0 + ($1.lockedQuantity * $1.averageBuyPrice) },
            cash: dictionary.double(["cash", "krwBalance", "availableCash", "cashBalance"]) ?? 0,
            holdings: holdings,
            fetchedAt: meta.fetchedAt,
            isStale: meta.isStale || dictionary.bool(["stale", "isStale"]) == true,
            partialFailureMessage: meta.partialFailureMessage ?? dictionary.string(["partialFailureMessage", "warningMessage"])
        )
    }
}

private struct PortfolioHistoryItemDTO {
    let entity: PortfolioHistoryItem

    init?(dictionary: JSONObject, exchange: Exchange) {
        let occurredAt = parseDateValue(dictionary["occurredAt"] ?? dictionary["timestamp"] ?? dictionary["time"])
        let type = dictionary.string(["type", "eventType", "kind"]) ?? "-"
        let detail = dictionary.string(["detail", "description", "message"]) ?? ""
        let status = dictionary.string(["status", "state"]) ?? "-"
        let rawSourceLabel = dictionary.string([
            "source",
            "sourceType",
            "source_type",
            "eventSource",
            "event_source",
            "origin",
            "scope"
        ])
        let symbol = dictionary.string(["symbol", "asset", "currency"])?.uppercased() ?? "-"
        let eventSource = Self.resolveEventSource(
            type: type,
            detail: detail,
            status: status,
            rawSourceLabel: rawSourceLabel
        )
        let relatedEventIdentifier = dictionary.string([
            "tradeId",
            "trade_id",
            "fillId",
            "fill_id",
            "orderId",
            "order_id",
            "transactionId",
            "transaction_id",
            "txId",
            "tx_id",
            "transferId",
            "transfer_id",
            "depositId",
            "deposit_id",
            "withdrawalId",
            "withdrawal_id",
            "executionId",
            "execution_id"
        ])
        let hasUserScope = Self.hasUserScope(dictionary)
        let hasExplicitVerification = dictionary.bool([
            "isUserEvent",
            "userEvent",
            "verifiedUserEvent",
            "verified",
            "isVerified",
            "isReal",
            "real",
            "actual"
        ]) == true
        let isMockLike = Self.isMockLike(
            dictionary: dictionary,
            type: type,
            detail: detail,
            status: status,
            rawSourceLabel: rawSourceLabel
        )
        self.entity = PortfolioHistoryItem(
            id: dictionary.string(["id", "historyId"]) ?? UUID().uuidString,
            exchange: exchange,
            symbol: symbol,
            type: type,
            amount: dictionary.double(["amount", "quantity", "qty", "balance"]) ?? 0,
            detail: detail,
            occurredAt: occurredAt,
            status: status,
            eventSource: eventSource,
            rawSourceLabel: rawSourceLabel,
            isVerifiedUserEvent: Self.isVerifiedUserEvent(
                eventSource: eventSource,
                symbol: symbol,
                occurredAt: occurredAt,
                hasUserScope: hasUserScope,
                hasExplicitVerification: hasExplicitVerification,
                relatedEventIdentifier: relatedEventIdentifier,
                isMockLike: isMockLike
            ),
            isMockLike: isMockLike,
            hasUserScope: hasUserScope,
            relatedEventIdentifier: relatedEventIdentifier
        )
    }

    private static func resolveEventSource(
        type: String,
        detail: String,
        status: String,
        rawSourceLabel: String?
    ) -> PortfolioHistoryEventSource {
        let normalizedValue = [type, detail, status, rawSourceLabel]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if containsAny(["deposit", "입금"], within: normalizedValue) {
            return .deposit
        }
        if containsAny(["withdraw", "withdrawal", "출금"], within: normalizedValue) {
            return .withdrawal
        }
        if containsAny(["transfer", "movement", "이체"], within: normalizedValue) {
            return .transfer
        }
        if containsAny(["trade", "fill", "filled", "execution", "executed", "buy", "sell", "체결", "매수", "매도"], within: normalizedValue) {
            return .tradeFill
        }
        if containsAny(["realized", "balance change", "asset change", "pnl", "settlement", "정산", "잔고"], within: normalizedValue) {
            return .realizedBalanceChange
        }
        return .unknown
    }

    private static func hasUserScope(_ dictionary: JSONObject) -> Bool {
        dictionary.string([
            "userId",
            "user_id",
            "accountId",
            "account_id",
            "walletId",
            "wallet_id",
            "portfolioId",
            "portfolio_id",
            "memberId",
            "member_id",
            "ownerId",
            "owner_id"
        ])?.isEmpty == false
    }

    private static func isVerifiedUserEvent(
        eventSource: PortfolioHistoryEventSource,
        symbol: String,
        occurredAt: Date?,
        hasUserScope: Bool,
        hasExplicitVerification: Bool,
        relatedEventIdentifier: String?,
        isMockLike: Bool
    ) -> Bool {
        guard symbol != "-", occurredAt != nil, isMockLike == false else {
            return false
        }
        if hasExplicitVerification || hasUserScope {
            return true
        }

        switch eventSource {
        case .tradeFill, .deposit, .withdrawal, .transfer:
            return relatedEventIdentifier?.isEmpty == false
        case .realizedBalanceChange, .unknown:
            return false
        }
    }

    private static func isMockLike(
        dictionary: JSONObject,
        type: String,
        detail: String,
        status: String,
        rawSourceLabel: String?
    ) -> Bool {
        if dictionary.bool([
            "isMock",
            "mock",
            "isSample",
            "sample",
            "isSeed",
            "seed",
            "isPlaceholder",
            "placeholder",
            "isSynthetic",
            "synthetic",
            "isGenerated",
            "generated",
            "isFallback",
            "fallback",
            "isDebug",
            "debug",
            "isTest",
            "test"
        ]) == true {
            return true
        }

        let normalizedValue = [type, detail, status, rawSourceLabel]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return containsAny(
            ["mock", "sample", "seed", "placeholder", "synthetic", "generated", "fallback", "debug", "test", "demo"],
            within: normalizedValue
        )
    }

    private static func containsAny(_ candidates: [String], within value: String) -> Bool {
        candidates.contains { value.contains($0) }
    }
}

private struct KimchiPremiumRowDTO {
    let entity: KimchiPremiumRow

    init?(dictionary: JSONObject) {
        guard let symbol = normalizeKimchiPremiumSymbol(from: dictionary) else {
            return nil
        }
        let exchange = Exchange(rawValue: (dictionary.string(["exchange", "domesticExchange"]) ?? "").lowercased()) ?? .upbit
        let sourceExchange = Exchange(rawValue: (dictionary.string(["sourceExchange", "exchange"]) ?? exchange.rawValue).lowercased()) ?? exchange
        let timestamp = parseDateValue(dictionary["timestamp"] ?? dictionary["updatedAt"])
        let sourceExchangeTimestamp = parseDateValue(dictionary["sourceExchangeTimestamp"] ?? dictionary["localTimestamp"])
        let referenceTimestamp = parseDateValue(dictionary["referenceTimestamp"] ?? dictionary["globalTimestamp"])
        let explicitFreshness = dictionary.string([
            "freshnessState",
            "freshness",
            "dataFreshness",
            "freshnessStatus",
            "status"
        ])
        let freshnessState = explicitFreshness.map { KimchiPremiumFreshnessState(rawServerValue: $0) }
        let freshnessReason = dictionary.string([
            "freshnessReason",
            "staleReason",
            "delayReason",
            "warningMessage",
            "reason"
        ])
        self.entity = KimchiPremiumRow(
            id: dictionary.string(["id"]) ?? "\(symbol)-\(exchange.rawValue)",
            symbol: symbol,
            exchange: exchange,
            sourceExchange: sourceExchange,
            domesticPrice: dictionary.double(["domesticPrice", "price", "localPrice"]),
            referenceExchangePrice: dictionary.double(["referenceExchangePrice", "globalPrice", "foreignPrice"]),
            premiumPercent: Self.normalizePercent(dictionary.double(["premiumPercent", "premium", "kimchiPremium"])),
            krwConvertedReference: dictionary.double(["krwConvertedReference", "krwReferencePrice"]),
            usdKrwRate: dictionary.double(["usdKrwRate", "fxRate", "usd_krw"]),
            timestamp: timestamp,
            sourceExchangeTimestamp: sourceExchangeTimestamp,
            referenceTimestamp: referenceTimestamp,
            isStale: dictionary.bool(["stale", "isStale"]) ?? false,
            staleReason: dictionary.string(["staleReason", "warningMessage"]),
            freshnessState: freshnessState,
            freshnessReason: freshnessReason,
            updatedAt: parseDateValue(dictionary["updatedAt"] ?? dictionary["asOf"] ?? dictionary["updated_at"])
                ?? timestamp
                ?? sourceExchangeTimestamp
                ?? referenceTimestamp
        )
    }

    private static func normalizePercent(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return abs(value) <= 1 ? value * 100 : value
    }
}

private func normalizeKimchiPremiumSymbol(from dictionary: JSONObject) -> String? {
    if let canonicalSymbol = dictionary.string([
        "canonicalSymbol",
        "canonical_symbol",
        "compareSymbol",
        "compare_symbol"
    ]) {
        return normalizeMarketSymbol(canonicalSymbol)
    }

    if let rawSymbol = dictionary.string([
        "symbol",
        "market",
        "code",
        "sourceSymbol",
        "source_symbol",
        "referenceSymbol",
        "reference_symbol",
        "baseAsset",
        "asset"
    ]) {
        return normalizeMarketSymbol(rawSymbol)
    }

    return nil
}

private struct ExchangeConnectionDTO {
    let entity: ExchangeConnection

    init?(dictionary: JSONObject) {
        guard let rawExchange = dictionary.string(["exchange", "name"]) else {
            return nil
        }
        guard let exchange = Exchange(rawValue: rawExchange.lowercased()) else {
            return nil
        }

        let rawPermission = dictionary.string(["permission", "scope", "mode"])?.lowercased()
        let permission: ExchangeConnectionPermission
        if let canTrade = dictionary.bool(["canTrade", "can_trade"]) {
            permission = canTrade ? .tradeEnabled : .readOnly
        } else {
            permission = rawPermission == ExchangeConnectionPermission.tradeEnabled.rawValue ? .tradeEnabled : .readOnly
        }

        let statusRawValue = dictionary.string(["status", "connectionStatus", "validationStatus"])?.lowercased()
        let status: ExchangeConnectionStatus
        switch statusRawValue {
        case "connected", "active", "validated":
            status = .connected
        case "disconnected", "inactive":
            status = .disconnected
        case "validating", "pending":
            status = .validating
        case "failed", "error", "authentication_failed":
            status = .failed
        case "maintenance":
            status = .maintenance
        default:
            status = .unknown
        }

        self.entity = ExchangeConnection(
            id: dictionary.string(["id", "connectionId", "connection_id"]) ?? exchange.rawValue,
            exchange: exchange,
            permission: permission,
            nickname: dictionary.string(["nickname", "label"]),
            isActive: dictionary.bool(["isActive", "is_active", "enabled"]) ?? (status != .disconnected),
            status: status,
            statusMessage: dictionary.string(["statusMessage", "validationMessage", "message"]),
            maskedCredentialSummary: dictionary.string(["maskedCredentialSummary", "maskedCredential", "credentialSummary"]),
            lastValidatedAt: parseDateValue(dictionary["lastValidatedAt"] ?? dictionary["validatedAt"]),
            updatedAt: parseDateValue(dictionary["updatedAt"] ?? dictionary["updated_at"])
        )
    }
}

private func splitPayload(_ json: Any) -> (payload: Any, meta: ResponseMeta) {
    guard let dictionary = json as? JSONObject else {
        return (json, .empty)
    }

    let payload = unwrapPayload(dictionary)
    let freshness = dictionary.string(["freshness", "dataFreshness", "status"])?.lowercased()
    let meta = ResponseMeta(
        fetchedAt: parseDateValue(dictionary["asOf"] ?? dictionary["fetchedAt"] ?? dictionary["timestamp"] ?? dictionary["serverTime"]),
        isStale: dictionary.bool(["stale", "isStale"]) ?? (freshness == "stale"),
        warningMessage: dictionary.string(["warningMessage", "message"]),
        partialFailureMessage: dictionary.string(["partialFailureMessage", "partialError", "partial_error"]),
        isChartAvailable: dictionary.bool(["isChartAvailable", "chartAvailable", "supportsChart"]),
        isOrderBookAvailable: dictionary.bool(["isOrderBookAvailable", "orderBookAvailable", "orderbookAvailable", "supportsOrderBook", "supportsOrderbook"]),
        isTradesAvailable: dictionary.bool(["isTradesAvailable", "tradesAvailable", "supportsTrades"]),
        unavailableReason: dictionary.string(["unavailableReason", "unavailable_reason", "reason"])
    )

    return (payload, meta)
}

private func unwrapPayload(_ json: Any) -> Any {
    guard let dictionary = json as? JSONObject else { return json }
    for key in ["data", "result", "payload"] {
        if let nested = dictionary[key] {
            return nested
        }
    }
    return json
}

private func unwrapArray(_ value: Any?) -> [Any]? {
    if let array = value as? [Any] {
        return array
    }
    if let dictionary = value as? JSONObject {
        for key in ["items", "rows", "results", "list"] {
            if let nested = dictionary[key] as? [Any] {
                return nested
            }
        }
    }
    return nil
}

private func normalizeMarketSymbol(from dictionary: JSONObject) -> String? {
    guard let rawSymbol = marketRawSymbol(from: dictionary) else {
        return nil
    }

    return SymbolNormalization.canonicalAssetCode(
        rawSymbol: rawSymbol,
        marketId: marketId(from: dictionary),
        baseAsset: marketBaseAsset(from: dictionary),
        quoteAsset: marketQuoteAsset(from: dictionary),
        canonicalSymbol: marketCanonicalSymbol(from: dictionary)
    )
}

private func normalizeMarketSymbol(_ rawSymbol: String) -> String {
    SymbolNormalization.canonicalAssetCode(rawSymbol: rawSymbol)
}

private func debugJSONString(_ value: Any, limit: Int = 1_200) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
          var string = String(data: data, encoding: .utf8) else {
        return String(describing: value)
    }

    if string.count > limit {
        string = String(string.prefix(limit)) + "…"
    }
    return string
}

private func maskedDebugJSONString(_ value: Any, limit: Int = 600) -> String {
    debugJSONString(maskSensitiveLogValue(value), limit: limit)
}

private func maskSensitiveLogValue(_ value: Any, parentKey: String? = nil) -> Any {
    if let dictionary = value as? JSONObject {
        return dictionary.reduce(into: JSONObject()) { result, item in
            result[item.key] = maskSensitiveLogValue(item.value, parentKey: item.key)
        }
    }

    if let array = value as? [Any] {
        return array.map { item in
            maskSensitiveLogValue(item, parentKey: parentKey)
        }
    }

    let normalizedKey = parentKey?.lowercased() ?? ""
    let shouldMask =
        normalizedKey.contains("password")
        || normalizedKey.contains("token")
        || normalizedKey.contains("access")
        || normalizedKey.contains("secret")
        || normalizedKey.contains("key")
        || normalizedKey.contains("email")
        || normalizedKey.contains("credential")

    if shouldMask {
        return AppLogger.masked(String(describing: value))
    }

    return value
}

private func parseOrderbookEntries(_ value: Any?, isBid: Bool) -> [OrderbookEntry] {
    let array = unwrapArray(value) ?? []
    return array.compactMap { item in
        guard let dictionary = item as? JSONObject else {
            return nil
        }

        let priceKeys = isBid ? ["price", "bidPrice", "bid_price"] : ["price", "askPrice", "ask_price"]
        let quantityKeys = isBid ? ["qty", "quantity", "size", "bidSize", "bid_size"] : ["qty", "quantity", "size", "askSize", "ask_size"]

        guard let price = dictionary.double(priceKeys), let quantity = dictionary.double(quantityKeys) else {
            return nil
        }

        return OrderbookEntry(price: price, qty: quantity)
    }
}

private func parseDateValue(_ rawValue: Any?) -> Date? {
    switch rawValue {
    case let number as NSNumber:
        let timestamp = number.doubleValue > 1_000_000_000_000 ? number.doubleValue / 1000 : number.doubleValue
        return Date(timeIntervalSince1970: timestamp)
    case let string as String:
        if let timestamp = Double(string) {
            let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        if let date = iso8601Formatter.date(from: string) {
            return date
        }
        if let date = alternateISO8601Formatter.date(from: string) {
            return date
        }
        return nil
    default:
        return nil
    }
}

private func parseSparklinePoints(from dictionary: JSONObject) -> [Double] {
    for key in ["sparkline", "sparklinePoints", "sparkline_points", "trend", "history", "prices"] {
        if let points = parseDoubleArray(dictionary[key]) {
            return points
        }

        if let nested = dictionary[key] as? JSONObject {
            for nestedKey in ["points", "values", "prices", "items"] {
                if let points = parseDoubleArray(nested[nestedKey]) {
                    return points
                }
            }
        }
    }

    return []
}

private func parseSparklinePointCount(from dictionary: JSONObject) -> Int? {
    if let pointCount = dictionary.int([
        "sparklinePointCount",
        "sparkline_point_count",
        "sparklinePointsCount",
        "sparkline_points_count",
        "pointCount",
        "point_count"
    ]) {
        return pointCount
    }

    for key in ["sparkline", "sparklinePoints", "sparkline_points", "trend", "history", "prices"] {
        if let nested = dictionary[key] as? JSONObject,
           let pointCount = nested.int(["pointCount", "point_count", "count"]) {
            return pointCount
        }
    }

    return nil
}

private func parseDoubleArray(_ rawValue: Any?) -> [Double]? {
    guard let array = unwrapArray(rawValue) else {
        return nil
    }

    let points = array.compactMap { item -> Double? in
        if let value = item as? Double {
            return value
        }
        if let value = item as? NSNumber {
            return value.doubleValue
        }
        if let value = item as? String {
            return Double(value.replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }

    return points.count >= 2 ? points : nil
}

private func formatTimestamp(_ date: Date?) -> String {
    guard let date else { return "-" }
    return shortTimeFormatter.string(from: date)
}

private func normalizePercent(_ value: Double) -> Double {
    abs(value) <= 1 ? value * 100 : value
}

private let shortTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let alternateISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private extension Dictionary where Key == String, Value == Any {
    func string(_ keys: [String]) -> String? {
        for key in keys {
            if let value = self[key] as? String, !value.isEmpty {
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
                return array.compactMap { item -> String? in
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

private extension URL {
    func appendingEndpointPath(_ endpointPath: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return appendingPathComponent(endpointPath)
        }

        let trimmedBase = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let normalizedEndpoint = endpointPath.hasPrefix("/") ? endpointPath : "/\(endpointPath)"
        components.path = "\(trimmedBase)\(normalizedEndpoint)"
        return components.url ?? appendingPathComponent(endpointPath)
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Dictionary where Key == ExchangeCredentialFieldKey, Value == String {
    func mapKeys(_ transform: (ExchangeCredentialFieldKey) -> String) -> [String: String] {
        Dictionary<String, String>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}
