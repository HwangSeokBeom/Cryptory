import SwiftUI

struct TradeView: View {
    @ObservedObject var vm: CryptoViewModel

    var body: some View {
        if vm.activeTab == .trade, let feature = vm.activeAuthGate {
            AuthGateView(feature: feature) {
                vm.presentLogin(for: feature)
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.exchangeConnectionsState {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView("거래소 연결 상태를 확인하는 중...")
                    .tint(.accent)
                Spacer()
            }

        case .failed(let message):
            messageState(
                icon: "exclamationmark.triangle",
                title: "거래소 연결을 불러오지 못했어요",
                detail: message,
                actionTitle: "다시 로그인"
            ) {
                vm.presentLogin(for: .trade)
            }

        case .empty:
            messageState(
                icon: "link.badge.plus",
                title: "연결된 거래소가 없어요",
                detail: "주문은 로그인과 거래소 연결이 필요한 기능이에요. 연결 후 주문과 체결 내역을 확인할 수 있어요.",
                actionTitle: "거래소 연결 관리"
            ) {
                vm.openExchangeConnections()
            }

        case .loaded:
            ScrollView {
                VStack(spacing: 12) {
                    connectionStatusCard

                    if let coin = vm.selectedCoin {
                        selectedCoinCard(coin)

                        if vm.hasTradeEnabledConnection {
                            buySellToggle
                            orderTypeToggle

                            if vm.orderType == .limit {
                                priceInput
                            }

                            qtyInput
                            percentButtons
                            orderSummary(coin)
                            executeButton(coin)
                        } else {
                            messageCard(
                                title: "주문 가능 권한 연결이 없어요",
                                detail: "현재 연결은 조회 전용이에요. 주문 가능 권한의 거래소 연결을 추가해야 주문을 실행할 수 있어요."
                            )
                        }
                    } else {
                        messageCard(
                            title: "시세 탭에서 코인을 선택해주세요",
                            detail: "공용 시세 화면에서 코인을 고르면 바로 이 주문 화면으로 이어서 사용할 수 있어요."
                        )
                    }

                    orderHistorySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnBackgroundTap()
        }
    }

    private var connectionStatusCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("연결 상태")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.themeText)

                Text(statusDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button {
                vm.openExchangeConnections()
            } label: {
                Text("관리")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private var statusDescription: String {
        let total = vm.exchangeConnections.count
        let tradable = vm.exchangeConnections.filter { $0.permission == .tradeEnabled && $0.isActive }.count
        return "총 \(total)개 연결, 주문 가능 \(tradable)개"
    }

    private func selectedCoinCard(_ coin: CoinInfo) -> some View {
        HStack {
            HStack(spacing: 8) {
                Text(coin.symbol)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.themeText)
                Text(coin.name)
                    .font(.system(size: 12))
                    .foregroundColor(.textMuted)
            }
            Spacer()

            if let ticker = vm.currentTicker {
                Text(PriceFormatter.formatPrice(ticker.price))
                    .font(.mono(16, weight: .bold))
                    .foregroundColor(.accent)
            } else {
                Text("—")
                    .font(.mono(16, weight: .bold))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private var buySellToggle: some View {
        HStack(spacing: 0) {
            toggleButton(title: "매수", isSelected: vm.orderSide == .buy, color: .up) {
                vm.orderSide = .buy
            }
            toggleButton(title: "매도", isSelected: vm.orderSide == .sell, color: .down) {
                vm.orderSide = .sell
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private func toggleButton(title: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(isSelected ? .white : .textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? color : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var orderTypeToggle: some View {
        HStack(spacing: 8) {
            orderTypeButton("지정가", type: .limit)
            orderTypeButton("시장가", type: .market)
        }
    }

    private func orderTypeButton(_ title: String, type: OrderType) -> some View {
        Button {
            vm.orderType = type
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(vm.orderType == type ? .accent : .textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(vm.orderType == type ? Color.bgTertiary : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(vm.orderType == type ? Color.accent : Color.themeBorder, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var priceInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("주문가격 (KRW)")
                .font(.system(size: 11))
                .foregroundColor(.textMuted)

            HStack(spacing: 0) {
                Button {
                    vm.adjustPrice(up: false)
                } label: {
                    Text("−")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.down)
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.plain)

                TextField("0", text: $vm.orderPrice)
                    .font(.mono(14, weight: .semibold))
                    .foregroundColor(.themeText)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: .infinity)

                Button {
                    vm.adjustPrice(up: true)
                } label: {
                    Text("+")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.up)
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
        }
    }

    private var qtyInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("주문수량")
                .font(.system(size: 11))
                .foregroundColor(.textMuted)

            TextField("0.000000", text: $vm.orderQty)
                .font(.mono(14, weight: .semibold))
                .foregroundColor(.themeText)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.bgSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.themeBorder, lineWidth: 1)
                        )
                )
        }
    }

    private var percentButtons: some View {
        HStack(spacing: 8) {
            ForEach([10.0, 25.0, 50.0, 100.0], id: \.self) { percent in
                Button {
                    vm.applyPercent(percent)
                } label: {
                    Text("\(Int(percent))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.bgTertiary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.themeBorder, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func orderSummary(_ coin: CoinInfo) -> some View {
        let price: Double = {
            if vm.orderType == .market {
                return vm.currentPrice
            }
            return Double(vm.orderPrice.replacingOccurrences(of: ",", with: "")) ?? vm.currentPrice
        }()
        let quantity = Double(vm.orderQty) ?? 0
        let total = price * quantity

        return VStack(spacing: 8) {
            HStack {
                Text("주문총액")
                    .font(.system(size: 12))
                    .foregroundColor(.textMuted)
                Spacer()
                Text(PriceFormatter.formatInteger(total) + " KRW")
                    .font(.mono(13, weight: .bold))
                    .foregroundColor(.themeText)
            }
            HStack {
                Text("주문가능")
                    .font(.system(size: 12))
                    .foregroundColor(.textMuted)
                Spacer()
                if vm.orderSide == .buy {
                    Text(PriceFormatter.formatInteger(vm.cash) + " KRW")
                        .font(.mono(13, weight: .bold))
                        .foregroundColor(.accent)
                } else {
                    let holding = vm.portfolio.first { $0.symbol == coin.symbol }
                    Text(PriceFormatter.formatQty6(holding?.qty ?? 0) + " \(coin.symbol)")
                        .font(.mono(13, weight: .bold))
                        .foregroundColor(.accent)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private func executeButton(_ coin: CoinInfo) -> some View {
        Button {
            Task {
                await vm.submitOrder()
            }
        } label: {
            HStack(spacing: 8) {
                if vm.isSubmittingOrder {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }

                Text(vm.isSubmittingOrder ? "전송 중..." : "\(coin.symbol) \(vm.orderSide == .buy ? "매수" : "매도")")
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: vm.orderSide == .buy
                                ? [Color(hex: "#EF4444"), Color(hex: "#DC2626")]
                                : [Color(hex: "#3B82F6"), Color(hex: "#2563EB")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: vm.orderSide == .buy ? Color.up.opacity(0.3) : Color.down.opacity(0.3),
                        radius: 8, x: 0, y: 4
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isSubmittingOrder)
    }

    @ViewBuilder
    private var orderHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("개인 체결/주문 내역")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.themeText)

            switch vm.orderHistoryState {
            case .idle, .loading:
                ProgressView("내 주문 내역을 불러오는 중...")
                    .tint(.accent)
                    .padding(.vertical, 12)

            case .failed(let message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.down)
                    .padding(.vertical, 8)

            case .empty:
                Text("개인 주문 내역이 아직 없어요.")
                    .font(.system(size: 12))
                    .foregroundColor(.textMuted)
                    .padding(.vertical, 8)

            case .loaded:
                ForEach(vm.orderHistory.prefix(8)) { record in
                    OrderHistoryRow(order: record)
                }
            }
        }
    }

    private func messageState(icon: String, title: String, detail: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.accent)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.themeText)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    private func messageCard(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.themeText)
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }
}
