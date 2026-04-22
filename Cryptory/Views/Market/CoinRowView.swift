import SwiftUI

struct MarketRowRenderModel: Identifiable, Equatable {
    let id: String
    let marketIdentity: MarketIdentity
    let exchange: Exchange
    let sourceExchange: Exchange
    let symbol: String
    let canonicalSymbol: String
    let displaySymbol: String
    let displayName: String
    let imageURL: String?
    let hasImage: Bool?
    let localAssetName: String
    let symbolImageState: MarketRowSymbolImageState
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
        self.marketIdentity = row.marketIdentity
        self.exchange = row.exchange
        self.sourceExchange = row.sourceExchange
        self.symbol = row.symbol
        self.canonicalSymbol = row.canonicalSymbol
        self.displaySymbol = row.displaySymbol
        self.displayName = row.displayName
        self.imageURL = row.imageURL
        self.hasImage = row.hasImage
        self.localAssetName = row.localAssetName
        self.symbolImageState = row.symbolImageState
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
        marketIdentity: MarketIdentity,
        symbol: String,
        canonicalSymbol: String? = nil,
        displaySymbol: String? = nil,
        displayName: String,
        imageURL: String?,
        hasImage: Bool? = nil,
        localAssetName: String? = nil,
        symbolImageState: MarketRowSymbolImageState = .placeholder,
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
        self.marketIdentity = marketIdentity
        self.exchange = exchange
        self.sourceExchange = sourceExchange
        self.symbol = symbol
        self.canonicalSymbol = canonicalSymbol ?? SymbolNormalization.canonicalAssetCode(rawSymbol: symbol)
        self.displaySymbol = displaySymbol ?? self.canonicalSymbol
        self.displayName = displayName
        self.imageURL = imageURL
        self.hasImage = hasImage
        self.localAssetName = localAssetName ?? SymbolNormalization.localAssetName(for: self.canonicalSymbol)
        self.symbolImageState = symbolImageState
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
        }
    }
}

struct MarketRowContent: View {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration
    let showsFavoriteControl: Bool
    let onToggleFavorite: (() -> Void)?

    private var sparklineColumnWidth: CGFloat {
        max(configuration.sparklineWidth, configuration.sparklineMinimumWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            MarketRowIdentitySection(
                model: model,
                configuration: configuration,
                showsFavoriteControl: showsFavoriteControl,
                onToggleFavorite: onToggleFavorite
            )
            .equatable()
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
            .equatable()
            .frame(width: configuration.priceWidth, alignment: .trailing)
            .layoutPriority(3)

            MarketRowChangeSection(
                model: model,
                configuration: configuration
            )
            .equatable()
            .frame(width: configuration.changeWidth, alignment: .trailing)
            .padding(.leading, configuration.changeColumnLeadingPadding)
            .layoutPriority(4)

            if configuration.showsVolume {
                MarketRowVolumeSection(
                    model: model,
                    configuration: configuration
                )
                .equatable()
                .frame(width: configuration.volumeWidth, alignment: .trailing)
                .padding(.leading, 6)
                .layoutPriority(1)
            }

            if configuration.showsSparkline {
                MarketSparklineSection(
                    payload: model.sparklinePayload,
                    isUp: model.isUp,
                    marketIdentity: model.marketIdentity,
                    width: configuration.sparklineWidth,
                    height: configuration.sparklineHeight
                )
                .equatable()
                .frame(width: sparklineColumnWidth, alignment: .trailing)
                .padding(.leading, configuration.sparklineColumnLeadingPadding)
                .layoutPriority(3)
            }
        }
        .frame(minHeight: configuration.rowHeight)
        .padding(.horizontal, 16)
        .padding(.vertical, configuration.rowVerticalPadding)
    }
}

private struct MarketRowIdentitySection: View, Equatable {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration
    let showsFavoriteControl: Bool
    let onToggleFavorite: (() -> Void)?

    static func == (lhs: MarketRowIdentitySection, rhs: MarketRowIdentitySection) -> Bool {
        lhs.model.marketIdentity == rhs.model.marketIdentity
            && lhs.model.exchange == rhs.model.exchange
            && lhs.model.symbol == rhs.model.symbol
            && lhs.model.canonicalSymbol == rhs.model.canonicalSymbol
            && lhs.model.displaySymbol == rhs.model.displaySymbol
            && lhs.model.displayName == rhs.model.displayName
            && lhs.model.imageURL == rhs.model.imageURL
            && lhs.model.hasImage == rhs.model.hasImage
            && lhs.model.localAssetName == rhs.model.localAssetName
            && lhs.model.symbolImageState == rhs.model.symbolImageState
            && lhs.model.isFavorite == rhs.model.isFavorite
            && lhs.configuration == rhs.configuration
            && lhs.showsFavoriteControl == rhs.showsFavoriteControl
    }

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
                    marketIdentity: model.marketIdentity,
                    symbol: model.symbol,
                    canonicalSymbol: model.canonicalSymbol,
                    imageURL: model.imageURL,
                    hasImage: model.hasImage,
                    localAssetName: model.localAssetName,
                    symbolImageState: model.symbolImageState,
                    size: configuration.symbolImageSize
                )
                .frame(width: configuration.symbolImageSize, height: configuration.symbolImageSize)
                .clipped()
            } else {
                Circle()
                    .fill(model.exchange.color.opacity(0.9))
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: configuration.compactLayout ? 1 : 2) {
                Text(model.displaySymbol)
                    .font(configuration.compactLayout ? .system(size: 12, weight: .heavy) : .system(size: 13, weight: .bold))
                    .foregroundColor(.themeText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .layoutPriority(2)

                Text(model.displayName)
                    .font(configuration.compactLayout ? .system(size: 9, weight: .medium) : .system(size: 10))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.84)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MarketRowPriceSection: View, Equatable {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration

    static func == (lhs: MarketRowPriceSection, rhs: MarketRowPriceSection) -> Bool {
        lhs.model.priceText == rhs.model.priceText
            && lhs.model.isPricePlaceholder == rhs.model.isPricePlaceholder
            && lhs.model.isUp == rhs.model.isUp
            && lhs.model.flash == rhs.model.flash
            && lhs.configuration == rhs.configuration
    }

    var body: some View {
        Text(model.priceText)
            .font(configuration.compactLayout ? .mono(12, weight: .bold) : .mono(13, weight: .bold))
            .foregroundColor(
                model.isPricePlaceholder
                    ? .textMuted
                    : (configuration.emphasizesChangeRate ? .themeText : (model.isUp ? .up : .down))
            )
            .lineLimit(1)
            .minimumScaleFactor(configuration.emphasizesChangeRate ? 0.74 : 0.82)
            .allowsTightening(true)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .trailing)
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

private struct MarketRowChangeSection: View, Equatable {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration

    static func == (lhs: MarketRowChangeSection, rhs: MarketRowChangeSection) -> Bool {
        lhs.model.changeText == rhs.model.changeText
            && lhs.model.isChangePlaceholder == rhs.model.isChangePlaceholder
            && lhs.model.isUp == rhs.model.isUp
            && lhs.configuration == rhs.configuration
    }

    var body: some View {
        if configuration.emphasizesChangeRate {
            Text(model.changeText)
                .font(.mono(12, weight: .bold))
                .foregroundColor(changeForegroundColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .padding(.horizontal, 10)
                .frame(
                    minWidth: configuration.changeBadgeMinWidth,
                    maxWidth: configuration.changeWidth,
                    minHeight: configuration.changeBadgeHeight,
                    alignment: .center
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: configuration.changeBadgeHeight > 0
                            ? configuration.changeBadgeHeight / 2
                            : 12,
                        style: .continuous
                    )
                        .fill(changeBackgroundColor)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Text(model.changeText)
                .font(.mono(12, weight: .semibold))
                .foregroundColor(changeForegroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .trailing)
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

private struct MarketRowVolumeSection: View, Equatable {
    let model: MarketRowRenderModel
    let configuration: MarketListDisplayConfiguration

    static func == (lhs: MarketRowVolumeSection, rhs: MarketRowVolumeSection) -> Bool {
        lhs.model.volumeText == rhs.model.volumeText
            && lhs.model.isVolumePlaceholder == rhs.model.isVolumePlaceholder
            && lhs.configuration == rhs.configuration
    }

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
    let marketIdentity: MarketIdentity
    let width: CGFloat
    let height: CGFloat

    static func == (lhs: MarketSparklineSection, rhs: MarketSparklineSection) -> Bool {
        lhs.payload == rhs.payload
            && lhs.isUp == rhs.isUp
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.marketIdentity == rhs.marketIdentity
    }

    var body: some View {
        SparklineView(
            payload: payload,
            isUp: isUp,
            marketIdentity: marketIdentity,
            width: width,
            height: height
        )
    }
}
