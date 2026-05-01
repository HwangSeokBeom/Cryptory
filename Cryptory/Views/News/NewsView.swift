import SwiftUI

private enum NewsCategory: String, CaseIterable, Identifiable {
    case trends
    case news
    case marketData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trends: return "최신동향"
        case .news: return "뉴스"
        case .marketData: return "시장 데이터"
        }
    }
}

struct NewsView: View {
    @ObservedObject var vm: CryptoViewModel
    @State private var selectedItem: CryptoNewsItem?
    @State private var selectedCategory: NewsCategory = .trends

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryBar
                content
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationDestination(item: $selectedItem) { item in
                NewsDetailView(item: item, onOpenChart: openChart)
            }
            .onAppear {
                vm.loadNewsAndTrendsIfNeeded()
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(NewsCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        VStack(spacing: 9) {
                            Text(category.title)
                                .font(.system(size: 16, weight: selectedCategory == category ? .heavy : .bold))
                                .foregroundColor(selectedCategory == category ? .themeText : .textMuted)
                                .lineLimit(1)
                            Rectangle()
                                .fill(selectedCategory == category ? Color.accent : Color.clear)
                                .frame(height: 4)
                                .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category.title) 카테고리")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .overlay(
            Rectangle()
                .fill(Color.themeBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var content: some View {
        switch selectedCategory {
        case .trends, .marketData:
            TrendsContentView(
                state: vm.marketTrendsState,
                category: selectedCategory,
                onRetry: { vm.loadMarketTrends(forceRefresh: true) }
            )
        case .news:
            newsList
        }
    }

    private var newsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headlineTicker
                switch vm.newsState {
                case .idle, .loading:
                    loadingCard(title: "뉴스를 불러오는 중...")
                case .failed(let message):
                    stateCard(title: "뉴스를 불러오지 못했어요", detail: message, actionTitle: "다시 시도") {
                        vm.loadNews(forceRefresh: true)
                    }
                case .empty:
                    stateCard(title: "표시할 뉴스가 없습니다", detail: "새 뉴스가 도착하면 날짜별로 표시합니다.", actionTitle: nil, action: nil)
                case .loaded(let items):
                    ForEach(groupedNews(items), id: \.date) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.date)
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(.themeText)
                            ForEach(group.items) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    NewsRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    providerNotice
                }
            }
            .padding(16)
            .padding(.bottom, 156)
        }
        .refreshable {
            vm.loadNews(forceRefresh: true)
            vm.loadMarketTrends(forceRefresh: true)
        }
    }

    private var headlineTicker: some View {
        HStack(spacing: 10) {
            Text("최신")
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accent))
            Text(vm.newsState.value?.first?.title ?? "시장 정보를 확인하고 있어요.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.themeText)
                .lineLimit(1)
            Spacer()
            Text(vm.newsState.value?.first?.timeText ?? "--:--")
                .font(.mono(13, weight: .bold))
                .foregroundColor(.textMuted)
        }
        .padding(.vertical, 10)
    }

    private var providerNotice: some View {
        Text("뉴스와 시장 정보는 참고용 데이터이며, 투자 조언이나 거래 신호가 아닙니다.")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textMuted)
            .lineSpacing(3)
            .padding(14)
            .background(sectionBackground)
    }

    private func groupedNews(_ items: [CryptoNewsItem]) -> [(date: String, items: [CryptoNewsItem])] {
        let groups = Dictionary(grouping: items) { $0.dateGroupText }
        return groups
            .map { (date: $0.key, items: $0.value.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }) }
            .sorted { ($0.items.first?.publishedAt ?? .distantPast) > ($1.items.first?.publishedAt ?? .distantPast) }
    }

    private func openChart(_ symbol: String) {
        vm.selectCoin(CoinCatalog.coin(symbol: symbol))
    }
}

private struct TrendsContentView: View {
    let state: Loadable<MarketTrendsSnapshot>
    let category: NewsCategory
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch state {
                case .idle, .loading:
                    loadingCard(title: loadingTitle)
                case .failed(let message):
                    stateCard(title: failedTitle, detail: message, actionTitle: "다시 시도", action: onRetry)
                case .empty:
                    stateCard(title: emptyTitle, detail: "시장 데이터가 확보되면 표시합니다.", actionTitle: nil, action: nil)
                case .loaded(let trends):
                    loadedContent(trends)
                    if let provider = trends.dataProvider {
                        Text("powered by \(provider)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 156)
        }
        .refreshable {
            onRetry()
        }
    }

    private var emptyTitle: String {
        switch category {
        case .trends: return "표시할 최신동향이 없어요"
        case .marketData: return "표시할 시장 데이터가 없어요"
        case .news: return "표시할 뉴스가 없어요"
        }
    }

    private var loadingTitle: String {
        switch category {
        case .trends: return "최신동향을 불러오는 중..."
        case .marketData: return "시장 데이터를 불러오는 중..."
        case .news: return "뉴스를 불러오는 중..."
        }
    }

    private var failedTitle: String {
        switch category {
        case .trends: return "최신동향을 불러오지 못했어요"
        case .marketData: return "시장 데이터를 불러오지 못했어요"
        case .news: return "뉴스를 불러오지 못했어요"
        }
    }

    @ViewBuilder
    private func loadedContent(_ trends: MarketTrendsSnapshot) -> some View {
        switch category {
        case .trends:
            if let headline = trends.latestHeadline {
                ticker(headline)
            }
            latestSummaryCard(trends)
            if let poll = trends.marketPoll {
                marketPollCard(poll)
            } else {
                preparationCard(title: "오늘 시장 투표", detail: "시장 투표 데이터 준비 중")
            }
            moversCard(trends.movers)
            marketSeriesCard(trends.marketCapVolumeSeries, title: "전체 시장 추이")
            preparationCard(title: "주요 이벤트", detail: "주요 이벤트 데이터 준비 중")
            disclaimer
        case .marketData:
            marketAnalysisCard(trends)
            marketSeriesCard(trends.marketCapVolumeSeries, title: "시가총액/거래량 추이")
            if let asOf = trends.asOf {
                Text(PriceFormatter.formatReferenceDate(asOf))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            if trends.fallbackUsed {
                Text("일부 시장 데이터는 거래소 스냅샷 기준으로 표시됩니다.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .padding(14)
                    .background(sectionBackground)
            }
            disclaimer
        case .news:
            EmptyView()
        }
    }

    private func ticker(_ headline: String) -> some View {
        HStack(spacing: 10) {
            Text("최신")
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accent))
            Text(headline)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.themeText)
                .lineLimit(1)
            Spacer()
        }
    }

    private func latestSummaryCard(_ trends: MarketTrendsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("시장 요약")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("전체 시가총액", value: compactCurrency(trends.totalMarketCap), subvalue: percent(trends.totalMarketCapChange24h), color: signedColor(trends.totalMarketCapChange24h))
                metric("24h 거래량", value: compactCurrency(trends.totalVolume24h ?? trends.marketCapVolumeSeries.last?.volume), subvalue: nil, color: .themeText)
                metric("BTC 도미넌스", value: percentValue(trends.btcDominance), subvalue: nil, color: .themeText)
                metric("ETH 도미넌스", value: percentValue(trends.ethDominance), subvalue: nil, color: .themeText)
                metric("공포/탐욕", value: trends.fearGreedIndex.map(String.init) ?? "-", subvalue: fearGreedLabel(trends.fearGreedIndex), color: .accent)
                metric("알트코인 지수", value: trends.altcoinIndex.map(String.init) ?? "-", subvalue: altSeasonLabel(trends.altcoinIndex), color: .accent)
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func marketAnalysisCard(_ trends: MarketTrendsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("전체 시장 데이터")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.textSecondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                metric("시가총액", value: compactCurrency(trends.totalMarketCap), subvalue: trends.totalMarketCap == nil ? "제공되지 않음" : percent(trends.totalMarketCapChange24h), color: signedColor(trends.totalMarketCapChange24h))
                metric("24h 거래량", value: compactCurrency(trends.totalVolume24h ?? trends.marketCapVolumeSeries.last?.volume), subvalue: nil, color: .themeText)
                metric("BTC 도미넌스", value: percentValue(trends.btcDominance), subvalue: nil, color: .themeText)
                metric("ETH 도미넌스", value: percentValue(trends.ethDominance), subvalue: nil, color: .themeText)
                metric("공포/탐욕 지수", value: trends.fearGreedIndex.map(String.init) ?? "-", subvalue: fearGreedLabel(trends.fearGreedIndex), color: .accent)
                metric("알트코인 지수", value: trends.altcoinIndex.map(String.init) ?? "-", subvalue: altSeasonLabel(trends.altcoinIndex), color: .accent)
                metric("BTC 롱숏(5분)", value: percentValue(trends.btcLongShortRatio), subvalue: nil, color: .up)
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func marketPollCard(_ poll: MarketPollSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("오늘 시장에 대해 어떻게 생각하세요?")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.themeText)
                Spacer()
                Image(systemName: "chevron.up")
                    .foregroundColor(.themeText)
            }
            HStack(spacing: 12) {
                pollButton(title: "상승", icon: "arrow.up.right", color: .up)
                Text("또는")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                pollButton(title: "하락", icon: "arrow.down.right", color: .down)
            }
            Text("\(poll.totalCount)명 참여")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textMuted)
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func marketSeriesCard(_ series: [MarketTrendPoint], title: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            let points = series.compactMap { $0.marketCap ?? $0.volume }
            if points.count >= 2 {
                TrendLineView(points: points, color: .accent)
                    .frame(height: 120)
                HStack {
                    Text("시가총액: \(compactCurrency(series.last?.marketCap))")
                        .foregroundColor(.cyan)
                    Spacer()
                    Text("거래량: \(compactCurrency(series.last?.volume))")
                        .foregroundColor(.pink)
                }
                .font(.system(size: 13, weight: .bold))
            } else {
                stateCard(title: "추이 데이터 준비 중", detail: "시장 추이 series가 제공되면 차트를 표시합니다.", actionTitle: nil, action: nil)
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func moversCard(_ movers: MarketMoversSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("주요 변동 코인")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            moverSection("상승폭", movers.topGainers)
            moverSection("하락폭", movers.topLosers)
            moverSection("거래량", movers.topVolume)
        }
        .padding(18)
        .background(sectionBackground)
    }

    @ViewBuilder
    private func moverSection(_ title: String, _ items: [MarketMover]) -> some View {
        if items.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textMuted)
                ForEach(items.prefix(3)) { item in
                    HStack {
                        Text(item.symbol)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.themeText)
                        Spacer()
                        Text(percent(item.changePercent24h) ?? compactCurrency(item.volume24h))
                            .font(.mono(13, weight: .bold))
                            .foregroundColor(signedColor(item.changePercent24h))
                    }
                }
            }
        }
    }

    private func preparationCard(title: String, detail: String) -> some View {
        stateCard(title: title, detail: detail, actionTitle: nil, action: nil)
    }

    private var disclaimer: some View {
        Text("뉴스와 시장 데이터는 참고용 정보이며, 투자 조언이나 거래 신호가 아닙니다.")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textMuted)
            .lineSpacing(3)
            .padding(14)
            .background(sectionBackground)
    }

    private func metric(_ title: String, value: String, subvalue: String?, color: Color) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.mono(20, weight: .heavy))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let subvalue {
                Text(subvalue)
                    .font(.mono(13, weight: .bold))
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pollButton(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgTertiary))
    }

    private func compactCurrency(_ value: Double?) -> String {
        guard let value else { return "제공되지 않음" }
        return PriceFormatter.formatCompactKRWAmount(value)
    }

    private func percentValue(_ value: Double?) -> String {
        guard let value else { return "제공되지 않음" }
        return String(format: "%.2f%%", value)
    }

    private func fearGreedLabel(_ value: Int?) -> String? {
        guard let value else { return nil }
        if value < 25 { return "공포" }
        if value > 75 { return "탐욕" }
        return "중립"
    }

    private func altSeasonLabel(_ value: Int?) -> String? {
        guard let value else { return nil }
        return value > 50 ? "알트코인 시즌" : "비트코인 시즌"
    }
}

private struct TrendLineView: View {
    let points: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let values = normalizedPoints
                guard values.count >= 2 else { return }
                let step = proxy.size.width / CGFloat(values.count - 1)
                for index in values.indices {
                    let point = CGPoint(
                        x: CGFloat(index) * step,
                        y: proxy.size.height * (1 - CGFloat(values[index]))
                    )
                    if index == values.startIndex {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("시가총액 거래량 추이 그래프")
    }

    private var normalizedPoints: [Double] {
        guard let minValue = points.min(), let maxValue = points.max(), maxValue > minValue else {
            return []
        }
        return points.map { ($0 - minValue) / (maxValue - minValue) }
    }
}

private struct NewsRow: View {
    let item: CryptoNewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(item.timeText)
                    .font(.mono(11, weight: .bold))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accent.opacity(0.12)))
                Spacer()
                Text(item.source)
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
        .background(sectionBackground)
        .accessibilityLabel("뉴스 \(item.title)")
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(item.relatedSymbols, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.themeText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.bgTertiary))
                }
            }
        }
    }
}

private struct NewsDetailView: View {
    let item: CryptoNewsItem
    let onOpenChart: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.source)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.accent)
                    Text(item.title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.themeText)
                    Text(item.timeText)
                        .font(.mono(12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
                Text((item.body?.isEmpty == false ? item.body : item.summary) ?? item.summary)
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(5)

                if item.relatedSymbols.isEmpty == false {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("관련 코인")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.themeText)
                        ForEach(item.relatedSymbols, id: \.self) { symbol in
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
                                }
                                .foregroundColor(.accent)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.accent.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let url = item.originalURL {
                    Link(destination: url) {
                        Label("원문 보기", systemImage: "safari")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.accent))
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
