import SwiftUI

struct TradeView: View {
    @ObservedObject var vm: CryptoViewModel
    @State private var safariDestination: SafariDestination?

    private struct OrderSideToggleButton: View {
        let title: String
        let selectedSide: OrderSide
        let isSelected: Bool
        let color: Color
        let action: () -> Void

        @State private var hasLoggedTouchDown = false

        var body: some View {
            Button {
                AppLogger.debug(
                    .lifecycle,
                    "[OrderModeDebug] touch_up_inside targetMode=\(selectedSide.rawValue)"
                )
                action()
            } label: {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(isSelected ? .white : .textMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? color : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard hasLoggedTouchDown == false else { return }
                        hasLoggedTouchDown = true
                        AppLogger.debug(
                            .lifecycle,
                            "[OrderModeDebug] touch_down targetMode=\(selectedSide.rawValue)"
                        )
                    }
                    .onEnded { _ in
                        hasLoggedTouchDown = false
                    }
            )
        }
    }

    var body: some View {
        Group {
            if vm.activeTab == .trade, let feature = vm.activeAuthGate {
                AuthGateView(feature: feature) {
                    vm.presentLogin(for: feature)
                }
            } else if vm.isSelectedExchangeTradingUnsupported {
                unsupportedState
            } else {
                content
            }
        }
        .sheet(item: $safariDestination) { destination in
            SafariSheet(destination: destination)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.exchangeConnectionsState {
        case .idle, .loading:
            tradeScrollContent

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
            tradeScrollContent
        }
    }

    private var tradeScrollContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                connectionStatusCard
                ScreenStatusBannerView(viewState: vm.tradingStatusViewState)
                investmentDisclaimerLink

                if let coin = vm.selectedCoin {
                    selectedCoinCard(coin)
                    orderEntryPanel(coin)
                    selectedOrderDetailSection
                    openOrdersSection
                    fillsSection
                } else {
                    messageCard(
                        title: "시세 탭에서 코인을 선택해주세요",
                        detail: "공용 시세 화면에서 코인을 고르면 바로 이 주문 화면으로 이어서 사용할 수 있어요."
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnBackgroundTap(enabled: !vm.showExchangeMenu)
        .onAppear {
            vm.logOrderHeaderPriceDebug(reason: "trade_view_appear", force: true)
        }
    }

    private var unsupportedState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.textSecondary)
            Text("이 거래소는 주문을 지원하지 않아요")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.themeText)
            Text("Exchange metadata 의 supportsOrder 기준으로 트레이딩 UI를 비활성화했어요.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
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

    private var investmentDisclaimerLink: some View {
        Button {
            openExternalLink(.investmentDisclaimer)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppExternalLink.investmentDisclaimer.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.accent)

                    Text("주문 전 거래 위험과 서비스 책임 범위를 확인하세요.")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "safari")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accent)
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
        .buttonStyle(.plain)
    }

    private var statusDescription: String {
        switch vm.exchangeConnectionsState {
        case .idle, .loading:
            return "거래소 연결 정보를 확인하는 중이에요."
        case .failed:
            return "연결 상태를 불러오지 못했어요."
        case .empty:
            return "연결된 거래소가 없어요."
        case .loaded:
            break
        }
        let total = vm.exchangeConnections.count
        let tradable = vm.exchangeConnections.filter { $0.permission == .tradeEnabled && $0.isActive }.count
        return "총 \(total)개 연결, 주문 가능 \(tradable)개"
    }

    private func openExternalLink(_ link: AppExternalLink) {
        AppLogger.debug(.auth, "DEBUG [LegalLink] open type=\(link.policyDebugName) urlExists=\(link.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)")
        guard let destination = SafariDestination(link: link) else {
            AppLogger.debug(.auth, "WARN [LegalLink] invalid type=\(link.policyDebugName) reason=invalidURL")
            vm.showNotification("링크를 열 수 없습니다.", type: .error)
            return
        }
        safariDestination = destination
    }

    private func selectedCoinCard(_ coin: CoinInfo) -> some View {
        let pricePresentation = vm.orderHeaderPricePresentation

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(coin.symbol)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.themeText)
                    Text(coin.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
                Text("\(vm.exchange.displayName) 현재가")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let price = pricePresentation.price {
                    Text(PriceFormatter.formatPrice(price))
                        .font(.mono(22, weight: .heavy))
                        .foregroundColor(.accent)
                        .contentTransition(.numericText())
                    Text(pricePresentation.secondaryText)
                        .font(.mono(10, weight: .bold))
                        .foregroundColor(.textMuted)
                } else {
                    Text("—")
                        .font(.mono(22, weight: .heavy))
                        .foregroundColor(.textMuted)
                    Text(pricePresentation.secondaryText)
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private func orderEntryPanel(_ coin: CoinInfo) -> some View {
        let chance = vm.currentTradingChance
        let isConnectionResolving = isTradeConnectionResolving
        let canSubmit = chance != nil && vm.hasTradeEnabledConnection

        return VStack(alignment: .leading, spacing: 14) {
            buySellToggle
            orderTypeToggle

            if vm.orderType == .limit {
                priceInput
            } else {
                marketPriceInput
            }

            qtyInput
            percentButtons
            orderSummary(coin, chance: chance)
            orderCapabilityInlineStatus()

            if vm.hasTradeEnabledConnection || isConnectionResolving {
                executeButton(coin, isEnabled: canSubmit)
            } else {
                permissionNotice
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private var isTradeConnectionResolving: Bool {
        switch vm.exchangeConnectionsState {
        case .idle, .loading:
            return true
        case .failed, .empty, .loaded:
            return false
        }
    }

    private var marketPriceInput: some View {
        let pricePresentation = vm.orderHeaderPricePresentation

        return VStack(alignment: .leading, spacing: 6) {
            Text("주문가격 (시장가)")
                .font(.system(size: 11))
                .foregroundColor(.textMuted)

            HStack {
                Text("시장 최우선 가격으로 주문")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Spacer()
                if let price = pricePresentation.price {
                    Text(PriceFormatter.formatPrice(price))
                        .font(.mono(14, weight: .bold))
                        .foregroundColor(.accent)
                        .contentTransition(.numericText())
                } else {
                    Text("가격 확인 중")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func orderCapabilityInlineStatus() -> some View {
        switch vm.tradingChanceState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.accent)
                Text("주문 가능 정보를 확인하는 중이에요.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 18)

        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.accent)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)

        case .empty:
            Text("주문 가능 정보가 아직 없어요. 이전 입력값은 유지됩니다.")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)

        case .loaded(let loadedChance):
            if let warningMessage = loadedChance.warningMessage, !warningMessage.isEmpty {
                Text(warningMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.accent)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            } else {
                Text("최소 주문 \(loadedChance.minimumOrderAmount.map { PriceFormatter.formatInteger($0) + " KRW" } ?? "제한 없음")")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            }
        }
    }

    private var permissionNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.accent)
            Text("주문 가능 권한의 거래소 연결을 추가해야 주문을 실행할 수 있어요.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgTertiary.opacity(0.7))
        )
    }

    private func chanceCard(_ chance: TradingChance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("주문 가능 정보")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.themeText)

            HStack(spacing: 8) {
                statItem(label: "지원 타입", value: chance.supportedOrderTypes.map(\.title).joined(separator: ", "))
                statItem(label: "최소 주문", value: chance.minimumOrderAmount.map { PriceFormatter.formatInteger($0) + " KRW" } ?? "—")
            }

            HStack(spacing: 8) {
                statItem(label: "매수 가능", value: PriceFormatter.formatInteger(chance.bidBalance) + " KRW")
                statItem(label: "매도 가능", value: PriceFormatter.formatQty6(chance.askBalance))
            }

            if let warningMessage = chance.warningMessage, !warningMessage.isEmpty {
                Text(warningMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
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

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textMuted)
            Text(value)
                .font(.mono(12, weight: .semibold))
                .foregroundColor(.themeText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgTertiary)
        )
    }

    private var buySellToggle: some View {
        HStack(spacing: 0) {
            toggleButton(title: "매수", selectedSide: .buy, isSelected: vm.orderSide == .buy, color: .up)
            toggleButton(title: "매도", selectedSide: .sell, isSelected: vm.orderSide == .sell, color: .down)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgTertiary.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private func toggleButton(
        title: String,
        selectedSide: OrderSide,
        isSelected: Bool,
        color: Color
    ) -> some View {
        OrderSideToggleButton(
            title: title,
            selectedSide: selectedSide,
            isSelected: isSelected,
            color: color
        ) {
            vm.setOrderSide(selectedSide, source: "trade_toggle_button")
        }
    }

    private var orderTypeToggle: some View {
        HStack(spacing: 8) {
            ForEach(vm.currentSupportedOrderTypes, id: \.self) { type in
                orderTypeButton(type.title, type: type)
            }
        }
    }

    private func orderTypeButton(_ title: String, type: OrderType) -> some View {
        Button {
            vm.setOrderType(type)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(vm.orderType == type ? .accent : .textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(vm.orderType == type ? Color.accent.opacity(0.12) : Color.bgTertiary.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
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

                TextField(
                    "0",
                    text: Binding(
                        get: { vm.orderPrice },
                        set: { vm.updateOrderPriceManually($0) }
                    )
                )
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
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.7))
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

            TextField(
                "0.000000",
                text: Binding(
                    get: { vm.orderQty },
                    set: { vm.updateOrderQuantityManually($0) }
                )
            )
                .font(.mono(14, weight: .semibold))
                .foregroundColor(.themeText)
                .keyboardType(.decimalPad)
                .frame(height: 40)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.bgTertiary.opacity(0.7))
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
                let isSelected = vm.selectedOrderRatioPercent == percent
                let isEnabled = vm.isOrderRatioButtonEnabled(percent)
                Button {
                    vm.applyPercent(percent)
                } label: {
                    Text("\(Int(percent))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? .black : (isEnabled ? .textSecondary : .textMuted))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accent : Color.bgTertiary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? Color.accent : Color.themeBorder, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.48)
            }
        }
    }

    private func orderSummary(_ coin: CoinInfo, chance: TradingChance?) -> some View {
        let price: Double = {
            if vm.orderType == .market {
                return vm.currentPrice
            }
            return Double(vm.orderPrice.replacingOccurrences(of: ",", with: "")) ?? vm.currentPrice
        }()
        let quantity = Double(vm.orderQty.replacingOccurrences(of: ",", with: "")) ?? 0
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
                if let chance, vm.orderSide == .buy {
                    Text(PriceFormatter.formatInteger(chance.bidBalance) + " KRW")
                        .font(.mono(13, weight: .bold))
                        .foregroundColor(.accent)
                } else if let chance {
                    Text(PriceFormatter.formatQty6(chance.askBalance) + " \(coin.symbol)")
                        .font(.mono(13, weight: .bold))
                        .foregroundColor(.accent)
                } else {
                    Text("확인 중")
                        .font(.mono(13, weight: .bold))
                        .foregroundColor(.textMuted)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgTertiary.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private func executeButton(_ coin: CoinInfo, isEnabled: Bool = true) -> some View {
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
        .disabled(vm.isSubmittingOrder || !isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
    }

    @ViewBuilder
    private var selectedOrderDetailSection: some View {
        switch vm.selectedOrderDetailState {
        case .idle:
            EmptyView()
        case .loading:
            compactLoadingRow("주문 상세를 확인하는 중이에요.")
                .padding(14)
                .background(sectionCardBackground)
        case .failed(let message):
            messageCard(title: "주문 상세를 불러오지 못했어요", detail: message)
        case .empty:
            EmptyView()
        case .loaded(let order):
            VStack(alignment: .leading, spacing: 8) {
                Text("주문 상세")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.themeText)
                statItem(label: "상태", value: order.status)
                statItem(label: "체결/잔량", value: "\(PriceFormatter.formatQty(order.executedQuantity)) / \(PriceFormatter.formatQty(order.remainingQuantity))")
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
    }

    @ViewBuilder
    private var openOrdersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("미체결 주문")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.themeText)

            switch vm.orderHistoryState {
            case .idle, .loading:
                compactLoadingRow("미체결 주문을 확인하는 중이에요.")

            case .failed(let message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.down)
                    .padding(.vertical, 8)

            case .empty:
                Text("미체결 주문이 없어요.")
                    .font(.system(size: 12))
                    .foregroundColor(.textMuted)
                    .padding(.vertical, 8)

            case .loaded(let orders):
                ForEach(orders.prefix(8)) { record in
                    VStack(spacing: 8) {
                        Button {
                            Task {
                                await vm.loadOrderDetail(orderID: record.id)
                            }
                        } label: {
                            OrderHistoryRow(order: record)
                        }
                        .buttonStyle(.plain)

                        if record.canCancel {
                            Button {
                                Task {
                                    await vm.cancelOrder(record)
                                }
                            } label: {
                                Text("주문 취소")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.down)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.down.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionCardBackground)
    }

    @ViewBuilder
    private var fillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("최근 체결")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.themeText)

            switch vm.fillsState {
            case .idle, .loading:
                compactLoadingRow("최근 체결을 확인하는 중이에요.")

            case .failed(let message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.down)
                    .padding(.vertical, 8)

            case .empty:
                Text("최근 체결이 아직 없어요.")
                    .font(.system(size: 12))
                    .foregroundColor(.textMuted)
                    .padding(.vertical, 8)

            case .loaded(let fills):
                ForEach(fills.prefix(8)) { fill in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fill.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.themeText)
                            Text(fill.side == "buy" ? "매수 체결" : "매도 체결")
                                .font(.system(size: 10))
                                .foregroundColor(fill.side == "buy" ? .up : .down)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(PriceFormatter.formatPrice(fill.price))
                                .font(.mono(12, weight: .semibold))
                                .foregroundColor(.themeText)
                            Text(fill.executedAtText)
                                .font(.system(size: 10))
                                .foregroundColor(.textMuted)
                        }
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
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionCardBackground)
    }

    private func compactLoadingRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.72)
                .tint(.accent)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private var sectionCardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
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
