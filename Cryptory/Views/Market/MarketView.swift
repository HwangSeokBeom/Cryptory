import SwiftUI

struct MarketView: View {
    @ObservedObject var vm: CryptoViewModel

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $vm.searchQuery)
            MarketSegmentedControl(selection: $vm.marketFilter)
                .padding(.bottom, 10)

            ScreenStatusBannerView(viewState: vm.marketStatusViewState)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            HStack(spacing: 0) {
                Text("코인")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("현재가(KRW)")
                    .frame(width: 96, alignment: .trailing)
                Text("등락률")
                    .frame(width: 68, alignment: .trailing)
                Text("거래량")
                    .frame(width: 68, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.textMuted)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            content
                .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnBackgroundTap()
    }

    @ViewBuilder
    private var content: some View {
        switch vm.marketState {
        case .idle, .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView("시세를 불러오는 중...")
                    .tint(.accent)
                Spacer()
            }

        case .failed(let message):
            stateView(
                title: "시세를 불러오지 못했어요",
                detail: message
            )

        case .empty:
            stateView(
                title: "노출할 거래쌍이 없어요",
                detail: "서버에서 선택 거래소의 market metadata 가 아직 내려오지 않았어요."
            )

        case .loaded:
            ScrollView {
                Group {
                    if vm.marketFilter == .fav && vm.filteredCoins.isEmpty {
                        stateView(
                            title: "관심 코인이 아직 없어요",
                            detail: "실데이터 연동 상태와 관계없이 별표를 눌러 guest 관심 코인을 저장할 수 있어요."
                        )
                    } else if vm.filteredCoins.isEmpty {
                        stateView(
                            title: "검색 결과가 없어요",
                            detail: "다른 검색어를 입력하거나 거래소를 바꿔보세요."
                        )
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.filteredCoins) { coin in
                                CoinRowView(vm: vm, coin: coin)
                                Divider()
                                    .background(Color.themeBorder.opacity(0.28))
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func stateView(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.themeText)
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
