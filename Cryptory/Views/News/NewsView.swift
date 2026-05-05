import SwiftUI
import Combine

private let newsTabBarReservedHeight: CGFloat = 92
private let newsScrollBottomPadding: CGFloat = 188

private enum NewsCategory: String, CaseIterable, Identifiable {
    case trends
    case news
    case calculator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trends: return "최신동향"
        case .news: return "뉴스"
        case .calculator: return "계산기"
        }
    }
}

private enum MarketTrendMetric: String, CaseIterable, Identifiable {
    case marketCap
    case volume
    case btcDominance
    case ethDominance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .marketCap: return "시가총액"
        case .volume: return "거래량"
        case .btcDominance: return "BTC 도미넌스"
        case .ethDominance: return "ETH 도미넌스"
        }
    }

    func values(from series: [MarketTrendPoint]) -> [Double] {
        switch self {
        case .marketCap: return series.compactMap(\.marketCap)
        case .volume: return series.compactMap(\.volume)
        case .btcDominance: return series.compactMap(\.btcDominance)
        case .ethDominance: return series.compactMap(\.ethDominance)
        }
    }

    func pointCount(in series: [MarketTrendPoint]) -> Int {
        values(from: series).count
    }
}

private enum MarketTrendRenderMode: String {
    case hidden
    case empty
    case mini
    case chart

    static func mode(pointCount: Int) -> MarketTrendRenderMode {
        if pointCount <= 0 { return .hidden }
        if pointCount <= 2 { return .empty }
        return .chart
    }
}

struct NewsView: View {
    @ObservedObject var vm: CryptoViewModel
    @State private var selectedItem: CryptoNewsItem?
    @State private var selectedCalculator: CalculatorKind?
    @State private var selectedCategory: NewsCategory = .trends
    @State private var originalNewsItemIds: Set<String> = []

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
            .navigationDestination(item: $selectedCalculator) { calculator in
                calculator.destination
            }
            .onAppear {
                vm.loadNewsAndTrendsIfNeeded()
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 24) {
                ForEach(NewsCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        VStack(spacing: 0) {
                            Text(category.title)
                                .font(.system(size: 16, weight: selectedCategory == category ? .heavy : .bold))
                                .foregroundColor(selectedCategory == category ? .themeText : .textMuted)
                                .lineLimit(1)
                                .frame(height: 24)
                                .padding(.top, 12)
                                .padding(.bottom, 10)
                            Rectangle()
                                .fill(selectedCategory == category ? Color.accent : Color.clear)
                                .frame(height: 4)
                                .clipShape(Capsule())
                        }
                        .frame(height: 50, alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category.title) 카테고리")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 58, alignment: .bottom)
        }
        .frame(height: 58)
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
        case .trends:
            TrendsContentView(
                state: vm.marketTrendsState,
                category: selectedCategory,
                newsItems: vm.newsState.value ?? [],
                selectedRange: vm.marketTrendRange,
                isVotingMarketSentiment: vm.isVotingMarketSentiment,
                marketSentimentMessage: vm.marketSentimentMessage,
                onSelectRange: vm.selectMarketTrendRange,
                onMarketVote: vm.voteMarketSentiment,
                onRetry: { vm.loadMarketTrends(forceRefresh: true) }
            )
        case .news:
            newsList
        case .calculator:
            CalculatorSectionView(onSelect: { selectedCalculator = $0 })
        }
    }

    private var newsList: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headlineTicker
                    HStack {
                        dateFilterBar(selectedDate: vm.newsSelectedDate, onSelect: vm.selectNewsDate)
                        Spacer(minLength: 8)
                        newsSortMenu(sortOrder: vm.newsSortOrder, onSelect: vm.selectNewsSort)
                    }
                    switch vm.newsState {
                    case .idle, .loading:
                        loadingCard(title: "뉴스를 불러오는 중...")
                    case .failed(let message):
                        stateCard(title: "뉴스를 불러오지 못했어요", detail: message, actionTitle: "다시 시도") {
                            vm.loadNews(forceRefresh: true)
                        }
                    case .empty:
                        stateCard(title: "표시할 뉴스가 없습니다", detail: newsEmptyDetail(vm.newsFeedViewState), actionTitle: nil, action: nil)
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
                                        NewsRow(
                                            item: item,
                                            showsOriginal: originalNewsItemIds.contains(item.id),
                                            onToggleOriginal: {
                                                toggleOriginal(for: item.id)
                                            }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        providerNotice
                    }
                }
                .padding(16)
                .padding(.bottom, newsScrollBottomPadding + proxy.safeAreaInsets.bottom + newsTabBarReservedHeight)
            }
            .refreshable {
                vm.loadNews(forceRefresh: true)
            }
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
        Text("뉴스와 최신동향은 참고용 데이터이며, 투자 조언이나 거래 신호가 아닙니다.")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textMuted)
            .lineSpacing(3)
            .padding(14)
            .background(sectionBackground)
    }

    private func newsEmptyDetail(_ state: NewsFeedViewState) -> String {
        var parts = [newsEmptyReasonText(state.emptyReason, symbol: nil)]
        if let fallbackDate = state.latestFallbackDate {
            parts.append("가장 최근 뉴스: \(PriceFormatter.formatReferenceDate(fallbackDate))")
        } else if let latestAvailable = state.availableDates.sorted(by: >).first {
            parts.append("가장 최근 뉴스: \(PriceFormatter.formatReferenceDate(latestAvailable))")
        }
        if let source = state.source?.trimmedNonEmpty {
            parts.append("source \(source)")
        }
        if let cacheHit = state.cacheHit {
            parts.append("cacheHit \(cacheHit ? "true" : "false")")
        }
        if let providerStatus = state.providerStatus?.trimmedNonEmpty {
            parts.append("providerStatus \(providerStatus)")
        }
        return parts.joined(separator: " · ")
    }

    private func groupedNews(_ items: [CryptoNewsItem]) -> [(date: String, items: [CryptoNewsItem])] {
        let isOldest = vm.newsSortOrder == .oldest
        let groups = Dictionary(grouping: items) { $0.dateGroupText }
        return groups
            .map { group in
                (
                    date: group.key,
                    items: group.value.sorted {
                        isOldest
                            ? (($0.publishedAt ?? .distantFuture) < ($1.publishedAt ?? .distantFuture))
                            : (($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast))
                    }
                )
            }
            .sorted {
                isOldest
                    ? (($0.items.first?.publishedAt ?? .distantFuture) < ($1.items.first?.publishedAt ?? .distantFuture))
                    : (($0.items.first?.publishedAt ?? .distantPast) > ($1.items.first?.publishedAt ?? .distantPast))
            }
    }

    private func openChart(_ symbol: String) {
        vm.selectCoin(CoinCatalog.coin(symbol: symbol))
    }

    private func toggleOriginal(for id: String) {
        if originalNewsItemIds.contains(id) {
            originalNewsItemIds.remove(id)
        } else {
            originalNewsItemIds.insert(id)
        }
    }
}

private enum CalculatorKind: String, CaseIterable, Identifiable {
    case usdt
    case profit
    case averageDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usdt: return "USDT 계산기"
        case .profit: return "수익률 계산기"
        case .averageDown: return "물타기 계산기"
        }
    }

    var description: String {
        switch self {
        case .usdt: return "USDT와 원화 환산을 빠르게 계산합니다."
        case .profit: return "매수가, 매도가, 수량 기준 수익률을 계산합니다."
        case .averageDown: return "추가 매수 후 평균 단가를 계산합니다."
        }
    }

    var iconName: String {
        switch self {
        case .usdt: return "dollarsign.circle.fill"
        case .profit: return "chart.line.uptrend.xyaxis.circle.fill"
        case .averageDown: return "arrow.down.forward.circle.fill"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .usdt:
            USDTCalculatorView()
        case .profit:
            ProfitCalculatorView()
        case .averageDown:
            AverageDownCalculatorView()
        }
    }
}

private struct CalculatorSectionView: View {
    let onSelect: (CalculatorKind) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(CalculatorKind.allCases) { calculator in
                        Button {
                            onSelect(calculator)
                        } label: {
                            CalculatorListCard(calculator: calculator)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(calculator.title)
                    }
                    Text("계산 결과는 참고용이며 투자 조언이나 거래 신호가 아닙니다.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                        .lineSpacing(3)
                        .padding(14)
                        .background(sectionBackground)
                }
                .padding(16)
                .padding(.bottom, newsScrollBottomPadding + proxy.safeAreaInsets.bottom + newsTabBarReservedHeight)
            }
            .background(Color.bg)
        }
    }
}

private struct CalculatorListCard: View {
    let calculator: CalculatorKind

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: calculator.iconName)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.accent)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                Text(calculator.title)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.themeText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(calculator.description)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }
}

@MainActor
private final class USDTCalculatorViewModel: ObservableObject {
    @Published private(set) var quoteState: Loadable<USDTQuote> = .idle
    @Published var usdtInput = ""
    @Published var krwInput = ""

    private static var cachedQuote: USDTQuote?
    private let useCase: CalculatorUseCase
    private var editingField: Field?
    private var isFormatting = false

    private enum Field {
        case usdt
        case krw
    }

    init(useCase: CalculatorUseCase = CalculatorUseCase()) {
        self.useCase = useCase
        if let cached = Self.cachedQuote {
            quoteState = .loaded(cached)
        }
    }

    var quote: USDTQuote? {
        quoteState.value
    }

    var shouldLoadOnAppear: Bool {
        quote == nil && quoteState.isLoading == false
    }

    func loadRate(forceRefresh: Bool = false) {
        if quoteState.isLoading && forceRefresh == false {
            return
        }
        if quote == nil {
            quoteState = .loading
        }
        Task { @MainActor in
            do {
                let quote = try await useCase.fetchUSDTRate()
                Self.cachedQuote = quote
                quoteState = .loaded(quote)
                recalculateFromActiveField()
            } catch {
                if quote == nil {
                    quoteState = .failed(NetworkServiceErrorMessage.make(error, fallback: "환율 정보를 불러오지 못했습니다."))
                }
            }
        }
    }

    func usdtChanged(_ value: String) {
        guard isFormatting == false else { return }
        editingField = .usdt
        let sanitized = Self.sanitizedDecimal(value, maxIntegerDigits: 15, maxFractionDigits: 6)
        setFormatted(.usdt, sanitized)
        guard let amount = Self.number(from: sanitized), let quote else {
            krwInput = ""
            return
        }
        guard let krwAmount = USDTExchangeRateMapper.krwAmount(usdt: amount, rate: quote.price) else {
            krwInput = ""
            return
        }
        krwInput = Self.formatNumber(krwAmount, maximumFractionDigits: 2)
    }

    func krwChanged(_ value: String) {
        guard isFormatting == false else { return }
        editingField = .krw
        let sanitized = Self.sanitizedDecimal(value, maxIntegerDigits: 18, maxFractionDigits: 0)
        setFormatted(.krw, sanitized)
        guard let amount = Self.number(from: sanitized), let quote else {
            usdtInput = ""
            return
        }
        guard let usdtAmount = USDTExchangeRateMapper.usdtAmount(krw: amount, rate: quote.price) else {
            usdtInput = ""
            return
        }
        usdtInput = Self.formatNumber(usdtAmount, maximumFractionDigits: 6)
    }

    private func recalculateFromActiveField() {
        switch editingField {
        case .usdt:
            usdtChanged(usdtInput)
        case .krw:
            krwChanged(krwInput)
        case nil:
            break
        }
    }

    private func setFormatted(_ field: Field, _ sanitized: String) {
        let formatted = Self.formatDecimalInput(sanitized)
        isFormatting = true
        switch field {
        case .usdt:
            usdtInput = formatted
        case .krw:
            krwInput = formatted
        }
        isFormatting = false
    }

    static func sanitizedDecimal(_ value: String, maxIntegerDigits: Int, maxFractionDigits: Int) -> String {
        let allowed = value
            .replacingOccurrences(of: ",", with: "")
            .filter { $0.isNumber || $0 == "." }
        var result = ""
        var hasDot = false
        var integerCount = 0
        var fractionCount = 0
        for character in allowed {
            if character == "." {
                guard hasDot == false else { continue }
                hasDot = true
                result.append(character)
            } else if hasDot {
                guard fractionCount < maxFractionDigits else { continue }
                fractionCount += 1
                result.append(character)
            } else {
                guard integerCount < maxIntegerDigits else { continue }
                integerCount += 1
                result.append(character)
            }
        }
        return result
    }

    static func number(from value: String) -> Double? {
        let normalized = value.replacingOccurrences(of: ",", with: "")
        guard let number = Double(normalized), number.isFinite else {
            return nil
        }
        return number
    }

    static func formatDecimalInput(_ value: String) -> String {
        guard value.isEmpty == false else { return "" }
        let hasTrailingDot = value.hasSuffix(".")
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let integerPart = String(parts.first ?? "")
        let fractionPart = parts.count > 1 ? String(parts[1]) : nil
        let groupedInteger = formatIntegerString(integerPart)
        if let fractionPart {
            return "\(groupedInteger).\(fractionPart)"
        }
        return hasTrailingDot ? "\(groupedInteger)." : groupedInteger
    }

    static func formatNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        guard value.isFinite, value < 1_000_000_000_000_000_000 else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)))
    }

    static func sourceDisplayName(_ source: String) -> String {
        switch source.lowercased() {
        case "coinmarketcap":
            return "CoinMarketCap"
        case "cache":
            return "cache"
        default:
            return source
        }
    }

    static func updateTimeText(_ date: Date?) -> String {
        guard let date else { return "업데이트 --:--" }
        return "업데이트 \(updateTimeFormatter.string(from: date))"
    }

    private static func formatIntegerString(_ value: String) -> String {
        guard let number = Int64(value), value.isEmpty == false else {
            return value
        }
        return number.formatted(.number.grouping(.automatic))
    }

    private static let updateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private enum NetworkServiceErrorMessage {
    static func make(_ error: Error, fallback: String) -> String {
        if let networkError = error as? NetworkServiceError {
            return networkError.userFacingDescription(fallback: fallback)
        }
        return fallback
    }
}

private struct USDTCalculatorView: View {
    @StateObject private var viewModel = USDTCalculatorViewModel()

    var body: some View {
        CalculatorDetailContainer {
            VStack(alignment: .leading, spacing: 16) {
                quoteStatus
                CalculatorInputField(title: "USDT 수량", text: $viewModel.usdtInput, placeholder: "0.00")
                    .onChange(of: viewModel.usdtInput) { _, value in
                        viewModel.usdtChanged(value)
                    }
                CalculatorInputField(title: "KRW 금액", text: $viewModel.krwInput, placeholder: "0")
                    .onChange(of: viewModel.krwInput) { _, value in
                        viewModel.krwChanged(value)
                    }
                Text("USDT 환산은 서버에서 제공하는 환율 기준입니다.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .lineSpacing(3)
            }
        }
        .navigationTitle("USDT 계산기")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.shouldLoadOnAppear {
                viewModel.loadRate()
            }
        }
    }

    @ViewBuilder
    private var quoteStatus: some View {
        switch viewModel.quoteState {
        case .idle, .loading:
            loadingCard(title: "환율 정보를 불러오는 중...")
        case .failed(let message):
            stateCard(title: "환율 정보를 불러오지 못했습니다.", detail: message, actionTitle: "재시도") {
                viewModel.loadRate(forceRefresh: true)
            }
        case .empty:
            stateCard(title: "환율 정보가 없습니다.", detail: "서버에서 USDT/KRW 환율을 제공하면 계산할 수 있습니다.", actionTitle: "재시도") {
                viewModel.loadRate(forceRefresh: true)
            }
        case .loaded(let quote):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("1 USDT = \(USDTCalculatorViewModel.formatNumber(quote.price, maximumFractionDigits: 2)) KRW")
                        .font(.mono(20, weight: .heavy))
                        .foregroundColor(.accent)
                    Spacer()
                    Button {
                        viewModel.loadRate(forceRefresh: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("환율 새로고침")
                }
                Text("source \(USDTCalculatorViewModel.sourceDisplayName(quote.source)) · \(USDTCalculatorViewModel.updateTimeText(quote.updatedAt))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            .padding(18)
            .background(sectionBackground)
        }
    }
}

private struct ProfitCalculatorView: View {
    @State private var buyPrice = ""
    @State private var sellPrice = ""
    @State private var quantity = ""
    @State private var feePercent = "0.05"

    private var result: ProfitResult? {
        guard let buy = parse(buyPrice), buy > 0,
              let sell = parse(sellPrice), sell >= 0,
              let qty = parse(quantity), qty > 0,
              let fee = parse(feePercent), fee >= 0 else {
            return nil
        }
        let buyTotal = buy * qty
        let sellTotal = sell * qty
        let feeAmount = (buyTotal + sellTotal) * (fee / 100)
        let profit = sellTotal - buyTotal - feeAmount
        let profitRate = buyTotal > 0 ? profit / buyTotal * 100 : 0
        return ProfitResult(buyTotal: buyTotal, sellTotal: sellTotal, fee: feeAmount, profit: profit, profitRate: profitRate)
    }

    var body: some View {
        CalculatorDetailContainer {
            VStack(alignment: .leading, spacing: 16) {
                CalculatorInputField(title: "매수가", text: formattedBinding($buyPrice, maxFractionDigits: 8), placeholder: "0")
                CalculatorInputField(title: "매도가", text: formattedBinding($sellPrice, maxFractionDigits: 8), placeholder: "0")
                CalculatorInputField(title: "수량", text: formattedBinding($quantity, maxFractionDigits: 8), placeholder: "0")
                CalculatorInputField(title: "수수료율(%)", text: formattedBinding($feePercent, maxIntegerDigits: 3, maxFractionDigits: 4), placeholder: "0.05")
                if let result {
                    CalculatorResultCard(
                        title: result.profit >= 0 ? "예상 수익" : "예상 손실",
                        value: "\(formatSignedCurrency(result.profit)) · \(formatSignedPercent(result.profitRate))",
                        color: signedColor(result.profit),
                        rows: [
                            ("총 매수금액", formatCurrency(result.buyTotal)),
                            ("총 매도금액", formatCurrency(result.sellTotal)),
                            ("예상 수수료", formatCurrency(result.fee)),
                            ("손익 금액", formatSignedCurrency(result.profit)),
                            ("수익률", formatSignedPercent(result.profitRate))
                        ]
                    )
                } else {
                    stateCard(title: "입력값을 확인해주세요", detail: "매수가, 매도가, 수량을 입력하면 예상 손익과 수익률을 계산합니다.", actionTitle: nil, action: nil)
                }
                CalculatorNotice(text: "투자 조언이 아닌 단순 계산 결과입니다.")
            }
        }
        .navigationTitle("수익률 계산기")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct ProfitResult {
        let buyTotal: Double
        let sellTotal: Double
        let fee: Double
        let profit: Double
        let profitRate: Double
    }
}

private struct AverageDownCalculatorView: View {
    @State private var oldAveragePrice = ""
    @State private var oldQuantity = ""
    @State private var addPrice = ""
    @State private var addQuantity = ""
    @State private var currentPrice = ""

    private var result: AverageDownResult? {
        guard let oldAverage = parse(oldAveragePrice), oldAverage > 0,
              let oldQty = parse(oldQuantity), oldQty > 0,
              let add = parse(addPrice), add > 0,
              let addQty = parse(addQuantity), addQty > 0 else {
            return nil
        }
        let oldTotal = oldAverage * oldQty
        let addTotal = add * addQty
        let totalQuantity = oldQty + addQty
        let newAverage = (oldTotal + addTotal) / totalQuantity
        let optionalCurrentPrice = parse(currentPrice)
        let profitRate = optionalCurrentPrice.map { ($0 - newAverage) / newAverage * 100 }
        return AverageDownResult(
            oldTotal: oldTotal,
            addTotal: addTotal,
            totalQuantity: totalQuantity,
            newAveragePrice: newAverage,
            averageDiff: newAverage - oldAverage,
            profitRate: profitRate
        )
    }

    var body: some View {
        CalculatorDetailContainer {
            VStack(alignment: .leading, spacing: 16) {
                CalculatorInputField(title: "기존 평균 단가", text: formattedBinding($oldAveragePrice, maxFractionDigits: 8), placeholder: "0")
                CalculatorInputField(title: "기존 수량", text: formattedBinding($oldQuantity, maxFractionDigits: 8), placeholder: "0")
                CalculatorInputField(title: "추가 매수 단가", text: formattedBinding($addPrice, maxFractionDigits: 8), placeholder: "0")
                CalculatorInputField(title: "추가 매수 수량", text: formattedBinding($addQuantity, maxFractionDigits: 8), placeholder: "0")
                CalculatorInputField(title: "현재가(선택)", text: formattedBinding($currentPrice, maxFractionDigits: 8), placeholder: "0")
                if let result {
                    CalculatorResultCard(
                        title: "새 평균 단가",
                        value: formatCurrency(result.newAveragePrice),
                        color: signedColor(-result.averageDiff),
                        rows: [
                            ("기존 평가금액", formatCurrency(result.oldTotal)),
                            ("추가 매수금액", formatCurrency(result.addTotal)),
                            ("총 보유 수량", formatPlain(result.totalQuantity, maxFractionDigits: 8)),
                            ("평균 단가 변화", result.averageDiff <= 0 ? "\(formatCurrency(abs(result.averageDiff))) 낮아짐" : "\(formatCurrency(result.averageDiff)) 높아짐"),
                            ("현재가 기준 손익률", result.profitRate.map(formatSignedPercent) ?? "현재가 미입력")
                        ]
                    )
                } else {
                    stateCard(title: "입력값을 확인해주세요", detail: "기존 평균 단가와 수량, 추가 매수 단가와 수량을 입력하면 새 평균 단가를 계산합니다.", actionTitle: nil, action: nil)
                }
                CalculatorNotice(text: "단순 계산 결과이며 투자 조언이 아닙니다.")
            }
        }
        .navigationTitle("물타기 계산기")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct AverageDownResult {
        let oldTotal: Double
        let addTotal: Double
        let totalQuantity: Double
        let newAveragePrice: Double
        let averageDiff: Double
        let profitRate: Double?
    }
}

private struct CalculatorDetailContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                    CalculatorNotice(text: "계산 결과는 참고용이며 투자 조언이나 거래 신호가 아닙니다.")
                }
                .padding(16)
                .padding(.bottom, newsScrollBottomPadding + proxy.safeAreaInsets.bottom + newsTabBarReservedHeight)
            }
            .background(Color.bg.ignoresSafeArea())
            .dismissKeyboardOnBackgroundTap()
        }
    }
}

private struct CalculatorInputField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textSecondary)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.mono(20, weight: .heavy))
                .foregroundColor(.themeText)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgTertiary)
                )
        }
        .padding(18)
        .background(sectionBackground)
    }
}

private struct CalculatorResultCard: View {
    let title: String
    let value: String
    let color: Color
    let rows: [(title: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(.textSecondary)
            Text(value)
                .font(.mono(26, weight: .heavy))
                .foregroundColor(color)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            VStack(spacing: 10) {
                ForEach(rows, id: \.title) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textMuted)
                        Spacer(minLength: 12)
                        Text(row.value)
                            .font(.mono(14, weight: .bold))
                            .foregroundColor(.themeText)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(18)
        .background(sectionBackground)
    }
}

private struct CalculatorNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textMuted)
            .lineSpacing(3)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sectionBackground)
    }
}

private func formattedBinding(
    _ binding: Binding<String>,
    maxIntegerDigits: Int = 15,
    maxFractionDigits: Int
) -> Binding<String> {
    Binding(
        get: { binding.wrappedValue },
        set: { value in
            let sanitized = USDTCalculatorViewModel.sanitizedDecimal(
                value,
                maxIntegerDigits: maxIntegerDigits,
                maxFractionDigits: maxFractionDigits
            )
            binding.wrappedValue = USDTCalculatorViewModel.formatDecimalInput(sanitized)
        }
    )
}

private func parse(_ value: String) -> Double? {
    USDTCalculatorViewModel.number(from: value)
}

private func formatPlain(_ value: Double, maxFractionDigits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)))
}

private func formatCurrency(_ value: Double) -> String {
    "₩" + value.formatted(.number.precision(.fractionLength(0...2)))
}

private func formatSignedCurrency(_ value: Double) -> String {
    let prefix = value >= 0 ? "+" : "-"
    return "\(prefix)₩\(abs(value).formatted(.number.precision(.fractionLength(0...2))))"
}

private func formatSignedPercent(_ value: Double) -> String {
    String(format: "%+.2f%%", value)
}

private func signedColor(_ value: Double) -> Color {
    if value > 0 { return .up }
    if value < 0 { return .down }
    return .textMuted
}

private struct TrendsContentView: View {
    let state: Loadable<MarketTrendsSnapshot>
    let category: NewsCategory
    let newsItems: [CryptoNewsItem]
    let selectedRange: MarketTrendRange
    let isVotingMarketSentiment: Bool
    let marketSentimentMessage: String?
    let onSelectRange: (MarketTrendRange) -> Void
    let onMarketVote: (String) -> Void
    let onRetry: () -> Void
    @State private var selectedMetric: MarketTrendMetric = .marketCap

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch state {
                    case .idle, .loading:
                        loadingCard(title: loadingTitle)
                    case .failed(let message):
                        stateCard(title: failedTitle, detail: message, actionTitle: "다시 시도", action: onRetry)
                    case .empty:
                        stateCard(title: emptyTitle, detail: "최신동향 데이터가 확보되면 표시합니다.", actionTitle: nil, action: nil)
                    case .loaded(let trends):
                        loadedContent(trends)
                        if let provider = trends.dataProvider, category == .trends {
                            Text("powered by \(provider)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textMuted)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, newsScrollBottomPadding + proxy.safeAreaInsets.bottom + newsTabBarReservedHeight)
            }
            .refreshable {
                onRetry()
            }
        }
    }

    private var emptyTitle: String {
        switch category {
        case .trends: return "표시할 최신동향이 없어요"
        case .calculator: return "표시할 계산기가 없어요"
        case .news: return "표시할 뉴스가 없어요"
        }
    }

    private var loadingTitle: String {
        switch category {
        case .trends: return "최신동향을 불러오는 중..."
        case .calculator: return "계산기를 준비하는 중..."
        case .news: return "뉴스를 불러오는 중..."
        }
    }

    private var failedTitle: String {
        switch category {
        case .trends: return "최신동향을 불러오지 못했어요"
        case .calculator: return "계산기를 표시하지 못했어요"
        case .news: return "뉴스를 불러오지 못했어요"
        }
    }

    @ViewBuilder
    private func loadedContent(_ trends: MarketTrendsSnapshot) -> some View {
        switch category {
        case .trends:
            marketSummaryCard(trends)
            marketPollCard(trends.marketPoll ?? .empty)
            newsSummaryCard(trends: trends, fallbackNews: newsItems)
            disclaimer
        case .calculator:
            EmptyView()
        case .news:
            EmptyView()
        }
    }

    private var marketRangePicker: some View {
        HStack(spacing: 8) {
            ForEach(MarketTrendRange.allCases) { range in
                Button {
                    onSelectRange(range)
                } label: {
                    Text(range.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selectedRange == range ? .black : .themeText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selectedRange == range ? Color.accent : Color.bgTertiary))
                }
                .buttonStyle(.plain)
            }
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

    private func marketSummaryCard(_ trends: MarketTrendsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("오늘 시장 요약")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.themeText)
                Spacer()
                if isStale(trends) {
                    Text("stale")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.yellow))
                }
            }
            Text(generatedHeadline(trends))
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.themeText)
                .fixedSize(horizontal: false, vertical: true)
            Text(marketSummaryDescription(trends))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textMuted)
                .lineSpacing(3)
            Text(sourceFooter(trends))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textMuted)
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func fearGreedMoodCard(_ trends: MarketTrendsSnapshot) -> some View {
        let value = trends.fearGreedIndex
        return VStack(alignment: .leading, spacing: 12) {
            Text("시장 분위기")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            HStack(alignment: .firstTextBaseline) {
                Text(value.map { "공포/탐욕 지수 \($0)" } ?? "공포/탐욕 지수 준비 중")
                    .font(.mono(21, weight: .heavy))
                    .foregroundColor(value == nil ? .textMuted : .accent)
                if let label = fearGreedLabel(value) {
                    Text("· \(label)")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.themeText)
                }
                Spacer()
            }
            Text(moodDescription(value))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
            HStack(spacing: 10) {
                moodChip("BTC", value: percentValueOptional(trends.btcDominance))
                moodChip("ETH", value: percentValueOptional(trends.ethDominance))
                moodChip("24h", value: compactCurrencyOptional(trends.totalVolume24h, currency: trends.currency))
            }
            Text("기준: 0~24 극단적 공포, 25~44 공포, 45~55 중립, 56~75 탐욕, 76~100 극단적 탐욕")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textMuted)
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func marketDashboardCard(_ trends: MarketTrendsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("시장 데이터 대시보드")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.textSecondary)
                Spacer()
                if isStale(trends) {
                    Text("stale")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.yellow))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                if trends.totalMarketCap != nil {
                    metric("시가총액", value: compactCurrencyOptional(trends.totalMarketCap, currency: trends.currency), subvalue: percent(trends.totalMarketCapChange24h), color: signedColor(trends.totalMarketCapChange24h))
                }
                if trends.totalVolume24h != nil || trends.marketCapVolumeSeries.last?.volume != nil {
                    metric("24h 거래량", value: compactCurrencyOptional(trends.totalVolume24h ?? trends.marketCapVolumeSeries.last?.volume, currency: trends.currency), subvalue: trends.currency ?? "통화 미확인", color: .themeText)
                }
                if trends.btcDominance != nil {
                    metric("BTC 도미넌스", value: percentValueOptional(trends.btcDominance), subvalue: nil, color: .themeText)
                }
                if trends.ethDominance != nil {
                    metric("ETH 도미넌스", value: percentValueOptional(trends.ethDominance), subvalue: nil, color: .themeText)
                }
                if trends.fearGreedIndex != nil {
                    metric("공포/탐욕 지수", value: trends.fearGreedIndex.map { "\($0) / 100" }, subvalue: fearGreedLabel(trends.fearGreedIndex), color: .accent)
                }
                if trends.altcoinIndex != nil {
                    metric("알트코인 지수", value: trends.altcoinIndex.map(String.init), subvalue: altSeasonLabel(trends.altcoinIndex), color: .accent)
                }
                if trends.btcLongShortRatio != nil {
                    metric("BTC 롱숏", value: percentValueOptional(trends.btcLongShortRatio), subvalue: nil, color: .up)
                }
            }
            unavailableMetrics(trends)
            if hasPartialMarketData(trends) {
                Text("일부 시장 데이터만 제공 중입니다.")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if trends.unavailableReasons.isEmpty == false {
                Text(trends.unavailableReasons.prefix(2).joined(separator: " · "))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .lineSpacing(2)
            }
            Text(sourceFooter(trends))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textMuted)
        }
        .padding(18)
        .background(sectionBackground)
        .onAppear {
            let available = marketAvailableMetricNames(trends)
            let unavailable = marketUnavailableMetricNames(trends)
            AppLogger.debug(.network, "[MarketDashboardRender] primaryMetrics=\(available.joined(separator: ",")) unavailableMetrics=\(unavailable.joined(separator: ",")) partialState=\(hasPartialMarketData(trends))")
        }
    }

    private func newsSummaryCard(trends: MarketTrendsSnapshot, fallbackNews: [CryptoNewsItem]) -> some View {
        let summaries = trends.topNews.prefix(3).map { item in
            (id: item.id, title: item.title, summary: item.summary, source: item.source, state: item.translationState, fallbackUsed: item.fallbackUsed)
        }
        let fallback = fallbackNews.prefix(3).map { item in
            (id: item.id, title: item.title, summary: Optional(item.summary), source: Optional(item.source), state: item.translationState, fallbackUsed: item.titleFallbackUsed || item.summaryFallbackUsed)
        }
        let items = summaries.isEmpty ? Array(fallback) : Array(summaries)
        return VStack(alignment: .leading, spacing: 12) {
            Text("주요 뉴스 요약")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            if items.isEmpty {
                Text("요약할 주요 뉴스가 없습니다.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textSecondary)
            } else {
                ForEach(items, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.themeText)
                            .lineLimit(2)
                        if item.source == nil, item.summary == nil {
                            EmptyView()
                        }
                        if let summary = item.summary, summary.isEmpty == false {
                            Text(summary)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .lineLimit(3)
                        }
                        if let source = item.source {
                            HStack(spacing: 6) {
                                Text(source)
                                if item.state == .translated, item.fallbackUsed == false, let badge = item.state.badgeText {
                                    Text(badge)
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textMuted)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func marketMetadataCard(_ trends: MarketTrendsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("데이터 기준")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            metadataRow("기준 시각", value: trends.asOf.map(PriceFormatter.formatReferenceDate) ?? "기준 시각 미제공")
            metadataRow("source", value: trends.dataProvider ?? "제공자 확인 중")
            if trends.fallbackUsed {
                Text("일부 시장 데이터는 거래소 스냅샷 기준으로 표시됩니다.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .lineSpacing(3)
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.themeText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func marketPollCard(_ poll: MarketPollSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("오늘 시장에 대해 어떻게 생각하세요?")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.themeText)
                Spacer()
                if isVotingMarketSentiment {
                    ProgressView()
                        .tint(.accent)
                }
            }
            HStack(spacing: 12) {
                Button {
                    onMarketVote("bullish")
                } label: {
                    pollButtonContent(title: "상승", icon: "arrow.up.right", color: .up, selected: poll.myVote == "bullish")
                }
                .buttonStyle(.plain)
                .disabled(isVotingMarketSentiment)
                Text("또는")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                Button {
                    onMarketVote("bearish")
                } label: {
                    pollButtonContent(title: "하락", icon: "arrow.down.right", color: .down, selected: poll.myVote == "bearish")
                }
                .buttonStyle(.plain)
                .disabled(isVotingMarketSentiment)
            }
            HStack {
                Text("\(poll.totalCount)명 참여")
                Spacer()
                Text("상승 \(ratioText(poll.bullishDisplayRatio)) · 하락 \(ratioText(poll.bearishDisplayRatio))")
            }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textMuted)
            if let myVote = poll.myVote {
                Text("내 선택: \(myVote == "bullish" ? "상승" : "하락")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accent)
            }
            if let marketSentimentMessage {
                Text(marketSentimentMessage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.down)
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func marketSeriesCard(_ series: [MarketTrendPoint], trends: MarketTrendsSnapshot, title: String) -> some View {
        let availableMetrics = MarketTrendMetric.allCases.filter { $0.pointCount(in: series) >= 1 }
        let metric = availableMetrics.contains(selectedMetric) ? selectedMetric : (availableMetrics.first ?? selectedMetric)
        let points = metric.values(from: series)
        let renderMode = MarketTrendRenderMode.mode(pointCount: points.count)
        let quality = marketTrendQuality(metric: metric, points: points)
        let changeText = marketTrendChangeText(metric: metric, points: points, rangeTitle: selectedRange.title)
        return VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            HStack(spacing: 8) {
                ForEach(MarketTrendMetric.allCases) { option in
                    let optionPointCount = option.pointCount(in: series)
                    Button {
                        selectedMetric = option
                    } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(metric == option ? .black : (optionPointCount >= 1 ? .themeText : .textMuted))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8).fill(metric == option ? Color.accent : Color.bgTertiary))
                    }
                    .buttonStyle(.plain)
                    .disabled(optionPointCount < 1)
                    .onAppear {
                        AppLogger.debug(.network, "[MarketTrendMetric] metric=\(option.rawValue) pointCount=\(optionPointCount) enabled=\(optionPointCount >= 1)")
                    }
                }
            }
            switch renderMode {
            case .chart:
                TrendLineView(points: points, color: .accent)
                    .frame(minHeight: 170)
                    .onAppear {
                        AppLogger.debug(.layout, "[MarketTrend] chartFrame height=170")
                    }
                HStack {
                    Text("\(metric.title): \(metricValueText(metric, series: series))")
                        .foregroundColor(.accent)
                    Spacer()
                    Text(changeText)
                        .foregroundColor(signedTrendColor(metric: metric, points: points))
                }
                .font(.system(size: 13, weight: .bold))
                HStack {
                    Text("포인트 \(points.count)개")
                        .foregroundColor(.textMuted)
                    Spacer()
                    Text("범위 \(selectedRange.title)")
                        .foregroundColor(.textMuted)
                }
                .font(.system(size: 13, weight: .bold))
                if quality.isFlat {
                    Text("변동폭이 작거나 데이터가 동일합니다.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
                if points.count < 7 {
                    Text("포인트 \(points.count)개만 제공되어 장기 추이 해석에는 제한이 있습니다.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
            case .mini:
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(metric.title): \(metricValueText(metric, series: series))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.accent)
                    Text("포인트 2개만 제공되어 추이 차트 대신 값 요약만 표시합니다.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgTertiary))
            case .empty:
                stateCard(title: "데이터 부족", detail: "현재 \(metric.title) 포인트가 \(points.count)개뿐이라 추이 차트를 표시하지 않습니다.", actionTitle: nil, action: nil)
            case .hidden:
                stateCard(title: "현재 제공 가능한 추이 데이터가 없습니다.", detail: "데이터가 3개 이상 제공되는 지표부터 차트로 표시합니다.", actionTitle: nil, action: nil)
            }
            Text("source \(trends.dataProvider ?? sourceLabelForSeries(series)) · updatedAt \(trends.asOf.map(PriceFormatter.formatReferenceDate) ?? "미확인") · \(seriesRangeText(series))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textMuted)
        }
        .padding(18)
        .background(sectionBackground)
        .onAppear {
            AppLogger.debug(.network, "[MarketTrend] points=\(series.count) metric=\(metric.rawValue) nonNil=\(points.count) renderMode=\(renderMode.rawValue)")
            if points.count < 3 {
                AppLogger.debug(.network, "WARN [MarketTrend] hidden reason=insufficientPoints metric=\(metric.rawValue)")
            }
        }
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

    private func hasMovers(_ movers: MarketMoversSnapshot) -> Bool {
        movers.topGainers.isEmpty == false || movers.topLosers.isEmpty == false || movers.topVolume.isEmpty == false
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
        Text("뉴스와 최신동향은 참고용 정보이며, 투자 조언이나 거래 신호가 아닙니다.")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textMuted)
            .lineSpacing(3)
            .padding(14)
            .background(sectionBackground)
    }

    private func metric(_ title: String, value: String?, subvalue: String?, color: Color) -> some View {
        let isAvailable = value != nil
        return VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value ?? "제공 안 됨")
                .font(.mono(isAvailable ? 20 : 14, weight: isAvailable ? .heavy : .semibold))
                .foregroundColor(isAvailable ? color : .textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let subvalue, isAvailable {
                Text(subvalue)
                    .font(.mono(13, weight: .bold))
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func moodChip(_ title: String, value: String?) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textMuted)
            Text(value ?? "준비 중")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(value == nil ? .textMuted : .themeText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgTertiary))
    }

    private func unavailableMetrics(_ trends: MarketTrendsSnapshot) -> some View {
        let rows = marketUnavailableMetricNames(trends)
        return Group {
            if rows.isEmpty == false {
                Text("준비 중: \(rows.joined(separator: " · "))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func marketAvailableMetricNames(_ trends: MarketTrendsSnapshot) -> [String] {
        [
            trends.totalMarketCap != nil ? "시가총액" : nil,
            trends.totalVolume24h != nil || trends.marketCapVolumeSeries.last?.volume != nil ? "24h 거래량" : nil,
            trends.btcDominance != nil ? "BTC 도미넌스" : nil,
            trends.ethDominance != nil ? "ETH 도미넌스" : nil,
            trends.fearGreedIndex != nil ? "공포/탐욕 지수" : nil,
            trends.altcoinIndex != nil ? "알트코인 지수" : nil,
            trends.btcLongShortRatio != nil ? "BTC 롱숏" : nil
        ].compactMap { $0 }
    }

    private func marketUnavailableMetricNames(_ trends: MarketTrendsSnapshot) -> [String] {
        [
            trends.totalMarketCap == nil ? "시가총액" : nil,
            trends.btcDominance == nil ? "BTC 도미넌스" : nil,
            trends.ethDominance == nil ? "ETH 도미넌스" : nil,
            trends.fearGreedIndex == nil ? "공포/탐욕 지수" : nil,
            trends.altcoinIndex == nil ? "알트코인 지수" : nil
        ].compactMap { $0 }
    }

    private func hasPartialMarketData(_ trends: MarketTrendsSnapshot) -> Bool {
        marketAvailableMetricNames(trends).count <= 1 && marketUnavailableMetricNames(trends).isEmpty == false
    }

    private func pollButtonContent(title: String, icon: String, color: Color, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundColor(selected ? .black : color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? color : Color.bgTertiary))
    }

    private func compactCurrency(_ value: Double?, currency: String? = nil) -> String {
        guard let value else { return "제공 안 됨" }
        let code = (currency ?? "KRW").uppercased()
        if code == "KRW" {
            return "KRW \(PriceFormatter.formatCompactKRWAmount(value))"
        }
        return "\(code) \(PriceFormatter.formatQty(value))"
    }

    private func compactCurrencyOptional(_ value: Double?, currency: String? = nil) -> String? {
        guard let value else { return nil }
        return compactCurrency(value, currency: currency)
    }

    private func percentValue(_ value: Double?) -> String {
        guard let value else { return "제공되지 않음" }
        return String(format: "%.2f%%", value)
    }

    private func percentValueOptional(_ value: Double?) -> String? {
        guard let value else { return nil }
        return String(format: "%.2f%%", value)
    }

    private func fearGreedLabel(_ value: Int?) -> String? {
        guard let value else { return nil }
        if value <= 24 { return "극단적 공포" }
        if value <= 44 { return "공포" }
        if value <= 55 { return "중립" }
        if value <= 75 { return "탐욕" }
        if value <= 100 { return "극단적 탐욕" }
        return "중립"
    }

    private func moodDescription(_ value: Int?) -> String {
        guard let value else { return "시장 심리 데이터가 준비되면 여기에 표시합니다." }
        if value <= 24 { return "위험 회피 심리가 매우 강한 구간입니다." }
        if value <= 44 { return "위험 회피 심리가 우세한 구간입니다." }
        if value <= 55 { return "공포와 탐욕이 균형을 이루는 구간입니다." }
        if value <= 75 { return "위험 선호가 우세한 구간입니다." }
        return "공포와 탐욕이 균형을 이루는 구간입니다."
    }

    private func generatedHeadline(_ trends: MarketTrendsSnapshot) -> String {
        if let headline = trends.latestHeadline, headline.isEmpty == false {
            return headline
        }
        if let change = trends.totalMarketCapChange24h {
            return change >= 0 ? "전체 시장 시가총액이 24시간 기준 상승 중입니다." : "전체 시장 시가총액이 24시간 기준 하락 중입니다."
        }
        if let label = fearGreedLabel(trends.fearGreedIndex) {
            return "현재 시장 심리는 \(label) 구간입니다."
        }
        return "시장 주요 지표를 확인하고 있습니다."
    }

    private func marketSummaryDescription(_ trends: MarketTrendsSnapshot) -> String {
        if let description = trends.summaryDescription, description.isEmpty == false {
            return description
        }
        let dominance = [
            trends.btcDominance.map { "BTC 도미넌스 \(String(format: "%.2f%%", $0))" },
            trends.ethDominance.map { "ETH 도미넌스 \(String(format: "%.2f%%", $0))" },
            trends.totalVolume24h.map { "24h 거래량 \(compactCurrency($0, currency: trends.currency))" }
        ].compactMap { $0 }
        return dominance.isEmpty ? "시장 핵심 지표가 제공되면 요약을 업데이트합니다." : dominance.joined(separator: " · ")
    }

    private func sourceFooter(_ trends: MarketTrendsSnapshot) -> String {
        let source = trends.dataProvider ?? "source 미확인"
        let updated = trends.asOf.map(PriceFormatter.formatReferenceDate) ?? "업데이트 시각 미확인"
        return "\(source) 기준 · \(updated) 업데이트"
    }

    private func isStale(_ trends: MarketTrendsSnapshot) -> Bool {
        guard let asOf = trends.asOf else { return false }
        return Date().timeIntervalSince(asOf) > 60 * 60 * 6
    }

    private func ratioText(_ ratio: Double) -> String {
        String(format: "%.0f%%", ratio * 100)
    }

    private func metricValueText(_ metric: MarketTrendMetric, series: [MarketTrendPoint]) -> String {
        switch metric {
        case .marketCap:
            return compactCurrency(series.last?.marketCap, currency: "KRW")
        case .volume:
            return compactCurrency(series.last?.volume, currency: "KRW")
        case .btcDominance:
            return percentValue(series.last?.btcDominance)
        case .ethDominance:
            return percentValue(series.last?.ethDominance)
        }
    }

    private func marketTrendChangeText(metric: MarketTrendMetric, points: [Double], rangeTitle: String) -> String {
        guard let first = points.first(where: { $0 != 0 }), let last = points.last else {
            return "\(rangeTitle) 변화율 미확인"
        }
        switch metric {
        case .marketCap, .volume:
            guard first != 0 else { return "\(rangeTitle) 변화율 미확인" }
            return "\(rangeTitle) \(String(format: "%+.1f%%", ((last - first) / first) * 100))"
        case .btcDominance, .ethDominance:
            return "\(rangeTitle) \(String(format: "%+.2f%%p", last - first))"
        }
    }

    private func signedTrendColor(metric: MarketTrendMetric, points: [Double]) -> Color {
        guard let first = points.first(where: { $0 != 0 }), let last = points.last else {
            return .textMuted
        }
        return signedColor(last - first)
    }

    private func marketTrendQuality(metric: MarketTrendMetric, points: [Double]) -> (isFlat: Bool, variationRate: Double) {
        guard points.count >= 3,
              let minValue = points.min(),
              let maxValue = points.max() else {
            return (false, 0)
        }
        if minValue == maxValue {
            return (true, 0)
        }
        let variation = (maxValue - minValue) / max(abs(minValue), abs(maxValue), 1)
        if variation < 0.001 {
            AppLogger.debug(.network, "WARN [MarketTrend] flatGraph metric=\(metric.rawValue) reason=variation_under_0_1_percent")
            return (true, variation)
        }
        return (false, variation)
    }

    private func seriesRangeText(_ series: [MarketTrendPoint]) -> String {
        let dates = series.compactMap(\.date)
        guard let first = dates.first, let last = dates.last else {
            return "범위 미확인"
        }
        return "\(PriceFormatter.formatReferenceDate(first)) - \(PriceFormatter.formatReferenceDate(last))"
    }

    private func sourceLabelForSeries(_ series: [MarketTrendPoint]) -> String {
        series.isEmpty ? "none" : "server"
    }

    private func halvingText(_ countdown: BitcoinHalvingCountdown) -> String {
        if let days = countdown.days {
            return "비트코인 반감기까지 약 \(days)일 남았습니다."
        }
        if let targetDate = countdown.targetDate {
            return "비트코인 반감기 예상일: \(PriceFormatter.formatReferenceDate(targetDate))"
        }
        return "비트코인 반감기 일정 데이터가 없습니다."
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
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.55))
                VStack {
                    Divider().background(Color.themeBorder.opacity(0.5))
                    Spacer()
                    Divider().background(Color.themeBorder.opacity(0.5))
                    Spacer()
                    Divider().background(Color.themeBorder.opacity(0.5))
                }
                .padding(.vertical, 16)
                Path { path in
                    let values = normalizedPoints
                    guard values.count >= 2 else { return }
                    let width = max(proxy.size.width - 24, 1)
                    let height = max(proxy.size.height - 28, 1)
                    let step = width / CGFloat(values.count - 1)
                    for index in values.indices {
                        let point = CGPoint(
                            x: 12 + CGFloat(index) * step,
                            y: 14 + height * (1 - CGFloat(values[index]))
                        )
                        if index == values.startIndex {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                ForEach(Array(normalizedPoints.enumerated()), id: \.offset) { index, value in
                    let width = max(proxy.size.width - 24, 1)
                    let height = max(proxy.size.height - 28, 1)
                    let step = normalizedPoints.count > 1 ? width / CGFloat(normalizedPoints.count - 1) : 0
                    let isEndpoint = index == 0 || index == normalizedPoints.count - 1
                    Circle()
                        .fill(color)
                        .opacity(isEndpoint || normalizedPoints.count <= 7 ? 1 : 0)
                        .frame(width: isEndpoint ? 8 : 5, height: isEndpoint ? 8 : 5)
                        .position(
                            x: 12 + CGFloat(index) * step,
                            y: 14 + height * (1 - CGFloat(value))
                        )
                }
            }
        }
        .accessibilityLabel("시가총액 거래량 추이 그래프")
    }

    private var normalizedPoints: [Double] {
        guard let minValue = points.min(), let maxValue = points.max(), maxValue > minValue else {
            return points.map { _ in 0.5 }
        }
        let range = maxValue - minValue
        let paddedMin = minValue - range * 0.08
        let paddedMax = maxValue + range * 0.08
        let paddedRange = paddedMax - paddedMin
        guard paddedRange > 0 else { return [] }
        return points.map { ($0 - paddedMin) / paddedRange }
    }
}

private struct NewsRow: View {
    let item: CryptoNewsItem
    let showsOriginal: Bool
    let onToggleOriginal: () -> Void

    private var text: (title: String, summary: String) {
        item.textVariant(showOriginal: showsOriginal)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(item.timeText)
                        .font(.mono(11, weight: .bold))
                        .foregroundColor(.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accent.opacity(0.12)))
                    Spacer()
                    Text(providerText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(text.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.themeText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if text.summary.isEmpty == false {
                    Text(text.summary)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(4)
                }
                tagRow
                HStack(spacing: 8) {
                    if showsOriginal == false,
                       item.hasTranslation,
                       item.translationState == .translated,
                       let translationStatusText = item.translationStatusText {
                        Text(translationStatusText)
                    }
                    if item.originalURL != nil {
                        Text("원문 링크")
                    }
                    if item.hasTranslation {
                        Button(showsOriginal ? "번역 보기" : "원문 보기", action: onToggleOriginal)
                            .foregroundColor(.accent)
                    }
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textMuted)
            }
        }
        .padding(14)
        .background(sectionBackground)
        .accessibilityLabel("뉴스 \(text.title)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = item.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Color.bgTertiary.overlay(Image(systemName: "newspaper").foregroundColor(.textMuted))
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var providerText: String {
        if let provider = item.provider, provider != item.source {
            return "\(item.source) · \(provider)"
        }
        return item.source
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
                ForEach(item.tags.prefix(4), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.textSecondary.opacity(0.12)))
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

func dateFilterBar(selectedDate: Date, onSelect: @escaping (Date) -> Void) -> some View {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
    let options: [(title: String, date: Date)] = [
        ("오늘", Date()),
        ("어제", calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()),
        ("2일 전", calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date())
    ]
    return ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            ForEach(options, id: \.title) { option in
                let selected = calendar.isDate(selectedDate, inSameDayAs: option.date)
                Button {
                    onSelect(option.date)
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selected ? .black : .themeText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accent : Color.bgTertiary))
                }
                .buttonStyle(.plain)
            }
            DatePicker(
                "날짜 선택",
                selection: Binding(get: { selectedDate }, set: onSelect),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .tint(.accent)
            .colorScheme(.dark)
        }
    }
}

func newsEmptyReasonText(_ reason: String?, symbol: String?) -> String {
    let displaySymbol = symbol.map(LivePublicContentRepository.normalizedSymbol)
    switch reason {
    case "no_related_news":
        return "관련 뉴스가 아직 없습니다."
    case "provider_limit":
        return "뉴스 공급원 제한으로 저장된 뉴스를 확인하고 있습니다."
    case "provider_error", "provider_unavailable":
        return "뉴스 공급원 응답이 불안정합니다."
    case "provider_limit_and_cache_empty":
        return "뉴스 공급원 제한으로 현재 표시할 뉴스가 없습니다."
    case "no_news_for_date", "date_no_news", "date_empty":
        return "선택한 날짜에 표시할 뉴스가 없습니다."
    case "cache_empty":
        return displaySymbol == nil ? "저장된 뉴스가 없습니다." : "저장된 관련 뉴스가 없습니다."
    default:
        if let displaySymbol {
            return "\(displaySymbol) 관련 뉴스가 아직 없습니다."
        }
        return "새 뉴스가 도착하면 날짜별로 표시합니다."
    }
}
