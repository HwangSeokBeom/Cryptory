import Foundation

typealias JSONObject = [String: Any]

enum RequestAccessRequirement: String {
    case publicAccess = "public"
    case authenticatedRequired = "authenticated"
}

enum NetworkServiceError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, String)
    case authenticationRequired
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "잘못된 서버 경로입니다: \(path)"
        case .invalidResponse:
            return "서버 응답을 확인할 수 없어요."
        case .httpError(_, let message):
            return message
        case .authenticationRequired:
            return "로그인이 필요한 요청이에요."
        case .parsingFailed(let message):
            return message
        }
    }
}

struct APIConfiguration {
    static let publicPrefix = "/api/v1/public"
    static let privatePrefix = "/api/v1/private"

    let baseURL: String
    let loginPath: String
    let tickersPath: String
    let candlesPath: String
    let orderbookPath: String
    let tradesPath: String
    let portfolioPath: String
    let ordersPath: String
    let exchangeConnectionsPath: String
    let exchangeConnectionsCreateEnabled: Bool
    let exchangeConnectionsDeleteEnabled: Bool

    func exchangeConnectionPath(id: String) -> String {
        "\(exchangeConnectionsPath)/\(id)"
    }

    static let live = APIConfiguration(
        baseURL: ProcessInfo.processInfo.environment["CRYPTORY_API_BASE_URL"] ?? "https://api.cryptomts.com",
        loginPath: ProcessInfo.processInfo.environment["CRYPTORY_LOGIN_PATH"] ?? "\(publicPrefix)/auth/login",
        tickersPath: ProcessInfo.processInfo.environment["CRYPTORY_PUBLIC_TICKERS_PATH"] ?? "\(publicPrefix)/markets/tickers",
        candlesPath: ProcessInfo.processInfo.environment["CRYPTORY_PUBLIC_CANDLES_PATH"] ?? "\(publicPrefix)/markets/candles",
        orderbookPath: ProcessInfo.processInfo.environment["CRYPTORY_PUBLIC_ORDERBOOK_PATH"] ?? "\(publicPrefix)/markets/orderbook",
        tradesPath: ProcessInfo.processInfo.environment["CRYPTORY_PUBLIC_TRADES_PATH"] ?? "\(publicPrefix)/markets/trades",
        portfolioPath: ProcessInfo.processInfo.environment["CRYPTORY_PORTFOLIO_PATH"] ?? "\(privatePrefix)/portfolio",
        ordersPath: ProcessInfo.processInfo.environment["CRYPTORY_ORDERS_PATH"] ?? "\(privatePrefix)/orders",
        exchangeConnectionsPath: ProcessInfo.processInfo.environment["CRYPTORY_EXCHANGE_CONNECTIONS_PATH"] ?? "\(privatePrefix)/exchange-connections",
        exchangeConnectionsCreateEnabled: ProcessInfo.processInfo.environment["CRYPTORY_EXCHANGE_CONNECTION_CREATE_ENABLED"] == "1",
        exchangeConnectionsDeleteEnabled: ProcessInfo.processInfo.environment["CRYPTORY_EXCHANGE_CONNECTION_DELETE_ENABLED"] == "1"
    )
}

struct OrderSubmissionRequest {
    let symbol: String
    let exchange: Exchange
    let side: OrderSide
    let type: OrderType
    let price: Double?
    let quantity: Double
}

protocol AuthenticationServiceProtocol {
    func signIn(email: String, password: String) async throws -> AuthSession
}

protocol PublicMarketDataServiceProtocol {
    func fetchTickers(exchange: Exchange) async throws -> [String: TickerData]
    func fetchCandles(symbol: String, exchange: Exchange, period: String) async throws -> [CandleData]
    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookData
    func fetchTrades(symbol: String, exchange: Exchange) async throws -> [PublicTrade]
}

protocol AccountServiceProtocol {
    var exchangeConnectionCRUDCapability: ExchangeConnectionCRUDCapability { get }

    func fetchPortfolio(session: AuthSession, exchange: Exchange) async throws -> PortfolioSnapshot
    func fetchOrders(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> [OrderRecord]
    func fetchExchangeConnections(session: AuthSession) async throws -> [ExchangeConnection]
    func submitOrder(session: AuthSession, request: OrderSubmissionRequest) async throws
    func createExchangeConnection(session: AuthSession, request: ExchangeConnectionCreateRequest) async throws -> ExchangeConnection
    func deleteExchangeConnection(session: AuthSession, connectionID: String) async throws
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

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseServerError(from: data) ?? "서버 요청에 실패했어요. (\(httpResponse.statusCode))"
            AppLogger.debug(.network, "HTTP \(httpResponse.statusCode) <- \(request.url?.absoluteString ?? path)")
            throw NetworkServiceError.httpError(httpResponse.statusCode, message)
        }

        if data.isEmpty {
            return [:]
        }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NetworkServiceError.parsingFailed("서버 응답 형식을 해석하지 못했어요.")
        }
    }

    private func normalizedPath(basePath: String, endpointPath: String) -> String {
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let normalizedEndpoint = endpointPath.hasPrefix("/") ? endpointPath : "/\(endpointPath)"
        return "\(trimmedBase)\(normalizedEndpoint)"
    }

    private func parseServerError(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? JSONObject
        else {
            return String(data: data, encoding: .utf8)
        }

        return json.string(["message", "error", "detail"])
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

        guard let accessToken = dictionary.string(["accessToken", "access_token", "token"]) else {
            throw NetworkServiceError.parsingFailed("로그인 토큰이 응답에 없어요.")
        }

        return AuthSession(
            accessToken: accessToken,
            refreshToken: dictionary.string(["refreshToken", "refresh_token"]),
            userID: dictionary.string(["userId", "user_id", "id"]),
            email: dictionary.string(["email"])
        )
    }
}

final class LivePublicMarketDataService: PublicMarketDataServiceProtocol {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchTickers(exchange: Exchange) async throws -> [String: TickerData] {
        let json = try await client.requestJSON(
            path: client.configuration.tickersPath,
            queryItems: [URLQueryItem(name: "exchange", value: exchange.rawValue)],
            accessRequirement: .publicAccess
        )

        let payload = unwrapPayload(json)
        var tickers: [String: TickerData] = [:]

        if let array = unwrapArray(payload) {
            for item in array {
                guard let dictionary = item as? JSONObject else { continue }
                if let parsed = parseTicker(dictionary, fallbackSymbol: nil) {
                    tickers[parsed.symbol] = parsed.ticker
                }
            }
        } else if let dictionary = payload as? JSONObject {
            if let nestedArray = unwrapArray(dictionary["tickers"] ?? dictionary["items"]) {
                for item in nestedArray {
                    guard let tickerDictionary = item as? JSONObject else { continue }
                    if let parsed = parseTicker(tickerDictionary, fallbackSymbol: nil) {
                        tickers[parsed.symbol] = parsed.ticker
                    }
                }
            } else {
                for (symbol, rawValue) in dictionary {
                    guard let tickerDictionary = rawValue as? JSONObject else { continue }
                    if let parsed = parseTicker(tickerDictionary, fallbackSymbol: symbol) {
                        tickers[parsed.symbol] = parsed.ticker
                    }
                }
            }
        }

        return tickers
    }

    func fetchCandles(symbol: String, exchange: Exchange, period: String) async throws -> [CandleData] {
        let json = try await client.requestJSON(
            path: client.configuration.candlesPath,
            queryItems: [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "exchange", value: exchange.rawValue),
                URLQueryItem(name: "period", value: period)
            ],
            accessRequirement: .publicAccess
        )

        let payload = unwrapPayload(json)
        let array = unwrapArray(payload) ?? []

        return array.compactMap { item in
            guard let dictionary = item as? JSONObject else { return nil }

            let timestamp = dictionary.int(["time", "timestamp", "candleDateTimeKst", "candle_date_time_utc"]) ?? 0
            guard
                let open = dictionary.double(["open", "openingPrice", "opening_price"]),
                let high = dictionary.double(["high", "highPrice", "high_price"]),
                let low = dictionary.double(["low", "lowPrice", "low_price"]),
                let close = dictionary.double(["close", "tradePrice", "trade_price"])
            else {
                return nil
            }

            return CandleData(
                time: timestamp,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: dictionary.int(["volume", "candleAccTradeVolume", "candle_acc_trade_volume"]) ?? 0
            )
        }
        .sorted { $0.time < $1.time }
    }

    func fetchOrderbook(symbol: String, exchange: Exchange) async throws -> OrderbookData {
        let json = try await client.requestJSON(
            path: client.configuration.orderbookPath,
            queryItems: [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "exchange", value: exchange.rawValue)
            ],
            accessRequirement: .publicAccess
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject else {
            throw NetworkServiceError.parsingFailed("호가 응답을 해석하지 못했어요.")
        }

        let asks = parseOrderbookEntries(dictionary["asks"] ?? dictionary["sell"], isBid: false)
        let bids = parseOrderbookEntries(dictionary["bids"] ?? dictionary["buy"], isBid: true)

        if !asks.isEmpty || !bids.isEmpty {
            return OrderbookData(asks: asks, bids: bids)
        }

        if let units = unwrapArray(dictionary["orderbook_units"]) {
            let parsedAsks = units.compactMap { item -> OrderbookEntry? in
                guard let unit = item as? JSONObject else { return nil }
                guard
                    let price = unit.double(["ask_price", "askPrice"]),
                    let quantity = unit.double(["ask_size", "askSize"])
                else {
                    return nil
                }
                return OrderbookEntry(price: price, qty: quantity)
            }

            let parsedBids = units.compactMap { item -> OrderbookEntry? in
                guard let unit = item as? JSONObject else { return nil }
                guard
                    let price = unit.double(["bid_price", "bidPrice"]),
                    let quantity = unit.double(["bid_size", "bidSize"])
                else {
                    return nil
                }
                return OrderbookEntry(price: price, qty: quantity)
            }

            return OrderbookData(asks: parsedAsks, bids: parsedBids)
        }

        throw NetworkServiceError.parsingFailed("호가 데이터가 비어 있어요.")
    }

    func fetchTrades(symbol: String, exchange: Exchange) async throws -> [PublicTrade] {
        let json = try await client.requestJSON(
            path: client.configuration.tradesPath,
            queryItems: [
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "exchange", value: exchange.rawValue)
            ],
            accessRequirement: .publicAccess
        )

        let payload = unwrapPayload(json)
        let array = unwrapArray(payload) ?? []

        return array.compactMap { item in
            guard let dictionary = item as? JSONObject else { return nil }
            guard let price = dictionary.double(["price", "tradePrice", "trade_price"]) else {
                return nil
            }

            return PublicTrade(
                id: dictionary.string(["id", "tradeId", "trade_id"]) ?? UUID().uuidString,
                price: price,
                quantity: dictionary.double(["qty", "size", "volume", "trade_volume"]) ?? 0,
                side: dictionary.string(["side", "askBid", "ask_bid"]) ?? "buy",
                executedAt: formatTimestamp(dictionary["time"] ?? dictionary["timestamp"] ?? dictionary["trade_timestamp"])
            )
        }
    }
}

final class LiveAccountService: AccountServiceProtocol {
    private let client: APIClient

    var exchangeConnectionCRUDCapability: ExchangeConnectionCRUDCapability {
        ExchangeConnectionCRUDCapability(
            canCreate: client.configuration.exchangeConnectionsCreateEnabled,
            canDelete: client.configuration.exchangeConnectionsDeleteEnabled
        )
    }

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchPortfolio(session: AuthSession, exchange: Exchange) async throws -> PortfolioSnapshot {
        let json = try await client.requestJSON(
            path: client.configuration.portfolioPath,
            queryItems: [URLQueryItem(name: "exchange", value: exchange.rawValue)],
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let payload = unwrapPayload(json)
        guard let dictionary = payload as? JSONObject else {
            throw NetworkServiceError.parsingFailed("포트폴리오 응답을 해석하지 못했어요.")
        }

        let holdingsArray = unwrapArray(dictionary["holdings"] ?? dictionary["assets"] ?? dictionary["balances"]) ?? []
        let holdings = holdingsArray.compactMap { item -> Holding? in
            guard let holdingDictionary = item as? JSONObject else { return nil }
            guard let symbol = holdingDictionary.string(["symbol", "asset", "currency"]) else {
                return nil
            }

            return Holding(
                symbol: symbol.uppercased(),
                qty: holdingDictionary.double(["qty", "quantity", "balance"]) ?? 0,
                avgPrice: holdingDictionary.double(["avgPrice", "averagePrice", "avg_buy_price"]) ?? 0
            )
        }

        let cash = dictionary.double(["cash", "availableCash", "krwBalance", "krw_balance"]) ?? 0
        return PortfolioSnapshot(cash: cash, holdings: holdings)
    }

    func fetchOrders(session: AuthSession, exchange: Exchange, symbol: String?) async throws -> [OrderRecord] {
        var queryItems = [URLQueryItem(name: "exchange", value: exchange.rawValue)]
        if let symbol, !symbol.isEmpty {
            queryItems.append(URLQueryItem(name: "symbol", value: symbol))
        }

        let json = try await client.requestJSON(
            path: client.configuration.ordersPath,
            queryItems: queryItems,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let payload = unwrapPayload(json)
        let array = unwrapArray(payload) ?? []

        return array.compactMap { item in
            guard let dictionary = item as? JSONObject else { return nil }
            let price = dictionary.double(["price", "avgPrice", "avg_price"]) ?? 0
            let quantity = dictionary.double(["qty", "quantity", "volume"]) ?? 0
            return OrderRecord(
                id: dictionary.string(["id", "orderId", "order_id", "uuid"]) ?? UUID().uuidString,
                symbol: dictionary.string(["symbol", "market", "asset"])?.uppercased() ?? "-",
                side: dictionary.string(["side", "type"]) ?? "buy",
                price: price,
                qty: quantity,
                total: dictionary.double(["total", "notional"]) ?? price * quantity,
                time: formatTimestamp(dictionary["time"] ?? dictionary["timestamp"] ?? dictionary["createdAt"] ?? dictionary["created_at"]),
                exchange: dictionary.string(["exchange"]) ?? exchange.displayName,
                status: dictionary.string(["status", "state"]) ?? "unknown"
            )
        }
    }

    func fetchExchangeConnections(session: AuthSession) async throws -> [ExchangeConnection] {
        let json = try await client.requestJSON(
            path: client.configuration.exchangeConnectionsPath,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let payload = unwrapPayload(json)
        let array = unwrapArray(payload) ?? []

        return array.compactMap { item in
            guard let dictionary = item as? JSONObject else { return nil }
            return parseExchangeConnection(dictionary)
        }
    }

    func submitOrder(session: AuthSession, request: OrderSubmissionRequest) async throws {
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

        _ = try await client.requestJSON(
            path: client.configuration.ordersPath,
            method: "POST",
            body: body,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
    }

    func createExchangeConnection(session: AuthSession, request: ExchangeConnectionCreateRequest) async throws -> ExchangeConnection {
        guard exchangeConnectionCRUDCapability.canCreate else {
            throw NetworkServiceError.httpError(405, "거래소 연결 생성 API가 아직 활성화되지 않았어요.")
        }

        var body: JSONObject = [
            "exchange": request.exchange.rawValue,
            "apiKey": request.apiKey,
            "secret": request.secret,
            "permission": request.permission.rawValue
        ]
        if let nickname = request.nickname, !nickname.isEmpty {
            body["nickname"] = nickname
        }

        let json = try await client.requestJSON(
            path: client.configuration.exchangeConnectionsPath,
            method: "POST",
            body: body,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )

        let payload = unwrapPayload(json)
        guard
            let dictionary = payload as? JSONObject,
            let connection = parseExchangeConnection(dictionary)
        else {
            throw NetworkServiceError.parsingFailed("생성된 거래소 연결 응답을 해석하지 못했어요.")
        }
        return connection
    }

    func deleteExchangeConnection(session: AuthSession, connectionID: String) async throws {
        guard exchangeConnectionCRUDCapability.canDelete else {
            throw NetworkServiceError.httpError(405, "거래소 연결 삭제 API가 아직 활성화되지 않았어요.")
        }

        _ = try await client.requestJSON(
            path: client.configuration.exchangeConnectionPath(id: connectionID),
            method: "DELETE",
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
    }
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

private func parseTicker(_ dictionary: JSONObject, fallbackSymbol: String?) -> (symbol: String, ticker: TickerData)? {
    guard let symbol = dictionary.string(["symbol", "market", "code"]) ?? fallbackSymbol else {
        return nil
    }

    guard let price = dictionary.double(["price", "lastPrice", "tradePrice", "trade_price", "closing_price"]) else {
        return nil
    }

    let change =
        dictionary.double(["change24h", "changePercent", "priceChangePercent", "signed_change_rate"]).map { abs($0) <= 1 ? $0 * 100 : $0 }
        ?? dictionary.double(["change"]).map { abs($0) <= 1 ? $0 * 100 : $0 }
        ?? 0

    let volume = dictionary.double(["volume24h", "volume", "acc_trade_price_24h", "quoteVolume"]) ?? 0
    let high24 = dictionary.double(["high24", "highPrice", "high_price"]) ?? price
    let low24 = dictionary.double(["low24", "lowPrice", "low_price"]) ?? price

    return (
        symbol.uppercased(),
        TickerData(
            price: price,
            change: change,
            volume: volume,
            high24: high24,
            low24: low24,
            sparkline: dictionary.doubleArray(["sparkline", "sparkLine"]),
            flash: nil
        )
    )
}

private func parseOrderbookEntries(_ value: Any?, isBid: Bool) -> [OrderbookEntry] {
    let array = unwrapArray(value) ?? []
    return array.compactMap { item in
        guard let dictionary = item as? JSONObject else { return nil }

        let priceKeys = isBid ? ["price", "bidPrice", "bid_price"] : ["price", "askPrice", "ask_price"]
        let quantityKeys = isBid ? ["qty", "quantity", "size", "bidSize", "bid_size"] : ["qty", "quantity", "size", "askSize", "ask_size"]

        guard let price = dictionary.double(priceKeys), let quantity = dictionary.double(quantityKeys) else {
            return nil
        }

        return OrderbookEntry(price: price, qty: quantity)
    }
}

private func parseExchangeConnection(_ dictionary: JSONObject) -> ExchangeConnection? {
    guard let rawExchange = dictionary.string(["exchange", "name"]) else { return nil }
    guard let exchange = Exchange(rawValue: rawExchange.lowercased()) else { return nil }

    let permission: ExchangeConnectionPermission
    if let canTrade = dictionary.bool(["canTrade", "can_trade"]) {
        permission = canTrade ? .tradeEnabled : .readOnly
    } else {
        let rawPermission = dictionary.string(["permission", "scope", "mode"])?.lowercased()
        permission = rawPermission == ExchangeConnectionPermission.tradeEnabled.rawValue ? .tradeEnabled : .readOnly
    }

    return ExchangeConnection(
        id: dictionary.string(["id", "connectionId", "connection_id"]) ?? exchange.rawValue,
        exchange: exchange,
        permission: permission,
        nickname: dictionary.string(["nickname", "label"]),
        isActive: dictionary.bool(["isActive", "is_active", "enabled"]) ?? true,
        updatedAt: dictionary.string(["updatedAt", "updated_at"])
    )
}

private func formatTimestamp(_ rawValue: Any?) -> String {
    switch rawValue {
    case let number as NSNumber:
        let timestamp = number.doubleValue > 1_000_000_000_000 ? number.doubleValue / 1000 : number.doubleValue
        let date = Date(timeIntervalSince1970: timestamp)
        return shortTimeFormatter.string(from: date)
    case let string as String:
        if let timestamp = Double(string) {
            let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp
            let date = Date(timeIntervalSince1970: seconds)
            return shortTimeFormatter.string(from: date)
        }
        return string
    default:
        return "-"
    }
}

private let shortTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "HH:mm:ss"
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
                case "true", "1", "yes", "enabled":
                    return true
                case "false", "0", "no", "disabled":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }

    func doubleArray(_ keys: [String]) -> [Double] {
        for key in keys {
            if let array = self[key] as? [Double] {
                return array
            }
            if let array = self[key] as? [NSNumber] {
                return array.map(\.doubleValue)
            }
            if let array = self[key] as? [String] {
                return array.compactMap(Double.init)
            }
        }
        return []
    }
}
