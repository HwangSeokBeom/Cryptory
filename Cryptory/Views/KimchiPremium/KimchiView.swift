import SwiftUI

struct KimchiView: View {
    @ObservedObject var vm: CryptoViewModel

    private var topCoins: [CoinInfo] { Array(COINS.prefix(8)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accent)
                        Text("김치 프리미엄 비교")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.themeText)
                    }
                    Text("바이낸스(USDT) 대비 국내 거래소 프리미엄")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.bgSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.themeBorder, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.top, 14)

                if vm.prices.isEmpty {
                    ProgressView("공용 시세 연결 중...")
                        .tint(.accent)
                        .padding(.top, 40)
                } else {
                    ForEach(topCoins) { coin in
                        PremiumCard(vm: vm, coin: coin)
                            .padding(.horizontal, 16)
                    }

                    PremiumSummary(vm: vm)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 20)
            }
        }
    }
}
