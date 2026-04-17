import SwiftUI
import Combine

enum ScreenAccessRequirement: String, Equatable {
    case publicAccess = "public access"
    case authenticatedRequired = "authenticated required"
}

enum Tab: String, CaseIterable, Equatable {
    case market
    case chart
    case trade
    case portfolio
    case kimchi

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
    case all
    case fav

    var title: String {
        switch self {
        case .all: return "전체"
        case .fav: return "관심"
        }
    }
}

enum OrderSide: String, Hashable {
    case buy
    case sell
}

enum OrderType: String, CaseIterable, Equatable, Hashable {
    case limit
    case market

    var title: String {
        switch self {
        case .limit:
            return "지정가"
        case .market:
            return "시장가"
        }
    }
}

enum NotifType {
    case success
    case error
}

@MainActor
final class CryptoViewModel: ObservableObject {
    @Published var activeTab: Tab = .market
    @Published var selectedExchange: Exchange = .upbit
    @Published var selectedCoin: CoinInfo?
    @Published var showExchangeMenu = false

    @Published private(set) var marketState: Loadable<[CoinInfo]> = .idle
    @Published private(set) var prices: [String: [String: TickerData]] = [:]
    @Published private(set) var marketStatusViewState: ScreenStatusViewState = .idle
    @Published var searchQuery = ""
    @Published var marketFilter: MarketFilter = .all
    @Published private(set) var favCoins: Set<String> = []

    @Published var chartPeriod = "1h"
    @Published private(set) var candlesState: Loadable<[CandleData]> = .idle
    @Published private(set) var orderbookState: Loadable<OrderbookData> = .idle
    @Published private(set) var recentTradesState: Loadable<[PublicTrade]> = .idle
    @Published private(set) var chartStatusViewState: ScreenStatusViewState = .idle

    @Published var orderSide: OrderSide = .buy
    @Published var orderType: OrderType = .limit
    @Published var orderPrice = ""
    @Published var orderQty = ""
    @Published private(set) var isSubmittingOrder = false
    @Published private(set) var tradingChanceState: Loadable<TradingChance> = .idle
    @Published private(set) var orderHistoryState: Loadable<[OrderRecord]> = .idle
    @Published private(set) var fillsState: Loadable<[TradeFill]> = .idle
    @Published private(set) var selectedOrderDetailState: Loadable<OrderRecord> = .idle
    @Published private(set) var tradingStatusViewState: ScreenStatusViewState = .idle

    @Published private(set) var portfolioState: Loadable<PortfolioSnapshot> = .idle
    @Published private(set) var portfolioHistoryState: Loadable<[PortfolioHistoryItem]> = .idle
    @Published private(set) var portfolioStatusViewState: ScreenStatusViewState = .idle

    @Published private(set) var kimchiPremiumState: Loadable<[KimchiPremiumCoinViewState]> = .idle
    @Published private(set) var kimchiStatusViewState: ScreenStatusViewState = .idle

    @Published private(set) var exchangeConnectionsState: Loadable<[ExchangeConnectionCardViewState]> = .idle
    @Published private(set) var authState: AuthState = .guest
    @Published private(set) var activeAuthGate: ProtectedFeature?
    @Published private(set) var publicWebSocketState: PublicWebSocketConnectionState = .disconnected
    @Published private(set) var privateWebSocketState: PrivateWebSocketConnectionState = .disconnected

    @Published var notification: (msg: String, type: NotifType)?
    @Published var isLoginPresented = false
    @Published var isExchangeConnectionsPresented = false
    @Published var loginEmail = ""
    @Published var loginPassword = ""
    @Published var loginErrorMessage: String?

    private let marketRepository: MarketRepositoryProtocol
    private let tradingRepository: TradingRepositoryProtocol
    private let portfolioRepository: PortfolioRepositoryProtocol
    private let kimchiPremiumRepository: KimchiPremiumRepositoryProtocol
    private let exchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol
    private let authService: AuthenticationServiceProtocol
    private let publicWebSocketService: PublicWebSocketServicing
    private let privateWebSocketService: PrivateWebSocketServicing

    private let capabilityResolver = ExchangeCapabilityResolver()
    private let screenStatusFactory = ScreenStatusFactory()
    private let exchangeConnectionsUseCase = ExchangeConnectionsUseCase()
    private let exchangeConnectionFormValidator = ExchangeConnectionFormValidator()
    private let kimchiPremiumViewStateUseCase = KimchiPremiumViewStateUseCase()

    private let favoritesKey = "guest.favorite.symbols"

    private var hasBootstrapped = false
    private var pendingPostLoginFeature: ProtectedFeature?
    private var marketsByExchange: [Exchange: [CoinInfo]] = [:]
    private var supportedIntervalsByExchangeAndSymbol: [Exchange: [String: [String]]] = [:]
    private var loadedExchangeConnections: [ExchangeConnection] = []
    private var publicPollingTask: Task<Void, Never>?
    private var privatePollingTask: Task<Void, Never>?
    private var isPublicPollingFallbackActive = false
    private var isPrivatePollingFallbackActive = false

    var exchange: Exchange {
        get { selectedExchange }
        set { updateExchange(newValue) }
    }

    init(
        marketRepository: MarketRepositoryProtocol? = nil,
        tradingRepository: TradingRepositoryProtocol? = nil,
        portfolioRepository: PortfolioRepositoryProtocol? = nil,
        kimchiPremiumRepository: KimchiPremiumRepositoryProtocol? = nil,
        exchangeConnectionsRepository: ExchangeConnectionsRepositoryProtocol? = nil,
        authService: AuthenticationServiceProtocol? = nil,
        publicWebSocketService: PublicWebSocketServicing? = nil,
        privateWebSocketService: PrivateWebSocketServicing? = nil
    ) {
        self.marketRepository = marketRepository ?? LiveMarketRepository()
        self.tradingRepository = tradingRepository ?? LiveTradingRepository()
        self.portfolioRepository = portfolioRepository ?? LivePortfolioRepository()
        self.kimchiPremiumRepository = kimchiPremiumRepository ?? LiveKimchiPremiumRepository()
        self.exchangeConnectionsRepository = exchangeConnectionsRepository ?? LiveExchangeConnectionsRepository()
        self.authService = authService ?? LiveAuthenticationService()
        self.publicWebSocketService = publicWebSocketService ?? WebSocketService()
        self.privateWebSocketService = privateWebSocketService ?? PrivateWebSocketService()
        self.favCoins = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])

        bindPublicWebSocket()
        bindPrivateWebSocket()
        connectPublicMarketFeed()
    }

    deinit {
        publicPollingTask?.cancel()
        privatePollingTask?.cancel()
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

    var currentTradingChance: TradingChance? {
        tradingChanceState.value
    }

    var portfolio: [Holding] {
        portfolioState.value?.holdings ?? []
    }

    var cash: Double {
        portfolioState.value?.cash ?? 0
    }

    var currentSupportedOrderTypes: [OrderType] {
        let supportedOrderTypes = tradingChanceState.value?.supportedOrderTypes ?? [.limit, .market]
        return supportedOrderTypes.isEmpty ? [.limit, .market] : supportedOrderTypes
    }

    var availableChartIntervals: [CandleIntervalOption] {
        CandleIntervalCatalog.options(supportedIntervals: supportedIntervals)
    }

    var exchangeConnectionCRUDCapability: ExchangeConnectionCRUDCapability {
        exchangeConnectionsRepository.crudCapability
    }

    var exchangeConnections: [ExchangeConnection] {
        loadedExchangeConnections
    }

    var hasAnyExchangeConnection: Bool {
        !loadedExchangeConnections.isEmpty
    }

    var hasTradeEnabledConnection: Bool {
        loadedExchangeConnections.contains {
            $0.exchange == selectedExchange && $0.isActive && $0.permission == .tradeEnabled
        }
    }

    var selectedExchangeConnection: ExchangeConnection? {
        loadedExchangeConnections.first { $0.exchange == selectedExchange && $0.isActive }
    }

    var filteredCoins: [CoinInfo] {
        let coins = marketState.value ?? derivedCoinListForSelectedExchange()

        let filteredByFavorite = marketFilter == .fav
            ? coins.filter { favCoins.contains($0.symbol) }
            : coins

        guard !searchQuery.isEmpty else {
            return filteredByFavorite
        }

        let query = searchQuery.lowercased()
        return filteredByFavorite.filter {
            $0.symbol.lowercased().contains(query)
            || $0.name.lowercased().contains(query)
            || $0.nameEn.lowercased().contains(query)
        }
    }

    var currentTicker: TickerData? {
        guard let coin = selectedCoin else { return nil }
        return prices[coin.symbol]?[exchange.rawValue]
    }

    var currentPrice: Double {
        currentTicker?.price ?? 0
    }

    var totalAsset: Double {
        portfolioState.value?.totalAsset ?? 0
    }

    var totalPnl: Double {
        portfolio.reduce(0) { $0 + $1.profitLoss }
    }

    var totalPnlPercent: Double {
        let investedAmount = totalAsset - totalPnl
        guard investedAmount > 0 else { return 0 }
        return (totalPnl / investedAmount) * 100
    }

    var isSelectedExchangeTradingUnsupported: Bool {
        !capabilityResolver.supportsTrading(on: selectedExchange)
    }

    var isSelectedExchangePortfolioUnsupported: Bool {
        !capabilityResolver.supportsPortfolio(on: selectedExchange)
    }

    var isSelectedExchangeChartUnsupported: Bool {
        !capabilityResolver.supportsChart(on: selectedExchange)
    }

    func onAppear() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        Task {
            await bootstrapPublicData()
            await refreshDataForCurrentRoute(forceRefresh: true)
        }
    }

    func onScenePhaseChanged(_ scenePhase: ScenePhase) {
        guard scenePhase == .active else { return }

        if authState.session != nil {
            connectPrivateTradingFeedIfNeeded()
        }
        connectPublicMarketFeed()

        Task {
            await refreshDataForCurrentRoute(forceRefresh: true)
        }
    }

    func setActiveTab(_ tab: Tab) {
        guard activeTab != tab else { return }
        activeTab = tab
        showExchangeMenu = false

        AppLogger.debug(.route, "Screen -> \(tab.title) (\(tab.accessRequirement.rawValue))")
        updateAuthGate()
        updatePublicSubscriptions()
        updatePrivateSubscriptions()
        updatePublicPollingIfNeeded()
        updatePrivatePollingIfNeeded()

        Task {
            await refreshDataForCurrentRoute(forceRefresh: false)
        }
    }

    func updateExchange(_ exchange: Exchange) {
        guard selectedExchange != exchange else { return }
        selectedExchange = exchange
        AppLogger.debug(.route, "Exchange changed -> \(exchange.rawValue)")

        ensureSelectedCoinForCurrentExchange()
        prefillOrderPriceIfPossible()
        updatePublicSubscriptions()
        updatePrivateSubscriptions()

        Task {
            await refreshDataForCurrentRoute(forceRefresh: false)
        }
    }

    func selectCoin(_ coin: CoinInfo) {
        selectedCoin = coin
        prefillOrderPriceIfPossible()
        setActiveTab(.chart)
    }

    func selectCoinForTrade(_ coin: CoinInfo) {
        selectedCoin = coin
        prefillOrderPriceIfPossible()
        setActiveTab(.trade)
    }

    func setChartInterval(_ interval: String) {
        chartPeriod = interval
        updatePublicSubscriptions()

        Task {
            await loadChartData()
        }
    }

    func loadChartData() async {
        guard capabilityResolver.supportsChart(on: selectedExchange) else {
            candlesState = .failed("이 거래소는 차트를 지원하지 않아요.")
            orderbookState = .failed("이 거래소는 호가를 지원하지 않아요.")
            recentTradesState = .failed("이 거래소는 최근 체결을 지원하지 않아요.")
            chartStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: .snapshotOnly,
                warningMessage: "지원하지 않는 기능입니다."
            )
            return
        }

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

        async let candleTask = marketRepository.fetchCandles(symbol: coin.symbol, exchange: exchange, interval: chartPeriod)
        async let orderbookTask = marketRepository.fetchOrderbook(symbol: coin.symbol, exchange: exchange)
        async let tradesTask = marketRepository.fetchTrades(symbol: coin.symbol, exchange: exchange)

        var metas: [ResponseMeta] = []
        var warningMessages: [String] = []

        do {
            let candleSnapshot = try await candleTask
            metas.append(candleSnapshot.meta)
            if candleSnapshot.meta.warningMessage != nil {
                warningMessages.append(candleSnapshot.meta.warningMessage!)
            }
            candlesState = candleSnapshot.candles.isEmpty ? .empty : .loaded(candleSnapshot.candles)
        } catch {
            candlesState = .failed(error.localizedDescription)
        }

        do {
            let orderbookSnapshot = try await orderbookTask
            metas.append(orderbookSnapshot.meta)
            if orderbookSnapshot.meta.warningMessage != nil {
                warningMessages.append(orderbookSnapshot.meta.warningMessage!)
            }
            orderbookState = .loaded(orderbookSnapshot.orderbook)
        } catch {
            orderbookState = .failed(error.localizedDescription)
        }

        do {
            let tradesSnapshot = try await tradesTask
            metas.append(tradesSnapshot.meta)
            if tradesSnapshot.meta.warningMessage != nil {
                warningMessages.append(tradesSnapshot.meta.warningMessage!)
            }
            recentTradesState = tradesSnapshot.trades.isEmpty ? .empty : .loaded(tradesSnapshot.trades)
        } catch {
            recentTradesState = .failed(error.localizedDescription)
        }

        chartStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: combineMetas(metas),
            streamingStatus: currentPublicStreamingStatus,
            warningMessage: resolvedWarningMessage(
                primary: warningMessages.first,
                fallback: currentPublicStreamingWarningMessage
            )
        )
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
            connectPrivateTradingFeedIfNeeded()

            if pendingPostLoginFeature == .exchangeConnections {
                await loadExchangeConnections()
            }
            await refreshDataForCurrentRoute(forceRefresh: true)

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
        portfolioHistoryState = .idle
        orderHistoryState = .idle
        fillsState = .idle
        selectedOrderDetailState = .idle
        exchangeConnectionsState = .idle
        loadedExchangeConnections = []
        privateWebSocketService.disconnect()
        updateAuthGate()
        updatePrivateSubscriptions()
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

    func makeExchangeConnectionFormViewState(
        exchange: Exchange,
        connection: ExchangeConnection? = nil
    ) -> ExchangeConnectionFormViewState {
        if let connection {
            return .edit(connection: connection)
        }
        return .create(exchange: exchange)
    }

    func validationMessageForExchangeConnectionForm(
        exchange: Exchange,
        nickname: String,
        credentials: [ExchangeCredentialFieldKey: String],
        mode: ExchangeConnectionFormViewState.Mode
    ) -> String? {
        exchangeConnectionFormValidator.validationMessage(
            exchange: exchange,
            nickname: nickname,
            credentials: credentials,
            mode: mode
        )
    }

    @discardableResult
    func createExchangeConnection(
        exchange: Exchange,
        nickname: String,
        permission: ExchangeConnectionPermission,
        credentials: [ExchangeCredentialFieldKey: String]
    ) async -> Bool {
        guard let session = authState.session else {
            presentLogin(for: .exchangeConnections)
            return false
        }

        let validationMessage = exchangeConnectionFormValidator.validationMessage(
            exchange: exchange,
            nickname: nickname,
            credentials: credentials,
            mode: .create
        )
        guard validationMessage == nil else {
            showNotification(validationMessage!, type: .error)
            return false
        }

        do {
            _ = try await exchangeConnectionsRepository.createConnection(
                session: session,
                request: ExchangeConnectionUpsertRequest(
                    exchange: exchange,
                    permission: permission,
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    credentials: credentials.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                )
            )
            showNotification("거래소 연결을 추가했어요", type: .success)
            await loadExchangeConnections()
            return true
        } catch {
            showNotification(error.localizedDescription, type: .error)
            return false
        }
    }

    @discardableResult
    func updateExchangeConnection(
        connection: ExchangeConnection,
        nickname: String,
        permission: ExchangeConnectionPermission,
        credentials: [ExchangeCredentialFieldKey: String]
    ) async -> Bool {
        guard let session = authState.session else {
            presentLogin(for: .exchangeConnections)
            return false
        }

        let filteredCredentials = credentials.filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let validationMessage = exchangeConnectionFormValidator.validationMessage(
            exchange: connection.exchange,
            nickname: nickname,
            credentials: filteredCredentials,
            mode: .edit(connectionID: connection.id)
        )

        guard validationMessage == nil else {
            showNotification(validationMessage!, type: .error)
            return false
        }

        do {
            _ = try await exchangeConnectionsRepository.updateConnection(
                session: session,
                request: ExchangeConnectionUpdateRequest(
                    id: connection.id,
                    permission: permission,
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    credentials: filteredCredentials
                )
            )
            showNotification("거래소 연결을 수정했어요", type: .success)
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
            try await exchangeConnectionsRepository.deleteConnection(session: session, connectionID: id)
            showNotification("거래소 연결을 삭제했어요", type: .success)
            await loadExchangeConnections()
            return true
        } catch {
            showNotification(error.localizedDescription, type: .error)
            return false
        }
    }

    func loadPortfolio() async {
        guard capabilityResolver.supportsPortfolio(on: selectedExchange) else {
            portfolioState = .failed("이 거래소는 자산 조회를 지원하지 않아요.")
            portfolioHistoryState = .idle
            portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: currentPrivateStreamingStatus,
                warningMessage: "지원하지 않는 기능입니다."
            )
            return
        }

        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip portfolio fetch in guest state")
            portfolioState = .idle
            portfolioHistoryState = .idle
            return
        }

        AppLogger.debug(.route, "Authenticated portfolio path -> \(exchange.rawValue)")
        portfolioState = .loading
        portfolioHistoryState = .loading

        do {
            async let summaryTask = portfolioRepository.fetchSummary(session: session, exchange: exchange)
            async let historyTask = portfolioRepository.fetchHistory(session: session, exchange: exchange)

            let summary = try await summaryTask
            portfolioState = summary.holdings.isEmpty && summary.cash == 0 ? .empty : .loaded(summary)

            do {
                let historySnapshot = try await historyTask
                portfolioHistoryState = historySnapshot.items.isEmpty ? .empty : .loaded(historySnapshot.items)
                portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
                    meta: combineMetas([summary.meta, historySnapshot.meta]),
                    streamingStatus: currentPrivateStreamingStatus,
                    warningMessage: resolvedWarningMessage(
                        primary: summary.partialFailureMessage ?? historySnapshot.meta.partialFailureMessage,
                        fallback: currentPrivateStreamingWarningMessage
                    )
                )
            } catch {
                portfolioHistoryState = .failed(error.localizedDescription)
                portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
                    meta: summary.meta,
                    streamingStatus: currentPrivateStreamingStatus,
                    warningMessage: resolvedWarningMessage(
                        primary: summary.partialFailureMessage ?? "일부 히스토리를 불러오지 못했어요.",
                        fallback: currentPrivateStreamingWarningMessage
                    )
                )
            }
        } catch {
            portfolioState = .failed(error.localizedDescription)
            portfolioHistoryState = .idle
            portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: currentPrivateStreamingStatus,
                warningMessage: resolvedWarningMessage(
                    primary: error.localizedDescription,
                    fallback: currentPrivateStreamingWarningMessage
                )
            )
        }
    }

    func loadOrders() async {
        guard capabilityResolver.supportsTrading(on: selectedExchange) else {
            orderHistoryState = .failed("이 거래소는 주문 기능을 지원하지 않아요.")
            fillsState = .idle
            tradingChanceState = .idle
            tradingStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: currentPrivateStreamingStatus,
                warningMessage: "지원하지 않는 기능입니다."
            )
            return
        }

        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip orders fetch in guest state")
            orderHistoryState = .idle
            fillsState = .idle
            tradingChanceState = .idle
            return
        }

        guard let coin = selectedCoin else {
            tradingChanceState = .idle
            orderHistoryState = .idle
            fillsState = .idle
            selectedOrderDetailState = .idle
            return
        }

        tradingChanceState = .loading
        orderHistoryState = .loading
        fillsState = .loading

        var metas: [ResponseMeta] = []
        var warningMessages: [String] = []

        do {
            let chance = try await tradingRepository.fetchChance(session: session, exchange: selectedExchange, symbol: coin.symbol)
            tradingChanceState = .loaded(chance)
            if !chance.supportedOrderTypes.contains(orderType) {
                orderType = chance.supportedOrderTypes.first ?? .limit
            }
            if let warningMessage = chance.warningMessage {
                warningMessages.append(warningMessage)
            }
        } catch {
            tradingChanceState = .failed(error.localizedDescription)
        }

        do {
            let openOrdersSnapshot = try await tradingRepository.fetchOpenOrders(session: session, exchange: selectedExchange, symbol: coin.symbol)
            metas.append(openOrdersSnapshot.meta)
            if let warningMessage = openOrdersSnapshot.meta.warningMessage {
                warningMessages.append(warningMessage)
            }
            orderHistoryState = openOrdersSnapshot.orders.isEmpty ? .empty : .loaded(openOrdersSnapshot.orders)
        } catch {
            orderHistoryState = .failed(error.localizedDescription)
        }

        do {
            let fillsSnapshot = try await tradingRepository.fetchFills(session: session, exchange: selectedExchange, symbol: coin.symbol)
            metas.append(fillsSnapshot.meta)
            if let warningMessage = fillsSnapshot.meta.warningMessage {
                warningMessages.append(warningMessage)
            }
            fillsState = fillsSnapshot.fills.isEmpty ? .empty : .loaded(fillsSnapshot.fills)
        } catch {
            fillsState = .failed(error.localizedDescription)
        }

        tradingStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: combineMetas(metas),
            streamingStatus: currentPrivateStreamingStatus,
            warningMessage: resolvedWarningMessage(
                primary: warningMessages.first,
                fallback: currentPrivateStreamingWarningMessage
            )
        )
    }

    func loadOrderDetail(orderID: String) async {
        guard let session = authState.session else {
            presentLogin(for: .trade)
            return
        }

        selectedOrderDetailState = .loading

        do {
            let detail = try await tradingRepository.fetchOrderDetail(session: session, exchange: selectedExchange, orderID: orderID)
            selectedOrderDetailState = .loaded(detail)
        } catch {
            selectedOrderDetailState = .failed(error.localizedDescription)
        }
    }

    func cancelOrder(_ order: OrderRecord) async {
        guard let session = authState.session else {
            presentLogin(for: .trade)
            return
        }

        do {
            try await tradingRepository.cancelOrder(session: session, exchange: selectedExchange, orderID: order.id)
            showNotification("주문을 취소했어요", type: .success)
            await loadOrders()
            await loadPortfolio()
        } catch {
            showNotification(error.localizedDescription, type: .error)
        }
    }

    func loadExchangeConnections() async {
        guard let session = authState.session else {
            AppLogger.debug(.auth, "Skip exchange connections fetch in guest state")
            exchangeConnectionsState = .idle
            loadedExchangeConnections = []
            return
        }

        exchangeConnectionsState = .loading

        do {
            let snapshot = try await exchangeConnectionsRepository.fetchConnections(session: session)
            loadedExchangeConnections = snapshot.connections
            let cards = exchangeConnectionsUseCase.makeCardViewStates(
                connections: snapshot.connections,
                crudCapability: exchangeConnectionCRUDCapability
            )
            exchangeConnectionsState = cards.isEmpty ? .empty : .loaded(cards)
            updatePrivateSubscriptions()
        } catch {
            exchangeConnectionsState = .failed(error.localizedDescription)
        }
    }

    func loadKimchiPremium() async {
        let symbols = preferredKimchiSymbols()
        kimchiPremiumState = .loading

        do {
            let snapshot = try await kimchiPremiumRepository.fetchSnapshot(symbols: symbols)
            let viewStates = kimchiPremiumViewStateUseCase.makeCoinViewStates(from: snapshot)
            kimchiPremiumState = viewStates.isEmpty ? .empty : .loaded(viewStates)
            kimchiStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: ResponseMeta(
                    fetchedAt: snapshot.fetchedAt,
                    isStale: snapshot.isStale,
                    warningMessage: snapshot.warningMessage,
                    partialFailureMessage: nil
                ),
                streamingStatus: currentPublicStreamingStatus,
                warningMessage: resolvedWarningMessage(
                    primary: snapshot.warningMessage,
                    fallback: currentPublicStreamingWarningMessage
                )
            )
        } catch {
            kimchiPremiumState = .failed(error.localizedDescription)
            kimchiStatusViewState = screenStatusFactory.makeStatusViewState(
                meta: .empty,
                streamingStatus: currentPublicStreamingStatus,
                warningMessage: resolvedWarningMessage(
                    primary: error.localizedDescription,
                    fallback: currentPublicStreamingWarningMessage
                )
            )
        }
    }

    func submitOrder() async {
        guard let session = authState.session else {
            presentLogin(for: .trade)
            return
        }

        guard capabilityResolver.supportsTrading(on: selectedExchange) else {
            showNotification("선택한 거래소는 주문을 지원하지 않아요.", type: .error)
            return
        }

        guard let coin = selectedCoin else {
            showNotification("시세 탭에서 코인을 먼저 선택해주세요", type: .error)
            return
        }

        guard hasTradeEnabledConnection else {
            showNotification("선택한 거래소에 주문 가능 권한 연결이 필요해요", type: .error)
            return
        }

        guard currentSupportedOrderTypes.contains(orderType) else {
            showNotification("서버에서 지원하는 주문 타입만 사용할 수 있어요", type: .error)
            return
        }

        let quantity = Double(orderQty.replacingOccurrences(of: ",", with: "")) ?? 0
        guard quantity > 0 else {
            showNotification("수량을 입력해주세요", type: .error)
            return
        }

        let price: Double?
        switch orderType {
        case .market:
            price = nil
        case .limit:
            let parsedPrice = Double(orderPrice.replacingOccurrences(of: ",", with: "")) ?? 0
            guard parsedPrice > 0 else {
                showNotification("주문 가격을 확인해주세요", type: .error)
                return
            }
            price = parsedPrice
        }

        if let minimumOrderAmount = tradingChanceState.value?.minimumOrderAmount {
            let notional = (price ?? currentPrice) * quantity
            guard notional >= minimumOrderAmount else {
                showNotification("최소 주문금액 \(PriceFormatter.formatInteger(minimumOrderAmount)) KRW 이상이어야 해요", type: .error)
                return
            }
        }

        isSubmittingOrder = true

        do {
            _ = try await tradingRepository.createOrder(
                session: session,
                request: TradingOrderCreateRequest(
                    symbol: coin.symbol,
                    exchange: selectedExchange,
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
            await loadOrders()
            await loadPortfolio()
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
            let buyingBalance = tradingChanceState.value?.bidBalance ?? cash
            let quantity = (buyingBalance * percent / 100.0) / price
            orderQty = String(format: "%.6f", quantity)
        } else {
            let holdingQuantity = portfolio.first { $0.symbol == coin.symbol }?.totalQuantity ?? 0
            let quantity = holdingQuantity * percent / 100.0
            orderQty = String(format: "%.6f", quantity)
        }
    }

    func adjustPrice(up: Bool) {
        let baseValue = Double(orderPrice.replacingOccurrences(of: ",", with: "")) ?? currentPrice
        let priceUnit = tradingChanceState.value?.priceUnit ?? max(baseValue * 0.001, 1)
        let newPrice = up ? baseValue + priceUnit : max(baseValue - priceUnit, 0)
        orderPrice = PriceFormatter.formatPrice(newPrice)
    }

    func showNotification(_ message: String, type: NotifType) {
        notification = (msg: message, type: type)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.notification = nil
        }
    }

    private func connectPublicMarketFeed() {
        publicWebSocketService.connect()
        updatePublicSubscriptions()
    }

    private func connectPrivateTradingFeedIfNeeded() {
        guard let session = authState.session else {
            privateWebSocketService.disconnect()
            return
        }

        privateWebSocketService.connect(accessToken: session.accessToken)
        updatePrivateSubscriptions()
    }

    private func bindPublicWebSocket() {
        publicWebSocketService.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.publicWebSocketState = state
                self.updatePublicPollingIfNeeded()
                self.refreshPublicStatusViewStates()
            }
        }

        publicWebSocketService.onTickerReceived = { [weak self] payload in
            Task { @MainActor in
                self?.applyTickerUpdate(payload)
            }
        }

        publicWebSocketService.onOrderbookReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard self.selectedCoin?.symbol == payload.symbol, self.exchange.rawValue == payload.exchange else { return }
                self.orderbookState = .loaded(payload.orderbook)
                self.refreshPublicStatusViewStates()
            }
        }

        publicWebSocketService.onTradesReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard self.selectedCoin?.symbol == payload.symbol, self.exchange.rawValue == payload.exchange else { return }
                self.recentTradesState = payload.trades.isEmpty ? .empty : .loaded(payload.trades)
                self.refreshPublicStatusViewStates()
            }
        }

        publicWebSocketService.onCandlesReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard self.selectedCoin?.symbol == payload.symbol, self.exchange.rawValue == payload.exchange else { return }
                guard self.chartPeriod.lowercased() == payload.interval.lowercased() else { return }
                self.mergeCandleUpdate(payload)
                self.refreshPublicStatusViewStates()
            }
        }
    }

    private func bindPrivateWebSocket() {
        privateWebSocketService.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.privateWebSocketState = state
                self.updatePrivatePollingIfNeeded()
                self.refreshPrivateStatusViewStates()
            }
        }

        privateWebSocketService.onOrderReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard payload.exchange == self.selectedExchange else { return }
                self.applyOrderStreamUpdate(payload.order)
                self.refreshPrivateStatusViewStates()
            }
        }

        privateWebSocketService.onFillReceived = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                guard payload.exchange == self.selectedExchange else { return }
                self.applyFillStreamUpdate(payload.fill)
                self.refreshPrivateStatusViewStates()
            }
        }
    }

    private func bootstrapPublicData() async {
        for exchange in Exchange.allCases {
            await loadMarkets(for: exchange)
            await loadTickers(for: exchange)
        }

        ensureSelectedCoinForCurrentExchange()
        refreshMarketStateForSelectedExchange()
    }

    private func loadMarkets(for exchange: Exchange) async {
        do {
            let catalogSnapshot = try await marketRepository.fetchMarkets(exchange: exchange)
            marketsByExchange[exchange] = catalogSnapshot.markets
            supportedIntervalsByExchangeAndSymbol[exchange] = catalogSnapshot.supportedIntervalsBySymbol
            if selectedExchange == exchange {
                refreshMarketStateForSelectedExchange(meta: catalogSnapshot.meta)
            }
        } catch {
            AppLogger.debug(.network, "Failed market catalog for \(exchange.rawValue): \(error.localizedDescription)")
            if selectedExchange == exchange, marketState.value == nil {
                refreshMarketStateForSelectedExchange()
            }
        }
    }

    private func loadTickers(for exchange: Exchange) async {
        do {
            let tickerSnapshot = try await marketRepository.fetchTickers(exchange: exchange)
            for (symbol, ticker) in tickerSnapshot.tickers {
                mergeTicker(symbol: symbol, exchange: exchange.rawValue, incoming: ticker)
            }

            if selectedExchange == exchange {
                refreshMarketStateForSelectedExchange(meta: tickerSnapshot.meta)
                marketStatusViewState = screenStatusFactory.makeStatusViewState(
                    meta: tickerSnapshot.meta,
                    streamingStatus: currentPublicStreamingStatus,
                    warningMessage: currentPublicStreamingWarningMessage
                )
            }
        } catch {
            AppLogger.debug(.network, "Failed public ticker snapshot for \(exchange.rawValue): \(error.localizedDescription)")
            if selectedExchange == exchange {
                refreshMarketStateForSelectedExchange()
            }
        }
    }

    private func refreshDataForCurrentRoute(forceRefresh: Bool) async {
        updateAuthGate()

        switch activeTab {
        case .market:
            if forceRefresh {
                await loadMarkets(for: selectedExchange)
                await loadTickers(for: selectedExchange)
            } else {
                refreshMarketStateForSelectedExchange()
            }
        case .kimchi:
            await loadKimchiPremium()
        case .chart:
            if forceRefresh {
                await loadTickers(for: selectedExchange)
            }
            await loadChartData()
        case .portfolio:
            await loadExchangeConnections()
            await loadPortfolio()
        case .trade:
            await loadExchangeConnections()
            await loadOrders()
            if portfolioState.value == nil || forceRefresh {
                await loadPortfolio()
            }
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

        let exchangesForTickerSubscriptions: [Exchange]
        if activeTab == .kimchi {
            exchangesForTickerSubscriptions = Exchange.allCases.filter(\.supportsKimchiPremium)
        } else {
            exchangesForTickerSubscriptions = Exchange.allCases
        }

        exchangesForTickerSubscriptions.forEach { exchange in
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

            if activeTab == .chart {
                subscriptions.insert(
                    PublicMarketSubscription(
                        channel: .candles,
                        exchange: exchange.rawValue,
                        symbol: selectedCoin.symbol,
                        interval: chartPeriod
                    )
                )
            }
        }

        publicWebSocketService.updateSubscriptions(subscriptions)
    }

    private func updatePrivateSubscriptions() {
        guard isAuthenticated else {
            privateWebSocketService.updateSubscriptions([])
            return
        }

        var subscriptions = Set<PrivateTradingSubscription>()

        if selectedExchange.supportsOrder {
            subscriptions.insert(
                PrivateTradingSubscription(
                    channel: .orders,
                    exchange: selectedExchange.rawValue,
                    symbol: selectedCoin?.symbol
                )
            )
            subscriptions.insert(
                PrivateTradingSubscription(
                    channel: .fills,
                    exchange: selectedExchange.rawValue,
                    symbol: selectedCoin?.symbol
                )
            )
        }

        if selectedExchange.supportsAsset {
            subscriptions.insert(
                PrivateTradingSubscription(
                    channel: .portfolio,
                    exchange: selectedExchange.rawValue,
                    symbol: nil
                )
            )
        }

        privateWebSocketService.updateSubscriptions(subscriptions)
    }

    private func updatePublicPollingIfNeeded() {
        publicPollingTask?.cancel()

        guard currentPublicStreamingStatus == .pollingFallback else {
            if isPublicPollingFallbackActive {
                AppLogger.debug(.network, "Public polling fallback -> inactive")
            }
            isPublicPollingFallbackActive = false
            return
        }

        if !isPublicPollingFallbackActive {
            AppLogger.debug(
                .network,
                "Public polling fallback -> active (state=\(describe(publicWebSocketState)), exchange=\(selectedExchange.rawValue), route=\(activeTab.rawValue))"
            )
        }
        isPublicPollingFallbackActive = true

        publicPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await self?.pollPublicFallback()
            }
        }
    }

    private func updatePrivatePollingIfNeeded() {
        privatePollingTask?.cancel()

        guard isAuthenticated, currentPrivateStreamingStatus == .pollingFallback else {
            if isPrivatePollingFallbackActive {
                AppLogger.debug(.network, "Private polling fallback -> inactive")
            }
            isPrivatePollingFallbackActive = false
            return
        }

        if !isPrivatePollingFallbackActive {
            AppLogger.debug(
                .network,
                "Private polling fallback -> active (state=\(describe(privateWebSocketState)), exchange=\(selectedExchange.rawValue), route=\(activeTab.rawValue))"
            )
        }
        isPrivatePollingFallbackActive = true

        privatePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                await self?.pollPrivateFallback()
            }
        }
    }

    private func pollPublicFallback() async {
        switch activeTab {
        case .market:
            await loadTickers(for: selectedExchange)
        case .chart:
            await loadTickers(for: selectedExchange)
            await loadChartData()
        case .kimchi:
            for exchange in Exchange.allCases.filter(\.supportsKimchiPremium) {
                await loadTickers(for: exchange)
            }
            await loadKimchiPremium()
        case .trade, .portfolio:
            break
        }
    }

    private func pollPrivateFallback() async {
        guard isAuthenticated else { return }

        switch activeTab {
        case .portfolio:
            await loadExchangeConnections()
            await loadPortfolio()
        case .trade:
            await loadExchangeConnections()
            await loadOrders()
        case .market, .chart, .kimchi:
            break
        }
    }

    private func applyTickerUpdate(_ payload: TickerStreamPayload) {
        mergeTicker(symbol: payload.symbol, exchange: payload.exchange, incoming: payload.ticker)
        refreshMarketStateForSelectedExchange()
        refreshPublicStatusViewStates()
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

    private func mergeCandleUpdate(_ payload: CandleStreamPayload) {
        var currentCandles = candlesState.value ?? []
        for incomingCandle in payload.candles {
            if let existingIndex = currentCandles.firstIndex(where: { $0.time == incomingCandle.time }) {
                currentCandles[existingIndex] = incomingCandle
            } else {
                currentCandles.append(incomingCandle)
            }
        }

        currentCandles.sort { $0.time < $1.time }
        candlesState = currentCandles.isEmpty ? .empty : .loaded(currentCandles)
    }

    private func applyOrderStreamUpdate(_ order: OrderRecord) {
        var orders = orderHistoryState.value ?? []
        if let existingIndex = orders.firstIndex(where: { $0.id == order.id }) {
            orders[existingIndex] = order
        } else {
            orders.insert(order, at: 0)
        }

        orderHistoryState = orders.isEmpty ? .empty : .loaded(orders)

        if case .loaded(let detail) = selectedOrderDetailState, detail.id == order.id {
            selectedOrderDetailState = .loaded(order)
        }
    }

    private func applyFillStreamUpdate(_ fill: TradeFill) {
        var fills = fillsState.value ?? []
        if fills.contains(where: { $0.id == fill.id }) == false {
            fills.insert(fill, at: 0)
        }
        fillsState = fills.isEmpty ? .empty : .loaded(Array(fills.prefix(20)))
    }

    private func prefillOrderPriceIfPossible() {
        guard let selectedCoin else { return }
        guard let price = prices[selectedCoin.symbol]?[selectedExchange.rawValue]?.price else { return }
        orderPrice = PriceFormatter.formatPrice(price)
    }

    private func refreshMarketStateForSelectedExchange(
        meta: ResponseMeta = ResponseMeta(
            fetchedAt: nil,
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil
        )
    ) {
        let coins = derivedCoinListForSelectedExchange()

        if coins.isEmpty {
            marketState = .empty
        } else {
            marketState = .loaded(coins)
        }

        marketStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: meta,
            streamingStatus: currentPublicStreamingStatus,
            warningMessage: currentPublicStreamingWarningMessage
        )
        ensureSelectedCoinForCurrentExchange()
    }

    private func derivedCoinListForSelectedExchange() -> [CoinInfo] {
        let catalogCoins = marketsByExchange[selectedExchange] ?? []
        let tickerSymbols = prices.compactMap { symbol, exchangeMap -> String? in
            exchangeMap[selectedExchange.rawValue] == nil ? nil : symbol
        }

        let fallbackCoins = tickerSymbols.map { CoinCatalog.coin(symbol: $0) }
        let merged = (fallbackCoins + catalogCoins).reduce(into: [String: CoinInfo]()) { partialResult, coin in
            partialResult[coin.symbol] = coin
        }

        return merged.values.sorted { leftCoin, rightCoin in
            let leftVolume = prices[leftCoin.symbol]?[selectedExchange.rawValue]?.volume ?? 0
            let rightVolume = prices[rightCoin.symbol]?[selectedExchange.rawValue]?.volume ?? 0
            if leftVolume == rightVolume {
                return leftCoin.symbol < rightCoin.symbol
            }
            return leftVolume > rightVolume
        }
    }

    private func ensureSelectedCoinForCurrentExchange() {
        let supportedCoins = marketsByExchange[selectedExchange] ?? derivedCoinListForSelectedExchange()
        guard let firstCoin = supportedCoins.first else {
            selectedCoin = nil
            return
        }

        if let selectedCoin, supportedCoins.contains(selectedCoin) {
            return
        }

        selectedCoin = firstCoin
        prefillOrderPriceIfPossible()
    }

    private func refreshPublicStatusViewStates() {
        marketStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: marketMetaForStatus,
            streamingStatus: currentPublicStreamingStatus,
            warningMessage: currentPublicStreamingWarningMessage
        )
        chartStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: chartMetaForStatus,
            streamingStatus: currentPublicStreamingStatus,
            warningMessage: currentPublicStreamingWarningMessage
        )
        kimchiStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: kimchiMetaForStatus,
            streamingStatus: currentPublicStreamingStatus,
            warningMessage: currentPublicStreamingWarningMessage
        )
    }

    private func refreshPrivateStatusViewStates() {
        portfolioStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: portfolioMetaForStatus,
            streamingStatus: currentPrivateStreamingStatus,
            warningMessage: resolvedWarningMessage(
                primary: portfolioState.value?.partialFailureMessage,
                fallback: currentPrivateStreamingWarningMessage
            )
        )
        tradingStatusViewState = screenStatusFactory.makeStatusViewState(
            meta: tradingMetaForStatus,
            streamingStatus: currentPrivateStreamingStatus,
            warningMessage: resolvedWarningMessage(
                primary: tradingChanceState.value?.warningMessage,
                fallback: currentPrivateStreamingWarningMessage
            )
        )
    }

    private var currentPublicStreamingStatus: StreamingStatus {
        switch publicWebSocketState {
        case .connected:
            return .live
        case .connecting:
            return .snapshotOnly
        case .disconnected, .failed:
            return .pollingFallback
        }
    }

    private var currentPrivateStreamingStatus: StreamingStatus {
        switch privateWebSocketState {
        case .connected:
            return .live
        case .connecting:
            return .snapshotOnly
        case .disconnected, .failed:
            return .pollingFallback
        }
    }

    private var currentPublicStreamingWarningMessage: String? {
        switch publicWebSocketState {
        case .failed(let message):
            return message
        case .disconnected:
            return "실시간 연결이 끊겨 polling 으로 갱신 중이에요."
        case .connected, .connecting:
            return nil
        }
    }

    private var currentPrivateStreamingWarningMessage: String? {
        switch privateWebSocketState {
        case .failed(let message):
            return message
        case .disconnected:
            return "실시간 연결이 끊겨 polling 으로 갱신 중이에요."
        case .connected, .connecting:
            return nil
        }
    }

    private func resolvedWarningMessage(primary: String?, fallback: String?) -> String? {
        primary ?? fallback
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

    private var supportedIntervals: [String] {
        guard let symbol = selectedCoin?.symbol else {
            return CandleIntervalCatalog.defaultOptions.map(\.value)
        }

        return supportedIntervalsByExchangeAndSymbol[selectedExchange]?[symbol] ?? CandleIntervalCatalog.defaultOptions.map(\.value)
    }

    private var marketMetaForStatus: ResponseMeta {
        ResponseMeta(
            fetchedAt: currentTicker?.timestamp,
            isStale: currentTicker?.isStale ?? false,
            warningMessage: nil,
            partialFailureMessage: nil
        )
    }

    private var chartMetaForStatus: ResponseMeta {
        let candleTimestamp = candles.last.map { Date(timeIntervalSince1970: TimeInterval($0.time)) }
        let orderbookTimestamp = orderbook?.timestamp
        let tradeTimestamp = recentTrades.first?.executedDate
        return combineMetas([
            ResponseMeta(fetchedAt: candleTimestamp, isStale: false, warningMessage: nil, partialFailureMessage: nil),
            ResponseMeta(fetchedAt: orderbookTimestamp, isStale: orderbook?.isStale ?? false, warningMessage: nil, partialFailureMessage: nil),
            ResponseMeta(fetchedAt: tradeTimestamp, isStale: false, warningMessage: nil, partialFailureMessage: nil)
        ])
    }

    private var portfolioMetaForStatus: ResponseMeta {
        guard let snapshot = portfolioState.value else { return .empty }
        return snapshot.meta
    }

    private var tradingMetaForStatus: ResponseMeta {
        if let firstOrder = orderHistoryState.value?.first, let createdAt = firstOrder.createdAt {
            return ResponseMeta(fetchedAt: createdAt, isStale: false, warningMessage: nil, partialFailureMessage: nil)
        }
        if let firstFill = fillsState.value?.first {
            return ResponseMeta(fetchedAt: firstFill.executedAt, isStale: false, warningMessage: nil, partialFailureMessage: nil)
        }
        return .empty
    }

    private var kimchiMetaForStatus: ResponseMeta {
        switch kimchiPremiumState {
        case .loaded:
            return ResponseMeta(
                fetchedAt: Date(),
                isStale: false,
                warningMessage: nil,
                partialFailureMessage: nil
            )
        default:
            return .empty
        }
    }

    private func combineMetas(_ metas: [ResponseMeta]) -> ResponseMeta {
        let fetchedAt = metas.compactMap(\.fetchedAt).sorted(by: >).first
        let isStale = metas.contains(where: \.isStale)
        let warningMessage = metas.compactMap(\.warningMessage).first
        let partialFailureMessage = metas.compactMap(\.partialFailureMessage).first

        return ResponseMeta(
            fetchedAt: fetchedAt,
            isStale: isStale,
            warningMessage: warningMessage,
            partialFailureMessage: partialFailureMessage
        )
    }

    private func preferredKimchiSymbols() -> [String] {
        let marketSymbols = Array(derivedCoinListForSelectedExchange().prefix(8)).map(\.symbol)
        if marketSymbols.isEmpty {
            return CoinCatalog.fallbackTopSymbols
        }
        return marketSymbols
    }
}

private extension PortfolioSnapshot {
    var meta: ResponseMeta {
        ResponseMeta(
            fetchedAt: fetchedAt,
            isStale: isStale,
            warningMessage: nil,
            partialFailureMessage: partialFailureMessage
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
