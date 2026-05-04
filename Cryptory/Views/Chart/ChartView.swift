import SwiftUI

struct ChartView: View {
    @ObservedObject var vm: CryptoViewModel
    @State private var isChartSettingsPresented = false
    private let instanceID: Int

    init(vm: CryptoViewModel) {
        self.vm = vm
        let instanceID = AppLogger.nextInstanceID(scope: "ChartView")
        self.instanceID = instanceID
        AppLogger.debug(.lifecycle, "[ViewIdentity] ChartView stableOwner=\(vm.debugOwnerID) viewInstance=\(instanceID)")
    }

    var body: some View {
        Group {
            if vm.isSelectedExchangeChartUnsupported {
                unsupportedState
            } else if let coin = vm.selectedCoin {
                VStack(spacing: 0) {
                    coinHeader(coin)
                    detailTabBar
                    detailContent(for: coin)
                }
                .onAppear {
                    AppLogger.debug(
                        .lifecycle,
                        "ChartView onAppear #\(instanceID) \(coin.marketIdentity(exchange: vm.exchange, quoteCurrency: vm.selectedQuoteCurrency).logFields) interval=\(vm.chartPeriod)"
                    )
                    vm.loadCoinDetailContent(symbol: coin.symbol)
                }
                .onDisappear {
                    AppLogger.debug(.lifecycle, "ChartView onDisappear #\(instanceID)")
                }
            } else {
                emptyState
            }
        }
        .background(
            ChartSettingsSheetPresenter(
                isPresented: $isChartSettingsPresented,
                state: vm.chartSettingsState,
                currentSymbol: vm.selectedCoin?.symbol,
                comparisonCandidates: vm.chartComparisonCandidates,
                onStateChange: { state in
                    vm.applyChartSettings(state)
                }
            )
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $vm.isPriceAlertSheetPresented) {
            PriceAlertSheet(
                draft: $vm.priceAlertDraft,
                isSaving: vm.isSavingPriceAlert,
                message: vm.priceAlertLoadMessage,
                onSave: vm.savePriceAlertDraft,
                onDelete: vm.deleteActivePriceAlert
            )
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.bg)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.textSecondary)
            Text("시세 탭에서 코인을 선택해주세요")
                .font(.system(size: 14))
                .foregroundColor(.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.textSecondary)
            Text("이 거래소는 차트를 지원하지 않아요")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.themeText)
            Text("선택한 거래소에서 차트 데이터를 아직 제공하지 않아요.")
                .font(.system(size: 12))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func coinHeader(_ coin: CoinInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SymbolImageView(
                    marketIdentity: coin.marketIdentity(exchange: vm.exchange, quoteCurrency: vm.selectedQuoteCurrency),
                    symbol: coin.symbol,
                    canonicalSymbol: coin.canonicalSymbol,
                    imageURL: coin.iconURL,
                    hasImage: coin.resolvedHasImage,
                    localAssetName: coin.localAssetName,
                    symbolImageState: AssetImageClient.shared.renderState(
                        for: AssetImageRequestDescriptor(
                            marketIdentity: coin.marketIdentity(exchange: vm.exchange, quoteCurrency: vm.selectedQuoteCurrency),
                            symbol: coin.symbol,
                            canonicalSymbol: coin.canonicalSymbol,
                            imageURL: coin.iconURL,
                            hasImage: coin.resolvedHasImage,
                            localAssetName: coin.localAssetName
                        )
                    ),
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(coin.displaySymbol)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(.themeText)
                        Text(coin.name)
                            .font(.system(size: 12))
                            .foregroundColor(.textMuted)
                    }

                    let ticker = vm.headerSummaryState.value ?? vm.currentTicker
                    let isUp = (ticker?.change ?? 0) >= 0

                    if let ticker {
                        Text(PriceFormatter.formatPrice(ticker.price))
                            .font(.mono(26, weight: .heavy))
                            .foregroundColor(isUp ? .up : .down)
                    } else {
                        Text("—")
                            .font(.mono(26, weight: .heavy))
                            .foregroundColor(.textMuted)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 10, weight: .bold))
                            .opacity(ticker == nil ? 0 : 1)
                        Text(ticker.map { String(format: "%@%.2f%%", $0.change >= 0 ? "+" : "", $0.change) } ?? "—")
                            .font(.mono(13))
                    }
                    .foregroundColor(ticker == nil ? .textMuted : (isUp ? .up : .down))
                }

                Spacer()

                Button {
                    vm.toggleFavorite(coin.symbol)
                } label: {
                    Image(systemName: vm.favCoins.contains(coin.symbol) ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(vm.favCoins.contains(coin.symbol) ? .accent : .textMuted)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.bgSecondary)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vm.favCoins.contains(coin.symbol) ? "관심 코인 해제" : "관심 코인 추가")

                Button {
                    vm.presentPriceAlertSheet()
                } label: {
                    Image(systemName: vm.activePriceAlert?.isActive == true ? "bell.badge.fill" : "bell.badge")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(vm.activePriceAlert?.isActive == true ? .accent : .textMuted)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.bgSecondary)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("가격 알림")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.themeBorder),
            alignment: .bottom
        )
    }

    private var detailTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 20) {
                ForEach(CoinDetailTab.allCases) { tab in
                    Button {
                        vm.selectedCoinDetailTab = tab
                    } label: {
                        VStack(spacing: 0) {
                            Text(tab.title)
                                .font(.system(size: 15, weight: vm.selectedCoinDetailTab == tab ? .heavy : .bold))
                                .foregroundColor(vm.selectedCoinDetailTab == tab ? .themeText : .textMuted)
                                .lineLimit(1)
                                .frame(height: 22, alignment: .center)
                                .padding(.top, 11)
                                .padding(.bottom, 10)
                            Rectangle()
                                .fill(vm.selectedCoinDetailTab == tab ? Color.accent : Color.clear)
                                .frame(height: 3)
                                .clipShape(Capsule())
                        }
                        .frame(minWidth: 54)
                        .frame(height: 46, alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tab.title) 탭")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54, alignment: .bottom)
        }
        .frame(height: 54)
        .clipped(antialiased: false)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.themeBorder),
            alignment: .bottom
        )
        .background(Color.bg)
    }

    @ViewBuilder
    private func detailContent(for coin: CoinInfo) -> some View {
        switch vm.selectedCoinDetailTab {
        case .info:
            CoinInfoDetailView(
                state: vm.coinInfoState,
                coin: coin,
                ticker: vm.headerSummaryState.value ?? vm.currentTicker,
                onRetry: { vm.loadCoinInfo(symbol: coin.symbol, forceRefresh: true) }
            )
        case .chart:
            chartTabContent(for: coin)
        case .analysis:
            CoinAnalysisDetailView(
                state: vm.coinAnalysisState,
                selectedTimeframe: vm.selectedAnalysisTimeframe,
                onSelectTimeframe: vm.selectAnalysisTimeframe,
                onRetry: {
                    vm.loadCoinAnalysis(
                        symbol: coin.symbol,
                        timeframe: vm.selectedAnalysisTimeframe,
                        forceRefresh: true
                    )
                }
            )
        case .community:
            CoinCommunityDetailView(
                symbol: coin.symbol,
                state: vm.coinCommunityState,
                draft: $vm.communityDraft,
                submitMessage: vm.communitySubmitMessage,
                onFilter: { filter in
                    vm.loadCoinCommunity(symbol: coin.symbol, filter: filter, forceRefresh: true)
                },
                sortOrder: vm.communitySortOrder,
                onSort: { sort, filter in
                    vm.selectCommunitySort(sort, symbol: coin.symbol, filter: filter)
                },
                onSubmit: {
                    vm.submitCoinCommunityPost(symbol: coin.symbol)
                },
                onVote: { direction in
                    vm.voteCoinOpinion(symbol: coin.symbol, direction: direction)
                },
                onLike: { post in
                    vm.toggleCommunityLike(symbol: coin.symbol, post: post)
                },
                onLoadComments: { postId in
                    vm.loadCommunityComments(symbol: coin.symbol, postId: postId)
                },
                onSubmitComment: { postId, content in
                    vm.submitCommunityComment(symbol: coin.symbol, postId: postId, content: content)
                },
                onFollow: { post in
                    vm.toggleAuthorFollow(post: post)
                },
                onReportPost: { post, reason in
                    vm.reportPost(post, reason: reason)
                },
                onBlockPostAuthor: { post in
                    vm.blockAuthor(of: post)
                },
                onReportComment: { comment, reason in
                    vm.reportComment(comment, reason: reason)
                },
                onBlockCommentAuthor: { comment in
                    vm.blockAuthor(of: comment)
                },
                onRetry: {
                    vm.loadCoinCommunity(symbol: coin.symbol, filter: .all, forceRefresh: true)
                },
                isSubmitting: vm.isSubmittingCommunityPost,
                isVoting: vm.isVotingCoinOpinion,
                likeRequestIds: vm.communityLikeRequestIds,
                followRequestUserIds: vm.communityFollowRequestUserIds,
                commentStates: vm.communityCommentsByPostId,
                commentSubmitIds: vm.communityCommentSubmitIds,
                commentSortOrders: vm.commentSortOrdersByPostId,
                onCommentSort: { postId, sort in
                    vm.selectCommentSort(sort, symbol: coin.symbol, postId: postId)
                }
            )
        case .news:
            CoinNewsDetailView(
                symbol: coin.symbol,
                state: vm.coinNewsState,
                feedViewState: vm.coinNewsFeedViewState,
                selectedDate: vm.coinNewsSelectedDate,
                sortOrder: vm.coinNewsSortOrder,
                onSelectDate: { date in
                    vm.selectCoinNewsDate(date, symbol: coin.symbol)
                },
                onSelectSort: { sort in
                    vm.selectCoinNewsSort(sort, symbol: coin.symbol)
                },
                onRetry: {
                    vm.loadCoinNews(symbol: coin.symbol, forceRefresh: true)
                }
            )
        }
    }

    private func chartTabContent(for coin: CoinInfo) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ScreenStatusBannerView(viewState: vm.chartStatusViewState)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    PeriodSelector(vm: vm) {
                        isChartSettingsPresented = true
                    }
                    candleSection
                    stats24H
                    coinMarketDataSection(coin)
                    orderbookSection
                    tradesSection
                    chartDisclaimer
                }
                .padding(.bottom, 188 + proxy.safeAreaInsets.bottom + 92)
            }
            .onAppear {
                AppLogger.debug(
                    .lifecycle,
                    "[ChartLayoutOrder] screen=coin_detail selectedTab=chart order=tabs,timeframe,chart,auxiliaryData chartExists=true auxiliaryBelowChart=true"
                )
            }
        }
    }
    @ViewBuilder
    private var candleSection: some View {
        switch vm.candlesState {
        case .idle, .loading:
            loadingSectionCard(
                title: "차트 데이터를 불러오는 중...",
                height: 220
            )

        case .failed(let message):
            sectionStateCard(
                icon: "exclamationmark.triangle.fill",
                title: "차트 데이터를 불러오지 못했어요",
                description: message,
                height: 220,
                actionTitle: "다시 시도",
                action: retryChartData
            )

        case .unavailable(let message):
            sectionStateCard(
                icon: "chart.xyaxis.line",
                title: "차트 데이터를 일시적으로 불러올 수 없어요",
                description: message,
                height: 220,
                actionTitle: "다시 시도",
                action: retryChartData
            )

        case .empty:
            sectionStateCard(
                icon: "chart.bar.xaxis",
                title: "차트 데이터가 아직 없어요",
                description: "거래소에서 캔들 데이터가 도착하면 바로 표시할게요.",
                height: 220,
                actionTitle: "다시 시도",
                action: retryChartData
            )

        case .loaded, .staleCache, .refreshing:
            VStack(spacing: 8) {
                if let warningMessage = vm.candlesState.warningMessage {
                    sectionWarningBanner(warningMessage)
                        .padding(.horizontal, 16)
                }
                GeometryReader { geo in
                    ZStack(alignment: .topTrailing) {
                        CandleChartView(
                            candles: vm.candles,
                            width: min(geo.size.width - 16, 390),
                            height: 220,
                            settings: vm.appliedChartSettingsState,
                            comparisonSeries: vm.comparedChartSeries,
                            currentPrice: vm.currentPrice,
                            bestAskPrice: vm.orderbook?.asks.first?.price,
                            bestBidPrice: vm.orderbook?.bids.first?.price
                        )
                        .frame(maxWidth: .infinity)

                        if case .refreshing = vm.candlesState {
                            ProgressView()
                                .tint(.accent)
                                .padding(10)
                        }
                    }
                }
                .frame(height: 220)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }

    private var stats24H: some View {
        HStack(spacing: 8) {
            let ticker = vm.marketStatsState.value ?? vm.currentTicker
            statItem(label: "고가(24H)", value: ticker.map { PriceFormatter.formatPrice($0.high24) } ?? "—", color: .up)
            statItem(label: "저가(24H)", value: ticker.map { PriceFormatter.formatPrice($0.low24) } ?? "—", color: .down)
            statItem(label: "거래량(24H)", value: ticker.map { PriceFormatter.formatVolume($0.volume) } ?? "—", color: .themeText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var chartDisclaimer: some View {
        Text("차트와 시장 데이터는 참고용 정보이며, 투자 조언이나 거래 신호가 아닙니다.")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.textMuted)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private func coinMarketDataSection(_ coin: CoinInfo) -> some View {
        let info = vm.coinInfoState.value
        let ticker = vm.marketStatsState.value ?? vm.currentTicker
        return VStack(alignment: .leading, spacing: 14) {
            Text("차트 보조 데이터")
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(.themeText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                marketMetric("현재가", krwPrice(info?.currentPrice ?? ticker?.price) ?? "데이터 준비 중", color: info?.currentPrice == nil && ticker == nil ? .textMuted : .themeText)
                marketMetric("24시간 고가", krwPrice(info?.high24h ?? ticker?.high24) ?? "제공되지 않음", color: info?.high24h == nil && ticker == nil ? .textMuted : .up)
                marketMetric("24시간 저가", krwPrice(info?.low24h ?? ticker?.low24) ?? "제공되지 않음", color: info?.low24h == nil && ticker == nil ? .textMuted : .down)
                marketMetric("24시간 거래대금", currency(info?.tradeValue24h ?? ticker?.volume) ?? "제공되지 않음", color: .themeText)
            }

            if let change = ticker?.change ?? info?.priceChangePercentages[.h24] {
                HStack {
                    Text("24시간 변동률")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text(String(format: "%+.2f%%", change))
                        .font(.mono(14, weight: .heavy))
                        .foregroundColor(change >= 0 ? .up : .down)
                }
            }

            if info == nil {
                Text("\(coin.displaySymbol) 시장 정보를 불러오는 중입니다. 제공되지 않는 항목은 준비 상태로 표시됩니다.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .lineSpacing(2)
            } else if info?.fallbackUsed == true {
                Text("일부 정보는 거래소 스냅샷 기준으로 표시됩니다.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background(sectionCardBackground)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func marketMetric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.mono(14, weight: .heavy))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.bgTertiary)
        )
    }

    @ViewBuilder
    private var orderbookSection: some View {
        switch vm.orderbookState {
        case .idle, .loading:
            loadingSectionCard(
                title: "호가 데이터를 불러오는 중...",
                height: 170
            )
            .padding(.top, 12)

        case .failed(let message):
            sectionStateCard(
                icon: "list.bullet.rectangle",
                title: "호가 데이터를 불러오지 못했어요",
                description: message,
                height: 170,
                actionTitle: "다시 시도",
                action: retryChartData
            )
            .padding(.top, 12)

        case .unavailable(let message):
            sectionStateCard(
                icon: "list.bullet.rectangle",
                title: "호가 데이터가 일시적으로 제공되지 않아요",
                description: message,
                height: 170,
                actionTitle: "다시 시도",
                action: retryChartData
            )
            .padding(.top, 12)

        case .empty:
            sectionStateCard(
                icon: "list.bullet.rectangle",
                title: "호가 데이터가 아직 없어요",
                description: "거래소에서 호가 데이터를 제공하면 이 영역에 표시됩니다.",
                height: 170,
                actionTitle: "다시 시도",
                action: retryChartData
            )
            .padding(.top, 12)

        case .loaded, .staleCache, .refreshing:
            VStack(spacing: 8) {
                if let warningMessage = vm.orderbookState.warningMessage {
                    sectionWarningBanner(warningMessage)
                        .padding(.horizontal, 16)
                }
                OrderbookView(orderbook: vm.orderbook, currentPrice: vm.currentPrice)
                    .overlay(alignment: .topTrailing) {
                        if case .refreshing = vm.orderbookState {
                            ProgressView()
                                .tint(.accent)
                                .padding(.trailing, 24)
                                .padding(.top, 28)
                        }
                    }
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var tradesSection: some View {
        switch vm.recentTradesState {
        case .idle, .loading:
            loadingSectionCard(
                title: "최근 시장 기록을 불러오는 중...",
                height: 124
            )
            .padding(.top, 14)

        case .failed(let message):
            sectionStateCard(
                icon: "clock.badge.exclamationmark",
                title: "최근 시장 기록을 불러오지 못했어요",
                description: message,
                height: 124,
                actionTitle: "다시 시도",
                action: retryChartData
            )
            .padding(.top, 14)

        case .unavailable(let message):
            sectionStateCard(
                icon: "clock.badge.exclamationmark",
                title: "최근 시장 기록이 일시적으로 제공되지 않아요",
                description: message,
                height: 124,
                actionTitle: "다시 시도",
                action: retryChartData
            )
            .padding(.top, 14)

        case .empty:
            sectionStateCard(
                icon: "clock",
                title: "최근 시장 기록이 아직 없어요",
                description: "새 시장 데이터가 들어오면 이 영역에 바로 표시됩니다.",
                height: 124,
                actionTitle: "다시 시도",
                action: retryChartData
            )
            .padding(.top, 14)

        case .loaded(let trades), .staleCache(let trades, _), .refreshing(let trades):
            VStack(spacing: 8) {
                if let warningMessage = vm.recentTradesState.warningMessage {
                    sectionWarningBanner(warningMessage)
                        .padding(.horizontal, 16)
                }
                RecentTradesView(trades: vm.recentTradeRows(for: trades))
                    .overlay(alignment: .topTrailing) {
                        if case .refreshing = vm.recentTradesState {
                            ProgressView()
                                .tint(.accent)
                                .padding(.trailing, 24)
                                .padding(.top, 18)
                        }
                    }
            }
            .padding(.top, 14)
        }
    }

    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textMuted)
            Text(value)
                .font(.mono(12, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private func loadingSectionCard(title: String, height: CGFloat) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.accent)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(sectionCardBackground)
        .padding(.horizontal, 16)
    }

    private func sectionStateCard(
        icon: String,
        title: String,
        description: String,
        height: CGFloat,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.accent)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.themeText)
                .multilineTextAlignment(.center)
            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 18)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.themeText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.bgTertiary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(sectionCardBackground)
        .padding(.horizontal, 16)
    }

    private func sectionWarningBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.accent)
            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentBg)
        )
    }

    private var sectionCardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
    }

    private func retryChartData() {
        Task {
            await vm.loadChartData(forceRefresh: true, reason: "chart_section_retry")
        }
    }
}
