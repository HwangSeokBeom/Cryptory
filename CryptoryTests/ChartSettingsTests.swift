import XCTest
@testable import Cryptory

final class ChartSettingsTests: XCTestCase {

    private func makeIsolatedDefaults(testName: String = #function) -> UserDefaults {
        let suiteName = "CryptoryTests.ChartSettings.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testTopIndicatorsAreLimitedToThreeAndCanBeDeselected() {
        var state = ChartSettingsState.default

        XCTAssertEqual(state.toggleIndicator(.volumeOverlay), .applied)
        XCTAssertEqual(state.toggleIndicator(.bollingerBand), .applied)

        let blockedResult = state.toggleIndicator(.envelope)

        XCTAssertEqual(
            blockedResult,
            .maximumSelectionReached(placement: .top, limit: ChartSettingsState.maximumTopIndicatorCount)
        )
        XCTAssertEqual(state.selectedTopIndicators.count, 3)
        XCTAssertFalse(state.selectedTopIndicators.contains(.envelope))

        XCTAssertEqual(state.toggleIndicator(.movingAverage), .applied)
        XCTAssertFalse(state.selectedTopIndicators.contains(.movingAverage))
        XCTAssertEqual(state.selectedTopIndicators.count, 2)
    }

    func testBottomIndicatorsAreLimitedToThreeAndCanBeDeselected() {
        var state = ChartSettingsState.default

        XCTAssertEqual(state.toggleIndicator(.macd), .applied)
        XCTAssertEqual(state.toggleIndicator(.rsi), .applied)

        let blockedResult = state.toggleIndicator(.mfi)

        XCTAssertEqual(
            blockedResult,
            .maximumSelectionReached(placement: .bottom, limit: ChartSettingsState.maximumBottomIndicatorCount)
        )
        XCTAssertEqual(state.selectedBottomIndicators.count, 3)
        XCTAssertFalse(state.selectedBottomIndicators.contains(.mfi))

        XCTAssertEqual(state.toggleIndicator(.volume), .applied)
        XCTAssertFalse(state.selectedBottomIndicators.contains(.volume))
        XCTAssertEqual(state.selectedBottomIndicators.count, 2)
    }

    func testChartStyleSelectionIsSingleValue() {
        var state = ChartSettingsState.default

        state.selectChartStyle(.line)
        XCTAssertEqual(state.selectedChartStyle, .line)

        state.selectChartStyle(.heikinAshi)
        XCTAssertEqual(state.selectedChartStyle, .heikinAshi)
    }

    func testChartSettingsStoragePersistsAndRestoresNormalizedState() {
        let defaults = makeIsolatedDefaults()
        let storage = ChartSettingsStorage(defaults: defaults)
        let state = ChartSettingsState(
            selectedTopIndicators: [.movingAverage, .bollingerBand, .pivot, .envelope],
            selectedBottomIndicators: [.volume, .macd, .rsi, .mfi],
            selectedChartStyle: .area,
            showBestBidAskLine: true,
            useGlobalExchangeColorScheme: true,
            useUTC: true,
            comparedSymbols: ["BTC", "ETH", "XRP", "SOL", "ADA", "DOGE"],
            movingAverageConfiguration: ChartIndicatorConfiguration(
                period: 12,
                secondaryPeriod: nil,
                tertiaryPeriod: nil,
                lineWidth: 2.4,
                primaryColorHex: "#34D399",
                secondaryColorHex: nil,
                fillColorHex: nil,
                primaryLevel: nil,
                secondaryLevel: nil,
                multiplier: nil
            ),
            bollingerBandConfiguration: ChartIndicatorConfiguration(
                period: 24,
                secondaryPeriod: nil,
                tertiaryPeriod: nil,
                lineWidth: 1.8,
                primaryColorHex: "#F59E0B",
                secondaryColorHex: nil,
                fillColorHex: "#F59E0B",
                primaryLevel: nil,
                secondaryLevel: nil,
                multiplier: 2.5
            ),
            volumeOverlayConfiguration: .volumeOverlayDefault,
            volumeConfiguration: .volumeDefault,
            momentumConfiguration: ChartIndicatorConfiguration(
                period: 14,
                secondaryPeriod: nil,
                tertiaryPeriod: nil,
                lineWidth: 2.0,
                primaryColorHex: "#F472B6",
                secondaryColorHex: nil,
                fillColorHex: nil,
                primaryLevel: 100,
                secondaryLevel: nil,
                multiplier: nil
            ),
            stochasticConfiguration: ChartIndicatorConfiguration(
                period: 9,
                secondaryPeriod: 5,
                tertiaryPeriod: nil,
                lineWidth: 1.5,
                primaryColorHex: "#F59E0B",
                secondaryColorHex: "#60A5FA",
                fillColorHex: nil,
                primaryLevel: 82,
                secondaryLevel: 18,
                multiplier: nil
            ),
            parabolicSARConfiguration: .parabolicSARDefault
        )

        storage.save(state)

        XCTAssertEqual(storage.load(), state.normalized)
        XCTAssertEqual(storage.load().selectedTopIndicators.count, ChartSettingsState.maximumTopIndicatorCount)
        XCTAssertEqual(storage.load().selectedBottomIndicators.count, ChartSettingsState.maximumBottomIndicatorCount)
        XCTAssertEqual(storage.load().comparedSymbols.count, 5)
        XCTAssertEqual(storage.load().movingAverageConfiguration.period, 12)
        XCTAssertEqual(storage.load().stochasticConfiguration.secondaryPeriod, 5)
    }

    func testComparedSymbolsRespectLimitDeduplicationAndRemoval() {
        var state = ChartSettingsState.default

        XCTAssertEqual(state.addComparedSymbol("btc"), .applied)
        XCTAssertEqual(state.addComparedSymbol("ETH"), .applied)
        XCTAssertEqual(state.addComparedSymbol("btc"), .duplicate)
        XCTAssertEqual(state.addComparedSymbol("XRP"), .applied)
        XCTAssertEqual(state.addComparedSymbol("SOL"), .applied)
        XCTAssertEqual(state.addComparedSymbol("ADA"), .applied)
        XCTAssertEqual(
            state.addComparedSymbol("DOGE"),
            .limitReached(limit: ChartSettingsState.maximumComparedSymbolCount)
        )

        XCTAssertEqual(state.comparedSymbols, ["BTC", "ETH", "XRP", "SOL", "ADA"])

        state.removeComparedSymbol("eth")
        XCTAssertEqual(state.comparedSymbols, ["BTC", "XRP", "SOL", "ADA"])
    }
}
