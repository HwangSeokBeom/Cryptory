import SwiftUI
import Combine

enum ScreenAccessRequirement: String, Equatable {
    case publicAccess = "public access"
    case authenticatedRequired = "authenticated required"
}

enum Tab: String, CaseIterable, Equatable {
    case market, chart, trade, portfolio, kimchi

    var systemImage: String {
        switch self {
        case .market: return "chart.line.uptrend.xyaxis"
        case .chart: return "chart.xyaxis.line"
        case .trade: return "arrow.left.arrow.right.circle"
        case .portfolio: return "wallet.pass"
        case .kimchi: return "flame"
        }
    }

    var title: String {
        switch self {
        case .market: return "시세"
        case .chart: return "차트"
        case .trade: return "주문"
        case .portfolio: return "자산"
        case .kimchi: return "김프"
        }
    }

    var accessRequirement: ScreenAccessRequirement {
        switch self {
        case .market, .chart, .kimchi:
            return .publicAccess
        case .trade, .portfolio:
            return .authenticatedRequired
        }
    }

    var showsExchangeSelector: Bool {
        switch self {
        case .market, .chart, .trade, .portfolio:
            return true
        case .kimchi:
            return false
        }
    }

    var protectedFeature: ProtectedFeature? {
        switch self {
        case .portfolio:
            return .portfolio
        case .trade:
            return .trade
        case .market, .chart, .kimchi:
            return nil
        }
    }
}

enum MarketFilter: String, CaseIterable {
    case all, fav

    var title: String {
        switch self {
        case .all: return "전체"
        case .fav: return "관심"
        }
    }
}

enum OrderSide: String {
    case buy, sell
}

enum OrderType: String {
    case limit, market
}

enum NotifType {
    case success, error
}

@MainActor
final class CryptoViewModel: ObservableObject {
    @Published var activeTab: Tab = .market
    @Published var selectedExchange: Exchange = .upbit
    @Published var selectedCoin: CoinInfo?
    @Published var showExchangeMenu = false

    @Published private(set) var prices: [String: [String: TickerData]] = [:]
    @Published var searchQuery = ""
    @Published var marketFilter: MarketFilter = .all
    @Published private(set) var favCoins: Set<String> = []

    @Published var chartPeriod = "1H"
    @Published private(set) var candlesState: Loadable<[CandleData]> = .idle
    @Published private(set) var orderbookState: Loadable<OrderbookData> = .idle
    @Published private(set) var recentTradesState: Loadable<[PublicTrade]> = .idle

    @Published var orderSide: OrderSide = .buy
    @Published var orderType: OrderType = .limit
    @Published var orderPrice = ""
    @Published var orderQty = ""
    @Published private(set) var isSubmittingOrder = false

    @Published private(set) var portfolioState: Loadable<PortfolioSnapshot> = .idle
    @Published private(set) var orderHistoryState: Loadable<[OrderRecord]> = .idle
    @Published private(set) var exchangeConnectionsState: Loadable<[ExchangeConnection]> = .idle

    @Published private(set) var authState: AuthState = .guest
    @Published private(set) var activeAuthGate: ProtectedFeature?
    @Published private(set) var publicWebSocketState: PublicWebSocketConnectionState = .disconnected

    @Published var notification: (msg: String, type: NotifType)?
    @Published var isLoginPresented = false
    @Published var isExchangeConnectionsPresented = false
    @Published var loginEmail = ""
    @Published var loginPassword = ""
    @Published var loginErrorMessage: String?

    private let publicService: PublicMarketDataServiceProtocol
    private let accountService: AccountServiceProtocol
    private let authService: AuthenticationServiceProtocol
    private let webSocketService: PublicWebSocketServicing
    private let favoritesKey = "guest.favorite.symbols"

    private var hasBootstrapped = false
    private var pendingPostLoginFeature: ProtectedFeature?

    var exchange: Exchange {
        get { selectedExchange }
        set { selectedExchange = newValue }
    }

    init(
        publicService: PublicMarketDataServiceProtocol? = nil,
        accountService: AccountServiceProtocol? = nil,
        authService: AuthenticationServiceProtocol? = nil,
        webSocketService: PublicWebSocketServicing? = nil
    ) {
        self.publicService = publicService ?? LivePublicMarketDataService()
        self.accountService = accountService ?? LiveAccountService()
        self.authService = authService ?? LiveAuthenticationService()
        self.webSocketService = webSocketService ?? WebSocketService()

        self.favCoins = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])

        bindWebSocket()
        connectPublicMarketFeed()
    }

    var isAuthenticated: Bool {
        authState.isAuthenticated
    }

    var shouldShowExchangeSelector: Bool {
        guard activeTab.showsExchangeSelector else { return false }
        if activeTab.accessRequirement == .publicAccess {
            return true
        }
        return isAuthenticated
    }

    var statusButtonTitle: String {
        isAuthenticated ? "연결" : "로그인"
    }

    var candles: [CandleData] {
        candlesState.value ?? []
    }

    var orderbook: OrderbookData? {
        orderbookState.value
    }

    var recentTrades: [PublicTrade] {
        recentTradesState.value ?? []
    }

    var portfolio: [Holding] {
        portfolioState.value?.holdings ?? []
    }

    var cash: Double {
        portfolioState.value?.cash ?? 0
    }

    var orderHistory: [OrderRecord] {
        orderHistoryState.value ?? []
    }

    var exchangeConnections: [ExchangeConnection] {
        exchangeConnectionsState.value ?? []
    }

    var exchangeConnectionCRUDCapability: ExchangeConnectionCRUDCapability {
        accountService.exchangeConnectionCRUDCapability
    }

    var hasAnyExchangeConnection: Bool {
        !exchangeConnections.isEmpty
    }

    var hasTradeEnabledConnection: Bool {
        exchangeConnections.contains { $0.isActive && $0.permission == .tradeEnabled }
    }

    var filteredCoins: [CoinInfo] {
        var coins = COINS

        if marketFilter == .fav {
            coins = coins.filter { favCoins.contains($0.symbol) }
        }

        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            coins = coins.filter {
                $0.symbol.lowercased().contains(query)
                || $0.name.contains(query)
                || $0.nameEn.lowercased().contains(query)
            }
        }

        return coins
    }

    var currentTicker: TickerData? {
        guard let coin = selectedCoin else { return nil }
        return prices[coin.symbol]?[exchange.rawValue]
    }

    var currentPrice: Double {
        currentTicker?.price ?? 0
    }

    var totalAsset: Double {
        cash + portfolio.reduce(0) { partialResult, holding in
            partialResult + (prices[holding.symbol]?[exchange.rawValue]?.price ?? holding.avgPrice) * holding.qty
        }
    }

    var totalPnl: Double {
        portfolio.reduce(0) { partialResult, holding in
            let currentPrice = prices[holding.symbol]?[exchange.rawValue]?.price ?? holding.avgPrice
            return partialResult + (currentPrice - holding.avgPrice) * holding.qty
        }
    }

    var totalPnlPercent: Double {
        let invested = totalAsset - totalPnl
        guard invested > 0 else { return 0 }
        return totalPnl / invested * 100
    }

    func onAppear() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        Task {
            await bootstrapPublicData()
            await refreshDataForCurrentRoute()
        }
    }

    func setActiveTab(_ tab: Tab) {
        guard activeTab != tab else { return }
        activeTab = tab
        showExchangeMenu = false

        AppLogger.debug(.route, "Screen -> \(tab.title) (\(tab.accessRequirement.rawValue))")
        updateAuthGate()
        updatePublicSubscriptions()

        Task {
            await refreshDataForCurrentRoute()
        }
    }

    func updateExchange(_ exchange: Exchange) {
        guard selectedExchange != exchange else { return }
        selectedExchange = exchange
        AppLogger.debug(.route, "Exchange changed -> \(exchange.rawValue)")

        prefillOrderPriceIfPossible()
        updatePublicSubscriptions()

        Task {
            await refreshDataForCurrentRoute()
        }
    }

    func selectCoin(_ coin: CoinInfo) {
        selectedCoin = coin
        prefillOrderPriceIfPossible()
        setActiveTab(.chart)

        Task {
            await loadChartData()
        }
    }

    func selectCoinForTrade(_ coin: CoinInfo) {
        selectedCoin = coin
        prefillOrderPriceIfPossible()
        setActiveTab(.trade)

        Task {
            await loadOrders()
        }
    }

    func loadChartData() async {
        guard let coin = selectedCoin else {
            candlesState = .idle
            orderbookState = .idle
            recentTradesState = .idle
            return
        }

        AppLogger.debug(.route, "Public chart path -> \(coin.symbol) @ \(exchange.rawValue)")
        updatePublicSubscriptions()

        candlesState = .loading
        orderbookState = .loading
        recentTradesState = .loading

        do {
            let candles = try await publicService.fetchCandles(symbol: coin.symbol, exchange: exchange, period: chartPeriod)
            candlesState = candles.isEmpty ? .empty : .loaded(candles)
        } catch {
            candlesState = .failed(error.localizedDescription)
        }

        do {
            let orderbook = try await publicService.fetchOrderbook(symbol: coin.symbol, exchange: exchange)
            let shouldReplaceOrderbook = selectedCoin?.symbol == coin.symbol && self.exchange == exchange
            if shouldReplaceOrderbook {
                orderbookState = .loaded(orderbook)
            }
        } catch {
            orderbookState = .failed(error.localizedDescription)
        }

        do {
            let trades = try await publicService.fetchTrades(symbol: coin.symbol, exchange: exchange)
            let shouldReplaceTrades = selectedCoin?.symbol == coin.symbol && self.exchange == exchange
            if shouldReplaceTrades {
                recentTradesState = trades.isEmpty ? .empty : .loaded(trades)
            }
        } catch {
            recentTradesState = .failed(error.localizedDescription)
        }
    }

    func toggleFavorite(_ symbol: String) {
        if favCoins.contains(symbol) {
            favCoins.remove(symbol)
        } else {
            favCoins.insert(symbol)
        }

        UserDefaults.standard.set(Array(favCoins).sorted(), forKey: favoritesKey)
    }

    func presentLogin(for feature: ProtectedFeature) {
        pendingPostLoginFeature = feature
        loginErrorMessage = nil
        isLoginPresented = true
        AppLogger.debug(.auth, "Present login for \(feature.rawValue)")
    }

    func submitLogin() async {
        guard !loginEmail.isEmpty, !loginPassword.isEmpty else {
            loginErrorMessage = "이메일과 비밀번호를 입력해주세요."
            return
        }

        authState = .signingIn
        loginErrorMessage = nil

        do {
            let session = try await authService.signIn(email: loginEmail, password: loginPassword)
            authState = .authenticated(session)
            AppLogger.debug(.auth, "Authentication success -> \(session.email ?? session.userID ?? "user")")

            loginPassword = ""
            isLoginPresented = false
            updateAuthGate()

            await loadExchangeConnections()
            await refreshDataForCurrentRoute()

            if pendingPostLoginFeature == .exchangeConnections {
                isExchangeConnectionsPresented = true
            }
            pendingPostLoginFeature = nil
        } catch {
            authState = .guest
            loginErrorMessage = error.localizedDescription
        }
    }

    func logout() {
        authState = .guest
        pendingPostLoginFeature = nil
        loginPassword = ""
        isExchangeConnectionsPresented = false
        portfolioState = .idle
        orderHistoryState = .idle
        exchangeConnectionsState = .idle
        updateAuthGate()
        AppLogger.debug(.auth, "User session cleared")
    }

    func openStatusAction() {
        if isAuthenticated {
            isExchangeConnectionsPresented = true
            Task {
                await loadExchangeConnections()
            }
        } else {
            presentLogin(for: activeTab.protectedFeature ?? .portfolio)
        }
    }

    func openExchangeConnections() {
        if isAuthenticated {
            isExchangeConnectionsPresented = true
            Task {
                await loadExchangeConnections()
            }
        } else {
            presentLogin(for: .exchangeConnections)
        }
    }

    @discardableResult
    func createExchangeConnection(_ request: ExchangeConnectionCreateRequest) async -> Bool {
        guard let session = authState.session else {
            presentLogin(for: .exchangeConnections)
            return false
        }

        do {
            _ = try await accountService.createExchangeConnection(session: session, request: request)
            showNotification("거래소 연결을 추가했어요", type: .success)
            await loadExchangeConnections()
            return true
        } catch {
            showNotification(error.localizedDescription, type: .error)
            return false
        }
    }

    @discardableResult
    func deleteExchangeConnection(id: String) async -> Bool {
        guard let session = authState.session else {
            presentLogin(for: .exchangeConnections)
            return false
        }

        do {
            try await accountService.deleteExchangeConnection(session: session, connectionID: id)
            showNotification("거래소 연결을 삭제했어요", type: .success)
            await loadExchangeConnections()
            return true
        } catch {
            showNotification(error.localizedDescription, type: .error)
            return false
        }
    }

    func loadPortfolio() async {
        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip portfolio fetch in guest state")
            portfolioState = .idle
            return
        }

        AppLogger.debug(.route, "Authenticated portfolio path -> \(exchange.rawValue)")
        portfolioState = .loading

        do {
            let snapshot = try await accountService.fetchPortfolio(session: session, exchange: exchange)
            if snapshot.holdings.isEmpty && snapshot.cash == 0 {
                portfolioState = .empty
            } else {
                portfolioState = .loaded(snapshot)
            }
        } catch {
            portfolioState = .failed(error.localizedDescription)
        }
    }

    func loadOrders() async {
        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip orders fetch in guest state")
            orderHistoryState = .idle
            return
        }

        AppLogger.debug(.route, "Authenticated orders path -> \(exchange.rawValue)")
        orderHistoryState = .loading

        do {
            let orders = try await accountService.fetchOrders(
                session: session,
                exchange: exchange,
                symbol: selectedCoin?.symbol
            )
            orderHistoryState = orders.isEmpty ? .empty : .loaded(orders)
        } catch {
            orderHistoryState = .failed(error.localizedDescription)
        }
    }

    func loadExchangeConnections() async {
        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip exchange connections fetch in guest state")
            exchangeConnectionsState = .idle
            return
        }

        exchangeConnectionsState = .loading

        do {
            let connections = try await accountService.fetchExchangeConnections(session: session)
            exchangeConnectionsState = connections.isEmpty ? .empty : .loaded(connections)
        } catch {
            exchangeConnectionsState = .failed(error.localizedDescription)
        }
    }

    func submitOrder() async {
        guard let session = authState.session else {
            presentLogin(for: .trade)
            return
        }

        guard let coin = selectedCoin else {
            showNotification("시세 탭에서 코인을 먼저 선택해주세요", type: .error)
            return
        }

        guard hasTradeEnabledConnection else {
            showNotification("주문 가능 권한의 거래소 연결이 필요해요", type: .error)
            return
        }

        let quantity = Double(orderQty) ?? 0
        guard quantity > 0 else {
            showNotification("수량을 입력해주세요", type: .error)
            return
        }

        let price: Double?
        switch orderType {
        case .market:
            price = nil
        case .limit:
            let value = Double(orderPrice.replacingOccurrences(of: ",", with: ""))
            guard let value, value > 0 else {
                showNotification("주문 가격을 확인해주세요", type: .error)
                return
            }
            price = value
        }

        isSubmittingOrder = true

        do {
            try await accountService.submitOrder(
                session: session,
                request: OrderSubmissionRequest(
                    symbol: coin.symbol,
                    exchange: exchange,
                    side: orderSide,
                    type: orderType,
                    price: price,
                    quantity: quantity
                )
            )

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            showNotification("\(coin.name) 주문 요청을 전송했어요", type: .success)
            orderQty = ""
            await loadPortfolio()
            await loadOrders()
        } catch {
            showNotification(error.localizedDescription, type: .error)
        }

        isSubmittingOrder = false
    }

    func applyPercent(_ percent: Double) {
        guard let coin = selectedCoin else { return }

        let price: Double
        switch orderType {
        case .market:
            price = currentPrice
        case .limit:
            price = Double(orderPrice.replacingOccurrences(of: ",", with: "")) ?? currentPrice
        }

        guard price > 0 else { return }

        if orderSide == .buy {
            let quantity = (cash * percent / 100.0) / price
            orderQty = String(format: "%.6f", quantity)
        } else {
            let quantity = (portfolio.first { $0.symbol == coin.symbol }?.qty ?? 0) * percent / 100.0
            orderQty = String(format: "%.6f", quantity)
        }
    }

    func adjustPrice(up: Bool) {
        let baseValue = Double(orderPrice.replacingOccurrences(of: ",", with: "")) ?? currentPrice
        let step = max(baseValue * 0.001, 1)
        let newPrice = up ? baseValue + step : max(baseValue - step, 0)
        orderPrice = PriceFormatter.formatPrice(newPrice)
    }

    func showNotification(_ message: String, type: NotifType) {
        notification = (msg: message, type: type)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.notification = nil
        }
    }

    private func connectPublicMarketFeed() {
        webSocketService.connect()
        updatePublicSubscriptions()
    }

    private func bindWebSocket() {
        webSocketService.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in
                self?.publicWebSocketState = state
            }
        }

        webSocketService.onTickerReceived = { [weak self] payload in
            Task { @MainActor in
                self?.applyTickerUpdate(payload)
            }
        }

        webSocketService.onOrderbookReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard self.selectedCoin?.symbol == payload.symbol, self.exchange.rawValue == payload.exchange else { return }
                self.orderbookState = .loaded(payload.orderbook)
            }
        }

        webSocketService.onTradesReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard self.selectedCoin?.symbol == payload.symbol, self.exchange.rawValue == payload.exchange else { return }
                self.recentTradesState = payload.trades.isEmpty ? .empty : .loaded(payload.trades)
            }
        }
    }

    private func bootstrapPublicData() async {
        await withTaskGroup(of: Void.self) { group in
            for exchange in Exchange.allCases {
                group.addTask { [weak self] in
                    await self?.loadTickers(for: exchange)
                }
            }
        }
    }

    private func loadTickers(for exchange: Exchange) async {
        do {
            let tickers = try await publicService.fetchTickers(exchange: exchange)
            for (symbol, ticker) in tickers {
                mergeTicker(symbol: symbol, exchange: exchange.rawValue, incoming: ticker)
            }
        } catch {
            AppLogger.debug(.network, "Failed public ticker snapshot for \(exchange.rawValue): \(error.localizedDescription)")
        }
    }

    private func refreshDataForCurrentRoute() async {
        updateAuthGate()

        switch activeTab {
        case .market, .kimchi:
            break
        case .chart:
            await loadChartData()
        case .portfolio:
            await loadExchangeConnections()
            await loadPortfolio()
        case .trade:
            await loadExchangeConnections()
            await loadOrders()
        }
    }

    private func updateAuthGate() {
        if let feature = activeTab.protectedFeature, !isAuthenticated {
            activeAuthGate = feature
        } else {
            activeAuthGate = nil
        }
    }

    private func updatePublicSubscriptions() {
        var subscriptions = Set<PublicMarketSubscription>()

        Exchange.allCases.forEach { exchange in
            subscriptions.insert(
                PublicMarketSubscription(
                    channel: .ticker,
                    exchange: exchange.rawValue,
                    symbol: nil
                )
            )
        }

        if let selectedCoin {
            subscriptions.insert(
                PublicMarketSubscription(
                    channel: .orderbook,
                    exchange: exchange.rawValue,
                    symbol: selectedCoin.symbol
                )
            )
            subscriptions.insert(
                PublicMarketSubscription(
                    channel: .trades,
                    exchange: exchange.rawValue,
                    symbol: selectedCoin.symbol
                )
            )
        }

        webSocketService.updateSubscriptions(subscriptions)
    }

    private func applyTickerUpdate(_ payload: TickerStreamPayload) {
        mergeTicker(symbol: payload.symbol, exchange: payload.exchange, incoming: payload.ticker)
    }

    private func mergeTicker(symbol: String, exchange: String, incoming: TickerData) {
        let previous = prices[symbol]?[exchange]
        var ticker = incoming

        let previousPrice = previous?.price ?? incoming.price
        var sparkline = previous?.sparkline ?? []
        sparkline.append(incoming.price)
        if sparkline.count > 20 {
            sparkline = Array(sparkline.suffix(20))
        }

        ticker.sparkline = sparkline
        ticker.flash = incoming.price > previousPrice ? .up : (incoming.price < previousPrice ? .down : nil)

        prices[symbol, default: [:]][exchange] = ticker

        if let selectedCoin, selectedCoin.symbol == symbol, self.exchange.rawValue == exchange {
            prefillOrderPriceIfPossible()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.prices[symbol]?[exchange]?.flash = nil
        }
    }

    private func prefillOrderPriceIfPossible() {
        guard let selectedCoin else { return }
        guard let price = prices[selectedCoin.symbol]?[selectedExchange.rawValue]?.price else { return }
        orderPrice = PriceFormatter.formatPrice(price)
    }
}
