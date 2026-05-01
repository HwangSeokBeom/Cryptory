import SwiftUI

private let coinDetailScrollBottomPadding: CGFloat = 156
private let coinCommunityScrollBottomPadding: CGFloat = 190

struct CoinInfoDetailView: View {
    let state: Loadable<CoinDetailInfo>
    let coin: CoinInfo
    let ticker: TickerData?
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch state {
                case .idle, .loading:
                    loadingCard(title: "코인 정보를 불러오는 중...")
                case .failed(let message):
                    stateCard(title: "코인 정보를 불러오지 못했어요", detail: message, actionTitle: "다시 시도", action: onRetry)
                case .empty:
                    stateCard(title: "표시할 코인 정보가 없어요", detail: "서버에서 정보가 제공되면 여기에 표시됩니다.", actionTitle: nil, action: nil)
                case .loaded(let info):
                    providerNotice(info)
                    profileCard(info)
                    marketDataCard(info)
                    priceChangeCard(info)
                    descriptionCard(info.description)
                }
            }
            .padding(16)
            .padding(.bottom, coinDetailScrollBottomPadding)
        }
        .background(Color.bg.ignoresSafeArea())
    }

    private func providerNotice(_ info: CoinDetailInfo) -> some View {
        Text("source: \(info.dataProvider ?? info.provider ?? "제공자 확인 중")")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textMuted)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("데이터 제공자 \(info.dataProvider ?? info.provider ?? "제공자 확인 중")")
    }

    private func profileCard(_ info: CoinDetailInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SymbolImageView(
                    marketIdentity: coin.marketIdentity(exchange: .upbit),
                    symbol: coin.symbol,
                    canonicalSymbol: coin.canonicalSymbol,
                    imageURL: info.logoURL?.absoluteString ?? coin.iconURL,
                    hasImage: info.logoURL != nil ? true : coin.resolvedHasImage,
                    localAssetName: coin.localAssetName,
                    symbolImageState: AssetImageClient.shared.renderState(
                        for: AssetImageRequestDescriptor(
                            marketIdentity: coin.marketIdentity(exchange: .upbit),
                            symbol: coin.symbol,
                            canonicalSymbol: coin.canonicalSymbol,
                            imageURL: info.logoURL?.absoluteString ?? coin.iconURL,
                            hasImage: info.logoURL != nil ? true : coin.resolvedHasImage,
                            localAssetName: coin.localAssetName
                        )
                    ),
                    size: 38
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.name ?? coin.nameEn)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.themeText)
                    Text("심볼: \(info.displaySymbol ?? info.symbol)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                if let officialURL = info.officialURL {
                    Link(destination: officialURL) {
                        pill(icon: "globe", title: "홈페이지")
                    }
                }
                if let explorerURL = info.explorerURL {
                    Link(destination: explorerURL) {
                        pill(icon: "link", title: "익스플로러")
                    }
                }
            }

            if info.fallbackUsed || info.dataProvider == "Market snapshot" {
                Text("일부 정보는 거래소 스냅샷 기준으로 표시됩니다.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(sectionBackground)
    }

    private func marketDataCard(_ info: CoinDetailInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("시장 데이터")
            keyValue("현재가", value: krwPrice(info.currentPrice ?? ticker?.price), placeholder: "데이터 준비 중")
            keyValue("24시간 고가", value: krwPrice(info.high24h), valueColor: .up, placeholder: "제공되지 않음")
            keyValue("24시간 저가", value: krwPrice(info.low24h), valueColor: .down, placeholder: "제공되지 않음")
            keyValue("24시간 거래량", value: quantity(info.volume24h, symbol: info.symbol), placeholder: "제공되지 않음")
            keyValue("24시간 거래대금", value: currency(info.tradeValue24h ?? ticker?.volume), placeholder: "제공되지 않음")
            let change24h = info.priceChangePercentages[.h24] ?? ticker?.change
            keyValue("24시간 변동률", value: percent(change24h), valueColor: signedColor(change24h), placeholder: "제공되지 않음")
            keyValue("시가총액", value: currency(info.marketCap), placeholder: "CoinGecko 매칭 대기")
            keyValue("시가총액 순위", value: info.rank.map(PriceFormatter.formatRank), placeholder: "제공되지 않음")
            keyValue("유통 공급량", value: quantity(info.circulatingSupply, symbol: info.symbol), placeholder: "제공되지 않음")
            keyValue("총 공급량", value: quantity(info.totalSupply, symbol: info.symbol), placeholder: "제공되지 않음")
            keyValue("최대 공급량", value: quantity(info.maxSupply, symbol: info.symbol), placeholder: "제공되지 않음")
            keyValue("역대 최고가", value: currency(info.allTimeHigh), placeholder: "제공되지 않음")
            keyValue("역대 최저가", value: currency(info.allTimeLow), placeholder: "제공되지 않음")
            keyValue("기준 시각", value: info.marketAsOf.map(PriceFormatter.formatReferenceDate), placeholder: "기준 시각 미제공")
        }
        .padding(16)
        .background(sectionBackground)
    }

    private func priceChangeCard(_ info: CoinDetailInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("기간별 가격 변동률")
            VStack(spacing: 9) {
                ForEach(CoinPriceChangePeriod.allCases, id: \.self) { period in
                    let value = info.priceChangePercentages[period]
                    keyValue(period.title, value: percent(value), valueColor: signedColor(value))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgTertiary)
            )
        }
        .padding(16)
        .background(sectionBackground)
    }

    private func descriptionCard(_ description: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("설명")
            Text(description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? description! : "프로젝트 설명 정보가 아직 제공되지 않았습니다.")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(sectionBackground)
    }

    private func keyValue(_ label: String, value: String?, valueColor: Color = .themeText, placeholder: String = "제공되지 않음") -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
            Spacer(minLength: 12)
            Text(value ?? placeholder)
                .font(.mono(14, weight: .semibold))
                .foregroundColor(value == nil ? .textMuted : valueColor)
                .multilineTextAlignment(.trailing)
                .minimumScaleFactor(0.75)
        }
    }

    private func pill(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.themeText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.bgTertiary))
    }
}

struct CoinAnalysisDetailView: View {
    let state: Loadable<CoinAnalysisSnapshot>
    let selectedTimeframe: CoinAnalysisTimeframe
    let onSelectTimeframe: (CoinAnalysisTimeframe) -> Void
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                title
                timeframeSelector
                content
            }
            .padding(16)
            .padding(.bottom, coinDetailScrollBottomPadding)
        }
        .background(Color.bg.ignoresSafeArea())
    }

    private var title: some View {
        Text("테크니컬 분석")
            .font(.system(size: 22, weight: .heavy))
            .foregroundColor(.themeText)
    }

    private var timeframeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CoinAnalysisTimeframe.allCases) { timeframe in
                    Button {
                        onSelectTimeframe(timeframe)
                    } label: {
                        Text(timeframe.title)
                            .font(.system(size: 14, weight: selectedTimeframe == timeframe ? .bold : .semibold))
                            .foregroundColor(selectedTimeframe == timeframe ? .white : .textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedTimeframe == timeframe ? Color.bgTertiary : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(timeframe.title) 분석 시간 프레임")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            loadingCard(title: "분석 정보를 계산하는 중...")
        case .failed(let message):
            stateCard(title: "분석 정보를 불러오지 못했어요", detail: message, actionTitle: "다시 시도", action: onRetry)
        case .empty:
            stateCard(title: "분석 정보가 없어요", detail: "캔들 데이터가 확보되면 참고용 분석을 표시합니다.", actionTitle: nil, action: nil)
        case .loaded(let snapshot):
            analysisCard(snapshot)
            indicatorsCard(snapshot)
            if snapshot.fallbackUsed {
                Text("일부 지표는 최근 시세 기반 fallback으로 계산되었습니다.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .lineSpacing(3)
                    .padding(14)
                    .background(sectionBackground)
            }
            Text(snapshot.disclaimer)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textMuted)
                .lineSpacing(3)
                .padding(14)
                .background(sectionBackground)
        }
    }

    private func analysisCard(_ snapshot: CoinAnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.summaryLabel.rawValue)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(color(for: snapshot.summaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("최근 \(snapshot.timeframe.title) 기준 참고 지표입니다.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
                Spacer()
                if let asOf = snapshot.asOf {
                    Text(PriceFormatter.formatReferenceDate(asOf))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textMuted)
                        .multilineTextAlignment(.trailing)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.bgTertiary)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color(for: snapshot.summaryLabel))
                        .frame(width: max(8, proxy.size.width * min(max((snapshot.score + 1) / 2, 0), 1)))
                }
            }
            .frame(height: 10)
            .accessibilityLabel("분석 점수 \(snapshot.summaryLabel.rawValue)")

            HStack {
                countColumn(title: "하락 신호 수", count: snapshot.bearishCount, color: .down)
                Spacer()
                countColumn(title: "중립 지표 수", count: snapshot.neutralCount, color: .textMuted)
                Spacer()
                countColumn(title: "상승 신호 수", count: snapshot.bullishCount, color: .up)
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func indicatorsCard(_ snapshot: CoinAnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("시장 참고 지표")
            ForEach(snapshot.indicators) { indicator in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(indicator.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.themeText)
                        Text(indicator.valueText)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                        if let description = indicator.description {
                            Text(description)
                                .font(.system(size: 12))
                                .foregroundColor(.textMuted)
                                .lineSpacing(2)
                        }
                    }
                    Spacer()
                    Text(indicator.label.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(color(for: indicator.label))
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(sectionBackground)
    }

    private func countColumn(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
            Text("\(count)")
                .font(.mono(26, weight: .heavy))
                .foregroundColor(color)
        }
    }

    private func color(for label: CoinAnalysisSummaryLabel) -> Color {
        switch label {
        case .strongBearish, .bearish:
            return .down
        case .strongBullish, .bullish:
            return .up
        case .neutral, .reference:
            return .textMuted
        }
    }
}

struct CoinCommunityDetailView: View {
    let symbol: String
    let state: Loadable<CoinCommunitySnapshot>
    @Binding var draft: String
    let onFilter: (CoinCommunityFilter) -> Void
    let onSubmit: () -> Void
    let onVote: (String) -> Void
    let onRetry: () -> Void
    let isSubmitting: Bool
    let isVoting: Bool

    @State private var selectedFilter: CoinCommunityFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    voteSection
                    filterBar
                    content
                    disclaimer
                }
                .padding(16)
                .padding(.bottom, coinCommunityScrollBottomPadding)
            }
            .background(Color.bg.ignoresSafeArea())
        }
        .safeAreaInset(edge: .bottom) {
            inputBar
        }
    }

    @ViewBuilder
    private var voteSection: some View {
        let vote = state.value?.vote ?? CoinVoteSnapshot(bullishCount: 0, bearishCount: 0, totalCount: 0, myVote: nil)
        VStack(alignment: .leading, spacing: 12) {
            Text("오늘 이 코인에 대해 어떻게 생각하세요?")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            HStack(spacing: 12) {
                voteButton(title: "상승", icon: "arrow.up.right", color: .up) {
                    onVote("bullish")
                }
                .disabled(isVoting)
                Text("또는")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                voteButton(title: "하락", icon: "arrow.down.right", color: .down) {
                    onVote("bearish")
                }
                .disabled(isVoting)
            }
            Text("\(vote.participantCount)명 참여")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textMuted)
        }
        .padding(16)
        .background(sectionBackground)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(CoinCommunityFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                    onFilter(filter)
                } label: {
                    Text(filter.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(selectedFilter == filter ? .themeText : .textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedFilter == filter ? Color.bgTertiary : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(selectedFilter == filter ? Color.themeText : Color.themeBorder, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("최신순")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textMuted)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            loadingCard(title: "커뮤니티 의견을 불러오는 중...")
        case .failed(let message):
            stateCard(title: "커뮤니티를 불러오지 못했어요", detail: message, actionTitle: "다시 시도", action: onRetry)
        case .empty:
            stateCard(title: "아직 등록된 의견이 없습니다", detail: "첫 의견을 남겨주세요.", actionTitle: nil, action: nil)
        case .loaded(let snapshot):
            if snapshot.posts.isEmpty {
                stateCard(title: "아직 등록된 의견이 없습니다", detail: "첫 의견을 남겨보세요.", actionTitle: nil, action: nil)
            } else {
                ForEach(snapshot.posts) { post in
                    communityPostCard(post)
                }
            }
        }
    }

    private var disclaimer: some View {
        Text("커뮤니티 의견은 사용자 의견이며 투자 조언이 아닙니다.")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textMuted)
            .lineSpacing(3)
            .padding(14)
            .background(sectionBackground)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("의견을 남겨주세요.", text: $draft, axis: .vertical)
                .font(.system(size: 14))
                .foregroundColor(.themeText)
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.bgTertiary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.themeBorder, lineWidth: 1)
                        )
                )
            Button(action: onSubmit) {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(.accent)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.accent)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .disabled(isSubmitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("의견 보내기")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 34)
        .background(Color.bg.opacity(0.98))
    }

    private func voteButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.bgTertiary)
            )
        }
        .buttonStyle(.plain)
    }

    private func communityPostCard(_ post: CoinCommunityPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.bgTertiary)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text(String(post.authorName.prefix(1)))
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.themeText)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(post.authorName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.themeText)
                        if let badge = post.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accent.opacity(0.12)))
                        }
                    }
                    Text(post.timeAgoText)
                        .font(.system(size: 12))
                        .foregroundColor(.textMuted)
                }
                Spacer()
                Button("팔로우") {}
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accent.opacity(0.16)))
            }

            Text(post.content)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.themeText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("\(post.symbol)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.themeText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.bgTertiary))
                ForEach(post.tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
            }

            HStack(spacing: 18) {
                Label("\(post.likeCount)", systemImage: "heart")
                Label("\(post.commentCount)", systemImage: "bubble.left")
                Spacer()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.textSecondary)
        }
        .padding(16)
        .background(sectionBackground)
    }
}

func sectionTitle(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 18, weight: .heavy))
        .foregroundColor(.themeText)
}

func loadingCard(title: String) -> some View {
    HStack(spacing: 10) {
        ProgressView()
            .tint(.accent)
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(sectionBackground)
}

func stateCard(title: String, detail: String, actionTitle: String?, action: (() -> Void)?) -> some View {
    VStack(spacing: 10) {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.themeText)
        Text(detail)
            .font(.system(size: 13))
            .foregroundColor(.textSecondary)
            .multilineTextAlignment(.center)
        if let actionTitle, let action {
            Button(actionTitle, action: action)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.accent)
        }
    }
    .frame(maxWidth: .infinity)
    .padding(18)
    .background(sectionBackground)
}

var sectionBackground: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.themeBorder, lineWidth: 1)
        )
}

func currency(_ value: Double?) -> String? {
    guard let value else { return nil }
    return PriceFormatter.formatCompactKRWAmount(value)
}

func quantity(_ value: Double?) -> String? {
    guard let value else { return nil }
    return PriceFormatter.formatQty(value)
}

func quantity(_ value: Double?, symbol: String) -> String? {
    guard let value else { return nil }
    return "\(PriceFormatter.formatQty(value)) \(symbol)"
}

func krwPrice(_ value: Double?) -> String? {
    guard let value else { return nil }
    return PriceFormatter.formatKRW(value)
}

func percent(_ value: Double?) -> String? {
    guard let value else { return nil }
    return PriceFormatter.formatPercent(value)
}

func signedColor(_ value: Double?) -> Color {
    guard let value else { return .textMuted }
    return value >= 0 ? .up : .down
}
