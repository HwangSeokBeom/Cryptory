import SwiftUI

struct ContentView: View {
    @StateObject private var vm: CryptoViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let instanceID: Int
    private let marketView: MarketView
    private let chartView: ChartView
    private let tradeView: TradeView
    private let portfolioView: PortfolioView
    private let kimchiView: KimchiView

    init() {
        #if DEBUG
        let viewModel = UITestFixtureFactory.makeViewModelIfNeeded() ?? CryptoViewModel()
        #else
        let viewModel = CryptoViewModel()
        #endif
        _vm = StateObject(wrappedValue: viewModel)

        self.marketView = MarketView(vm: viewModel)
        self.chartView = ChartView(vm: viewModel)
        self.tradeView = TradeView(vm: viewModel)
        self.portfolioView = PortfolioView(vm: viewModel)
        self.kimchiView = KimchiView(vm: viewModel)

        let instanceID = AppLogger.nextInstanceID(scope: "ContentView")
        self.instanceID = instanceID
        AppLogger.debug(.lifecycle, "ContentView init #\(instanceID)")
    }

    private var tabSelection: Binding<Tab> {
        Binding(
            get: { vm.activeTab },
            set: { vm.setActiveTab($0) }
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView(vm: vm)

                TabView(selection: tabSelection) {
                    marketView
                        .tag(Tab.market)
                        .tabItem {
                            Label(Tab.market.title, systemImage: Tab.market.systemImage)
                        }

                    chartView
                        .tag(Tab.chart)
                        .tabItem {
                            Label(Tab.chart.title, systemImage: Tab.chart.systemImage)
                        }

                    tradeView
                        .tag(Tab.trade)
                        .tabItem {
                            Label(Tab.trade.title, systemImage: Tab.trade.systemImage)
                        }

                    portfolioView
                        .tag(Tab.portfolio)
                        .tabItem {
                            Label(Tab.portfolio.title, systemImage: Tab.portfolio.systemImage)
                        }

                    kimchiView
                        .tag(Tab.kimchi)
                        .tabItem {
                            Label(Tab.kimchi.title, systemImage: Tab.kimchi.systemImage)
                        }
                }
                .tint(.accent)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.dark, for: .tabBar)
                .animation(.easeInOut(duration: 0.2), value: vm.activeTab)
            }

            if let notif = vm.notification {
                VStack {
                    ToastView(message: notif.msg, type: notif.type)
                        .padding(.top, 84)
                    Spacer()
                }
                .animation(.easeOut(duration: 0.3), value: vm.notification != nil)
                .zIndex(200)
            }
        }
        .frame(maxWidth: 420)
        .overlayPreferenceValue(ExchangeButtonBoundsPreferenceKey.self) { anchor in
            GeometryReader { proxy in
                if vm.showExchangeMenu, vm.shouldShowExchangeSelector, let anchor {
                    let buttonFrame = proxy[anchor]
                    let dropdownWidth = max(buttonFrame.width, 168)
                    let horizontalInset: CGFloat = 16
                    let dropdownX = min(
                        max(horizontalInset, buttonFrame.minX),
                        max(horizontalInset, proxy.size.width - dropdownWidth - horizontalInset)
                    )

                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.01)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    vm.showExchangeMenu = false
                                }
                            }

                        ExchangeDropdown(vm: vm)
                            .frame(width: dropdownWidth)
                            .offset(x: dropdownX, y: buttonFrame.maxY + 8)
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
        .onAppear {
            AppLogger.debug(.lifecycle, "ContentView onAppear #\(instanceID) tab=\(vm.activeTab.rawValue)")
            vm.onAppear()
        }
        .onDisappear {
            AppLogger.debug(.lifecycle, "ContentView onDisappear #\(instanceID) tab=\(vm.activeTab.rawValue)")
        }
        .onChange(of: scenePhase) { _, newValue in
            vm.onScenePhaseChanged(newValue)
        }
        .fullScreenCover(isPresented: $vm.isLoginPresented) {
            LoginView(vm: vm)
        }
        .sheet(isPresented: $vm.isExchangeConnectionsPresented) {
            ExchangeConnectionsView(vm: vm)
                .presentationDetents([.large])
        }
    }
}

#Preview {
    ContentView()
}
