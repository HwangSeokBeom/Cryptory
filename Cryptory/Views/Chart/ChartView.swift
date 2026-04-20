import SwiftUI

struct ChartView: View {
    @ObservedObject var vm: CryptoViewModel
    private let instanceID: Int

    init(vm: CryptoViewModel) {
        self.vm = vm
        let instanceID = AppLogger.nextInstanceID(scope: "ChartView")
        self.instanceID = instanceID
        AppLogger.debug(.lifecycle, "[ViewIdentity] ChartView stableOwner=\(vm.debugOwnerID) viewInstance=\(instanceID)")
    }

    var body: some View {
        if vm.isSelectedExchangeChartUnsupported {
            unsupportedState
        } else if let coin = vm.selectedCoin {
            ScrollView {
                VStack(spacing: 0) {
                    coinHeader(coin)
                    ScreenStatusBannerView(viewState: vm.chartStatusViewState)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    PeriodSelector(vm: vm)
                    candleSection
                    stats24H
                    orderbookSection
                    tradesSection
                }
            }
            .onAppear {
                AppLogger.debug(.lifecycle, "ChartView onAppear #\(instanceID) symbol=\(coin.symbol) exchange=\(vm.exchange.rawValue) interval=\(vm.chartPeriod)")
            }
            .onDisappear {
                AppLogger.debug(.lifecycle, "ChartView onDisappear #\(instanceID)")
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.textSecondary)
            Text("시세 탭에서 코인을 선택해주세요")
                .font(.system(size: 14))
                .foregroundColor(.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.textSecondary)
            Text("이 거래소는 차트를 지원하지 않아요")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.themeText)
            Text("선택한 거래소에서 차트 데이터를 아직 제공하지 않아요.")
                .font(.system(size: 12))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func coinHeader(_ coin: CoinInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(coin.symbol)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(.themeText)
                        Text(coin.name)
                            .font(.system(size: 12))
                            .foregroundColor(.textMuted)
                    }

                    let ticker = vm.currentTicker
                    let isUp = (ticker?.change ?? 0) >= 0

                    if let ticker {
                        Text(PriceFormatter.formatPrice(ticker.price))
                            .font(.mono(26, weight: .heavy))
                            .foregroundColor(isUp ? .up : .down)
                    } else {
                        Text("—")
                            .font(.mono(26, weight: .heavy))
                            .foregroundColor(.textMuted)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 10, weight: .bold))
                            .opacity(ticker == nil ? 0 : 1)
                        Text(ticker.map { String(format: "%@%.2f%%", $0.change >= 0 ? "+" : "", $0.change) } ?? "—")
                            .font(.mono(13))
                    }
                    .foregroundColor(ticker == nil ? .textMuted : (isUp ? .up : .down))
                }

                Spacer()

                Button {
                    vm.toggleFavorite(coin.symbol)
                } label: {
                    Image(systemName: vm.favCoins.contains(coin.symbol) ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(vm.favCoins.contains(coin.symbol) ? .accent : .textMuted)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.bgSecondary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.themeBorder),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var candleSection: some View {
        switch vm.candlesState {
        case .idle, .loading:
            ProgressView("캔들 데이터를 불러오는 중...")
                .tint(.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .padding(.top, 8)

        case .failed(let message):
            stateMessage(message)
                .frame(height: 220)

        case .empty:
            stateMessage("캔들 데이터가 아직 없어요.")
                .frame(height: 220)

        case .loaded, .staleCache, .refreshing:
            GeometryReader { geo in
                CandleChartView(
                    candles: vm.candles,
                    width: min(geo.size.width - 16, 390),
                    height: 220
                )
                .frame(maxWidth: .infinity)
            }
            .frame(height: 220)
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }

    private var stats24H: some View {
        HStack(spacing: 8) {
            let ticker = vm.currentTicker
            statItem(label: "고가(24H)", value: ticker.map { PriceFormatter.formatPrice($0.high24) } ?? "—", color: .up)
            statItem(label: "저가(24H)", value: ticker.map { PriceFormatter.formatPrice($0.low24) } ?? "—", color: .down)
            statItem(label: "거래량(24H)", value: ticker.map { PriceFormatter.formatVolume($0.volume) } ?? "—", color: .themeText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var orderbookSection: some View {
        switch vm.orderbookState {
        case .idle, .loading:
            ProgressView("호가 데이터를 불러오는 중...")
                .tint(.accent)
                .padding(.top, 18)
                .padding(.bottom, 20)

        case .failed(let message):
            stateMessage(message)
                .padding(.top, 18)
                .padding(.bottom, 20)

        case .loaded:
            OrderbookView(orderbook: vm.orderbook, currentPrice: vm.currentPrice)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var tradesSection: some View {
        switch vm.recentTradesState {
        case .idle, .loading:
            ProgressView("실시간 체결을 불러오는 중...")
                .tint(.accent)
                .padding(.top, 14)
                .padding(.bottom, 20)

        case .failed(let message):
            stateMessage(message)
                .padding(.top, 14)
                .padding(.bottom, 20)

        case .loaded(let trades):
            RecentTradesView(trades: trades)
                .padding(.top, 14)
        }
    }

    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textMuted)
            Text(value)
                .font(.mono(12, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private func stateMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundColor(.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
    }
}
