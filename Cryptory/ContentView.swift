import SwiftUI

struct ContentView: View {
    @StateObject private var vm: CryptoViewModel
    @State private var isExchangeConnectionsSheetPresented = false
    @State private var isProfilePresented = false
    @Environment(\.scenePhase) private var scenePhase
    private let instanceID: Int
    private let marketView: MarketView
    private let chartView: ChartView
    private let newsView: NewsView
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
        self.newsView = NewsView(vm: viewModel)
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
                HeaderView(vm: vm) {
                    isProfilePresented = true
                }

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

                    newsView
                        .tag(Tab.news)
                        .tabItem {
                            Label(Tab.news.title, systemImage: Tab.news.systemImage)
                        }
                        .accessibilityLabel("뉴스 탭")

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
                    let dropdownHeight = CGFloat(Exchange.allCases.count) * ExchangeDropdown.rowHeight
                        + CGFloat(max(Exchange.allCases.count - 1, 0)) * ExchangeDropdown.rowSpacing
                        + ExchangeDropdown.containerInset * 2
                    let dropdownFrame = CGRect(
                        x: dropdownX,
                        y: buttonFrame.maxY + 8,
                        width: dropdownWidth,
                        height: dropdownHeight
                    )

                    ZStack(alignment: .topLeading) {
                        ExchangeDropdownDismissOverlay(
                            canvasSize: proxy.size,
                            menuFrame: dropdownFrame
                        ) {
                            withAnimation(.easeOut(duration: 0.16)) {
                                vm.setExchangeMenuVisible(false)
                            }
                        }

                        ExchangeDropdown(vm: vm)
                            .frame(width: dropdownWidth)
                            .offset(x: dropdownFrame.minX, y: dropdownFrame.minY)
                            .zIndex(1)
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
        .onAppear {
            vm.configureExchangeConnectionsPresentation(
                onPresent: { isExchangeConnectionsSheetPresented = true },
                onDismiss: { isExchangeConnectionsSheetPresented = false }
            )
            vm.syncExchangeConnectionsPresentationState(
                isExchangeConnectionsSheetPresented,
                reason: "content_view_sync"
            )
            AppLogger.debug(.lifecycle, "ContentView onAppear #\(instanceID) tab=\(vm.activeTab.rawValue)")
            vm.onAppear()
        }
        .onDisappear {
            AppLogger.debug(.lifecycle, "ContentView onDisappear #\(instanceID) tab=\(vm.activeTab.rawValue)")
        }
        .onChange(of: scenePhase) { _, newValue in
            vm.onScenePhaseChanged(newValue)
        }
        .onOpenURL { url in
            if LiveGoogleSignInProvider.shared.handleOpenURL(url) == false {
                _ = vm.handleIncomingURL(url)
            }
        }
        .onChange(of: isExchangeConnectionsSheetPresented) { _, isPresented in
            vm.syncExchangeConnectionsPresentationState(
                isPresented,
                reason: isPresented ? "content_sheet_presented" : "content_sheet_dismissed"
            )
        }
        .sheet(isPresented: $vm.isLoginPresented) {
            LoginView(vm: vm)
                .presentationDetents([.fraction(0.88)])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationCornerRadius(24)
                .presentationBackground(Color.bg)
                .interactiveDismissDisabled(false)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isExchangeConnectionsSheetPresented) {
            ExchangeConnectionsView(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationCornerRadius(28)
                .presentationBackground(Color.bg)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isProfilePresented) {
            ProfileView(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationCornerRadius(28)
                .presentationBackground(Color.bg)
                .preferredColorScheme(.dark)
        }
    }
}

private struct ExchangeDropdownDismissOverlay: View {
    let canvasSize: CGSize
    let menuFrame: CGRect
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            dismissRect(
                x: 0,
                y: 0,
                width: canvasSize.width,
                height: max(menuFrame.minY, 0)
            )
            dismissRect(
                x: 0,
                y: menuFrame.maxY,
                width: canvasSize.width,
                height: max(canvasSize.height - menuFrame.maxY, 0)
            )
            dismissRect(
                x: 0,
                y: max(menuFrame.minY, 0),
                width: max(menuFrame.minX, 0),
                height: max(menuFrame.height, 0)
            )
            dismissRect(
                x: menuFrame.maxX,
                y: max(menuFrame.minY, 0),
                width: max(canvasSize.width - menuFrame.maxX, 0),
                height: max(menuFrame.height, 0)
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func dismissRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        if width > 0, height > 0 {
            Color.black.opacity(0.01)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .offset(x: x, y: y)
                .onTapGesture(perform: onDismiss)
        }
    }
}

#Preview {
    ContentView()
}
