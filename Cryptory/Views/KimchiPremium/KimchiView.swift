import SwiftUI

private struct KimchiExchangeStyle {
    let title: String
    let subtitle: String
    let representativeTitle: String
    let listTitle: String
}

struct KimchiView: View {
    @ObservedObject var vm: CryptoViewModel
    private let instanceID: Int

    init(vm: CryptoViewModel) {
        self.vm = vm
        let instanceID = AppLogger.nextInstanceID(scope: "KimchiView")
        self.instanceID = instanceID
        AppLogger.debug(.lifecycle, "[ViewIdentity] KimchiView stableOwner=\(vm.debugOwnerID) viewInstance=\(instanceID)")
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                header
                domesticExchangeSelector
                ScreenStatusBannerView(viewState: vm.kimchiStatusViewState)
                    .padding(.horizontal, 16)

                if let kimchiTransitionMessage = vm.kimchiTransitionMessage,
                   vm.kimchiPresentationState.sameExchangeStaleReuse {
                    transitionBanner(message: kimchiTransitionMessage)
                        .padding(.horizontal, 16)
                }

                representativeSection
                listSection

                Spacer(minLength: 20)
            }
        }
        .refreshable {
            await vm.refreshKimchiPremium(forceRefresh: true, reason: "kimchi_pull_to_refresh")
        }
        .onAppear {
            AppLogger.debug(.lifecycle, "KimchiView onAppear #\(instanceID)")
        }
        .onDisappear {
            AppLogger.debug(.lifecycle, "KimchiView onDisappear #\(instanceID)")
        }
    }

    private var kimchiStyle: KimchiExchangeStyle {
        switch vm.selectedDomesticKimchiExchange {
        case .upbit:
            return KimchiExchangeStyle(
                title: "업비트 기준 빠른 비교",
                subtitle: "대표 종목부터 먼저 보여드리고, 비교 가능한 종목을 넓게 확장합니다.",
                representativeTitle: "대표 비교",
                listTitle: "전체 비교"
            )
        case .bithumb:
            return KimchiExchangeStyle(
                title: "빗썸 프리미엄 보드",
                subtitle: "선택 직후 주요 코인을 먼저 그리고, 나머지 코인을 순차 반영합니다.",
                representativeTitle: "주요 코인",
                listTitle: "확대 비교"
            )
        case .coinone:
            return KimchiExchangeStyle(
                title: "코인원 김프 랭킹",
                subtitle: "대표 코인 우선 반영 후 전체 비교를 채워 넣습니다.",
                representativeTitle: "대표 랭킹",
                listTitle: "전체 랭킹"
            )
        case .korbit:
            return KimchiExchangeStyle(
                title: "코빗 비교 시트",
                subtitle: "글로벌 기준가와 국내가를 빠르게 맞춰서 확인합니다.",
                representativeTitle: "핵심 비교",
                listTitle: "전체 비교"
            )
        case .binance:
            return KimchiExchangeStyle(
                title: "글로벌 기준 비교",
                subtitle: "국내 거래소 김프 비교에는 국내 거래소를 선택해 주세요.",
                representativeTitle: "대표 비교",
                listTitle: "전체 비교"
            )
        }
    }

    private var header: some View {
        let badgeState = vm.kimchiHeaderState.badgeState
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ExchangeIcon(exchange: vm.selectedDomesticKimchiExchange, size: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.selectedDomesticKimchiExchange.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                    Text(kimchiStyle.title)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.white)
                }
                Spacer()
                Text(kimchiBadgeTitle(for: badgeState))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(kimchiBadgeBackground(for: badgeState))
                    .clipShape(Capsule())
            }
            Text(kimchiStyle.subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.82))
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            vm.selectedDomesticKimchiExchange.color.opacity(0.92),
                            vm.selectedDomesticKimchiExchange.color.opacity(0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var domesticExchangeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("국내 거래소 선택")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.kimchiDomesticExchanges) { exchange in
                        Button {
                            vm.updateSelectedDomesticKimchiExchange(exchange, source: "kimchi_selector")
                        } label: {
                            HStack(spacing: 8) {
                                ExchangeIcon(exchange: exchange, size: 18)
                                Text(exchange.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(vm.selectedDomesticKimchiExchange == exchange ? .themeText : .textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(vm.selectedDomesticKimchiExchange == exchange ? Color.bgTertiary : Color.bgSecondary)
                                    .overlay(
                                        Capsule()
                                            .stroke(vm.selectedDomesticKimchiExchange == exchange ? exchange.color : Color.themeBorder, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }
        }
    }

    @ViewBuilder
    private var representativeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: kimchiStyle.representativeTitle,
                detail: representativeDetail
            )

            if representativeRows.isEmpty && vm.kimchiPresentationState.representativeRowsState.isLoading {
                LazyVStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        premiumSkeletonCard
                    }
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(representativeRows) { coinViewState in
                        EquatableView(content:
                            PremiumCard(
                                coinViewState: coinViewState,
                                selectedExchange: vm.selectedDomesticKimchiExchange
                            )
                        )
                        .onAppear {
                            vm.markKimchiRowVisible(
                                symbol: coinViewState.symbol,
                                exchange: vm.selectedDomesticKimchiExchange
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var listSection: some View {
        let remainder = remainingRows
        if !remainder.isEmpty || shouldShowListSkeleton {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: kimchiStyle.listTitle,
                    detail: listSectionDetail
                )

                if shouldShowListSkeleton {
                    LazyVStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            premiumSkeletonCard
                        }
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(remainder) { coinViewState in
                            EquatableView(content:
                                PremiumCard(
                                    coinViewState: coinViewState,
                                    selectedExchange: vm.selectedDomesticKimchiExchange
                                )
                            )
                            .onAppear {
                                vm.markKimchiRowVisible(
                                    symbol: coinViewState.symbol,
                                    exchange: vm.selectedDomesticKimchiExchange
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        } else if case .failed(let message) = vm.kimchiPremiumState, representativeRows.isEmpty {
            stateCard(
                title: "김치 프리미엄을 불러오지 못했어요",
                detail: message
            )
        } else if case .empty = vm.kimchiPremiumState, representativeRows.isEmpty {
            stateCard(
                title: "비교 가능한 김프 데이터가 없어요",
                detail: "비교 가능한 대표 종목을 아직 준비하지 못했어요. 잠시 후 다시 확인해주세요."
            )
        }
    }

    private var representativeRows: [KimchiPremiumCoinViewState] {
        vm.representativeKimchiRows
    }

    private var remainingRows: [KimchiPremiumCoinViewState] {
        let hiddenSymbols = Set(representativeRows.map(\.symbol))
        return vm.kimchiPresentationState.listRowsState.rows.filter { hiddenSymbols.contains($0.symbol) == false }
    }

    private var shouldShowListSkeleton: Bool {
        vm.kimchiPresentationState.listRowsState.isLoading && representativeRows.isEmpty
    }

    private var listSectionDetail: String {
        switch vm.kimchiHeaderState.copyState {
        case .representativeLoading:
            return "선택 거래소 기준으로 다시 맞추는 중"
        case .representativeVisible:
            return "대표 코인 우선 반영 후 전체 비교를 채워 넣습니다"
        case .progressiveHydrating:
            return "대표 코인 우선 반영 후 전체 비교를 채워 넣습니다"
        case .fullyHydrated:
            return "전체 비교 반영 완료"
        case .delayed:
            return "이미 보이는 비교값을 유지한 채 다시 맞추는 중"
        case .degraded:
            return "표시 가능한 비교값부터 유지하고 일부 지연을 표시합니다"
        }
    }

    private var representativeDetail: String {
        switch vm.kimchiHeaderState.copyState {
        case .representativeLoading:
            return "선택 거래소 우선 비교 준비 중"
        case .representativeVisible:
            return "대표 코인 우선 반영 후 전체 비교를 채워 넣습니다"
        case .progressiveHydrating:
            return "대표 코인 우선 반영 후 전체 비교를 채워 넣습니다"
        case .fullyHydrated:
            return "선택 거래소 전체 비교 반영 완료"
        case .delayed:
            return "이미 보이는 비교값을 유지한 채 다시 맞추는 중"
        case .degraded:
            return "비교 가능한 대표 코인 기준으로 일부 지연을 유지합니다"
        }
    }

    private func kimchiBadgeTitle(for state: KimchiHeaderBadgeState) -> String {
        switch state {
        case .idle, .syncing:
            return "SYNC"
        case .ready:
            return "READY"
        case .delayed:
            return "DELAYED"
        case .degraded:
            return "DEGRADED"
        }
    }

    private func kimchiBadgeBackground(for state: KimchiHeaderBadgeState) -> Color {
        switch state {
        case .idle, .syncing, .ready:
            return Color.white.opacity(0.16)
        case .delayed:
            return Color.accent.opacity(0.26)
        case .degraded:
            return Color.down.opacity(0.24)
        }
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

    private var premiumSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: 80, height: 16)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: 120, height: 12)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(height: 52)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.bgTertiary)
                .frame(width: 94, height: 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .redacted(reason: .placeholder)
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
}
