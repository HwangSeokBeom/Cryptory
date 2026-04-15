import SwiftUI

struct MarketView: View {
    @ObservedObject var vm: CryptoViewModel

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $vm.searchQuery)
            MarketSegmentedControl(selection: $vm.marketFilter)
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
            .padding(.top, 0)
            .padding(.bottom, 8)

            ScrollView {
                Group {
                    if vm.marketFilter == .fav && vm.filteredCoins.isEmpty {
                        VStack(spacing: 12) {
                            Spacer(minLength: 60)
                            Image(systemName: "star")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            Text("관심 코인이 아직 없어요")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.themeText)
                            Text("로그인 없이도 별표를 눌러 guest 관심 코인을 임시로 저장할 수 있어요.")
                                .font(.system(size: 12))
                                .foregroundColor(.textMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity)
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
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnBackgroundTap()
    }
}
