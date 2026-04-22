import Foundation

struct ChartComparisonCandidate: Hashable {
    let symbol: String
    let name: String
    let nameEn: String
    let isFavorite: Bool
}

struct ChartComparisonSeries: Identifiable, Equatable {
    var id: String { symbol }

    let symbol: String
    let name: String
    let candles: [CandleData]
    let colorHex: String
}

struct ChartIndicatorConfiguration: Codable, Equatable {
    var period: Int
    var secondaryPeriod: Int?
    var tertiaryPeriod: Int?
    var lineWidth: Double
    var primaryColorHex: String
    var secondaryColorHex: String?
    var fillColorHex: String?
    var primaryLevel: Double?
    var secondaryLevel: Double?
    var multiplier: Double?

    var normalized: ChartIndicatorConfiguration {
        var configuration = self
        configuration.period = min(max(configuration.period, 1), 400)
        configuration.secondaryPeriod = configuration.secondaryPeriod.map { min(max($0, 1), 400) }
        configuration.tertiaryPeriod = configuration.tertiaryPeriod.map { min(max($0, 1), 400) }
        configuration.lineWidth = min(max(configuration.lineWidth, 0.5), 6)
        configuration.primaryLevel = configuration.primaryLevel.map { min(max($0, -1_000), 1_000) }
        configuration.secondaryLevel = configuration.secondaryLevel.map { min(max($0, -1_000), 1_000) }
        configuration.multiplier = configuration.multiplier.map { min(max($0, 0.1), 10) }
        return configuration
    }

    static let movingAverageDefault = ChartIndicatorConfiguration(
        period: 7,
        secondaryPeriod: nil,
        tertiaryPeriod: nil,
        lineWidth: 1.6,
        primaryColorHex: "#F59E0B",
        secondaryColorHex: nil,
        fillColorHex: nil,
        primaryLevel: nil,
        secondaryLevel: nil,
        multiplier: nil
    )

    static let bollingerBandDefault = ChartIndicatorConfiguration(
        period: 20,
        secondaryPeriod: nil,
        tertiaryPeriod: nil,
        lineWidth: 1.2,
        primaryColorHex: "#F59E0B",
        secondaryColorHex: nil,
        fillColorHex: "#F59E0B",
        primaryLevel: nil,
        secondaryLevel: nil,
        multiplier: 2
    )

    static let volumeOverlayDefault = ChartIndicatorConfiguration(
        period: 1,
        secondaryPeriod: nil,
        tertiaryPeriod: nil,
        lineWidth: 1,
        primaryColorHex: "#F59E0B",
        secondaryColorHex: nil,
        fillColorHex: nil,
        primaryLevel: nil,
        secondaryLevel: nil,
        multiplier: nil
    )

    static let volumeDefault = ChartIndicatorConfiguration(
        period: 1,
        secondaryPeriod: nil,
        tertiaryPeriod: nil,
        lineWidth: 1,
        primaryColorHex: "#F59E0B",
        secondaryColorHex: nil,
        fillColorHex: nil,
        primaryLevel: nil,
        secondaryLevel: nil,
        multiplier: nil
    )

    static let momentumDefault = ChartIndicatorConfiguration(
        period: 10,
        secondaryPeriod: nil,
        tertiaryPeriod: nil,
        lineWidth: 1.4,
        primaryColorHex: "#F59E0B",
        secondaryColorHex: nil,
        fillColorHex: nil,
        primaryLevel: 100,
        secondaryLevel: nil,
        multiplier: nil
    )

    static let stochasticDefault = ChartIndicatorConfiguration(
        period: 14,
        secondaryPeriod: 3,
        tertiaryPeriod: nil,
        lineWidth: 1.2,
        primaryColorHex: "#F59E0B",
        secondaryColorHex: "#60A5FA",
        fillColorHex: nil,
        primaryLevel: 80,
        secondaryLevel: 20,
        multiplier: nil
    )

    static let parabolicSARDefault = ChartIndicatorConfiguration(
        period: 3,
        secondaryPeriod: nil,
        tertiaryPeriod: nil,
        lineWidth: 1.8,
        primaryColorHex: "#F59E0B",
        secondaryColorHex: nil,
        fillColorHex: nil,
        primaryLevel: nil,
        secondaryLevel: nil,
        multiplier: 0.02
    )
}

enum ChartSettingsTab: Int, CaseIterable, Equatable {
    case indicators
    case chartStyle
    case viewOptions

    nonisolated var title: String {
        switch self {
        case .indicators:
            return "지표 설정"
        case .chartStyle:
            return "차트 형식"
        case .viewOptions:
            return "보기 설정"
        }
    }
}

enum ChartIndicatorPlacement: String, Codable, Equatable {
    case top
    case bottom
}

enum ChartIndicatorID: String, Codable, CaseIterable, Hashable {
    case volumeOverlay
    case volumeProfile
    case bollingerBand
    case envelope
    case movingAverage
    case ichimoku
    case parabolicSAR
    case pivot
    case volume
    case momentum
    case volumeOscillator
    case stochastic
    case aroon
    case adxDms
    case atr
    case cci
    case macd
    case mfi
    case obv
    case rsi
    case vroc
    case wr

    nonisolated var title: String {
        switch self {
        case .volumeOverlay:
            return "거래량 겹쳐보기"
        case .volumeProfile:
            return "매물대"
        case .bollingerBand:
            return "볼린저 밴드"
        case .envelope:
            return "엔벨로프"
        case .movingAverage:
            return "이동평균선"
        case .ichimoku:
            return "일목균형표"
        case .parabolicSAR:
            return "파라볼릭 SAR"
        case .pivot:
            return "피봇"
        case .volume:
            return "거래량"
        case .momentum:
            return "모멘텀"
        case .volumeOscillator:
            return "볼륨 오실레이터"
        case .stochastic:
            return "스토캐스틱"
        case .aroon:
            return "아룬"
        case .adxDms:
            return "ADX/DMS"
        case .atr:
            return "ATR"
        case .cci:
            return "CCI"
        case .macd:
            return "MACD"
        case .mfi:
            return "MFI"
        case .obv:
            return "OBV"
        case .rsi:
            return "RSI"
        case .vroc:
            return "VROC"
        case .wr:
            return "WR"
        }
    }

    nonisolated var placement: ChartIndicatorPlacement {
        switch self {
        case .volumeOverlay, .volumeProfile, .bollingerBand, .envelope, .movingAverage, .ichimoku, .parabolicSAR, .pivot:
            return .top
        case .volume, .momentum, .volumeOscillator, .stochastic, .aroon, .adxDms, .atr, .cci, .macd, .mfi, .obv, .rsi, .vroc, .wr:
            return .bottom
        }
    }

    nonisolated var isConfigurable: Bool {
        switch self {
        case .volumeProfile, .pivot, .obv, .vroc, .wr:
            return false
        case .volumeOverlay, .bollingerBand, .envelope, .movingAverage, .ichimoku, .parabolicSAR, .volume, .momentum, .volumeOscillator, .stochastic, .aroon, .adxDms, .atr, .cci, .macd, .mfi, .rsi:
            return true
        }
    }
}

struct ChartIndicatorItem: Hashable {
    let id: ChartIndicatorID
    let title: String
    let placement: ChartIndicatorPlacement
    let isConfigurable: Bool

    nonisolated init(id: ChartIndicatorID) {
        self.id = id
        self.title = id.title
        self.placement = id.placement
        self.isConfigurable = id.isConfigurable
    }
}

enum ChartStyleID: String, Codable, CaseIterable, Hashable {
    case candle
    case bar
    case coloredBar
    case line
    case lineWithMarkers
    case stepLine
    case area
    case baseline
    case hollowCandle
    case volumeCandle
    case coloredHLCBar
    case distribution
    case histogram
    case heikinAshi

    nonisolated var title: String {
        switch self {
        case .candle:
            return "캔들"
        case .bar:
            return "봉"
        case .coloredBar:
            return "색칠된 봉"
        case .line:
            return "라인"
        case .lineWithMarkers:
            return "마커가 있는 라인"
        case .stepLine:
            return "스텝 라인"
        case .area:
            return "영역"
        case .baseline:
            return "베이스라인"
        case .hollowCandle:
            return "할로우 캔들"
        case .volumeCandle:
            return "볼륨 캔들"
        case .coloredHLCBar:
            return "색칠된 HLC 봉"
        case .distribution:
            return "분포도"
        case .histogram:
            return "히스토그램"
        case .heikinAshi:
            return "하이킨 아시"
        }
    }

    nonisolated var iconSystemName: String {
        switch self {
        case .candle, .hollowCandle, .volumeCandle, .heikinAshi:
            return "chart.bar.fill"
        case .bar, .coloredBar, .coloredHLCBar:
            return "chart.bar"
        case .line, .lineWithMarkers:
            return "chart.xyaxis.line"
        case .stepLine:
            return "point.3.connected.trianglepath.dotted"
        case .area, .baseline:
            return "chart.line.uptrend.xyaxis"
        case .distribution:
            return "square.grid.3x3"
        case .histogram:
            return "chart.bar.xaxis"
        }
    }
}

struct ChartStyleItem: Hashable {
    let id: ChartStyleID
    let title: String
    let iconSystemName: String
    let isSupported: Bool

    nonisolated init(id: ChartStyleID, isSupported: Bool = true) {
        self.id = id
        self.title = id.title
        self.iconSystemName = id.iconSystemName
        self.isSupported = isSupported
    }
}

enum ChartSettingsMutationResult: Equatable {
    case applied
    case maximumSelectionReached(placement: ChartIndicatorPlacement, limit: Int)

    var userMessage: String? {
        switch self {
        case .applied:
            return nil
        case .maximumSelectionReached(_, let limit):
            return "최대 \(limit)개까지 선택할 수 있어요"
        }
    }
}

enum ChartComparedSymbolMutationResult: Equatable {
    case applied
    case duplicate
    case limitReached(limit: Int)

    var userMessage: String? {
        switch self {
        case .applied:
            return nil
        case .duplicate:
            return "이미 비교 목록에 추가된 종목이에요"
        case .limitReached(let limit):
            return "비교 종목은 최대 \(limit)개까지 추가할 수 있어요"
        }
    }
}

struct ChartSettingsState: Codable, Equatable {
    static let maximumTopIndicatorCount = 3
    static let maximumBottomIndicatorCount = 3
    static let maximumComparedSymbolCount = 5

    var selectedTopIndicators: [ChartIndicatorID]
    var selectedBottomIndicators: [ChartIndicatorID]
    var selectedChartStyle: ChartStyleID
    var showBestBidAskLine: Bool
    var useGlobalExchangeColorScheme: Bool
    var useUTC: Bool
    var comparedSymbols: [String]
    var movingAverageConfiguration: ChartIndicatorConfiguration
    var bollingerBandConfiguration: ChartIndicatorConfiguration
    var volumeOverlayConfiguration: ChartIndicatorConfiguration
    var volumeConfiguration: ChartIndicatorConfiguration
    var momentumConfiguration: ChartIndicatorConfiguration
    var stochasticConfiguration: ChartIndicatorConfiguration
    var parabolicSARConfiguration: ChartIndicatorConfiguration

    static let `default` = ChartSettingsState(
        selectedTopIndicators: [.movingAverage],
        selectedBottomIndicators: [.volume],
        selectedChartStyle: .candle,
        showBestBidAskLine: false,
        useGlobalExchangeColorScheme: false,
        useUTC: false,
        comparedSymbols: [],
        movingAverageConfiguration: .movingAverageDefault,
        bollingerBandConfiguration: .bollingerBandDefault,
        volumeOverlayConfiguration: .volumeOverlayDefault,
        volumeConfiguration: .volumeDefault,
        momentumConfiguration: .momentumDefault,
        stochasticConfiguration: .stochasticDefault,
        parabolicSARConfiguration: .parabolicSARDefault
    )

    init(
        selectedTopIndicators: [ChartIndicatorID],
        selectedBottomIndicators: [ChartIndicatorID],
        selectedChartStyle: ChartStyleID,
        showBestBidAskLine: Bool,
        useGlobalExchangeColorScheme: Bool,
        useUTC: Bool,
        comparedSymbols: [String],
        movingAverageConfiguration: ChartIndicatorConfiguration = .movingAverageDefault,
        bollingerBandConfiguration: ChartIndicatorConfiguration = .bollingerBandDefault,
        volumeOverlayConfiguration: ChartIndicatorConfiguration = .volumeOverlayDefault,
        volumeConfiguration: ChartIndicatorConfiguration = .volumeDefault,
        momentumConfiguration: ChartIndicatorConfiguration = .momentumDefault,
        stochasticConfiguration: ChartIndicatorConfiguration = .stochasticDefault,
        parabolicSARConfiguration: ChartIndicatorConfiguration = .parabolicSARDefault
    ) {
        self.selectedTopIndicators = selectedTopIndicators
        self.selectedBottomIndicators = selectedBottomIndicators
        self.selectedChartStyle = selectedChartStyle
        self.showBestBidAskLine = showBestBidAskLine
        self.useGlobalExchangeColorScheme = useGlobalExchangeColorScheme
        self.useUTC = useUTC
        self.comparedSymbols = comparedSymbols
        self.movingAverageConfiguration = movingAverageConfiguration
        self.bollingerBandConfiguration = bollingerBandConfiguration
        self.volumeOverlayConfiguration = volumeOverlayConfiguration
        self.volumeConfiguration = volumeConfiguration
        self.momentumConfiguration = momentumConfiguration
        self.stochasticConfiguration = stochasticConfiguration
        self.parabolicSARConfiguration = parabolicSARConfiguration
    }

    private enum CodingKeys: String, CodingKey {
        case selectedTopIndicators
        case selectedBottomIndicators
        case selectedChartStyle
        case showBestBidAskLine
        case useGlobalExchangeColorScheme
        case useUTC
        case comparedSymbols
        case movingAverageConfiguration
        case bollingerBandConfiguration
        case volumeOverlayConfiguration
        case volumeConfiguration
        case momentumConfiguration
        case stochasticConfiguration
        case parabolicSARConfiguration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        selectedTopIndicators = try container.decodeIfPresent([ChartIndicatorID].self, forKey: .selectedTopIndicators) ?? defaults.selectedTopIndicators
        selectedBottomIndicators = try container.decodeIfPresent([ChartIndicatorID].self, forKey: .selectedBottomIndicators) ?? defaults.selectedBottomIndicators
        selectedChartStyle = try container.decodeIfPresent(ChartStyleID.self, forKey: .selectedChartStyle) ?? defaults.selectedChartStyle
        showBestBidAskLine = try container.decodeIfPresent(Bool.self, forKey: .showBestBidAskLine) ?? defaults.showBestBidAskLine
        useGlobalExchangeColorScheme = try container.decodeIfPresent(Bool.self, forKey: .useGlobalExchangeColorScheme) ?? defaults.useGlobalExchangeColorScheme
        useUTC = try container.decodeIfPresent(Bool.self, forKey: .useUTC) ?? defaults.useUTC
        comparedSymbols = try container.decodeIfPresent([String].self, forKey: .comparedSymbols) ?? defaults.comparedSymbols
        movingAverageConfiguration = try container.decodeIfPresent(ChartIndicatorConfiguration.self, forKey: .movingAverageConfiguration) ?? defaults.movingAverageConfiguration
        bollingerBandConfiguration = try container.decodeIfPresent(ChartIndicatorConfiguration.self, forKey: .bollingerBandConfiguration) ?? defaults.bollingerBandConfiguration
        volumeOverlayConfiguration = try container.decodeIfPresent(ChartIndicatorConfiguration.self, forKey: .volumeOverlayConfiguration) ?? defaults.volumeOverlayConfiguration
        volumeConfiguration = try container.decodeIfPresent(ChartIndicatorConfiguration.self, forKey: .volumeConfiguration) ?? defaults.volumeConfiguration
        momentumConfiguration = try container.decodeIfPresent(ChartIndicatorConfiguration.self, forKey: .momentumConfiguration) ?? defaults.momentumConfiguration
        stochasticConfiguration = try container.decodeIfPresent(ChartIndicatorConfiguration.self, forKey: .stochasticConfiguration) ?? defaults.stochasticConfiguration
        parabolicSARConfiguration = try container.decodeIfPresent(ChartIndicatorConfiguration.self, forKey: .parabolicSARConfiguration) ?? defaults.parabolicSARConfiguration
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedTopIndicators, forKey: .selectedTopIndicators)
        try container.encode(selectedBottomIndicators, forKey: .selectedBottomIndicators)
        try container.encode(selectedChartStyle, forKey: .selectedChartStyle)
        try container.encode(showBestBidAskLine, forKey: .showBestBidAskLine)
        try container.encode(useGlobalExchangeColorScheme, forKey: .useGlobalExchangeColorScheme)
        try container.encode(useUTC, forKey: .useUTC)
        try container.encode(comparedSymbols, forKey: .comparedSymbols)
        try container.encode(movingAverageConfiguration, forKey: .movingAverageConfiguration)
        try container.encode(bollingerBandConfiguration, forKey: .bollingerBandConfiguration)
        try container.encode(volumeOverlayConfiguration, forKey: .volumeOverlayConfiguration)
        try container.encode(volumeConfiguration, forKey: .volumeConfiguration)
        try container.encode(momentumConfiguration, forKey: .momentumConfiguration)
        try container.encode(stochasticConfiguration, forKey: .stochasticConfiguration)
        try container.encode(parabolicSARConfiguration, forKey: .parabolicSARConfiguration)
    }

    static var topIndicatorItems: [ChartIndicatorItem] {
        ChartIndicatorID.allCases
            .filter { $0.placement == .top }
            .map(ChartIndicatorItem.init)
    }

    static var bottomIndicatorItems: [ChartIndicatorItem] {
        ChartIndicatorID.allCases
            .filter { $0.placement == .bottom }
            .map(ChartIndicatorItem.init)
    }

    static var chartStyleItems: [ChartStyleItem] {
        ChartStyleID.allCases.map { ChartStyleItem(id: $0) }
    }

    var normalized: ChartSettingsState {
        var state = self
        state.selectedTopIndicators = state.uniqueKnownIndicators(
            state.selectedTopIndicators,
            placement: .top,
            limit: Self.maximumTopIndicatorCount
        )
        state.selectedBottomIndicators = state.uniqueKnownIndicators(
            state.selectedBottomIndicators,
            placement: .bottom,
            limit: Self.maximumBottomIndicatorCount
        )
        state.comparedSymbols = state.normalizedComparedSymbols(state.comparedSymbols)
        state.movingAverageConfiguration = state.movingAverageConfiguration.normalized
        state.bollingerBandConfiguration = state.bollingerBandConfiguration.normalized
        state.volumeOverlayConfiguration = state.volumeOverlayConfiguration.normalized
        state.volumeConfiguration = state.volumeConfiguration.normalized
        state.momentumConfiguration = state.momentumConfiguration.normalized
        state.stochasticConfiguration = state.stochasticConfiguration.normalized
        state.parabolicSARConfiguration = state.parabolicSARConfiguration.normalized
        return state
    }

    var selectedConfigurableIndicators: [ChartIndicatorID] {
        (selectedTopIndicators + selectedBottomIndicators).filter(\.isConfigurable)
    }

    func isIndicatorSelected(_ id: ChartIndicatorID) -> Bool {
        switch id.placement {
        case .top:
            return selectedTopIndicators.contains(id)
        case .bottom:
            return selectedBottomIndicators.contains(id)
        }
    }

    func selectedIndicatorCount(for placement: ChartIndicatorPlacement) -> Int {
        switch placement {
        case .top:
            return selectedTopIndicators.count
        case .bottom:
            return selectedBottomIndicators.count
        }
    }

    mutating func toggleIndicator(_ id: ChartIndicatorID) -> ChartSettingsMutationResult {
        setIndicatorSelected(id, isSelected: !isIndicatorSelected(id))
    }

    @discardableResult
    mutating func setIndicatorSelected(_ id: ChartIndicatorID, isSelected: Bool) -> ChartSettingsMutationResult {
        switch id.placement {
        case .top:
            var nextSelection = selectedTopIndicators
            let result = Self.setIndicatorSelected(
                id,
                isSelected: isSelected,
                in: &nextSelection,
                limit: Self.maximumTopIndicatorCount,
                placement: .top
            )
            if result == .applied {
                selectedTopIndicators = nextSelection
            }
            return result
        case .bottom:
            var nextSelection = selectedBottomIndicators
            let result = Self.setIndicatorSelected(
                id,
                isSelected: isSelected,
                in: &nextSelection,
                limit: Self.maximumBottomIndicatorCount,
                placement: .bottom
            )
            if result == .applied {
                selectedBottomIndicators = nextSelection
            }
            return result
        }
    }

    mutating func selectChartStyle(_ style: ChartStyleID) {
        selectedChartStyle = style
    }

    func indicatorConfiguration(for id: ChartIndicatorID) -> ChartIndicatorConfiguration? {
        switch id {
        case .movingAverage:
            return movingAverageConfiguration
        case .bollingerBand:
            return bollingerBandConfiguration
        case .volumeOverlay:
            return volumeOverlayConfiguration
        case .volume:
            return volumeConfiguration
        case .momentum:
            return momentumConfiguration
        case .stochastic:
            return stochasticConfiguration
        case .parabolicSAR:
            return parabolicSARConfiguration
        default:
            return nil
        }
    }

    mutating func updateIndicatorConfiguration(
        for id: ChartIndicatorID,
        mutation: (inout ChartIndicatorConfiguration) -> Void
    ) {
        switch id {
        case .movingAverage:
            mutation(&movingAverageConfiguration)
            movingAverageConfiguration = movingAverageConfiguration.normalized
        case .bollingerBand:
            mutation(&bollingerBandConfiguration)
            bollingerBandConfiguration = bollingerBandConfiguration.normalized
        case .volumeOverlay:
            mutation(&volumeOverlayConfiguration)
            volumeOverlayConfiguration = volumeOverlayConfiguration.normalized
        case .volume:
            mutation(&volumeConfiguration)
            volumeConfiguration = volumeConfiguration.normalized
        case .momentum:
            mutation(&momentumConfiguration)
            momentumConfiguration = momentumConfiguration.normalized
        case .stochastic:
            mutation(&stochasticConfiguration)
            stochasticConfiguration = stochasticConfiguration.normalized
        case .parabolicSAR:
            mutation(&parabolicSARConfiguration)
            parabolicSARConfiguration = parabolicSARConfiguration.normalized
        default:
            break
        }
    }

    mutating func addComparedSymbol(_ symbol: String) -> ChartComparedSymbolMutationResult {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedSymbol.isEmpty == false else {
            return .duplicate
        }
        guard comparedSymbols.contains(normalizedSymbol) == false else {
            return .duplicate
        }
        guard comparedSymbols.count < Self.maximumComparedSymbolCount else {
            return .limitReached(limit: Self.maximumComparedSymbolCount)
        }
        comparedSymbols.append(normalizedSymbol)
        return .applied
    }

    mutating func removeComparedSymbol(_ symbol: String) {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        comparedSymbols.removeAll { $0 == normalizedSymbol }
    }

    private static func setIndicatorSelected(
        _ id: ChartIndicatorID,
        isSelected: Bool,
        in selection: inout [ChartIndicatorID],
        limit: Int,
        placement: ChartIndicatorPlacement
    ) -> ChartSettingsMutationResult {
        if isSelected == false {
            if let index = selection.firstIndex(of: id) {
                selection.remove(at: index)
            }
            return .applied
        }

        if selection.contains(id) {
            return .applied
        }

        guard selection.count < limit else {
            return .maximumSelectionReached(placement: placement, limit: limit)
        }

        selection.append(id)
        return .applied
    }

    private func uniqueKnownIndicators(
        _ indicators: [ChartIndicatorID],
        placement: ChartIndicatorPlacement,
        limit: Int
    ) -> [ChartIndicatorID] {
        var seen = Set<ChartIndicatorID>()
        var values: [ChartIndicatorID] = []

        for indicator in indicators where indicator.placement == placement && !seen.contains(indicator) {
            seen.insert(indicator)
            values.append(indicator)
            if values.count == limit {
                break
            }
        }

        return values
    }

    private func normalizedComparedSymbols(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        var values: [String] = []
        for symbol in symbols {
            let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard normalizedSymbol.isEmpty == false,
                  seen.insert(normalizedSymbol).inserted else {
                continue
            }
            values.append(normalizedSymbol)
            if values.count == Self.maximumComparedSymbolCount {
                break
            }
        }
        return values
    }
}
