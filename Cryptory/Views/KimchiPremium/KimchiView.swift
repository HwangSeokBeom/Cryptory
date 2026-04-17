import SwiftUI

struct KimchiView: View {
    @ObservedObject var vm: CryptoViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                ScreenStatusBannerView(viewState: vm.kimchiStatusViewState)
                    .padding(.horizontal, 16)

                switch vm.kimchiPremiumState {
                case .idle, .loading:
                    ProgressView("김치 프리미엄을 불러오는 중...")
                        .tint(.accent)
                        .padding(.top, 40)

                case .failed(let message):
                    stateCard(
                        title: "김치 프리미엄을 불러오지 못했어요",
                        detail: message
                    )

                case .empty:
                    stateCard(
                        title: "비교 가능한 김프 데이터가 없어요",
                        detail: "서버의 /kimchi-premium 응답이 비어 있거나 아직 준비되지 않았어요."
                    )

                case .loaded(let coinViewStates):
                    ForEach(coinViewStates) { coinViewState in
                        PremiumCard(coinViewState: coinViewState)
                            .padding(.horizontal, 16)
                    }

                    PremiumSummary(coinViewStates: coinViewStates)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 20)
            }
        }
        .task {
            await vm.loadKimchiPremium()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accent)
                Text("김치 프리미엄 비교")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.themeText)
            }
            Text("서버 canonical model 기준으로 국내 거래소 현재가와 바이낸스 환산가를 비교합니다.")
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
    }

    private func stateCard(title: String, detail: String) -> some View {
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
        .padding(.vertical, 28)
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
