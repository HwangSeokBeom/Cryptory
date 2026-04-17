import XCTest
@testable import Cryptory

final class FormAndViewStateTests: XCTestCase {

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
            streamingStatus: .pollingFallback
        )

        XCTAssertTrue(viewState.badges.contains(where: { $0.title == "Polling Fallback" }))
        XCTAssertTrue(viewState.badges.contains(where: { $0.title == "Stale" }))
        XCTAssertTrue(viewState.badges.contains(where: { $0.title == "Partial" }))
        XCTAssertEqual(viewState.refreshMode, .pollingFallback)
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
            warningMessage: nil
        )

        let viewStates = useCase.makeCoinViewStates(from: snapshot)

        XCTAssertEqual(viewStates.count, 1)
        XCTAssertEqual(viewStates[0].symbol, "BTC")
        XCTAssertEqual(viewStates[0].cells.count, 2)
    }
}
