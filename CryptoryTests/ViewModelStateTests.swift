import XCTest
@testable import Cryptory

final class ViewModelStateTests: XCTestCase {

    @MainActor
    func testGuestProtectedLoadsDoNotCallPrivateRepositories() async {
        let portfolioRepository = SpyPortfolioRepository()
        let tradingRepository = SpyTradingRepository()
        let connectionsRepository = SpyExchangeConnectionsRepository()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: tradingRepository,
            portfolioRepository: portfolioRepository,
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: connectionsRepository,
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        await Task.yield()

        await vm.loadPortfolio()
        await vm.loadOrders()
        await vm.loadExchangeConnections()

        XCTAssertEqual(portfolioRepository.fetchSummaryCount, 0)
        XCTAssertEqual(tradingRepository.fetchChanceCount, 0)
        XCTAssertEqual(connectionsRepository.fetchConnectionsCount, 0)
        XCTAssertFalse(vm.isAuthenticated)
    }

    @MainActor
    func testLoginOnPortfolioGateReturnsToPortfolioAndLoadsAuthenticatedData() async {
        let portfolioRepository = SpyPortfolioRepository()
        let tradingRepository = SpyTradingRepository()
        let connectionsRepository = SpyExchangeConnectionsRepository()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: tradingRepository,
            portfolioRepository: portfolioRepository,
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: connectionsRepository,
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        await Task.yield()

        vm.setActiveTab(.portfolio)
        await Task.yield()
        vm.presentLogin(for: .portfolio)
        vm.loginEmail = "user@example.com"
        vm.loginPassword = "password"

        await vm.submitLogin()

        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertEqual(connectionsRepository.fetchConnectionsCount, 1)
        XCTAssertEqual(portfolioRepository.fetchSummaryCount, 1)
        XCTAssertEqual(portfolioRepository.fetchHistoryCount, 1)
        XCTAssertEqual(vm.activeAuthGate, nil)
    }

    @MainActor
    func testLoginOnTradeGateReturnsToTradeAndLoadsTradingData() async {
        let portfolioRepository = SpyPortfolioRepository()
        let tradingRepository = SpyTradingRepository()
        let connectionsRepository = SpyExchangeConnectionsRepository()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: tradingRepository,
            portfolioRepository: portfolioRepository,
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: connectionsRepository,
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        await Task.yield()

        vm.onAppear()
        vm.selectedCoin = CoinCatalog.coin(symbol: "BTC")
        vm.setActiveTab(.trade)
        await Task.yield()
        vm.presentLogin(for: .trade)
        vm.loginEmail = "user@example.com"
        vm.loginPassword = "password"

        await vm.submitLogin()

        XCTAssertEqual(vm.activeTab, .trade)
        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertEqual(connectionsRepository.fetchConnectionsCount, 1)
        XCTAssertEqual(tradingRepository.fetchChanceCount, 1)
        XCTAssertEqual(tradingRepository.fetchOpenOrdersCount, 1)
        XCTAssertEqual(tradingRepository.fetchFillsCount, 1)
        XCTAssertEqual(vm.activeAuthGate, nil)
    }

    @MainActor
    func testLoadKimchiPremiumUpdatesState() async {
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: NoOpPublicWebSocketService(),
            privateWebSocketService: NoOpPrivateWebSocketService()
        )
        await Task.yield()

        await vm.loadKimchiPremium()
        await Task.yield()

        guard case .loaded(let coinViewStates) = vm.kimchiPremiumState else {
            return XCTFail("Expected loaded kimchi premium state")
        }

        XCTAssertEqual(coinViewStates.first?.symbol, "BTC")
        XCTAssertEqual(vm.kimchiStatusViewState.refreshMode, .streaming)
    }

    @MainActor
    func testPublicWebSocketFailureShowsPollingFallbackStatusMessage() async {
        let publicWebSocketService = ManualPublicWebSocketService()
        let vm = CryptoViewModel(
            marketRepository: StubMarketRepository(),
            tradingRepository: SpyTradingRepository(),
            portfolioRepository: SpyPortfolioRepository(),
            kimchiPremiumRepository: StubKimchiPremiumRepository(),
            exchangeConnectionsRepository: SpyExchangeConnectionsRepository(),
            authService: StubAuthenticationService(),
            publicWebSocketService: publicWebSocketService,
            privateWebSocketService: NoOpPrivateWebSocketService()
        )

        publicWebSocketService.emitState(.failed("서버 주소를 확인할 수 없어요. 현재 앱 환경 설정을 확인해주세요."))
        await Task.yield()

        XCTAssertEqual(vm.marketStatusViewState.refreshMode, .pollingFallback)
        XCTAssertEqual(vm.marketStatusViewState.message, "서버 주소를 확인할 수 없어요. 현재 앱 환경 설정을 확인해주세요.")
        XCTAssertTrue(vm.marketStatusViewState.badges.contains { $0.title == "Polling Fallback" })
    }
}
