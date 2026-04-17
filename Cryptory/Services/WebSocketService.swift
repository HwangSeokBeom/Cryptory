import Foundation

enum PublicStreamChannel: String {
    case ticker
    case orderbook
    case trades
    case candles
}

enum PrivateStreamChannel: String {
    case orders
    case fills
    case portfolio
}

enum PublicWebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

enum PrivateWebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

struct PublicMarketSubscription: Hashable {
    let channel: PublicStreamChannel
    let exchange: String?
    let symbol: String?
    let interval: String?

    init(channel: PublicStreamChannel, exchange: String?, symbol: String?, interval: String? = nil) {
        self.channel = channel
        self.exchange = exchange
        self.symbol = symbol
        self.interval = interval
    }
}

struct PrivateTradingSubscription: Hashable {
    let channel: PrivateStreamChannel
    let exchange: String?
    let symbol: String?
}

struct TickerStreamPayload {
    let symbol: String
    let exchange: String
    let ticker: TickerData
}

struct OrderbookStreamPayload {
    let symbol: String
    let exchange: String
    let orderbook: OrderbookData
}

struct TradesStreamPayload {
    let symbol: String
    let exchange: String
    let trades: [PublicTrade]
}

struct CandleStreamPayload {
    let symbol: String
    let exchange: String
    let interval: String
    let candles: [CandleData]
}

struct OrderStreamPayload {
    let exchange: Exchange
    let order: OrderRecord
}

struct FillStreamPayload {
    let exchange: Exchange
    let fill: TradeFill
}

enum MarketWebSocketParsedMessage {
    case ticker(TickerStreamPayload)
    case orderbook(OrderbookStreamPayload)
    case trades(TradesStreamPayload)
    case candles(CandleStreamPayload)
}

enum PrivateWebSocketParsedMessage {
    case order(OrderStreamPayload)
    case fill(FillStreamPayload)
}

enum MarketWebSocketMessageParser {
    static func parse(_ text: String) -> MarketWebSocketParsedMessage? {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let type = websocketString(json, keys: ["type", "channel"])?.lowercased()
        if ["subscribed", "pong", "ping", "ack"].contains(type ?? "") {
            return nil
        }

        guard
            let exchange = websocketString(json, keys: ["exchange"])?.lowercased(),
            let symbol = websocketString(json, keys: ["symbol"])?.uppercased()
        else {
            return nil
        }

        let payload = (json["data"] as? [String: Any]) ?? json

        switch type {
        case PublicStreamChannel.ticker.rawValue:
            guard let price = websocketDouble(payload, keys: ["price", "tradePrice"]) else {
                return nil
            }

            let ticker = TickerData(
                price: price,
                change: normalizeChangePercent(websocketDouble(payload, keys: ["changePercent", "changeRate"]) ?? 0),
                volume: websocketDouble(payload, keys: ["volume24h", "volume"]) ?? 0,
                high24: websocketDouble(payload, keys: ["high24", "highPrice"]) ?? price,
                low24: websocketDouble(payload, keys: ["low24", "lowPrice"]) ?? price,
                timestamp: websocketDate(payload["timestamp"] ?? payload["time"] ?? payload["updatedAt"]),
                isStale: websocketBool(payload, keys: ["stale", "isStale"]) ?? false,
                sourceExchange: Exchange(rawValue: exchange)
            )

            return .ticker(TickerStreamPayload(symbol: symbol, exchange: exchange, ticker: ticker))

        case PublicStreamChannel.orderbook.rawValue:
            let asks = websocketOrderbookEntries(payload["asks"] ?? payload["sell"], priceKeys: ["price", "askPrice"], sizeKeys: ["quantity", "size", "askSize"])
            let bids = websocketOrderbookEntries(payload["bids"] ?? payload["buy"], priceKeys: ["price", "bidPrice"], sizeKeys: ["quantity", "size", "bidSize"])
            guard !asks.isEmpty || !bids.isEmpty else { return nil }

            let orderbook = OrderbookData(
                asks: asks,
                bids: bids,
                timestamp: websocketDate(payload["timestamp"] ?? payload["updatedAt"]),
                isStale: websocketBool(payload, keys: ["stale", "isStale"]) ?? false
            )

            return .orderbook(OrderbookStreamPayload(symbol: symbol, exchange: exchange, orderbook: orderbook))

        case PublicStreamChannel.trades.rawValue:
            guard let rawTrades = payload["trades"] as? [Any] else {
                return nil
            }

            let trades = rawTrades.compactMap { item -> PublicTrade? in
                guard let dictionary = item as? [String: Any] else { return nil }
                guard let price = websocketDouble(dictionary, keys: ["price", "tradePrice"]) else { return nil }
                let executedDate = websocketDate(dictionary["executedAt"] ?? dictionary["timestamp"] ?? dictionary["time"])
                return PublicTrade(
                    id: websocketString(dictionary, keys: ["id", "tradeId"]) ?? UUID().uuidString,
                    price: price,
                    quantity: websocketDouble(dictionary, keys: ["quantity", "qty", "volume"]) ?? 0,
                    side: websocketString(dictionary, keys: ["side"]) ?? "buy",
                    executedAt: websocketTimeString(executedDate),
                    executedDate: executedDate
                )
            }

            guard !trades.isEmpty else { return nil }
            return .trades(TradesStreamPayload(symbol: symbol, exchange: exchange, trades: trades))

        case PublicStreamChannel.candles.rawValue, "candle":
            let interval = websocketString(payload, keys: ["interval"]) ?? websocketString(json, keys: ["interval"]) ?? "1h"
            let rawCandles = (payload["candles"] as? [Any]) ?? [payload]
            let candles = rawCandles.compactMap { item -> CandleData? in
                guard let dictionary = item as? [String: Any] else { return nil }
                guard
                    let open = websocketDouble(dictionary, keys: ["open"]),
                    let high = websocketDouble(dictionary, keys: ["high"]),
                    let low = websocketDouble(dictionary, keys: ["low"]),
                    let close = websocketDouble(dictionary, keys: ["close"])
                else {
                    return nil
                }

                let timestamp = websocketDate(dictionary["timestamp"] ?? dictionary["time"]) ?? Date()
                return CandleData(
                    time: Int(timestamp.timeIntervalSince1970),
                    open: open,
                    high: high,
                    low: low,
                    close: close,
                    volume: Int(websocketDouble(dictionary, keys: ["volume"]) ?? 0)
                )
            }

            guard !candles.isEmpty else { return nil }
            return .candles(CandleStreamPayload(symbol: symbol, exchange: exchange, interval: interval.lowercased(), candles: candles))

        default:
            return nil
        }
    }
}

enum PrivateWebSocketMessageParser {
    static func parse(_ text: String) -> PrivateWebSocketParsedMessage? {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let type = websocketString(json, keys: ["type", "channel"])?.lowercased()
        if ["subscribed", "pong", "ping", "ack"].contains(type ?? "") {
            return nil
        }

        let payload = (json["data"] as? [String: Any]) ?? json
        guard let exchangeRawValue = websocketString(payload, keys: ["exchange"])?.lowercased() ?? websocketString(json, keys: ["exchange"])?.lowercased(),
              let exchange = Exchange(rawValue: exchangeRawValue) else {
            return nil
        }

        switch type {
        case "order", PrivateStreamChannel.orders.rawValue:
            guard let order = websocketOrderRecord(payload, exchange: exchange) else {
                return nil
            }
            return .order(OrderStreamPayload(exchange: exchange, order: order))

        case "fill", PrivateStreamChannel.fills.rawValue:
            guard let fill = websocketTradeFill(payload, exchange: exchange) else {
                return nil
            }
            return .fill(FillStreamPayload(exchange: exchange, fill: fill))

        default:
            return nil
        }
    }
}

protocol PublicWebSocketServicing: AnyObject {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)? { get set }
    var onTickerReceived: ((TickerStreamPayload) -> Void)? { get set }
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)? { get set }
    var onTradesReceived: ((TradesStreamPayload) -> Void)? { get set }
    var onCandlesReceived: ((CandleStreamPayload) -> Void)? { get set }

    func connect()
    func disconnect()
    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>)
}

protocol PrivateWebSocketServicing: AnyObject {
    var onConnectionStateChange: ((PrivateWebSocketConnectionState) -> Void)? { get set }
    var onOrderReceived: ((OrderStreamPayload) -> Void)? { get set }
    var onFillReceived: ((FillStreamPayload) -> Void)? { get set }

    func connect(accessToken: String)
    func disconnect()
    func updateSubscriptions(_ subscriptions: Set<PrivateTradingSubscription>)
}

final class WebSocketService: PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?
    var onCandlesReceived: ((CandleStreamPayload) -> Void)?

    private let session: URLSession
    private let urls: [URL]
    private var currentURLIndex = 0
    private var webSocketTask: URLSessionWebSocketTask?
    private var subscriptions = Set<PublicMarketSubscription>()
    private var connectionState: PublicWebSocketConnectionState = .disconnected {
        didSet {
            guard oldValue != connectionState else { return }
            AppLogger.debug(.websocket, "Public connection state -> \(describe(connectionState))")
            DispatchQueue.main.async { [connectionState, weak self] in
                self?.onConnectionStateChange?(connectionState)
            }
        }
    }
    private var intentionalDisconnect = false
    private var reconnectWorkItem: DispatchWorkItem?

    init(
        session: URLSession = .shared,
        runtimeConfiguration: AppRuntimeConfiguration = .live
    ) {
        self.session = session
        self.urls = [runtimeConfiguration.publicMarketWebSocketURL]
    }

    func connect() {
        guard webSocketTask == nil else { return }
        intentionalDisconnect = false
        reconnectWorkItem?.cancel()

        let url = urls[currentURLIndex]
        AppLogger.debug(.websocket, "Opening public websocket -> \(url.absoluteString)")

        connectionState = .connecting
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        receiveMessage()
        flushSubscriptions()
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectWorkItem?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>) {
        let removedSubscriptions = self.subscriptions.subtracting(subscriptions)
        let addedSubscriptions = subscriptions.subtracting(self.subscriptions)
        self.subscriptions = subscriptions

        if webSocketTask == nil {
            connect()
            return
        }

        removedSubscriptions.forEach { send(subscriptionMessage(for: $0, action: "unsubscribe")) }
        addedSubscriptions.forEach { send(subscriptionMessage(for: $0, action: "subscribe")) }
    }

    private func flushSubscriptions() {
        subscriptions.forEach { send(subscriptionMessage(for: $0, action: "subscribe")) }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.connectionState = .connected

                switch message {
                case .string(let text):
                    self.parseMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.parseMessage(text)
                    }
                @unknown default:
                    break
                }

                self.receiveMessage()

            case .failure(let error):
                guard !self.intentionalDisconnect else { return }
                self.handleFailure(error)
            }
        }
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        webSocketTask = nil
        currentURLIndex = (currentURLIndex + 1) % urls.count

        let workItem = DispatchWorkItem { [weak self] in
            self?.connect()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func send(_ message: String) {
        guard let webSocketTask else { return }

        webSocketTask.send(.string(message)) { [weak self] error in
            if let error {
                guard self?.intentionalDisconnect == false else { return }
                self?.handleFailure(error)
                return
            }

            if self?.connectionState != .connected {
                self?.connectionState = .connected
            }
        }
    }

    private func handleFailure(_ error: Error) {
        let failure = TransportFailureMapper.map(error)
        connectionState = .failed(failure.message)
        webSocketTask = nil

        guard failure.shouldRetry else {
            AppLogger.debug(.websocket, "Public reconnect skipped -> \(failure.message)")
            return
        }

        scheduleReconnect()
    }

    private func subscriptionMessage(for subscription: PublicMarketSubscription, action: String) -> String {
        var payload: [String: String] = [
            "action": action,
            "channel": subscription.channel.rawValue
        ]

        if let exchange = subscription.exchange {
            payload["exchange"] = exchange
        }
        if let symbol = subscription.symbol {
            payload["symbol"] = symbol
        }
        if let interval = subscription.interval {
            payload["interval"] = interval
        }

        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func parseMessage(_ text: String) {
        switch MarketWebSocketMessageParser.parse(text) {
        case .some(.ticker(let payload)):
            DispatchQueue.main.async { [weak self] in self?.onTickerReceived?(payload) }
        case .some(.orderbook(let payload)):
            DispatchQueue.main.async { [weak self] in self?.onOrderbookReceived?(payload) }
        case .some(.trades(let payload)):
            DispatchQueue.main.async { [weak self] in self?.onTradesReceived?(payload) }
        case .some(.candles(let payload)):
            DispatchQueue.main.async { [weak self] in self?.onCandlesReceived?(payload) }
        case .none:
            break
        }
    }

    private func describe(_ state: PublicWebSocketConnectionState) -> String {
        switch state {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .failed(let message):
            return "failed(\(message))"
        }
    }
}

final class PrivateWebSocketService: PrivateWebSocketServicing {
    var onConnectionStateChange: ((PrivateWebSocketConnectionState) -> Void)?
    var onOrderReceived: ((OrderStreamPayload) -> Void)?
    var onFillReceived: ((FillStreamPayload) -> Void)?

    private let session: URLSession
    private let url: URL
    private var webSocketTask: URLSessionWebSocketTask?
    private var accessToken: String?
    private var subscriptions = Set<PrivateTradingSubscription>()
    private var connectionState: PrivateWebSocketConnectionState = .disconnected {
        didSet {
            guard oldValue != connectionState else { return }
            AppLogger.debug(.websocket, "Private connection state -> \(describe(connectionState))")
            DispatchQueue.main.async { [connectionState, weak self] in
                self?.onConnectionStateChange?(connectionState)
            }
        }
    }
    private var intentionalDisconnect = false
    private var reconnectWorkItem: DispatchWorkItem?

    init(
        session: URLSession = .shared,
        runtimeConfiguration: AppRuntimeConfiguration = .live
    ) {
        self.session = session
        self.url = runtimeConfiguration.privateTradingWebSocketURL
    }

    func connect(accessToken: String) {
        self.accessToken = accessToken
        guard webSocketTask == nil else { return }
        intentionalDisconnect = false
        reconnectWorkItem?.cancel()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        AppLogger.debug(.websocket, "Opening private websocket -> \(url.absoluteString)")
        connectionState = .connecting
        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        receiveMessage()
        flushSubscriptions()
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectWorkItem?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    func updateSubscriptions(_ subscriptions: Set<PrivateTradingSubscription>) {
        let removedSubscriptions = self.subscriptions.subtracting(subscriptions)
        let addedSubscriptions = subscriptions.subtracting(self.subscriptions)
        self.subscriptions = subscriptions

        if webSocketTask == nil, let accessToken {
            connect(accessToken: accessToken)
            return
        }

        removedSubscriptions.forEach { send(subscriptionMessage(for: $0, action: "unsubscribe")) }
        addedSubscriptions.forEach { send(subscriptionMessage(for: $0, action: "subscribe")) }
    }

    private func flushSubscriptions() {
        subscriptions.forEach { send(subscriptionMessage(for: $0, action: "subscribe")) }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.connectionState = .connected

                switch message {
                case .string(let text):
                    self.parseMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.parseMessage(text)
                    }
                @unknown default:
                    break
                }

                self.receiveMessage()

            case .failure(let error):
                guard !self.intentionalDisconnect else { return }
                self.handleFailure(error)
            }
        }
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        webSocketTask = nil

        guard let accessToken else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.connect(accessToken: accessToken)
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func send(_ message: String) {
        guard let webSocketTask else { return }

        webSocketTask.send(.string(message)) { [weak self] error in
            if let error {
                guard self?.intentionalDisconnect == false else { return }
                self?.handleFailure(error)
                return
            }

            if self?.connectionState != .connected {
                self?.connectionState = .connected
            }
        }
    }

    private func handleFailure(_ error: Error) {
        let failure = TransportFailureMapper.map(error)
        connectionState = .failed(failure.message)
        webSocketTask = nil

        guard failure.shouldRetry else {
            AppLogger.debug(.websocket, "Private reconnect skipped -> \(failure.message)")
            return
        }

        scheduleReconnect()
    }

    private func subscriptionMessage(for subscription: PrivateTradingSubscription, action: String) -> String {
        var payload: [String: String] = [
            "action": action,
            "channel": subscription.channel.rawValue
        ]

        if let exchange = subscription.exchange {
            payload["exchange"] = exchange
        }
        if let symbol = subscription.symbol {
            payload["symbol"] = symbol
        }

        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func parseMessage(_ text: String) {
        switch PrivateWebSocketMessageParser.parse(text) {
        case .some(.order(let payload)):
            DispatchQueue.main.async { [weak self] in self?.onOrderReceived?(payload) }
        case .some(.fill(let payload)):
            DispatchQueue.main.async { [weak self] in self?.onFillReceived?(payload) }
        case .none:
            break
        }
    }

    private func describe(_ state: PrivateWebSocketConnectionState) -> String {
        switch state {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .failed(let message):
            return "failed(\(message))"
        }
    }
}

private func websocketString(_ dictionary: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = dictionary[key] as? String, !value.isEmpty {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.stringValue
        }
    }
    return nil
}

private func websocketDouble(_ dictionary: [String: Any], keys: [String]) -> Double? {
    for key in keys {
        if let value = dictionary[key] as? Double {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.doubleValue
        }
        if let value = dictionary[key] as? String, let number = Double(value.replacingOccurrences(of: ",", with: "")) {
            return number
        }
    }
    return nil
}

private func websocketBool(_ dictionary: [String: Any], keys: [String]) -> Bool? {
    for key in keys {
        if let value = dictionary[key] as? Bool {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.boolValue
        }
        if let value = dictionary[key] as? String {
            switch value.lowercased() {
            case "true", "1", "yes", "active", "enabled":
                return true
            case "false", "0", "no", "inactive", "disabled":
                return false
            default:
                continue
            }
        }
    }
    return nil
}

private func websocketOrderbookEntries(_ rawValue: Any?, priceKeys: [String], sizeKeys: [String]) -> [OrderbookEntry] {
    guard let array = rawValue as? [Any] else { return [] }

    return array.compactMap { item in
        guard let dictionary = item as? [String: Any] else { return nil }

        guard let price = websocketDouble(dictionary, keys: priceKeys), let quantity = websocketDouble(dictionary, keys: sizeKeys) else {
            return nil
        }

        return OrderbookEntry(price: price, qty: quantity)
    }
}

private func websocketDate(_ rawValue: Any?) -> Date? {
    switch rawValue {
    case let number as NSNumber:
        let timestamp = number.doubleValue > 1_000_000_000_000 ? number.doubleValue / 1000 : number.doubleValue
        return Date(timeIntervalSince1970: timestamp)
    case let string as String:
        if let timestamp = Double(string) {
            let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        return websocketISO8601Formatter.date(from: string) ?? websocketSimpleISO8601Formatter.date(from: string)
    default:
        return nil
    }
}

private func websocketTimeString(_ date: Date?) -> String {
    guard let date else { return "-" }
    return websocketTimeFormatter.string(from: date)
}

private func normalizeChangePercent(_ value: Double) -> Double {
    abs(value) <= 1 ? value * 100 : value
}

private func websocketOrderRecord(_ dictionary: [String: Any], exchange: Exchange) -> OrderRecord? {
    let price = websocketDouble(dictionary, keys: ["price", "limitPrice", "avgPrice"]) ?? 0
    let quantity = websocketDouble(dictionary, keys: ["quantity", "qty", "volume"]) ?? 0
    let executedQuantity = websocketDouble(dictionary, keys: ["executedQuantity", "filledQuantity"]) ?? 0
    let remainingQuantity = websocketDouble(dictionary, keys: ["remainingQuantity", "remainingVolume"]) ?? max(quantity - executedQuantity, 0)
    let createdAt = websocketDate(dictionary["createdAt"] ?? dictionary["timestamp"] ?? dictionary["time"])

    guard let rawSymbol = websocketString(dictionary, keys: ["symbol", "market", "asset"]) else {
        return nil
    }

    return OrderRecord(
        id: websocketString(dictionary, keys: ["id", "orderId", "uuid"]) ?? UUID().uuidString,
        symbol: rawSymbol.uppercased(),
        side: websocketString(dictionary, keys: ["side"]) ?? "buy",
        orderType: OrderType(rawValue: (websocketString(dictionary, keys: ["orderType", "type", "ordType"]) ?? OrderType.limit.rawValue).lowercased()) ?? .limit,
        price: price,
        averageExecutedPrice: websocketDouble(dictionary, keys: ["averageExecutedPrice", "avgExecutedPrice"]),
        qty: quantity,
        executedQuantity: executedQuantity,
        remainingQuantity: remainingQuantity,
        total: websocketDouble(dictionary, keys: ["total", "notional"]) ?? price * quantity,
        time: websocketTimeString(createdAt),
        createdAt: createdAt,
        exchange: exchange.displayName,
        status: websocketString(dictionary, keys: ["status", "state"]) ?? "unknown",
        canCancel: websocketBool(dictionary, keys: ["canCancel", "cancelable"]) ?? (remainingQuantity > 0)
    )
}

private func websocketTradeFill(_ dictionary: [String: Any], exchange: Exchange) -> TradeFill? {
    guard let price = websocketDouble(dictionary, keys: ["price", "tradePrice", "executedPrice"]) else {
        return nil
    }

    let executedAt = websocketDate(dictionary["executedAt"] ?? dictionary["timestamp"] ?? dictionary["time"])

    return TradeFill(
        id: websocketString(dictionary, keys: ["id", "fillId", "tradeId"]) ?? UUID().uuidString,
        orderID: websocketString(dictionary, keys: ["orderId", "order_id"]) ?? "-",
        symbol: (websocketString(dictionary, keys: ["symbol", "market", "asset"]) ?? "-").uppercased(),
        side: websocketString(dictionary, keys: ["side"]) ?? "buy",
        price: price,
        quantity: websocketDouble(dictionary, keys: ["quantity", "qty", "volume"]) ?? 0,
        fee: websocketDouble(dictionary, keys: ["fee", "paidFee"]) ?? 0,
        executedAtText: websocketTimeString(executedAt),
        executedAt: executedAt,
        exchange: exchange
    )
}

private let websocketTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

private let websocketISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let websocketSimpleISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
