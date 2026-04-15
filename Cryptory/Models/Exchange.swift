import SwiftUI

enum Exchange: String, CaseIterable, Identifiable {
    case upbit, bithumb, coinone, korbit, binance

    struct Metadata {
        let id: String
        let displayName: String
        let shortName: String
        let iconImageName: String
        let color: Color
        let iconText: String
        let supportsOrder: Bool
        let supportsAsset: Bool
        let supportsChart: Bool
        let supportsKimchiPremium: Bool
        let kimchiMultiplier: Double
    }

    var id: String { rawValue }

    var metadata: Metadata {
        switch self {
        case .upbit:
            return Metadata(
                id: rawValue,
                displayName: "업비트",
                shortName: "업비트",
                iconImageName: "exchange.upbit",
                color: Color(hex: "#0050FF"),
                iconText: "U",
                supportsOrder: true,
                supportsAsset: true,
                supportsChart: true,
                supportsKimchiPremium: true,
                kimchiMultiplier: 1.035
            )
        case .bithumb:
            return Metadata(
                id: rawValue,
                displayName: "빗썸",
                shortName: "빗썸",
                iconImageName: "exchange.bithumb",
                color: Color(hex: "#F89F1B"),
                iconText: "B",
                supportsOrder: true,
                supportsAsset: true,
                supportsChart: true,
                supportsKimchiPremium: true,
                kimchiMultiplier: 1.032
            )
        case .coinone:
            return Metadata(
                id: rawValue,
                displayName: "코인원",
                shortName: "코인원",
                iconImageName: "exchange.coinone",
                color: Color(hex: "#00C4B3"),
                iconText: "C",
                supportsOrder: true,
                supportsAsset: true,
                supportsChart: true,
                supportsKimchiPremium: true,
                kimchiMultiplier: 1.028
            )
        case .korbit:
            return Metadata(
                id: rawValue,
                displayName: "코빗",
                shortName: "코빗",
                iconImageName: "exchange.korbit",
                color: Color(hex: "#4A90D9"),
                iconText: "K",
                supportsOrder: true,
                supportsAsset: true,
                supportsChart: true,
                supportsKimchiPremium: true,
                kimchiMultiplier: 1.025
            )
        case .binance:
            return Metadata(
                id: rawValue,
                displayName: "바이낸스",
                shortName: "바낸",
                iconImageName: "exchange.binance",
                color: Color(hex: "#F0B90B"),
                iconText: "Bn",
                supportsOrder: false,
                supportsAsset: false,
                supportsChart: true,
                supportsKimchiPremium: true,
                kimchiMultiplier: 1.0
            )
        }
    }

    var displayName: String { metadata.displayName }

    var shortName: String { metadata.shortName }

    var iconImageName: String { metadata.iconImageName }

    var color: Color { metadata.color }

    var iconText: String { metadata.iconText }

    var supportsOrder: Bool { metadata.supportsOrder }

    var supportsAsset: Bool { metadata.supportsAsset }

    var supportsChart: Bool { metadata.supportsChart }

    var supportsKimchiPremium: Bool { metadata.supportsKimchiPremium }

    var kimchiMultiplier: Double { metadata.kimchiMultiplier }
}
