import SwiftUI

private let customTabBarReservedHeight: CGFloat = 92
private let coinDetailScrollBottomPadding: CGFloat = 188
private let coinCommunityScrollBottomPadding: CGFloat = 220

struct CoinInfoDetailView: View {
    let state: Loadable<CoinDetailInfo>
    let coin: CoinInfo
    let ticker: TickerData?
    let onRetry: () -> Void
    @State private var isDescriptionExpanded = false
    @State private var showsOriginalDescription = false

    var body: some View {
        GeometryReader { proxy in
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
                        descriptionCard(info)
                    }
                }
                .padding(16)
                .padding(.bottom, coinDetailScrollBottomPadding + proxy.safeAreaInsets.bottom + customTabBarReservedHeight)
            }
            .background(Color.bg.ignoresSafeArea())
        }
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
        let extraPeriods = info.availablePriceChangePeriods
            .filter { $0 != .h24 }
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("기간별 가격 변동률")
            VStack(spacing: 9) {
                if let change24h = info.priceChangePercentages[.h24] {
                    keyValue("24시간", value: percent(change24h), valueColor: signedColor(change24h))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(signedColor(change24h).opacity(0.12))
                        )
                }
                ForEach(extraPeriods, id: \.self) { period in
                    let value = info.priceChangePercentages[period]
                    keyValue(period.title, value: percent(value), valueColor: signedColor(value))
                }
                if extraPeriods.isEmpty {
                    Text(info.priceChangePercentages[.h24] == nil ? "변동률 데이터 준비 중" : "추가 기간 데이터 준비 중")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func descriptionCard(_ info: CoinDetailInfo) -> some View {
        let text = (showsOriginalDescription ? (info.originalDescription ?? info.description) : info.description)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDescription = text?.isEmpty == false
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("설명")
                Spacer()
                if showsOriginalDescription == false,
                   info.translatedDescription?.trimmedNonEmpty != nil,
                   info.descriptionTranslationState == .translated,
                   let badge = info.descriptionTranslationState.badgeText {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.bgTertiary))
                }
            }
            if let notice = info.descriptionFallbackNotice {
                Text(notice)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textMuted)
            }
            Text(hasDescription ? text! : "현재 제공 가능한 코인 설명이 없습니다.")
                .font(.system(size: 14))
                .foregroundColor(hasDescription ? .textSecondary : .textMuted)
                .lineSpacing(5)
                .lineLimit(isDescriptionExpanded ? nil : 8)
                .fixedSize(horizontal: false, vertical: true)
            if let text, text.count > 360 {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isDescriptionExpanded.toggle()
                    }
                } label: {
                    Text(isDescriptionExpanded ? "접기" : "더보기")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.accent)
                }
                .buttonStyle(.plain)
            }
            if info.translatedDescription?.trimmedNonEmpty != nil,
               info.originalDescription?.trimmedNonEmpty != nil {
                Button {
                    showsOriginalDescription.toggle()
                } label: {
                    Text(showsOriginalDescription ? "번역 보기" : "원문 보기")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.accent)
                }
                .buttonStyle(.plain)
            }
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
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    title
                    timeframeSelector
                    content
                }
                .padding(16)
                .padding(.bottom, coinDetailScrollBottomPadding + proxy.safeAreaInsets.bottom + customTabBarReservedHeight)
            }
            .background(Color.bg.ignoresSafeArea())
        }
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
    let submitMessage: String?
    let onFilter: (CoinCommunityFilter) -> Void
    let sortOrder: ContentSortOrder
    let onSort: (ContentSortOrder, CoinCommunityFilter) -> Void
    let onSubmit: () -> Void
    let onVote: (String) -> Void
    let onLike: (CoinCommunityPost) -> Void
    let onLoadComments: (String) -> Void
    let onSubmitComment: (String, String) -> Void
    let onFollow: (CoinCommunityPost) -> Void
    let onReportPost: (CoinCommunityPost, CommunityReportReason) -> Void
    let onBlockPostAuthor: (CoinCommunityPost) -> Void
    let onReportComment: (CoinCommunityComment, CommunityReportReason) -> Void
    let onBlockCommentAuthor: (CoinCommunityComment) -> Void
    let onRetry: () -> Void
    let isSubmitting: Bool
    let isVoting: Bool
    let likeRequestIds: Set<String>
    let followRequestUserIds: Set<String>
    let commentStates: [String: Loadable<[CoinCommunityComment]>]
    let commentSubmitIds: Set<String>
    let commentSortOrders: [String: ContentSortOrder]
    let onCommentSort: (String, ContentSortOrder) -> Void

    @State private var selectedFilter: CoinCommunityFilter = .all
    @State private var selectedCommentPost: CoinCommunityPost?
    @State private var actionPost: CoinCommunityPost?
    @State private var reportPost: CoinCommunityPost?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        voteSection
                        filterBar
                        content
                        disclaimer
                    }
                    .padding(16)
                    .padding(.bottom, communityListBottomInset(proxy.safeAreaInsets.bottom))
                }
                .background(Color.bg.ignoresSafeArea())
                .zIndex(0)
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                inputBar(bottomInset: proxy.safeAreaInsets.bottom)
                    .zIndex(2)
            }
            .sheet(item: $selectedCommentPost) { post in
                CommunityCommentsSheet(
                    post: post,
                    state: commentStates[post.id] ?? .idle,
                    isSubmitting: commentSubmitIds.contains(post.id),
                    onLoad: { onLoadComments(post.id) },
                    onSubmit: { content in onSubmitComment(post.id, content) },
                    onReport: onReportComment,
                    onBlockAuthor: onBlockCommentAuthor,
                    sortOrder: commentSortOrders[post.id] ?? .latest,
                    onSort: { sort in onCommentSort(post.id, sort) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog("게시글 관리", isPresented: Binding(get: { actionPost != nil }, set: { if !$0 { actionPost = nil } })) {
                Button("신고하기", role: .destructive) {
                    reportPost = actionPost
                    actionPost = nil
                }
                if actionPost?.authorId != nil, actionPost?.isOwnPost == false {
                    Button("작성자 차단하기", role: .destructive) {
                        if let post = actionPost {
                            onBlockPostAuthor(post)
                        }
                        actionPost = nil
                    }
                }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("신고 사유 선택", isPresented: Binding(get: { reportPost != nil }, set: { if !$0 { reportPost = nil } })) {
                ForEach(CommunityReportReason.allCases) { reason in
                    Button(reason.title, role: .destructive) {
                        if let post = reportPost {
                            onReportPost(post, reason)
                        }
                        reportPost = nil
                    }
                }
                Button("취소", role: .cancel) {}
            }
        }
    }

    private func communityListBottomInset(_ safeAreaBottom: CGFloat) -> CGFloat {
        let inputHeight: CGFloat = submitMessage == nil ? 78 : 104
        let tabReserve: CGFloat = isInputFocused ? 12 : 20
        let bottomInset = inputHeight + tabReserve + max(safeAreaBottom, 0)
        AppLogger.debug(.layout, "[DiscussionListInset] bottomInset=\(bottomInset) itemCount=\(state.value?.posts.count ?? 0) isEmpty=\((state.value?.posts.isEmpty ?? true))")
        return bottomInset
    }

    @ViewBuilder
    private var voteSection: some View {
        let vote = state.value?.vote ?? CoinVoteSnapshot(bullishCount: 0, bearishCount: 0, totalCount: 0, myVote: nil)
        VStack(alignment: .leading, spacing: 12) {
            Text("오늘 이 코인에 대해 어떻게 생각하세요?")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            HStack(spacing: 12) {
                voteButton(title: "상승", icon: "arrow.up.right", color: .up, selected: vote.myVote == "bullish") {
                    onVote("bullish")
                }
                .disabled(isVoting)
                Text("또는")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                voteButton(title: "하락", icon: "arrow.down.right", color: .down, selected: vote.myVote == "bearish") {
                    onVote("bearish")
                }
                .disabled(isVoting)
            }
            HStack {
                Text("\(vote.participantCount)명 참여")
                Spacer()
                Text("상승 \(ratioText(vote.bullishDisplayRatio)) · 하락 \(ratioText(vote.bearishDisplayRatio))")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.textMuted)
            if let myVote = vote.myVote {
                Text("내 선택: \(myVote == "bullish" ? "상승" : "하락")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accent)
            }
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
            Menu {
                ForEach([ContentSortOrder.latest, .oldest, .popular]) { sort in
                    Button(sort.title) {
                        onSort(sort, selectedFilter)
                    }
                }
            } label: {
                Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            .buttonStyle(.plain)
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
            stateCard(title: "아직 등록된 의견이 없습니다", detail: "첫 의견을 남겨보세요.", actionTitle: nil, action: nil)
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

    private func inputBar(bottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let submitMessage, submitMessage.isEmpty == false {
                Text(submitMessage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.down)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                                    .stroke(submitMessage == nil ? Color.themeBorder : Color.down.opacity(0.7), lineWidth: 1)
                            )
                    )
                    .focused($isInputFocused)
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.bg.opacity(0.98))
        .onAppear {
            let inputHeight: CGFloat = submitMessage == nil ? 78 : 104
            let bottomPadding = communityListBottomInset(bottomInset)
            AppLogger.debug(.layout, "[DiscussionLayout] tabBarHeight=\(customTabBarReservedHeight) safeAreaBottom=\(bottomInset) keyboardHeight=\(isInputFocused ? "shown" : "0") inputBarHeight=\(inputHeight) bottomPadding=\(bottomPadding)")
            AppLogger.debug(.layout, "[DiscussionInputPosition] mode=\(isInputFocused ? "keyboardShown" : "keyboardHidden") bottomOffset=8")
        }
        .onChange(of: isInputFocused) { _, focused in
            AppLogger.debug(.layout, "[DiscussionInputPosition] mode=\(focused ? "keyboardShown" : "keyboardHidden") bottomOffset=8")
        }
    }

    private func voteButton(title: String, icon: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(selected ? .black : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? color : Color.bgTertiary)
            )
        }
        .buttonStyle(.plain)
    }

    private func ratioText(_ ratio: Double) -> String {
        String(format: "%.0f%%", ratio * 100)
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
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .layoutPriority(1)
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
                if post.authorId != nil, post.isOwnPost == false {
                    Button(post.isFollowing ? "팔로잉" : "팔로우") {
                        onFollow(post)
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(post.isFollowing ? .themeText : .accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(post.isFollowing ? Color.bgTertiary : Color.accent.opacity(0.16)))
                    .disabled(post.authorId.map { followRequestUserIds.contains($0) } ?? true)
                }
                Button {
                    actionPost = post
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textMuted)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("게시글 더보기")
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
                Button {
                    onLike(post)
                } label: {
                    Label("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart")
                        .foregroundColor(post.isLiked ? .down : .textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(likeRequestIds.contains(post.id))
                Button {
                    selectedCommentPost = post
                    onLoadComments(post.id)
                } label: {
                    Label("\(post.commentCount)", systemImage: "bubble.left")
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
                Label(post.timeAgoText, systemImage: "clock")
                    .foregroundColor(.textMuted)
                Spacer()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.textSecondary)
        }
        .padding(16)
        .background(sectionBackground)
    }
}

private struct CommunityCommentsSheet: View {
    let post: CoinCommunityPost
    let state: Loadable<[CoinCommunityComment]>
    let isSubmitting: Bool
    let onLoad: () -> Void
    let onSubmit: (String) -> Void
    let onReport: (CoinCommunityComment, CommunityReportReason) -> Void
    let onBlockAuthor: (CoinCommunityComment) -> Void
    let sortOrder: ContentSortOrder
    let onSort: (ContentSortOrder) -> Void
    @State private var draft = ""
    @State private var actionComment: CoinCommunityComment?
    @State private var reportComment: CoinCommunityComment?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("댓글")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.themeText)
                Text(post.content)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .lineLimit(2)
                Menu {
                    ForEach([ContentSortOrder.latest, .oldest]) { sort in
                        Button(sort.title) {
                            onSort(sort)
                        }
                    }
                } label: {
                    Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.accent)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch state {
                    case .idle, .loading:
                        loadingCard(title: "댓글을 불러오는 중...")
                    case .failed(let message):
                        stateCard(title: "댓글을 불러오지 못했어요", detail: message, actionTitle: "다시 시도", action: onLoad)
                    case .empty:
                        stateCard(title: "아직 댓글이 없습니다", detail: "첫 댓글을 남겨보세요.", actionTitle: nil, action: nil)
                    case .loaded(let comments):
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(comment.authorName)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.themeText)
                                    Spacer()
                                    Text(comment.timeAgoText)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.textMuted)
                                    Button {
                                        actionComment = comment
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("댓글 더보기")
                                }
                                Text(comment.content)
                                    .font(.system(size: 14))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(sectionBackground)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            HStack(spacing: 10) {
                TextField("댓글을 남겨주세요.", text: $draft, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgTertiary))
                Button {
                    let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard content.isEmpty == false else { return }
                    onSubmit(content)
                    draft = ""
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.accent)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.accent)
                    }
                }
                .frame(width: 44, height: 44)
                .disabled(isSubmitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
            .background(Color.bg)
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear(perform: onLoad)
        .confirmationDialog("댓글 관리", isPresented: Binding(get: { actionComment != nil }, set: { if !$0 { actionComment = nil } })) {
            Button("댓글 신고하기", role: .destructive) {
                reportComment = actionComment
                actionComment = nil
            }
            if actionComment?.authorId != nil, actionComment?.isOwnComment == false {
                Button("댓글 작성자 차단하기", role: .destructive) {
                    if let comment = actionComment {
                        onBlockAuthor(comment)
                    }
                    actionComment = nil
                }
            }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("신고 사유 선택", isPresented: Binding(get: { reportComment != nil }, set: { if !$0 { reportComment = nil } })) {
            ForEach(CommunityReportReason.allCases) { reason in
                Button(reason.title, role: .destructive) {
                    if let comment = reportComment {
                        onReport(comment, reason)
                    }
                    reportComment = nil
                }
            }
            Button("취소", role: .cancel) {}
        }
    }
}

struct CoinNewsDetailView: View {
    let symbol: String
    let state: Loadable<[CryptoNewsItem]>
    let feedViewState: NewsFeedViewState
    let selectedDate: Date
    let sortOrder: ContentSortOrder
    let onSelectDate: (Date) -> Void
    let onSelectSort: (ContentSortOrder) -> Void
    let onRetry: () -> Void
    @State private var originalNewsItemIds: Set<String> = []

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("\(LivePublicContentRepository.normalizedSymbol(symbol)) 뉴스")
                    HStack {
                        dateFilterBar(selectedDate: selectedDate, onSelect: onSelectDate)
                        Spacer(minLength: 8)
                        newsSortMenu(sortOrder: sortOrder, onSelect: onSelectSort)
                    }
                    content
                    Text("코인 상세 뉴스는 해당 심볼 관련 뉴스만 표시합니다. 전체 시장 뉴스는 하단 뉴스 탭에서 확인할 수 있습니다.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                        .lineSpacing(3)
                        .padding(14)
                        .background(sectionBackground)
                }
                .padding(16)
                .padding(.bottom, coinCommunityScrollBottomPadding + proxy.safeAreaInsets.bottom + customTabBarReservedHeight)
            }
            .background(Color.bg.ignoresSafeArea())
            .refreshable {
                onRetry()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            loadingCard(title: "관련 뉴스를 불러오는 중...")
        case .failed(let message):
            stateCard(title: "관련 뉴스를 불러오지 못했어요", detail: message, actionTitle: "다시 시도", action: onRetry)
        case .empty:
            stateCard(title: "\(LivePublicContentRepository.normalizedSymbol(symbol)) 관련 뉴스가 아직 없습니다.", detail: coinNewsEmptyDetail, actionTitle: nil, action: nil)
        case .loaded(let items):
            ForEach(items) { item in
                coinNewsCard(item, showsOriginal: originalNewsItemIds.contains(item.id))
            }
        }
    }

    private var coinNewsEmptyDetail: String {
        var parts = [newsEmptyReasonText(feedViewState.emptyReason, symbol: symbol)]
        if let fallbackDate = feedViewState.latestFallbackDate {
            parts.append("가장 최근 뉴스: \(PriceFormatter.formatReferenceDate(fallbackDate))")
        } else if let latestAvailable = feedViewState.availableDates.sorted(by: >).first {
            parts.append("가장 최근 뉴스: \(PriceFormatter.formatReferenceDate(latestAvailable))")
        }
        if let source = feedViewState.source?.trimmedNonEmpty {
            parts.append("source \(source)")
        }
        if let cacheHit = feedViewState.cacheHit {
            parts.append("cacheHit \(cacheHit ? "true" : "false")")
        }
        if let providerStatus = feedViewState.providerStatus?.trimmedNonEmpty {
            parts.append("providerStatus \(providerStatus)")
        }
        return parts.joined(separator: " · ")
    }

    private func coinNewsCard(_ item: CryptoNewsItem, showsOriginal: Bool) -> some View {
        let text = item.textVariant(showOriginal: showsOriginal)
        return HStack(alignment: .top, spacing: 12) {
            if let url = item.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.bgTertiary.overlay(Image(systemName: "newspaper").foregroundColor(.textMuted))
                    }
                }
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(item.provider.map { "\(item.source) · \($0)" } ?? item.source)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if showsOriginal == false,
                       item.hasTranslation,
                       item.translationState == .translated,
                       let translationStatusText = item.translationStatusText {
                        Text(translationStatusText)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.bgTertiary))
                    }
                    Spacer()
                    Text(item.timeText)
                        .font(.mono(12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
                Text(text.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.themeText)
                    .lineLimit(3)
                if text.summary.isEmpty == false {
                    Text(text.summary)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                }
                HStack(spacing: 6) {
                    ForEach(item.relatedSymbols.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.themeText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.bgTertiary))
                    }
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.textSecondary.opacity(0.12)))
                    }
                    Spacer()
                    if let url = item.originalURL {
                        Link(destination: url) {
                            Label("열기", systemImage: "safari")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accent)
                        }
                    }
                    if item.hasTranslation {
                        Button(showsOriginal ? "번역 보기" : "원문 보기") {
                            toggleOriginal(for: item.id)
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.accent)
                    }
                }
            }
        }
        .padding(16)
        .background(sectionBackground)
    }

    private func toggleOriginal(for id: String) {
        if originalNewsItemIds.contains(id) {
            originalNewsItemIds.remove(id)
        } else {
            originalNewsItemIds.insert(id)
        }
    }
}

func sectionTitle(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 18, weight: .heavy))
        .foregroundColor(.themeText)
}

func newsSortMenu(sortOrder: ContentSortOrder, onSelect: @escaping (ContentSortOrder) -> Void) -> some View {
    Menu {
        ForEach([ContentSortOrder.latest, .oldest]) { sort in
            Button(sort.title) {
                onSelect(sort)
            }
        }
    } label: {
        Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.bgTertiary))
    }
    .buttonStyle(.plain)
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
