import SwiftUI

struct NewsView: View {
    @ObservedObject var vm: CryptoViewModel
    @State private var selectedItem: NewsItem?

    private let items = NewsItem.sampleItems

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ForEach(items) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            NewsRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                    providerNotice
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationDestination(item: $selectedItem) { item in
                NewsDetailView(item: item, onOpenChart: openChart)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("뉴스")
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(.themeText)

            Text("오늘, \(Self.todayString)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
        }
    }

    private var providerNotice: some View {
        Text("powered by Coinness")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private func openChart(_ symbol: String) {
        vm.selectCoin(CoinCatalog.coin(symbol: symbol))
    }

    private static var todayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(item.timeText)
                    .font(.mono(11, weight: .bold))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accent.opacity(0.12))
                    )

                Spacer()

                Text(item.provider)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textMuted)
            }

            Text(item.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.themeText)
                .multilineTextAlignment(.leading)

            Text(item.summary)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
                .lineLimit(4)

            tagRow
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

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(item.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.themeText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.bgTertiary)
                        )
                }
            }
        }
    }
}

private struct NewsDetailView: View {
    let item: NewsItem
    let onOpenChart: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.provider)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.accent)

                    Text(item.title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.themeText)

                    Text(item.timeText)
                        .font(.mono(12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }

                Text(item.summary)
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("관련 코인")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.themeText)

                    ForEach(item.symbols, id: \.self) { symbol in
                        Button {
                            onOpenChart(symbol)
                        } label: {
                            HStack {
                                Text(symbol)
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Text("관련 차트 보기")
                                    .font(.system(size: 12, weight: .semibold))
                                Image(systemName: "chart.xyaxis.line")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.accent)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.accent.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let url = item.sourceURL {
                    Link(destination: url) {
                        HStack {
                            Text("원문 보기")
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                            Image(systemName: "safari")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accent)
                        )
                    }
                }

                Text("뉴스와 시장 정보는 참고용 데이터이며, 투자 조언이나 거래 신호가 아닙니다.")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
                    .lineSpacing(2)
            }
            .padding(16)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("뉴스 상세")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NewsItem: Identifiable, Hashable {
    let id = UUID()
    let timeText: String
    let title: String
    let summary: String
    let tags: [String]
    let symbols: [String]
    let provider: String
    let sourceURL: URL?

    static let sampleItems: [NewsItem] = [
        NewsItem(
            timeText: "09:10",
            title: "비트코인 가격 변동성 확대, 주요 지표 혼조",
            summary: "비트코인은 글로벌 거시 지표 발표 이후 변동성이 커졌습니다. 단기 추세와 거래량 지표가 엇갈리며 시장 참여자들은 추가 데이터를 확인하는 흐름입니다.",
            tags: ["BTC", "거시", "변동성"],
            symbols: ["BTC"],
            provider: "Coinness",
            sourceURL: URL(string: "https://coinness.com")
        ),
        NewsItem(
            timeText: "11:35",
            title: "이더리움 네트워크 수수료 안정세",
            summary: "이더리움 네트워크 평균 수수료가 최근 고점 대비 안정된 수준을 보이고 있습니다. 온체인 활동과 레이어2 지표를 함께 확인할 필요가 있습니다.",
            tags: ["ETH", "온체인", "L2"],
            symbols: ["ETH"],
            provider: "Coinness",
            sourceURL: URL(string: "https://coinness.com")
        ),
        NewsItem(
            timeText: "14:20",
            title: "국내외 주요 가격 차이 축소",
            summary: "일부 주요 자산의 국내외 가격 차이가 전일 대비 좁혀졌습니다. 환율과 거래소별 기준 가격에 따라 실제 수치는 달라질 수 있습니다.",
            tags: ["김프", "환율", "시장"],
            symbols: ["BTC", "ETH"],
            provider: "Coinness",
            sourceURL: URL(string: "https://coinness.com")
        )
    ]
}
