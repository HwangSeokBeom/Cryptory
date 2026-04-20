import SwiftUI

struct MarketRowRenderModel: Identifiable, Equatable {
    let id: String
    let exchange: Exchange
    let sourceExchange: Exchange
    let symbol: String
    let displayName: String
    let imageURL: String?
    let priceText: String
    let changeText: String
    let volumeText: String
    let sparklinePayload: MarketSparklineRenderPayload
    let isPricePlaceholder: Bool
    let isChangePlaceholder: Bool
    let isVolumePlaceholder: Bool
    let isUp: Bool
    let flash: FlashType?
    let isFavorite: Bool
    let dataState: MarketRowDataState
    let baseFreshnessState: MarketRowFreshnessState
    let graphState: MarketRowGraphState
    let hasPrice: Bool
    let hasVolume: Bool
    let hasEnoughSparklineData: Bool
    let sparklinePoints: Int

    init(row: MarketRowViewState) {
        self.id = row.id
        self.exchange = row.exchange
        self.sourceExchange = row.sourceExchange
        self.symbol = row.symbol
        self.displayName = row.displayName
        self.imageURL = row.imageURL
        self.priceText = row.priceText
        self.changeText = row.changeText
        self.volumeText = row.volumeText
        self.sparklinePayload = row.sparklinePayload
        self.isPricePlaceholder = row.isPricePlaceholder
        self.isChangePlaceholder = row.isChangePlaceholder
        self.isVolumePlaceholder = row.isVolumePlaceholder
        self.isUp = row.isUp
        self.flash = row.flash
        self.isFavorite = row.isFavorite
        self.dataState = row.dataState
        self.baseFreshnessState = row.baseFreshnessState
        self.graphState = row.graphState
        self.hasPrice = row.hasPrice
        self.hasVolume = row.hasVolume
        self.hasEnoughSparklineData = row.hasEnoughSparklineData
        self.sparklinePoints = row.sparklinePoints
    }

    init(
        id: String,
        exchange: Exchange,
        sourceExchange: Exchange,
        symbol: String,
        displayName: String,
        imageURL: String?,
        priceText: String,
        changeText: String,
        volumeText: String,
        sparklinePayload: MarketSparklineRenderPayload,
        isPricePlaceholder: Bool = false,
        isChangePlaceholder: Bool = false,
        isVolumePlaceholder: Bool = false,
        isUp: Bool,
        flash: FlashType? = nil,
        isFavorite: Bool = false,
        dataState: MarketRowDataState = .live,
        baseFreshnessState: MarketRowFreshnessState = .live,
        graphState: MarketRowGraphState = .liveVisible,
        hasPrice: Bool = true,
        hasVolume: Bool = true,
        hasEnoughSparklineData: Bool = true,
        sparklinePoints: Int
    ) {
        self.id = id
        self.exchange = exchange
        self.sourceExchange = sourceExchange
        self.symbol = symbol
        self.displayName = displayName
        self.imageURL = imageURL
        self.priceText = priceText
        self.changeText = changeText
        self.volumeText = volumeText
        self.sparklinePayload = sparklinePayload
        self.isPricePlaceholder = isPricePlaceholder
        self.isChangePlaceholder = isChangePlaceholder
        self.isVolumePlaceholder = isVolumePlaceholder
        self.isUp = isUp
        self.flash = flash
        self.isFavorite = isFavorite
        self.dataState = dataState
        self.baseFreshnessState = baseFreshnessState
        self.graphState = graphState
        self.hasPrice = hasPrice
        self.hasVolume = hasVolume
        self.hasEnoughSparklineData = hasEnoughSparklineData
        self.sparklinePoints = sparklinePoints
    }
}

struct CoinRowView: View, Equatable {
    let row: MarketRowViewState
    let configuration: MarketListDisplayConfiguration
    let selectedExchange: Exchange
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onVisible: () -> Void

    static func == (lhs: CoinRowView, rhs: CoinRowView) -> Bool {
        lhs.row == rhs.row
            && lhs.selectedExchange == rhs.selectedExchange
            && lhs.configuration == rhs.configuration
    }

    private var renderModel: MarketRowRenderModel {
        MarketRowRenderModel(row: row)
    }

    var body: some View {
        Button(action: onSelect) {
            MarketRowContent(
                model: renderModel,
                configuration: configuration,
                showsFavoriteControl: true,
                onToggleFavorite: onToggleFavorite
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            onVisible()
            logRender()
        }
        .onChange(of: renderSignature) { _, _ in
            logRender()
        }
    }

    private var renderSignature: String {
        [
            row.id,
            configuration.mode.rawValue,
            row.priceText,
            row.changeText,
            row.volumeText,
            row.sparklineRenderToken,
            row.isFavorite ? "1" : "0"
        ].joined(separator: "|")
    }

    private func logRender() {
        AppLogger.debug(
            .lifecycle,
            "[MarketRow] render selectedExchange=\(selectedExchange.rawValue) sourceExchange=\(row.sourceExchange.rawValue) exchange=\(row.exchange.rawValue) symbol=\(row.symbol) mode=\(configuration.mode.rawValue) state=\(String(describing: row.dataState)) baseFreshness=\(row.baseFreshnessState) graphState=\(row.graphState) hasPrice=\(row.hasPrice) hasVolume=\(row.hasVolume) sparklinePointCount=\(row.sparklinePoints) hasEnoughSparklineData=\(row.hasEnoughSparklineData)"
        )
        AppLogger.debug(
            .lifecycle,
            "[CellLayout] symbol=\(row.symbol) mode=\(configuration.mode.rawValue) graphWidth=\(Int(configuration.sparklineWidth)) image=\(configuration.showsSymbolImage)"
        )
    }
}

struct MarketRowContent: View {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration
    let showsFavoriteControl: Bool
    let onToggleFavorite: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            MarketRowIdentitySection(
                model: model,
                configuration: configuration,
                showsFavoriteControl: showsFavoriteControl,
                onToggleFavorite: onToggleFavorite
            )
            .frame(
                minWidth: configuration.symbolColumnMinimumWidth,
                maxWidth: .infinity,
                alignment: .leading
            )
            .layoutPriority(4)

            MarketRowPriceSection(
                model: model,
                configuration: configuration
            )
            .frame(width: configuration.priceWidth, alignment: .trailing)
            .layoutPriority(3)

            MarketRowChangeSection(
                model: model,
                configuration: configuration
            )
            .frame(width: configuration.changeWidth, alignment: .trailing)
            .padding(.leading, configuration.compactLayout ? 8 : 0)
            .layoutPriority(2)

            if configuration.showsVolume {
                MarketRowVolumeSection(
                    model: model,
                    configuration: configuration
                )
                .frame(width: configuration.volumeWidth, alignment: .trailing)
                .padding(.leading, 6)
                .layoutPriority(1)
            }

            if configuration.showsSparkline {
                MarketSparklineSection(
                    payload: model.sparklinePayload,
                    isUp: model.isUp,
                    exchange: model.exchange,
                    symbol: model.symbol,
                    width: configuration.sparklineWidth,
                    height: configuration.sparklineHeight
                )
                .equatable()
                .frame(width: configuration.sparklineWidth, alignment: .trailing)
                .padding(.leading, configuration.compactLayout ? 10 : 6)
                .layoutPriority(2)
            }
        }
        .frame(minHeight: configuration.rowHeight)
        .padding(.horizontal, 16)
        .padding(.vertical, configuration.rowVerticalPadding)
    }
}

private struct MarketRowIdentitySection: View {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration
    let showsFavoriteControl: Bool
    let onToggleFavorite: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if showsFavoriteControl {
                Button(action: { onToggleFavorite?() }) {
                    Image(systemName: model.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(model.isFavorite ? .accent : .textMuted)
                }
                .buttonStyle(.plain)
            }

            if configuration.showsSymbolImage {
                SymbolImageView(
                    symbol: model.symbol,
                    imageURL: model.imageURL,
                    size: configuration.symbolImageSize
                )
            } else {
                Circle()
                    .fill(model.exchange.color.opacity(0.9))
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: configuration.compactLayout ? 1 : 2) {
                Text(model.symbol)
                    .font(configuration.compactLayout ? .system(size: 12, weight: .heavy) : .system(size: 13, weight: .bold))
                    .foregroundColor(.themeText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(3)

                Text(model.displayName)
                    .font(configuration.compactLayout ? .system(size: 9, weight: .medium) : .system(size: 10))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
        }
    }
}

private struct MarketRowPriceSection: View {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration

    var body: some View {
        Text(model.priceText)
            .font(configuration.compactLayout ? .mono(12, weight: .bold) : .mono(13, weight: .bold))
            .foregroundColor(
                model.isPricePlaceholder
                    ? .textMuted
                    : (configuration.emphasizesChangeRate ? .themeText : (model.isUp ? .up : .down))
            )
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.vertical, 4)
            .background(flashBackground)
    }

    private var flashBackground: some View {
        Group {
            if let flash = model.flash {
                RoundedRectangle(cornerRadius: 4)
                    .fill(flash == .up ? Color.up.opacity(0.15) : Color.down.opacity(0.15))
                    .animation(.easeOut(duration: 0.5), value: model.flash == nil)
            } else {
                Color.clear
            }
        }
    }
}

private struct MarketRowChangeSection: View {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration

    var body: some View {
        if configuration.emphasizesChangeRate {
            Text(model.changeText)
                .font(.mono(12, weight: .bold))
                .foregroundColor(changeForegroundColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(changeBackgroundColor)
                )
        } else {
            Text(model.changeText)
                .font(.mono(12, weight: .semibold))
                .foregroundColor(changeForegroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private var changeForegroundColor: Color {
        model.isChangePlaceholder ? .textMuted : (model.isUp ? .up : .down)
    }

    private var changeBackgroundColor: Color {
        if model.isChangePlaceholder {
            return Color.bgTertiary.opacity(0.8)
        }
        return model.isUp ? Color.up.opacity(0.14) : Color.down.opacity(0.16)
    }
}

private struct MarketRowVolumeSection: View {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration

    var body: some View {
        Text(model.volumeText)
            .font(configuration.compactLayout ? .mono(10, weight: .medium) : .mono(10, weight: .medium))
            .foregroundColor(model.isVolumePlaceholder ? .textMuted : .textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

private struct MarketSparklineSection: View, Equatable {
    let payload: MarketSparklineRenderPayload
    let isUp: Bool
    let exchange: Exchange
    let symbol: String
    let width: CGFloat
    let height: CGFloat

    static func == (lhs: MarketSparklineSection, rhs: MarketSparklineSection) -> Bool {
        lhs.payload == rhs.payload
            && lhs.isUp == rhs.isUp
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.exchange == rhs.exchange
            && lhs.symbol == rhs.symbol
    }

    var body: some View {
        SparklineView(
            payload: payload,
            isUp: isUp,
            exchange: exchange,
            symbol: symbol,
            width: width,
            height: height
        )
    }
}
