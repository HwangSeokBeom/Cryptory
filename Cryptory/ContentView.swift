import SwiftUI

struct ContentView: View {
    @StateObject private var vm = CryptoViewModel()
    @Environment(\.scenePhase) private var scenePhase

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
                    MarketView(vm: vm)
                        .tag(Tab.market)
                        .tabItem {
                            Label(Tab.market.title, systemImage: Tab.market.systemImage)
                        }

                    ChartView(vm: vm)
                        .tag(Tab.chart)
                        .tabItem {
                            Label(Tab.chart.title, systemImage: Tab.chart.systemImage)
                        }

                    TradeView(vm: vm)
                        .tag(Tab.trade)
                        .tabItem {
                            Label(Tab.trade.title, systemImage: Tab.trade.systemImage)
                        }

                    PortfolioView(vm: vm)
                        .tag(Tab.portfolio)
                        .tabItem {
                            Label(Tab.portfolio.title, systemImage: Tab.portfolio.systemImage)
                        }

                    KimchiView(vm: vm)
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
            vm.onAppear()
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
