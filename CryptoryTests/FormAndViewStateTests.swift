import XCTest
import UIKit
@testable import Cryptory

final class FormAndViewStateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AssetImageDebugClient.shared.reset()
        AssetImageClient.shared.debugReset()
    }

    func testAppExternalLinksPointToProductionLegalPages() {
        let expectedLinks: [(AppExternalLink, String, String)] = [
            (.home, "홈페이지", "https://hwangseokbeom.github.io/Cryptory-legal/"),
            (.privacyPolicy, "개인정보처리방침", "https://hwangseokbeom.github.io/Cryptory-legal/privacy.html"),
            (.termsOfService, "이용약관", "https://hwangseokbeom.github.io/Cryptory-legal/terms.html"),
            (.support, "고객지원", "https://hwangseokbeom.github.io/Cryptory-legal/support.html"),
            (.deleteAccount, "계정삭제 안내", "https://hwangseokbeom.github.io/Cryptory-legal/delete-account.html"),
            (.investmentDisclaimer, "투자 유의 및 면책", "https://hwangseokbeom.github.io/Cryptory-legal/disclaimer.html")
        ]

        XCTAssertEqual(AppExternalLink.allCases.count, expectedLinks.count)

        for (link, title, urlString) in expectedLinks {
            XCTAssertEqual(link.title, title)
            XCTAssertEqual(link.urlString, urlString)
            XCTAssertEqual(link.url?.absoluteString, urlString)
            XCTAssertNotNil(SafariDestination(link: link))
        }
    }

    func testSafariDestinationRejectsInvalidExternalURLs() {
        XCTAssertNil(SafariDestination(title: "비어 있는 링크", urlString: " "))
        XCTAssertNil(SafariDestination(title: "스킴 없는 링크", urlString: "hwangseokbeom.github.io/Cryptory-legal/"))
        XCTAssertNil(SafariDestination(title: "지원하지 않는 링크", urlString: "ftp://hwangseokbeom.github.io/Cryptory-legal/"))
        XCTAssertNotNil(SafariDestination(title: "정상 링크", urlString: "https://hwangseokbeom.github.io/Cryptory-legal/"))
    }

    func testExchangeConnectionFormValidationRequiresFieldsOnCreate() {
        let validator = ExchangeConnectionFormValidator()

        let message = validator.validationMessage(
            exchange: .upbit,
            nickname: "메인",
            credentials: [.accessKey: ""],
            mode: .create
        )

        XCTAssertEqual(message, "Access Key을 입력해주세요.")
    }

    func testExchangeConnectionFormValidationAllowsEmptySecretOnEdit() {
        let validator = ExchangeConnectionFormValidator()

        let message = validator.validationMessage(
            exchange: .upbit,
            nickname: "메인",
            credentials: [:],
            mode: .edit(connectionID: "upbit-1")
        )

        XCTAssertNil(message)
    }

    func testScreenStatusFactoryMarksPollingFallbackAndStale() {
        let factory = ScreenStatusFactory()
        let viewState = factory.makeStatusViewState(
            meta: ResponseMeta(
                fetchedAt: Date(),
                isStale: true,
                warningMessage: nil,
                partialFailureMessage: "partial"
            ),
            streamingStatus: .pollingFallback,
            context: .market
        )

        XCTAssertTrue(viewState.badges.contains(where: { $0.title == "약간 지연" }))
        XCTAssertTrue(viewState.badges.contains(where: { $0.title == "일부 지연" }))
        XCTAssertEqual(viewState.refreshMode, .pollingFallback)
    }

    func testScreenStatusFactoryKeepsRecentTimestampStableWithinFirstMinute() {
        let factory = ScreenStatusFactory()
        let viewState = factory.makeStatusViewState(
            meta: ResponseMeta(
                fetchedAt: Date().addingTimeInterval(-24),
                isStale: false,
                warningMessage: nil,
                partialFailureMessage: nil
            ),
            streamingStatus: .live,
            context: .market
        )

        XCTAssertEqual(viewState.lastUpdatedText, "업데이트 방금 전")
    }

    func testExchangeConnectionsUseCaseBuildsValidationChip() {
        let useCase = ExchangeConnectionsUseCase()
        let connection = ExchangeConnection(
            id: "upbit-1",
            exchange: .upbit,
            permission: .tradeEnabled,
            nickname: "업비트 메인",
            isActive: true,
            status: .connected,
            statusMessage: "테스트 성공",
            maskedCredentialSummary: nil,
            lastValidatedAt: Date(),
            updatedAt: Date()
        )

        let cards = useCase.makeCardViewStates(
            connections: [connection],
            crudCapability: ExchangeConnectionCRUDCapability(canCreate: true, canDelete: true, canUpdate: true)
        )

        XCTAssertEqual(cards.count, 1)
        XCTAssertTrue(cards[0].statusChips.contains(where: { $0.contains("검증") }))
        XCTAssertEqual(cards[0].secondaryMessage, "테스트 성공")
    }

    func testCoinCatalogPrefersMarketIdWhenBaseAssetLooksTruncated() {
        let coin = CoinCatalog.coin(
            symbol: "FI",
            exchange: .upbit,
            marketId: "KRW-ETHFI",
            baseAsset: "FI",
            displayName: "Ether.fi"
        )

        XCTAssertEqual(coin.symbol, "ETHFI")
        XCTAssertEqual(coin.canonicalSymbol, "ETHFI")
        XCTAssertEqual(coin.marketId, "KRW-ETHFI")
    }

    func testExchangeConnectionsUseCaseRoundsRecentStatusChipToJustNow() {
        let useCase = ExchangeConnectionsUseCase()
        let connection = ExchangeConnection(
            id: "upbit-1",
            exchange: .upbit,
            permission: .tradeEnabled,
            nickname: nil,
            isActive: true,
            status: .connected,
            statusMessage: nil,
            maskedCredentialSummary: nil,
            lastValidatedAt: Date().addingTimeInterval(-18),
            updatedAt: Date().addingTimeInterval(-42)
        )

        let cards = useCase.makeCardViewStates(
            connections: [connection],
            crudCapability: .readOnly
        )

        XCTAssertTrue(cards[0].statusChips.contains("검증 방금 전"))
        XCTAssertTrue(cards[0].statusChips.contains("수정 방금 전"))
    }

    func testLoadableEquatableComparesLoadedValues() {
        let lhs: Loadable<[String]> = .loaded(["BTC", "ETH"])
        let rhs: Loadable<[String]> = .loaded(["BTC", "ETH"])
        let different: Loadable<[String]> = .loaded(["BTC"])

        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, different)
    }

    func testKimchiPremiumViewStateUseCaseGroupsRows() {
        let useCase = KimchiPremiumViewStateUseCase()
        let snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                KimchiPremiumRow(
                    id: "btc-upbit",
                    symbol: "BTC",
                    exchange: .upbit,
                    sourceExchange: .upbit,
                    domesticPrice: 150_000_000,
                    referenceExchangePrice: 100_000,
                    premiumPercent: 3.2,
                    krwConvertedReference: 145_000_000,
                    usdKrwRate: 1450,
                    timestamp: Date(),
                    sourceExchangeTimestamp: Date(),
                    referenceTimestamp: Date(),
                    isStale: false,
                    staleReason: nil
                ),
                KimchiPremiumRow(
                    id: "btc-bithumb",
                    symbol: "BTC",
                    exchange: .bithumb,
                    sourceExchange: .bithumb,
                    domesticPrice: 149_800_000,
                    referenceExchangePrice: 100_000,
                    premiumPercent: 3.0,
                    krwConvertedReference: 145_000_000,
                    usdKrwRate: 1450,
                    timestamp: Date(),
                    sourceExchangeTimestamp: Date(),
                    referenceTimestamp: Date(),
                    isStale: false,
                    staleReason: nil
                )
            ],
            fetchedAt: Date(),
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil,
            failedSymbols: []
        )

        let viewStates = useCase.makeCoinViewStates(
            from: snapshot,
            comparableSymbols: ["BTC"],
            selectedDomesticExchange: .bithumb
        )

        XCTAssertEqual(viewStates.count, 1)
        XCTAssertEqual(viewStates[0].symbol, "BTC")
        XCTAssertEqual(viewStates[0].cells.count, 1)
        XCTAssertEqual(viewStates[0].cells.first?.exchange, .bithumb)
    }

    func testKimchiPremiumViewStateUseCasePreservesRequestedComparableSymbols() {
        let useCase = KimchiPremiumViewStateUseCase()
        let snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [],
            fetchedAt: Date(),
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil,
            failedSymbols: []
        )

        let viewStates = useCase.makeCoinViewStates(
            from: snapshot,
            comparableSymbols: ["BTC", "ETH"],
            selectedDomesticExchange: .upbit,
            phase: .settled
        )

        XCTAssertEqual(viewStates.map(\.symbol), ["BTC", "ETH"])
        XCTAssertEqual(viewStates.first?.status, .unavailable)
    }

    func testKimchiPremiumFreshDataDisplaysWithoutDelayBadgeState() {
        let useCase = KimchiPremiumViewStateUseCase()
        let updatedAt = Date()
        let snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                kimchiRow(
                    freshnessState: .available,
                    updatedAt: updatedAt
                )
            ],
            fetchedAt: updatedAt,
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil,
            failedSymbols: []
        )

        let viewStates = useCase.makeCoinViewStates(
            from: snapshot,
            comparableSymbols: ["BTC"],
            selectedDomesticExchange: .upbit
        )

        let cell = viewStates[0].cells[0]
        XCTAssertEqual(viewStates[0].status, .loaded)
        XCTAssertEqual(cell.freshnessState, .available)
        XCTAssertNil(cell.freshnessReason)
        XCTAssertEqual(cell.updatedAt, updatedAt)
        XCTAssertFalse(cell.isPreviousSnapshot)
    }

    func testKimchiPremiumStaleDataKeepsValuesAndMarksDelay() {
        let useCase = KimchiPremiumViewStateUseCase()
        let snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                kimchiRow(
                    isStale: true,
                    staleReason: "기준가 반영이 늦어지고 있어요.",
                    freshnessState: .stale
                )
            ],
            fetchedAt: Date(),
            isStale: true,
            warningMessage: nil,
            partialFailureMessage: nil,
            failedSymbols: []
        )

        let viewStates = useCase.makeCoinViewStates(
            from: snapshot,
            comparableSymbols: ["BTC"],
            selectedDomesticExchange: .upbit
        )

        let cell = viewStates[0].cells[0]
        XCTAssertEqual(viewStates[0].status, .stale)
        XCTAssertEqual(cell.freshnessState, .stale)
        XCTAssertEqual(cell.premiumText, "+3.20%")
        XCTAssertEqual(cell.freshnessReason, "약간 지연")
    }

    func testKimchiPremiumPartialDataMarksPartialUpdate() {
        let useCase = KimchiPremiumViewStateUseCase()
        let snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                kimchiRow()
            ],
            fetchedAt: Date(),
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: "일부 비교 종목이 제외되었어요.",
            failedSymbols: ["BTC"]
        )

        let viewStates = useCase.makeCoinViewStates(
            from: snapshot,
            comparableSymbols: ["BTC"],
            selectedDomesticExchange: .upbit
        )

        let cell = viewStates[0].cells[0]
        XCTAssertEqual(cell.freshnessState, .partialUpdate)
        XCTAssertEqual(viewStates[0].freshnessState, .partialUpdate)
        XCTAssertFalse(cell.premiumIsPlaceholder)
    }

    func testKimchiPremiumPartialSuccessSkipsMissingRowsWhenSomeRowsExist() {
        let useCase = KimchiPremiumViewStateUseCase()
        let snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                kimchiRow()
            ],
            fetchedAt: Date(),
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: "일부 비교 종목이 제외되었어요.",
            failedSymbols: ["ETH"]
        )

        let viewStates = useCase.makeCoinViewStates(
            from: snapshot,
            comparableSymbols: ["BTC", "ETH"],
            selectedDomesticExchange: .upbit
        )

        XCTAssertEqual(viewStates.map(\.symbol), ["BTC"])
        XCTAssertEqual(viewStates.first?.freshnessState, .partialUpdate)
    }

    func testKimchiPremiumSourceExchangeMismatchDoesNotRenderAsSelectedExchangeData() {
        let useCase = KimchiPremiumViewStateUseCase()
        let snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                kimchiRow(sourceExchange: .bithumb)
            ],
            fetchedAt: Date(),
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil,
            failedSymbols: []
        )

        let viewStates = useCase.makeCoinViewStates(
            from: snapshot,
            comparableSymbols: ["BTC"],
            selectedDomesticExchange: .upbit,
            phase: .settled
        )

        let cell = viewStates[0].cells[0]
        XCTAssertEqual(cell.exchange, .upbit)
        XCTAssertEqual(cell.sourceExchange, .upbit)
        XCTAssertEqual(cell.freshnessState, .unavailable)
        XCTAssertTrue(cell.premiumIsPlaceholder)
        XCTAssertEqual(cell.premiumText, "데이터 없음")
    }

    func testKimchiPremiumRawFreshnessReasonsAreSanitizedForUI() {
        let useCase = KimchiPremiumViewStateUseCase()
        let snapshot = KimchiPremiumSnapshot(
            referenceExchange: .binance,
            rows: [
                kimchiRow(
                    freshnessState: .partialUpdate,
                    freshnessReason: "fx_rate_delayed,timestamp_skew_detected"
                )
            ],
            fetchedAt: Date(),
            isStale: false,
            warningMessage: nil,
            partialFailureMessage: nil,
            failedSymbols: []
        )

        let viewStates = useCase.makeCoinViewStates(
            from: snapshot,
            comparableSymbols: ["BTC"],
            selectedDomesticExchange: .upbit
        )

        XCTAssertEqual(viewStates[0].cells[0].freshnessReason, "약간 지연")
    }

    func testMarketDisplayModeRowHeightsStayCompact() {
        XCTAssertLessThanOrEqual(MarketListDisplayMode.chart.configuration.rowHeight, 44)
        XCTAssertLessThanOrEqual(MarketListDisplayMode.chart.configuration.rowVerticalPadding, 6)
        XCTAssertLessThanOrEqual(MarketListDisplayMode.info.configuration.rowHeight, 48)
        XCTAssertLessThanOrEqual(MarketListDisplayMode.emphasis.configuration.rowHeight, 50)
    }

    func testGraphRenderVersionChangesForCachedToLivePatch() {
        let cachedRow = marketRow(
            priceText: "125,000,000",
            graphState: .cachedVisible,
            points: [1, 2, 3, 4]
        )
        let liveRow = cachedRow.replacingSparkline(
            points: [1, 2, 3, 4],
            pointCount: 4,
            graphState: .liveVisible
        )

        XCTAssertEqual(cachedRow.sparkline, liveRow.sparkline)
        XCTAssertGreaterThan(liveRow.graphRenderVersion, cachedRow.graphRenderVersion)
        XCTAssertGreaterThan(liveRow.graphPathVersion, cachedRow.graphPathVersion)
        XCTAssertNotEqual(liveRow.sparklineRenderToken, cachedRow.sparklineRenderToken)
    }

    func testGraphDetailUpgradeSeparatesRenderIdentityAndCacheKey() {
        let coarseRow = marketRow(
            priceText: "125,000,000",
            graphState: .cachedVisible,
            points: [1, 2]
        )
        let refinedRow = coarseRow.replacingSparkline(
            points: [1, 2, 1.5, 2.4, 2.1, 3],
            pointCount: 6,
            graphState: .liveVisible
        )

        XCTAssertEqual(coarseRow.sparklinePayload.detailLevel, .retainedCoarse)
        XCTAssertEqual(refinedRow.sparklinePayload.detailLevel, .liveDetailed)
        XCTAssertNotEqual(coarseRow.sparklinePayload.graphRenderIdentity, refinedRow.sparklinePayload.graphRenderIdentity)
        XCTAssertNotEqual(coarseRow.graphPathVersion, refinedRow.graphPathVersion)
        XCTAssertNotEqual(coarseRow.sparklineRenderToken, refinedRow.sparklineRenderToken)
    }

    func testTextOnlyMarketRowUpdateKeepsGraphRenderVersion() {
        let originalRow = marketRow(
            priceText: "125,000,000",
            graphState: .liveVisible,
            points: [1, 2, 3, 4]
        )
        let textOnlyRow = marketRow(
            priceText: "126,000,000",
            graphState: .liveVisible,
            points: [1, 2, 3, 4]
        )

        XCTAssertNotEqual(originalRow.priceText, textOnlyRow.priceText)
        XCTAssertEqual(originalRow.graphRenderVersion, textOnlyRow.graphRenderVersion)
        XCTAssertEqual(originalRow.graphPathVersion, textOnlyRow.graphPathVersion)
        XCTAssertEqual(originalRow.sparklineRenderToken, textOnlyRow.sparklineRenderToken)
    }

    func testMarketSparklineQualityBlocksLiveDetailedDowngradeToRetainedDetailed() {
        let liveQuality = MarketSparklineQuality(
            graphState: .liveVisible,
            points: [1, 2, 1.5, 2.4, 2.1, 3],
            pointCount: 6
        )
        let retainedQuality = MarketSparklineQuality(
            graphState: .cachedVisible,
            points: [1, 2, 1.5, 2.4, 2.1, 3],
            pointCount: 6
        )

        let decision = retainedQuality.promotionDecision(over: liveQuality)

        XCTAssertFalse(decision.accepted)
        XCTAssertEqual(decision.reason, "quality_downgrade_blocked")
    }

    func testMarketSparklineQualityBlocksVeryLowCoarseFallbackWhenUsableGraphExists() {
        let detailedQuality = MarketSparklineQuality(
            graphState: .cachedVisible,
            points: [1, 2, 1.5, 2.4, 2.1, 3],
            pointCount: 6
        )
        let coarseFallbackQuality = MarketSparklineQuality(
            graphState: .cachedVisible,
            points: [1, 2],
            pointCount: 2
        )

        let decision = coarseFallbackQuality.promotionDecision(over: detailedQuality)

        XCTAssertTrue(coarseFallbackQuality.isVeryLowCoarse)
        XCTAssertFalse(decision.accepted)
        XCTAssertEqual(decision.reason, "quality_downgrade_blocked")
    }

    @MainActor
    func testSparklineRenderViewRedrawsWhenGraphStateChanges() {
        let cachedRow = marketRow(
            priceText: "125,000,000",
            graphState: .cachedVisible,
            points: [1, 2, 3, 4]
        )
        let liveRow = cachedRow.replacingSparkline(
            points: [1, 2, 3, 4],
            pointCount: 4,
            graphState: .liveVisible
        )
        let sparklineRenderView = SparklineRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")

        sparklineRenderView.debugApply(
            payload: cachedRow.sparklinePayload,
            visualState: cachedRow.sparklinePayload.graphVisualState,
            isUp: true,
            marketIdentity: marketIdentity,
            size: CGSize(width: 72, height: 20)
        )
        let cachedSnapshot = sparklineRenderView.debugSnapshot

        sparklineRenderView.debugApply(
            payload: liveRow.sparklinePayload,
            visualState: liveRow.sparklinePayload.graphVisualState,
            isUp: true,
            marketIdentity: marketIdentity,
            size: CGSize(width: 72, height: 20)
        )
        let liveSnapshot = sparklineRenderView.debugSnapshot

        XCTAssertTrue(cachedSnapshot.hasVisibleGraph)
        XCTAssertTrue(liveSnapshot.hasVisibleGraph)
        XCTAssertNotEqual(cachedSnapshot.graphPathVersion, liveSnapshot.graphPathVersion)
        XCTAssertNotEqual(cachedSnapshot.renderVersion, liveSnapshot.renderVersion)
    }

    @MainActor
    func testSparklineRenderViewAppliesRefinedPatchWithoutReuse() {
        let coarseRow = marketRow(
            priceText: "125,000,000",
            graphState: .cachedVisible,
            points: [1, 2]
        )
        let refinedRow = coarseRow.replacingSparkline(
            points: [1, 2, 1.5, 2.4, 2.1, 3],
            pointCount: 6,
            graphState: .liveVisible
        )
        let sparklineRenderView = SparklineRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")

        sparklineRenderView.debugApply(
            payload: coarseRow.sparklinePayload,
            visualState: coarseRow.sparklinePayload.graphVisualState,
            isUp: true,
            marketIdentity: marketIdentity,
            size: CGSize(width: 72, height: 20)
        )
        let coarseSnapshot = sparklineRenderView.debugSnapshot

        sparklineRenderView.debugApply(
            payload: refinedRow.sparklinePayload,
            visualState: refinedRow.sparklinePayload.graphVisualState,
            isUp: true,
            marketIdentity: marketIdentity,
            size: CGSize(width: 72, height: 20)
        )
        let refinedSnapshot = sparklineRenderView.debugSnapshot

        XCTAssertTrue(coarseSnapshot.hasVisibleGraph)
        XCTAssertTrue(refinedSnapshot.hasVisibleGraph)
        XCTAssertEqual(refinedSnapshot.detailLevel, .liveDetailed)
        XCTAssertGreaterThan(refinedSnapshot.redrawCount, coarseSnapshot.redrawCount)
        XCTAssertEqual(refinedSnapshot.lastRedrawReason, "detail_upgrade")
    }

    @MainActor
    func testSparklineRenderViewForcesPlaceholderToLiveDetailedUpgrade() {
        let placeholderRow = marketRow(
            priceText: "125,000,000",
            graphState: .placeholder,
            points: []
        )
        let liveRow = marketRow(
            priceText: "125,000,000",
            graphState: .liveVisible,
            points: [1, 2, 1.5, 2.4, 2.1, 3]
        )
        let sparklineRenderView = SparklineRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")

        sparklineRenderView.debugApply(
            payload: placeholderRow.sparklinePayload,
            visualState: placeholderRow.sparklinePayload.graphVisualState,
            isUp: true,
            marketIdentity: marketIdentity,
            size: CGSize(width: 72, height: 20)
        )
        let placeholderSnapshot = sparklineRenderView.debugSnapshot

        sparklineRenderView.debugApply(
            payload: liveRow.sparklinePayload,
            visualState: liveRow.sparklinePayload.graphVisualState,
            isUp: true,
            marketIdentity: marketIdentity,
            size: CGSize(width: 72, height: 20)
        )
        let liveSnapshot = sparklineRenderView.debugSnapshot

        XCTAssertTrue(placeholderSnapshot.hasPlaceholder)
        XCTAssertTrue(liveSnapshot.hasVisibleGraph)
        XCTAssertEqual(liveSnapshot.detailLevel, .liveDetailed)
        XCTAssertGreaterThan(liveSnapshot.redrawCount, placeholderSnapshot.redrawCount)
        XCTAssertNotEqual(placeholderSnapshot.graphPathVersion, liveSnapshot.graphPathVersion)
    }

    @MainActor
    func testSparklineRenderViewSkipsSameGraphApplyForTextOnlyUpdate() {
        let row = marketRow(
            priceText: "125,000,000",
            graphState: .liveVisible,
            points: [1, 2, 1.5, 2.4]
        )
        let sparklineRenderView = SparklineRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")

        sparklineRenderView.debugApply(
            payload: row.sparklinePayload,
            visualState: row.sparklinePayload.graphVisualState,
            isUp: true,
            marketIdentity: marketIdentity,
            size: CGSize(width: 72, height: 20)
        )
        let firstSnapshot = sparklineRenderView.debugSnapshot

        sparklineRenderView.debugApply(
            payload: row.sparklinePayload,
            visualState: row.sparklinePayload.graphVisualState,
            isUp: true,
            marketIdentity: marketIdentity,
            size: CGSize(width: 72, height: 20)
        )
        let secondSnapshot = sparklineRenderView.debugSnapshot

        XCTAssertEqual(firstSnapshot.redrawCount, secondSnapshot.redrawCount)
        XCTAssertEqual(secondSnapshot.graphPathVersion, row.graphPathVersion)
        XCTAssertEqual(secondSnapshot.renderVersion, row.graphRenderVersion)
    }

    @MainActor
    func testSparklineRenderViewPrepareForReuseClearsRenderedGraph() {
        let row = marketRow(
            priceText: "125,000,000",
            graphState: .liveVisible,
            points: [1, 2, 1.5, 2.4]
        )
        let sparklineRenderView = SparklineRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")

        sparklineRenderView.debugApply(
            payload: row.sparklinePayload,
            visualState: row.sparklinePayload.graphVisualState,
            isUp: true,
            marketIdentity: marketIdentity,
            size: CGSize(width: 72, height: 20)
        )
        XCTAssertTrue(sparklineRenderView.debugSnapshot.hasVisibleGraph)

        sparklineRenderView.prepareForReuse()

        XCTAssertFalse(sparklineRenderView.debugSnapshot.hasVisibleGraph)
        XCTAssertFalse(sparklineRenderView.debugSnapshot.hasPlaceholder)
    }

    @MainActor
    func testSymbolImageRenderViewFallsBackForNilURL() {
        let symbolImageRenderView = SymbolImageRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")

        symbolImageRenderView.debugApply(
            marketIdentity: marketIdentity,
            symbol: "BTC",
            imageURL: nil,
            size: 24
        )

        XCTAssertEqual(symbolImageRenderView.debugState, .fallback("no_image_url"))
        XCTAssertEqual(symbolImageRenderView.debugPlaceholderText, "BT")
    }

    @MainActor
    func testSymbolImageRenderViewPrepareForReuseClearsFallbackState() {
        let symbolImageRenderView = SymbolImageRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")

        symbolImageRenderView.debugApply(
            marketIdentity: marketIdentity,
            symbol: "BTC",
            imageURL: nil,
            size: 24
        )
        XCTAssertEqual(symbolImageRenderView.debugPlaceholderText, "BT")

        symbolImageRenderView.prepareForReuse()

        XCTAssertEqual(symbolImageRenderView.debugState, .idle)
        XCTAssertEqual(symbolImageRenderView.debugPlaceholderText, "")
    }

    @MainActor
    func testSymbolImageRenderViewFallsBackForMalformedURL() {
        let symbolImageRenderView = SymbolImageRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")

        symbolImageRenderView.debugApply(
            marketIdentity: marketIdentity,
            symbol: "BTC",
            imageURL: "://bad url",
            size: 24
        )

        XCTAssertEqual(symbolImageRenderView.debugState, .fallback("alias_miss"))
    }

    @MainActor
    func testSymbolImageRenderViewFallsBackImmediatelyWhenHasImageIsFalse() {
        let symbolImageRenderView = SymbolImageRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-XRP", symbol: "XRP")

        symbolImageRenderView.debugApply(
            marketIdentity: marketIdentity,
            symbol: "XRP",
            imageURL: nil,
            hasImage: false,
            size: 24
        )

        XCTAssertEqual(symbolImageRenderView.debugState, .fallback("unsupported_asset"))
        XCTAssertEqual(symbolImageRenderView.debugPlaceholderText, "XR")
        XCTAssertEqual(symbolImageRenderView.debugEventCounts["placeholder_applied"], 1)
    }

    @MainActor
    func testAssetImageClientLoadsLocalFileURLSuccessfully() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let renderedImage = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        guard let pngData = renderedImage.pngData() else {
            return XCTFail("Expected png data")
        }

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try pngData.write(to: imageURL)

        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")
        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: "BTC",
            canonicalSymbol: "BTC",
            imageURL: imageURL.absoluteString,
            hasImage: true,
            localAssetName: nil
        )
        let outcome = await AssetImageClient.shared.requestImage(for: descriptor, mode: .visible)

        XCTAssertEqual(outcome.state, .live)
        XCTAssertEqual(AssetImageClient.shared.renderState(for: descriptor), .live)
        XCTAssertEqual(AssetImageDebugClient.shared.snapshotEventCounts()["request_start"], 1)
    }

    @MainActor
    func testAssetImageClientAttemptsURLEvenWhenHasImageFlagIsFalse() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let renderedImage = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        guard let pngData = renderedImage.pngData() else {
            return XCTFail("Expected png data")
        }

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try pngData.write(to: imageURL)

        let marketIdentity = MarketIdentity(exchange: .bithumb, marketId: "KRW-T", symbol: "T")
        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: "T",
            canonicalSymbol: "T",
            imageURL: imageURL.absoluteString,
            hasImage: false,
            localAssetName: nil
        )
        let outcome = await AssetImageClient.shared.requestImage(for: descriptor, mode: .visible)

        XCTAssertEqual(outcome.state, .live)
        XCTAssertEqual(outcome.fallbackReason, nil)
        XCTAssertEqual(AssetImageClient.shared.renderState(for: descriptor), .live)
    }

    @MainActor
    func testAssetImageClientPlaceholderGraceDecisionReportsMemoryExpectedAfterCachedLoad() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let renderedImage = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        guard let pngData = renderedImage.pngData() else {
            return XCTFail("Expected png data")
        }

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try pngData.write(to: imageURL)

        let assetImageClient = AssetImageClient(namespace: UUID().uuidString)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")
        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: "BTC",
            canonicalSymbol: "BTC",
            imageURL: imageURL.absoluteString,
            hasImage: true,
            localAssetName: nil
        )

        let outcome = await assetImageClient.requestImage(for: descriptor, mode: .prefetch)
        let graceDecision = assetImageClient.placeholderGraceDecision(for: descriptor)

        XCTAssertEqual(outcome.state, .live)
        XCTAssertFalse(graceDecision.shouldDelay)
        XCTAssertEqual(graceDecision.reason, "memory_expected")
    }

    func testAssetImageRequestDescriptorNormalizesSchemeLessURL() {
        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC"),
            symbol: "BTC",
            canonicalSymbol: "BTC",
            imageURL: "assets.example.com/icons/btc logo.png",
            hasImage: true,
            localAssetName: nil
        )

        XCTAssertEqual(
            descriptor.normalizedImageURL?.absoluteString,
            "https://assets.example.com/icons/btc%20logo.png"
        )
    }

    @MainActor
    func testSymbolImageRenderViewUsesCachedImageWhileRowStateIsStillPlaceholder() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let renderedImage = renderer.image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        guard let pngData = renderedImage.pngData() else {
            return XCTFail("Expected png data")
        }

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try pngData.write(to: imageURL)

        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-BTC", symbol: "BTC")
        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: "BTC",
            canonicalSymbol: "BTC",
            imageURL: imageURL.absoluteString,
            hasImage: true,
            localAssetName: nil
        )
        _ = await AssetImageClient.shared.requestImage(for: descriptor, mode: .prefetch)

        let symbolImageRenderView = SymbolImageRenderView(frame: .zero)
        symbolImageRenderView.debugApply(
            marketIdentity: marketIdentity,
            symbol: "BTC",
            imageURL: imageURL.absoluteString,
            hasImage: true,
            symbolImageState: .placeholder,
            size: 24
        )

        XCTAssertEqual(symbolImageRenderView.debugState, .success)
    }

    @MainActor
    func testSymbolImageRenderViewReplacesPlaceholderWhenImageURLAppears() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let renderedImage = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        guard let pngData = renderedImage.pngData() else {
            return XCTFail("Expected png data")
        }

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try pngData.write(to: imageURL)

        let symbolImageRenderView = SymbolImageRenderView(frame: .zero)
        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-XRP", symbol: "XRP")
        symbolImageRenderView.debugApply(
            marketIdentity: marketIdentity,
            symbol: "XRP",
            imageURL: nil,
            hasImage: false,
            size: 24
        )

        XCTAssertEqual(symbolImageRenderView.debugState, .fallback("unsupported_asset"))

        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: "XRP",
            canonicalSymbol: "XRP",
            imageURL: imageURL.absoluteString,
            hasImage: true,
            localAssetName: nil
        )
        _ = await AssetImageClient.shared.requestImage(for: descriptor, mode: .visible)

        symbolImageRenderView.debugApply(
            marketIdentity: marketIdentity,
            symbol: "XRP",
            imageURL: imageURL.absoluteString,
            hasImage: true,
            symbolImageState: AssetImageClient.shared.renderState(for: descriptor),
            size: 24
        )

        XCTAssertEqual(symbolImageRenderView.debugState, .success)
        XCTAssertEqual(symbolImageRenderView.debugEventCounts["live_image_applied"], 1)
    }

    @MainActor
    func testAssetImageClientSuppressesImmediateRetryAfterLoadFailure() async throws {
        let invalidImageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("not-an-image".utf8).write(to: invalidImageURL)

        let marketIdentity = MarketIdentity(exchange: .upbit, marketId: "KRW-T", symbol: "T")
        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: marketIdentity,
            symbol: "T",
            canonicalSymbol: "T",
            imageURL: invalidImageURL.absoluteString,
            hasImage: true,
            localAssetName: nil
        )

        let firstOutcome = await AssetImageClient.shared.requestImage(for: descriptor, mode: .visible)
        let secondOutcome = await AssetImageClient.shared.requestImage(for: descriptor, mode: .visible)

        XCTAssertEqual(firstOutcome.fallbackReason, .fetchFailed)
        XCTAssertEqual(secondOutcome.fallbackReason, .cooldownBlocked)
        XCTAssertEqual(firstOutcome.state, .missing)
        XCTAssertEqual(secondOutcome.state, .missing)
        XCTAssertEqual(AssetImageDebugClient.shared.snapshotEventCounts()["image_load_failed"], 1)
    }

    func testChartDisplayModeShowsSymbolImageAlongsideSparkline() {
        XCTAssertTrue(MarketListDisplayMode.chart.configuration.showsSparkline)
        XCTAssertTrue(MarketListDisplayMode.chart.configuration.showsSymbolImage)
        XCTAssertTrue(MarketListDisplayMode.info.configuration.showsSymbolImage)
        XCTAssertTrue(MarketListDisplayMode.emphasis.configuration.showsSymbolImage)
    }

    private func kimchiRow(
        sourceExchange: Exchange = .upbit,
        isStale: Bool = false,
        staleReason: String? = nil,
        freshnessState: KimchiPremiumFreshnessState? = nil,
        freshnessReason: String? = nil,
        updatedAt: Date? = nil
    ) -> KimchiPremiumRow {
        KimchiPremiumRow(
            id: "btc-upbit",
            symbol: "BTC",
            exchange: .upbit,
            sourceExchange: sourceExchange,
            domesticPrice: 150_000_000,
            referenceExchangePrice: 100_000,
            premiumPercent: 3.2,
            krwConvertedReference: 145_000_000,
            usdKrwRate: 1450,
            timestamp: updatedAt ?? Date(),
            sourceExchangeTimestamp: updatedAt ?? Date(),
            referenceTimestamp: updatedAt ?? Date(),
            isStale: isStale,
            staleReason: staleReason,
            freshnessState: freshnessState,
            freshnessReason: freshnessReason ?? staleReason,
            updatedAt: updatedAt
        )
    }

    private func marketRow(
        priceText: String,
        graphState: MarketRowGraphState,
        points: [Double],
        suppressesCoarseRetainedReuse: Bool = false
    ) -> MarketRowViewState {
        MarketRowViewState(
            selectedExchange: .upbit,
            exchange: .upbit,
            sourceExchange: .upbit,
            coin: CoinCatalog.coin(symbol: "BTC"),
            priceText: priceText,
            changeText: "+1.20%",
            volumeText: "1.2조",
            sparkline: points,
            sparklinePointCount: points.count,
            sparklineTimeframe: "1h",
            hasEnoughSparklineData: points.count >= 4,
            chartPresentation: graphState.chartPresentation,
            baseFreshnessState: .live,
            graphState: graphState,
            symbolImageState: .placeholder,
            isPricePlaceholder: false,
            isChangePlaceholder: false,
            isVolumePlaceholder: false,
            isUp: true,
            flash: nil,
            isFavorite: false,
            dataState: .live,
            suppressesCoarseRetainedReuse: suppressesCoarseRetainedReuse
        )
    }
}
