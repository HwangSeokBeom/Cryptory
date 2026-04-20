import SwiftUI

enum Exchange: String, CaseIterable, Identifiable, Codable {
    case upbit
    case bithumb
    case coinone
    case korbit
    case binance

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
        let supportsConnectionManagement: Bool
        let isDomestic: Bool
        let credentialFields: [ExchangeCredentialFieldDefinition]
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
                supportsConnectionManagement: true,
                isDomestic: true,
                credentialFields: [
                    ExchangeCredentialFieldDefinition(fieldKey: .accessKey, title: "Access Key", placeholder: "업비트 Access Key", isSecureEntry: false),
                    ExchangeCredentialFieldDefinition(fieldKey: .secretKey, title: "Secret Key", placeholder: "업비트 Secret Key", isSecureEntry: true)
                ]
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
                supportsConnectionManagement: true,
                isDomestic: true,
                credentialFields: [
                    ExchangeCredentialFieldDefinition(fieldKey: .accessKey, title: "Access Key", placeholder: "빗썸 Access Key", isSecureEntry: false),
                    ExchangeCredentialFieldDefinition(fieldKey: .secretKey, title: "Secret Key", placeholder: "빗썸 Secret Key", isSecureEntry: true)
                ]
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
                supportsConnectionManagement: true,
                isDomestic: true,
                credentialFields: [
                    ExchangeCredentialFieldDefinition(fieldKey: .accessToken, title: "Access Token", placeholder: "코인원 Access Token", isSecureEntry: false),
                    ExchangeCredentialFieldDefinition(fieldKey: .secretKey, title: "Secret Key", placeholder: "코인원 Secret Key", isSecureEntry: true)
                ]
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
                supportsConnectionManagement: true,
                isDomestic: true,
                credentialFields: [
                    ExchangeCredentialFieldDefinition(fieldKey: .accessKey, title: "Access Key", placeholder: "코빗 Access Key", isSecureEntry: false),
                    ExchangeCredentialFieldDefinition(fieldKey: .secretKey, title: "Secret Key", placeholder: "코빗 Secret Key", isSecureEntry: true)
                ]
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
                supportsConnectionManagement: false,
                isDomestic: false,
                credentialFields: []
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
    var supportsConnectionManagement: Bool { metadata.supportsConnectionManagement }
    var isDomestic: Bool { metadata.isDomestic }
    var credentialFields: [ExchangeCredentialFieldDefinition] { metadata.credentialFields }
}
