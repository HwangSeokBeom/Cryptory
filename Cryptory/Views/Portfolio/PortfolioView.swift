import SwiftUI

struct PortfolioView: View {
    @ObservedObject var vm: CryptoViewModel

    var body: some View {
        if vm.activeTab == .portfolio, let feature = vm.activeAuthGate {
            AuthGateView(feature: feature) {
                vm.presentLogin(for: feature)
            }
        } else if vm.isSelectedExchangePortfolioUnsupported {
            unsupportedState
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    connectionSummaryCard
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    ScreenStatusBannerView(viewState: vm.portfolioStatusViewState)
                        .padding(.horizontal, 16)

                    switch vm.portfolioState {
                    case .idle, .loading:
                        ProgressView("내 자산을 불러오는 중...")
                            .tint(.accent)
                            .padding(.top, 40)

                    case .failed(let message):
                        stateMessage(
                            title: "자산 데이터를 불러오지 못했어요",
                            detail: message
                        )

                    case .empty:
                        stateMessage(
                            title: "보유 자산이 없어요",
                            detail: "거래소 연결 후 자산이 있으면 여기에서 확인할 수 있어요."
                        )

                    case .loaded:
                        TotalAssetCard(vm: vm)
                            .padding(.horizontal, 16)

                        holdingsSection
                        historySection
                    }

                    Spacer(minLength: 20)
                }
            }
        }
    }

    private var unsupportedState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wallet.pass")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.textSecondary)
            Text("이 거래소는 자산 조회를 지원하지 않아요")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.themeText)
            Text("Exchange metadata 의 supportsAsset 기준으로 빈 상태를 노출했습니다.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
    }

    private var connectionSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("거래소 연결")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.themeText)
                    Text(connectionSummaryText)
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

    private var connectionSummaryText: String {
        switch vm.exchangeConnectionsState {
        case .idle, .loading:
            return "거래소 연결 정보를 확인하는 중이에요."
        case .failed:
            return "연결 상태를 불러오지 못했어요."
        case .empty:
            return "연결된 거래소가 없어요."
        case .loaded:
            let tradableCount = vm.exchangeConnections.filter { $0.permission == .tradeEnabled && $0.isActive }.count
            return "총 \(vm.exchangeConnections.count)개 연결, 주문 가능 \(tradableCount)개"
        }
    }

    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("보유 코인")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.themeText)
                .padding(.horizontal, 16)

            if vm.portfolio.isEmpty {
                stateMessage(
                    title: "보유 코인이 없어요",
                    detail: "거래소에 보유한 자산이 생기면 여기에 표시돼요."
                )
            } else {
                ForEach(vm.portfolio) { holding in
                    HoldingCard(vm: vm, holding: holding)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 자산 히스토리")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.themeText)
                .padding(.horizontal, 16)

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
                    title: "최근 히스토리가 없어요",
                    detail: "입출금이나 체결 이력이 생기면 여기에 표시돼요."
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
}
