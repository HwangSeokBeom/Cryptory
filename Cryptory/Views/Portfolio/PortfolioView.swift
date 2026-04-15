import SwiftUI

struct PortfolioView: View {
    @ObservedObject var vm: CryptoViewModel

    var body: some View {
        if vm.activeTab == .portfolio, let feature = vm.activeAuthGate {
            AuthGateView(feature: feature) {
                vm.presentLogin(for: feature)
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    connectionSummaryCard
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

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

                    Spacer(minLength: 20)
                }
            }
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
        case .loaded(let connections):
            let tradableCount = connections.filter { $0.permission == .tradeEnabled && $0.isActive }.count
            return "총 \(connections.count)개 연결, 주문 가능 \(tradableCount)개"
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
