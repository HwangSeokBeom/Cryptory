import Foundation

enum PublicStreamChannel: String {
    case ticker
    case orderbook
    case trades
}

enum PublicWebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

struct PublicMarketSubscription: Hashable {
    let channel: PublicStreamChannel
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

enum MarketWebSocketParsedMessage {
    case ticker(TickerStreamPayload)
    case orderbook(OrderbookStreamPayload)
    case trades(TradesStreamPayload)
}

enum MarketWebSocketMessageParser {
    static func parse(_ text: String) -> MarketWebSocketParsedMessage? {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = websocketString(json, keys: ["type"])?.lowercased()
        else {
            return nil
        }

        if ["subscribed", "pong", "ping"].contains(type) {
            return nil
        }

        guard
            let exchange = websocketString(json, keys: ["exchange"])?.lowercased(),
            let symbol = websocketString(json, keys: ["symbol"])?.uppercased()
        else {
            return nil
        }

        switch type {
        case PublicStreamChannel.ticker.rawValue:
            guard let payload = json["data"] as? [String: Any] else { return nil }
            guard let price = websocketDouble(payload, keys: ["price"]) else { return nil }

            let ticker = TickerData(
                price: price,
                change: websocketDouble(payload, keys: ["changePercent"]) ?? 0,
                volume: websocketDouble(payload, keys: ["volume24h"]) ?? 0,
                high24: websocketDouble(payload, keys: ["high24"]) ?? price,
                low24: websocketDouble(payload, keys: ["low24"]) ?? price,
                sparkline: [],
                flash: nil
            )

            return .ticker(TickerStreamPayload(symbol: symbol, exchange: exchange, ticker: ticker))

        case PublicStreamChannel.orderbook.rawValue:
            guard let payload = json["data"] as? [String: Any] else { return nil }

            let asks = websocketOrderbookEntries(payload["asks"], priceKeys: ["price"], sizeKeys: ["quantity"])
            let bids = websocketOrderbookEntries(payload["bids"], priceKeys: ["price"], sizeKeys: ["quantity"])
            guard !asks.isEmpty || !bids.isEmpty else { return nil }

            return .orderbook(
                OrderbookStreamPayload(
                    symbol: symbol,
                    exchange: exchange,
                    orderbook: OrderbookData(asks: asks, bids: bids)
                )
            )

        case PublicStreamChannel.trades.rawValue:
            guard let payload = json["data"] as? [String: Any] else { return nil }
            guard let rawTrades = payload["trades"] as? [Any] else { return nil }

            let trades = rawTrades.compactMap { item -> PublicTrade? in
                guard let dictionary = item as? [String: Any] else { return nil }
                guard let price = websocketDouble(dictionary, keys: ["price"]) else { return nil }

                return PublicTrade(
                    id: websocketString(dictionary, keys: ["id"]) ?? UUID().uuidString,
                    price: price,
                    quantity: websocketDouble(dictionary, keys: ["quantity"]) ?? 0,
                    side: websocketString(dictionary, keys: ["side"]) ?? "buy",
                    executedAt: websocketTimestamp(dictionary["executedAt"])
                )
            }

            guard !trades.isEmpty else { return nil }
            return .trades(TradesStreamPayload(symbol: symbol, exchange: exchange, trades: trades))

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

    func connect()
    func disconnect()
    func updateSubscriptions(_ subscriptions: Set<PublicMarketSubscription>)
}

final class WebSocketService: PublicWebSocketServicing {
    var onConnectionStateChange: ((PublicWebSocketConnectionState) -> Void)?
    var onTickerReceived: ((TickerStreamPayload) -> Void)?
    var onOrderbookReceived: ((OrderbookStreamPayload) -> Void)?
    var onTradesReceived: ((TradesStreamPayload) -> Void)?

    private let session: URLSession
    private let urls: [URL]
    private var currentURLIndex = 0
    private var webSocketTask: URLSessionWebSocketTask?
    private var subscriptions = Set<PublicMarketSubscription>()
    private var connectionState: PublicWebSocketConnectionState = .disconnected {
        didSet {
            guard oldValue != connectionState else { return }
            AppLogger.debug(.websocket, "Connection state -> \(describe(connectionState))")
            DispatchQueue.main.async { [connectionState, weak self] in
                self?.onConnectionStateChange?(connectionState)
            }
        }
    }
    private var intentionalDisconnect = false
    private var reconnectWorkItem: DispatchWorkItem?

    init(session: URLSession = .shared) {
        self.session = session

        let environment = ProcessInfo.processInfo.environment
        let configuredURL = environment["CRYPTORY_PUBLIC_WS_URL"].flatMap(URL.init(string:))
        self.urls = [configuredURL ?? URL(string: "wss://api.cryptomts.com/ws/market")!]
    }

    func connect() {
        guard webSocketTask == nil else { return }
        intentionalDisconnect = false
        reconnectWorkItem?.cancel()

        let url = urls[currentURLIndex]
        AppLogger.debug(.websocket, "Opening unified public websocket -> \(url.absoluteString)")

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
        let removed = self.subscriptions.subtracting(subscriptions)
        let added = subscriptions.subtracting(self.subscriptions)
        self.subscriptions = subscriptions

        if webSocketTask == nil {
            connect()
            return
        }

        removed.forEach { send(subscriptionMessage(for: $0, action: "unsubscribe")) }
        added.forEach { send(subscriptionMessage(for: $0, action: "subscribe")) }
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
                self.connectionState = .failed(error.localizedDescription)
                self.scheduleReconnect()
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
                self?.connectionState = .failed(error.localizedDescription)
                self?.scheduleReconnect()
                return
            }

            if self?.connectionState != .connected {
                self?.connectionState = .connected
            }
        }
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

        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func parseMessage(_ text: String) {
        switch MarketWebSocketMessageParser.parse(text) {
        case .some(.ticker(let payload)):
            DispatchQueue.main.async { [weak self] in
                self?.onTickerReceived?(payload)
            }
        case .some(.orderbook(let payload)):
            DispatchQueue.main.async { [weak self] in
                self?.onOrderbookReceived?(payload)
            }
        case .some(.trades(let payload)):
            DispatchQueue.main.async { [weak self] in
                self?.onTradesReceived?(payload)
            }
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

private func websocketTimestamp(_ rawValue: Any?) -> String {
    switch rawValue {
    case let number as NSNumber:
        let timestamp = number.doubleValue > 1_000_000_000_000 ? number.doubleValue / 1000 : number.doubleValue
        return websocketTimeFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    case let string as String:
        if let timestamp = Double(string) {
            let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp
            return websocketTimeFormatter.string(from: Date(timeIntervalSince1970: seconds))
        }
        return string
    default:
        return "-"
    }
}

private let websocketTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()
