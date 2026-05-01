import SwiftUI

struct PortfolioView: View {
    @ObservedObject var vm: CryptoViewModel
    @State private var collapsedExchangeIDs: Set<String> = []

    var body: some View {
        Group {
            if vm.activeTab == .portfolio, let feature = vm.activeAuthGate {
                AuthGateView(feature: feature) {
                    vm.presentLogin(for: feature)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        PortfolioConnectionSummaryCard(
                            summaryText: connectionSummaryText,
                            onManage: vm.openExchangeConnections
                        )
                        .equatable()
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                        readOnlyNotice
                            .padding(.horizontal, 16)

                        ScreenStatusBannerView(viewState: vm.portfolioStatusViewState)
                            .padding(.horizontal, 16)

                        portfolioSummarySection

                        portfolioBodySection

                        Spacer(minLength: 20)
                    }
                }
            }
        }
        .onAppear {
            AppLogger.debug(
                .lifecycle,
                "[AssetScreenRenderDebug] render_reason=portfolio_view_appear state_transition=current:\(portfolioStateDescription)"
            )
        }
    }

    private var connectionSummaryText: String {
        switch vm.exchangeConnectionsState {
        case .idle, .loading:
            return "거래소 연결 정보를 확인하는 중이에요."
        case .failed:
            return "연결 상태를 불러오지 못했어요."
        case .empty:
            return "연결된 거래소가 없어요."
        case .loaded:
            return "총 \(vm.exchangeConnections.count)개 읽기 전용 연결"
        }
    }

    private var shouldShowSummaryPlaceholder: Bool {
        vm.portfolioOverviewViewState == nil
            && vm.portfolioSummaryCardState == nil
            && (vm.portfolioState.isLoading || vm.portfolioState == .idle)
    }

    @ViewBuilder
    private var portfolioSummarySection: some View {
        if let overview = vm.portfolioOverviewViewState {
            TotalAssetCard(overview: overview.summary)
                .equatable()
                .padding(.horizontal, 16)
        } else if let summary = vm.portfolioSummaryCardState {
            TotalAssetCard(summary: summary)
                .equatable()
                .padding(.horizontal, 16)
        } else if shouldShowSummaryPlaceholder {
            PortfolioSummaryPlaceholderCard()
                .padding(.horizontal, 16)
        }
    }

    private var portfolioStateDescription: String {
        switch vm.portfolioState {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded(let snapshot):
            return "loaded(holdings:\(snapshot.holdings.count))"
        case .empty:
            return "empty"
        case .failed:
            return "failed"
        }
    }

    @ViewBuilder
    private var portfolioBodySection: some View {
        switch vm.portfolioState {
        case .idle, .loading:
            if vm.portfolioOverviewViewState == nil {
                PortfolioBodyPlaceholderSection()
                    .padding(.horizontal, 16)
            } else {
                portfolioLoadedSections
            }

        case .failed(let message):
            if vm.portfolioOverviewViewState == nil {
                stateMessage(
                    title: "자산 데이터를 불러오지 못했어요",
                    detail: message
                )
            } else {
                portfolioLoadedSections
            }

        case .empty:
            portfolioLoadedSections

        case .loaded:
            portfolioLoadedSections
        }
    }

    private var portfolioLoadedSections: some View {
        VStack(spacing: 16) {
            portfolioCompositionSection
            exchangeAssetsSection
            topAssetsSection
        }
    }

    private var readOnlyNotice: some View {
        Text("거래소 연동은 읽기 전용 자산 조회 목적으로만 사용됩니다. Cryptory는 암호화폐 매수·매도·전송·입금·출금·주문 실행 기능을 제공하지 않습니다.")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textSecondary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accent.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.accent.opacity(0.26), lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    private var portfolioCompositionSection: some View {
        if let overview = vm.portfolioOverviewViewState {
            PortfolioCompositionCard(overview: overview)
                .padding(.horizontal, 16)
        }
    }

    private var exchangeAssetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("거래소별 보유 자산", subtitle: "거래소 subtotal과 코인 비중")

            if vm.portfolioOverviewViewState?.exchangeSections.isEmpty ?? true {
                stateMessage(
                    title: "거래소별 보유 자산이 없어요",
                    detail: "연결된 거래소에 보유 자산이 생기면 거래소별로 나누어 표시돼요."
                )
            } else {
                ForEach(vm.portfolioOverviewViewState?.exchangeSections ?? []) { section in
                    ExchangeAssetSectionCard(
                        section: section,
                        isCollapsed: collapsedExchangeIDs.contains(section.id),
                        onToggle: { toggleExchangeSection(section.id) },
                        onSelect: { row in
                            vm.selectCoinForTrade(CoinCatalog.coin(symbol: row.symbol))
                        }
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var topAssetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("주요 보유 자산", subtitle: "평가금액 기준 TOP")

            if let topAssets = vm.portfolioOverviewViewState?.topAssets, !topAssets.isEmpty {
                VStack(spacing: 8) {
                    ForEach(topAssets) { asset in
                        TopPortfolioAssetRow(asset: asset) {
                            vm.selectCoinForTrade(CoinCatalog.coin(symbol: asset.symbol))
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.themeBorder, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
            } else {
                stateMessage(
                    title: "주요 보유 자산이 없어요",
                    detail: "코인 보유 평가금액이 확인되면 비중 순으로 표시돼요."
                )
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("최근 자산 변동", subtitle: "읽기 전용 자산 변화만 표시")

            switch vm.portfolioHistoryState {
            case .idle, .loading:
                ProgressView("히스토리를 불러오는 중...")
                    .tint(.accent)
                    .padding(.horizontal, 16)

            case .failed(let message):
                stateMessage(
                    title: "일부 히스토리를 불러오지 못했어요",
                    detail: message
                )

            case .empty:
                stateMessage(
                    title: "최근 자산 변동 내역이 없어요.",
                    detail: "동기화된 자산 변화가 확인되면 여기에 표시돼요."
                )

            case .loaded(let items):
                ForEach(items.prefix(8)) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.symbol)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.themeText)
                            Text(item.type)
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(PriceFormatter.formatQty(item.amount))
                                .font(.mono(12, weight: .semibold))
                                .foregroundColor(.themeText)
                            Text(item.status)
                                .font(.system(size: 10))
                                .foregroundColor(.textMuted)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.bgSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.themeBorder, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func stateMessage(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.themeText)
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.themeText)
            Spacer()
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.textMuted)
        }
        .padding(.horizontal, 16)
    }

    private func toggleExchangeSection(_ id: String) {
        if collapsedExchangeIDs.contains(id) {
            collapsedExchangeIDs.remove(id)
        } else {
            collapsedExchangeIDs.insert(id)
        }
    }
}

private struct PortfolioSummaryPlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: 74, height: 10)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)

            HStack(spacing: 10) {
                placeholderMetric
                placeholderMetric
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
        .redacted(reason: .placeholder)
    }

    private var placeholderMetric: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: 58, height: 10)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PortfolioConnectionSummaryCard: View, Equatable {
    let summaryText: String
    let onManage: () -> Void

    static func == (lhs: PortfolioConnectionSummaryCard, rhs: PortfolioConnectionSummaryCard) -> Bool {
        lhs.summaryText == rhs.summaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("거래소 연결")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.themeText)
                    Text(summaryText)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Button(action: onManage) {
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
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }
}

private struct PortfolioBodyPlaceholderSection: View {
    var body: some View {
        VStack(spacing: 14) {
            placeholderCard(height: 118)
            placeholderCard(height: 160)
            placeholderCard(height: 132)
        }
        .redacted(reason: .placeholder)
    }

    private func placeholderCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: 110, height: 10)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 14)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }
}

private struct PortfolioCompositionCard: View, Equatable {
    let overview: PortfolioOverviewViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("포트폴리오 분포")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.themeText)
                    Text(compositionSummaryText)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }

                Spacer()
            }

            SegmentedWeightBar(rows: cashAndCoinRows)

            if !overview.exchangeDistribution.isEmpty {
                allocationGroup(title: "거래소별 비중", rows: overview.exchangeDistribution)
            }

            if !overview.assetDistribution.isEmpty {
                allocationGroup(title: "자산별 TOP 비중", rows: overview.assetDistribution)
            }

            if let warningMessage = overview.warningMessage, !warningMessage.isEmpty {
                Text(warningMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.accent)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private var compositionSummaryText: String {
        String(
            format: "코인 %.1f%% · 현금성 %.1f%%",
            overview.coinWeightPercent,
            overview.cashWeightPercent
        )
    }

    private var cashAndCoinRows: [PortfolioAllocationRowState] {
        [
            PortfolioAllocationRowState(
                id: "coin-weight",
                title: "코인",
                subtitle: "평가 자산",
                amount: overview.summary.totalAsset - overview.summary.cash,
                percent: overview.coinWeightPercent,
                tintHex: "#F59E0B"
            ),
            PortfolioAllocationRowState(
                id: "cash-weight",
                title: "현금성",
                subtitle: "대기 자산",
                amount: overview.summary.cash,
                percent: overview.cashWeightPercent,
                tintHex: "#10B981"
            )
        ]
    }

    private func allocationGroup(title: String, rows: [PortfolioAllocationRowState]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.textSecondary)

            VStack(spacing: 8) {
                ForEach(rows.prefix(5)) { row in
                    AllocationProgressRow(row: row)
                }
            }
        }
    }
}

private struct SegmentedWeightBar: View, Equatable {
    let rows: [PortfolioAllocationRowState]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(rows.filter { $0.percent > 0 }) { row in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(hex: row.tintHex))
                        .frame(width: max(3, proxy.size.width * CGFloat(row.percent / 100)))
                }
                if rows.allSatisfy({ $0.percent <= 0 }) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.bgTertiary)
                }
            }
        }
        .frame(height: 10)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct AllocationProgressRow: View, Equatable {
    let row: PortfolioAllocationRowState

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: row.tintHex))
                    .frame(width: 7, height: 7)
                Text(row.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.themeText)
                Text(row.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.1f%%", row.percent))
                    .font(.mono(11, weight: .bold))
                    .foregroundColor(.themeText)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.bgTertiary)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: row.tintHex))
                        .frame(width: max(3, proxy.size.width * CGFloat(min(row.percent, 100) / 100)))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct ExchangeAssetSectionCard: View, Equatable {
    let section: ExchangePortfolioSectionViewState
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onSelect: (PortfolioHoldingRowState) -> Void

    static func == (lhs: ExchangeAssetSectionCard, rhs: ExchangeAssetSectionCard) -> Bool {
        lhs.section == rhs.section && lhs.isCollapsed == rhs.isCollapsed
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 10) {
                    PortfolioExchangeIcon(exchange: section.exchange)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.exchange.displayName)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.themeText)
                        Text("\(section.assetCount)개 자산 · \(String(format: "%.1f%%", section.weightPercent))")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("₩" + PriceFormatter.formatInteger(section.totalAsset))
                            .font(.mono(14, weight: .bold))
                            .foregroundColor(.themeText)
                        Text("조회액 ₩" + PriceFormatter.formatInteger(section.availableAsset))
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                    }

                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textMuted)
                }
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(spacing: 8) {
                    ForEach(section.holdings.prefix(8)) { row in
                        ExchangeHoldingRow(row: row) {
                            onSelect(row)
                        }
                    }
                }
            }

            if let partialFailureMessage = section.partialFailureMessage, !partialFailureMessage.isEmpty {
                Text(partialFailureMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }
}

private struct PortfolioExchangeIcon: View, Equatable {
    let exchange: Exchange

    var body: some View {
        Text(exchange.iconText)
            .font(.system(size: 11, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(exchange.color)
            )
    }
}

private struct ExchangeHoldingRow: View, Equatable {
    let row: PortfolioHoldingRowState
    let onSelect: () -> Void

    static func == (lhs: ExchangeHoldingRow, rhs: ExchangeHoldingRow) -> Bool {
        lhs.row == rhs.row
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(row.symbol)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(.themeText)
                            Text(row.name)
                                .font(.system(size: 10))
                                .foregroundColor(.textMuted)
                        }
                        Text("수량 \(PriceFormatter.formatQty6(row.totalQuantity))")
                            .font(.mono(10, weight: .semibold))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("₩" + PriceFormatter.formatInteger(row.evaluationAmount))
                            .font(.mono(13, weight: .bold))
                            .foregroundColor(.themeText)
                        Text(String(format: "%.1f%%", row.weightPercent))
                            .font(.mono(10, weight: .semibold))
                            .foregroundColor(.accent)
                    }
                }

                HStack {
                    Text("평균 단가 \(PriceFormatter.formatPrice(row.averageBuyPrice))")
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted)
                    Spacer()
                    Text("\(row.profitLoss >= 0 ? "+" : "")₩" + PriceFormatter.formatInteger(row.profitLoss))
                        .font(.mono(10, weight: .bold))
                        .foregroundColor(row.profitLoss >= 0 ? .up : .down)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.72))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TopPortfolioAssetRow: View, Equatable {
    let asset: PortfolioTopAssetViewState
    let onSelect: () -> Void

    static func == (lhs: TopPortfolioAssetRow, rhs: TopPortfolioAssetRow) -> Bool {
        lhs.asset == rhs.asset
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(asset.symbol)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.themeText)
                        Text(asset.name)
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                    }
                    Text("\(asset.exchangeCount)개 거래소 · 수량 \(PriceFormatter.formatQty6(asset.totalQuantity))")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("₩" + PriceFormatter.formatInteger(asset.evaluationAmount))
                        .font(.mono(13, weight: .bold))
                        .foregroundColor(.themeText)
                    Text(String(format: "%.1f%%", asset.weightPercent))
                        .font(.mono(10, weight: .semibold))
                        .foregroundColor(.accent)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.72))
            )
        }
        .buttonStyle(.plain)
    }
}
