import SwiftUI

private struct MarketExchangeStyle {
    let title: String
    let subtitle: String
    let representativeTitle: String
    let listTitle: String
    let volumeTitle: String
    let accentStart: Color
    let accentEnd: Color
}

private enum MarketDisplayModeSheetPresentation: String, Identifiable {
    case guide
    case settings

    var id: String { rawValue }

    var source: String {
        switch self {
        case .guide:
            return "market_guide"
        case .settings:
            return "market_sheet"
        }
    }
}

struct MarketView: View {
    @ObservedObject var vm: CryptoViewModel
    @State private var displayModeSheetPresentation: MarketDisplayModeSheetPresentation?
    @State private var activeDisplayModeSheetPresentation: MarketDisplayModeSheetPresentation?
    private let instanceID: Int

    init(vm: CryptoViewModel) {
        self.vm = vm
        let instanceID = AppLogger.nextInstanceID(scope: "MarketView")
        self.instanceID = instanceID
        AppLogger.debug(.lifecycle, "[ViewIdentity] MarketView stableOwner=\(vm.debugOwnerID) viewInstance=\(instanceID)")
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $vm.searchQuery)
            MarketSegmentedControl(selection: $vm.marketFilter)
                .padding(.bottom, 10)

            ScreenStatusBannerView(viewState: vm.marketStatusViewState)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if let marketTransitionMessage = vm.marketTransitionMessage,
               vm.marketPresentationState.sameExchangeStaleReuse {
                transitionBanner(message: marketTransitionMessage)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            ScrollView {
                VStack(spacing: 16) {
                    exchangeHero
                    representativeSection
                    listSection
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnBackgroundTap()
        .onAppear {
            AppLogger.debug(.lifecycle, "MarketView onAppear #\(instanceID) exchange=\(vm.selectedExchange.rawValue)")
            logDisplayedRows(reason: "on_appear")
            presentMarketDisplayGuideIfNeeded()
        }
        .onDisappear {
            AppLogger.debug(.lifecycle, "MarketView onDisappear #\(instanceID) exchange=\(vm.selectedExchange.rawValue)")
        }
        .onChange(of: vm.displayedMarketRowIDs) { _, _ in
            logDisplayedRows(reason: "rows_changed")
        }
        .sheet(item: $displayModeSheetPresentation, onDismiss: {
            handleDisplayModeSheetDismiss()
        }) { presentation in
            MarketDisplayModeSheet(
                committedMode: vm.marketDisplayMode,
                initialPreviewMode: vm.activeMarketDisplayMode,
                isGuide: presentation == .guide,
                onPreview: { mode in
                    vm.previewMarketDisplayMode(mode, source: presentation.source)
                },
                onApply: { mode in
                    handleDisplayModeSheetApply(mode, presentation: presentation)
                },
                onClose: {
                    handleDisplayModeSheetClose(presentation: presentation)
                }
            )
            .presentationDetents(presentation == .guide ? [.fraction(0.62), .large] : [.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var marketStyle: MarketExchangeStyle {
        switch vm.selectedExchange {
        case .upbit:
            return MarketExchangeStyle(
                title: "원화 마켓 빠른 보기",
                subtitle: "거래대금 상위 종목부터 즉시 반응하게 보여줍니다.",
                representativeTitle: "대표 종목",
                listTitle: "전체 원화 마켓",
                volumeTitle: "거래대금",
                accentStart: vm.selectedExchange.color.opacity(0.92),
                accentEnd: vm.selectedExchange.color.opacity(0.58)
            )
        case .bithumb:
            return MarketExchangeStyle(
                title: "실시간 주요 종목",
                subtitle: "빗썸 체감에 맞춰 강한 변동 종목을 먼저 보여줍니다.",
                representativeTitle: "주요 종목",
                listTitle: "실시간 시세 리스트",
                volumeTitle: "거래량",
                accentStart: vm.selectedExchange.color.opacity(0.88),
                accentEnd: Color(hex: "#F8C86A")
            )
        case .coinone:
            return MarketExchangeStyle(
                title: "실시간 랭킹 보드",
                subtitle: "대표 종목과 전체 리스트가 순차적으로 채워집니다.",
                representativeTitle: "랭킹 보드",
                listTitle: "코인원 시세",
                volumeTitle: "체결량",
                accentStart: vm.selectedExchange.color.opacity(0.9),
                accentEnd: Color(hex: "#8DE4DB")
            )
        case .korbit:
            return MarketExchangeStyle(
                title: "코빗 원화 시세",
                subtitle: "선택 직후 대표 종목부터 먼저 보여드리고 전체를 확장합니다.",
                representativeTitle: "주요 페어",
                listTitle: "코빗 전체 리스트",
                volumeTitle: "거래량",
                accentStart: vm.selectedExchange.color.opacity(0.9),
                accentEnd: Color(hex: "#90B8EA")
            )
        case .binance:
            return MarketExchangeStyle(
                title: "글로벌 마켓",
                subtitle: "국내 김프 비교용 글로벌 기준가 흐름을 빠르게 확인합니다.",
                representativeTitle: "대표 마켓",
                listTitle: "글로벌 시세",
                volumeTitle: "거래량",
                accentStart: vm.selectedExchange.color.opacity(0.88),
                accentEnd: Color(hex: "#F7D55B")
            )
        }
    }

    private var displayConfiguration: MarketListDisplayConfiguration {
        vm.marketDisplayConfiguration
    }

    private var exchangeHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ExchangeIcon(exchange: vm.selectedExchange, size: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.selectedExchange.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                    Text(marketStyle.title)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.white)
                }
                Spacer()
                Text(vm.marketPresentationState.transitionState.phase == .hydrated ? "LIVE" : "READY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
            }

            Text(marketStyle.subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.82))
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [marketStyle.accentStart, marketStyle.accentEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var representativeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: marketStyle.representativeTitle,
                detail: vm.marketPresentationState.transitionState.phase == .partial ? "대표 종목부터 먼저 반영 중" : "선택 거래소 핵심 종목"
            )

            if representativeRows.isEmpty && vm.marketPresentationState.representativeRowsState.isLoading {
                LazyVGrid(columns: representativeColumns, spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        representativeSkeletonCard
                    }
                }
            } else if !representativeRows.isEmpty {
                LazyVGrid(columns: representativeColumns, spacing: 10) {
                    ForEach(representativeRows) { row in
                        representativeCard(row)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var listSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                sectionHeader(
                    title: marketStyle.listTitle,
                    detail: listSectionDetail
                )
                Spacer(minLength: 8)
                displayModeButton
            }

            marketTableHeader

            if shouldShowListSkeleton {
                LazyVStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        marketRowSkeleton
                        Divider()
                            .background(Color.themeBorder.opacity(0.28))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.bgSecondary)
                )
            } else if case .failed(let message) = vm.marketState, vm.displayedMarketRows.isEmpty {
                stateView(
                    title: "시세를 불러오지 못했어요",
                    detail: message
                )
            } else if case .empty = vm.marketState, vm.displayedMarketRows.isEmpty {
                stateView(
                    title: "노출할 거래쌍이 없어요",
                    detail: "선택한 거래소에서 보여드릴 시세를 아직 준비하지 못했어요."
                )
            } else if vm.marketFilter == .fav && vm.displayedMarketRows.isEmpty {
                stateView(
                    title: "관심 코인이 아직 없어요",
                    detail: "별표를 눌러 관심 코인을 추가해보세요."
                )
            } else if vm.displayedMarketRows.isEmpty {
                stateView(
                    title: "검색 결과가 없어요",
                    detail: "다른 검색어를 입력하거나 거래소를 바꿔보세요."
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(vm.displayedMarketRows) { row in
                        CoinRowView(
                            row: row,
                            configuration: displayConfiguration,
                            selectedExchange: vm.selectedExchange,
                            onSelect: {
                                vm.selectCoin(row.coin)
                            },
                            onToggleFavorite: {
                                vm.toggleFavorite(row.symbol)
                            },
                            onVisible: {
                                vm.markMarketRowVisible(marketIdentity: row.marketIdentity)
                            }
                        )
                        .equatable()

                        Divider()
                            .background(Color.themeBorder.opacity(0.28))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.bgSecondary)
                )
            }
        }
        .padding(.horizontal, 16)
    }

    private var marketTableHeader: some View {
        HStack(spacing: 0) {
            Text("코인")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("현재가")
                .frame(width: displayConfiguration.priceWidth, alignment: .trailing)
            Text("등락률")
                .frame(width: displayConfiguration.changeWidth, alignment: .trailing)
                .padding(.leading, displayConfiguration.changeColumnLeadingPadding)
            if displayConfiguration.showsVolume {
                Text(marketStyle.volumeTitle)
                    .frame(width: displayConfiguration.volumeWidth, alignment: .trailing)
            }
            if displayConfiguration.showsSparkline {
                Text("추이")
                    .frame(
                        width: max(displayConfiguration.sparklineWidth, displayConfiguration.sparklineMinimumWidth),
                        alignment: .trailing
                    )
                    .padding(.leading, displayConfiguration.sparklineColumnLeadingPadding)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.textMuted)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var representativeRows: [MarketRowViewState] {
        vm.representativeMarketRows
    }

    private var representativeColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var shouldShowListSkeleton: Bool {
        vm.marketPresentationState.listRowsState.isLoading && vm.displayedMarketRows.isEmpty
    }

    private var listSectionDetail: String {
        switch vm.marketPresentationState.transitionState.phase {
        case .exchangeChanged, .loading:
            return "거래소 변경 직후 바로 준비 중"
        case .partial:
            return "리스트와 sparkline 순차 반영 중"
        case .hydrated:
            return "전체 리스트 반영 완료"
        }
    }

    private var displayModeButton: some View {
        Button {
            AppLogger.debug(
                .lifecycle,
                "[MarketDisplayModeDebug] action=present_sheet source=market_tab"
            )
            presentDisplayModeSheet(.settings)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .bold))
                Text("종목 뷰 설정")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.themeText)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgSecondary.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.themeText)
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func representativeCard(_ row: MarketRowViewState) -> some View {
        Button {
            vm.selectCoin(row.coin)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.symbol)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.themeText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(row.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    Text(row.changeText)
                        .font(.mono(11, weight: .bold))
                        .foregroundColor(row.isChangePlaceholder ? .textMuted : (row.isUp ? .up : .down))
                }

                Text(row.priceText)
                    .font(.mono(16, weight: .heavy))
                    .foregroundColor(row.isPricePlaceholder ? .textMuted : .themeText)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(marketStyle.volumeTitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.textMuted)
                        Text(row.volumeText)
                            .font(.mono(11, weight: .semibold))
                            .foregroundColor(row.isVolumePlaceholder ? .textMuted : .textSecondary)
                    }
                    Spacer()
                    EquatableView(content:
                        SparklineView(
                            payload: row.sparklinePayload,
                            isUp: row.isUp,
                            marketIdentity: row.marketIdentity,
                            width: 76,
                            height: 24
                        )
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(vm.selectedExchange.color.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var representativeSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: 54, height: 14)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: 94, height: 12)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(height: 18)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.bgTertiary.opacity(0.75))
                .frame(height: 24)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .redacted(reason: .placeholder)
    }

    private var marketRowSkeleton: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(
                    minWidth: displayConfiguration.symbolColumnMinimumWidth,
                    maxWidth: .infinity,
                    minHeight: 14,
                    alignment: .leading
                )
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: displayConfiguration.priceWidth, height: 14)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: displayConfiguration.changeWidth, height: 14)
                .padding(.leading, displayConfiguration.changeColumnLeadingPadding)
            if displayConfiguration.showsVolume {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.bgTertiary)
                    .frame(width: displayConfiguration.volumeWidth, height: 14)
                    .padding(.leading, 6)
            }
            if displayConfiguration.showsSparkline {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.75))
                    .frame(
                        width: max(displayConfiguration.sparklineWidth, displayConfiguration.sparklineMinimumWidth),
                        height: max(displayConfiguration.sparklineHeight, 18)
                    )
                    .padding(.leading, displayConfiguration.sparklineColumnLeadingPadding)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, displayConfiguration.rowVerticalPadding)
        .redacted(reason: .placeholder)
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
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgSecondary)
        )
    }

    private func transitionBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accent.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func logDisplayedRows(reason: String) {
        AppLogger.debug(
            .lifecycle,
            "[MarketScreen] displayed items count=\(vm.displayedMarketRows.count) exchange=\(vm.selectedExchange.rawValue) reason=\(reason)"
        )
    }

    private func presentMarketDisplayGuideIfNeeded() {
        guard displayModeSheetPresentation == nil else {
            return
        }
        guard vm.consumeMarketDisplayGuidePresentationIfNeeded(reason: "first_launch") else {
            return
        }
        presentDisplayModeSheet(.guide)
    }

    private func presentDisplayModeSheet(_ presentation: MarketDisplayModeSheetPresentation) {
        activeDisplayModeSheetPresentation = presentation
        vm.beginMarketDisplayModePreview(source: presentation.source)
        displayModeSheetPresentation = presentation
    }

    private func handleDisplayModeSheetApply(
        _ mode: MarketListDisplayMode,
        presentation: MarketDisplayModeSheetPresentation
    ) {
        vm.previewMarketDisplayMode(mode, source: presentation.source)
        vm.applyMarketDisplayModePreview(source: presentation.source)
        if presentation == .guide {
            vm.dismissMarketDisplayGuide(reason: "apply")
        }
        activeDisplayModeSheetPresentation = nil
        displayModeSheetPresentation = nil
    }

    private func handleDisplayModeSheetClose(presentation: MarketDisplayModeSheetPresentation) {
        vm.cancelMarketDisplayModePreview(source: presentation.source)
        if presentation == .guide {
            vm.dismissMarketDisplayGuide(reason: "close")
        }
        activeDisplayModeSheetPresentation = nil
        displayModeSheetPresentation = nil
    }

    private func handleDisplayModeSheetDismiss() {
        guard let presentation = activeDisplayModeSheetPresentation else {
            return
        }
        handleDisplayModeSheetClose(presentation: presentation)
    }
}
