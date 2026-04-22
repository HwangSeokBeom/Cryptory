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
                supportsConnectionManagement: true,
                isDomestic: false,
                credentialFields: [
                    ExchangeCredentialFieldDefinition(fieldKey: .accessKey, title: "API Key", placeholder: "바이낸스 API Key", isSecureEntry: false),
                    ExchangeCredentialFieldDefinition(fieldKey: .secretKey, title: "Secret Key", placeholder: "바이낸스 Secret Key", isSecureEntry: true)
                ]
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

    var connectionGuide: ExchangeConnectionGuide {
        switch self {
        case .upbit:
            return ExchangeConnectionGuide(
                apiManagementURLString: "https://docs.upbit.com/kr",
                documentationURLString: "https://support.upbit.com/hc/ko/articles/4403180359705-Open-API%EB%A5%BC-%EC%82%AC%EC%9A%A9%ED%95%98%EA%B3%A0-%EC%8B%B6%EC%96%B4%EC%9A%94",
                permissionGuideURLString: "https://docs.upbit.com/kr/docs/api-key",
                issueSummary: "API 키는 업비트 공식 웹사이트에서 직접 발급한 뒤 앱에 붙여넣어 주세요.",
                issuanceSteps: [
                    "이미 키가 있다면 외부 링크를 열지 않고 위 인증 정보에 바로 붙여넣으세요.",
                    "처음 발급하는 경우 공식 Open API 안내에서 발급 조건과 허용 IP 등록 방법을 확인하세요.",
                    "조회 전용은 자산/주문 조회만, 주문 기능은 조회 권한에 주문 권한만 추가하세요."
                ],
                permissionTips: [
                    "조회 전용 연결: 자산 조회, 주문 조회",
                    "주문 가능 연결: 조회 권한 + 주문 권한",
                    "출금 권한은 부여하지 않는 것을 권장"
                ],
                cautionNotes: [
                    "2채널 인증 완료 후 발급할 수 있어요.",
                    "허용 IP는 Key당 최대 10개까지 등록할 수 있어요.",
                    "Secret Key는 발급 시 1회만 확인 가능하고, API Key 유효기간은 1년입니다."
                ],
                testDescription: "입력 형식과 필수 권한 안내를 먼저 점검하고, 저장 후 서버 연결 상태로 최종 반영합니다."
            )
        case .bithumb:
            return ExchangeConnectionGuide(
                apiManagementURLString: "https://apidocs.bithumb.com",
                documentationURLString: "https://apidocs.bithumb.com/v2.1.0/docs/%EB%B9%A0%EB%A5%B8-%EC%8B%9C%EC%9E%91-%EA%B0%80%EC%9D%B4%EB%93%9C",
                permissionGuideURLString: nil,
                issueSummary: "빗썸 마이페이지 API 관리에서 API Key / Secret Key를 발급합니다.",
                issuanceSteps: [
                    "빗썸 웹 로그인 후 마이페이지 > API 관리로 이동하세요.",
                    "자동 거래에 필요한 권한만 선택하고 Key를 생성하세요.",
                    "발급된 Secret Key를 즉시 복사한 뒤 앱에 붙여넣으세요."
                ],
                permissionTips: [
                    "조회용 연결: 자산조회, 주문조회",
                    "주문 연결: 자산조회 + 주문조회 + 주문하기",
                    "불필요한 기능은 허용하지 않는 것이 안전합니다."
                ],
                cautionNotes: [
                    "처음 발급할 때 사용할 기능을 선택해야 해요.",
                    "자동 거래 기준으로는 자산조회, 주문조회, 주문하기만 허용하면 됩니다.",
                    "출금 관련 권한은 연결하지 않는 것을 권장합니다."
                ],
                testDescription: "저장 전에는 필수 필드와 권한 조합을 점검하고, 저장 후 응답 상태로 연결 여부를 확인합니다."
            )
        case .coinone:
            return ExchangeConnectionGuide(
                apiManagementURLString: "https://docs.coinone.co.kr",
                documentationURLString: "https://docs.coinone.co.kr/v1.1/docs/about-public-api",
                permissionGuideURLString: nil,
                issueSummary: "코인원 통합 API 관리에서 Access Token / Secret Key를 발급합니다.",
                issuanceSteps: [
                    "코인원 웹사이트 footer > Open API > 통합 API 관리 > 개인용 API로 이동하세요.",
                    "새로운 키 발급에서 목적에 맞는 권한과 허용 IP를 등록하세요.",
                    "발급된 Access Token과 Secret Key를 앱에 붙여넣고 연결 테스트 후 저장하세요."
                ],
                permissionTips: [
                    "조회용 연결: 잔고 조회, 고객 정보, 주문 조회",
                    "주문 연결: 조회 권한 + 주문 관리",
                    "출금 관련 권한은 비활성화 권장"
                ],
                cautionNotes: [
                    "Private API는 Access Token과 Secret Key 조합을 사용합니다.",
                    "2026년 5월 7일 이후 신규 발급 키는 IP 등록이 필수입니다.",
                    "신규 발급 키 유효기간은 발급 시점부터 1년입니다."
                ],
                testDescription: "코인원은 권한 구성이 세분화되어 있어 저장 전 권한 선택을 다시 확인하는 것이 좋습니다."
            )
        case .korbit:
            return ExchangeConnectionGuide(
                apiManagementURLString: "https://docs.korbit.co.kr",
                documentationURLString: "https://docs.korbit.co.kr/",
                permissionGuideURLString: nil,
                issueSummary: "코빗 계정의 API 관리 페이지에서 API Key를 생성하고 현재 앱은 HMAC 기반 Key/Secret 입력을 사용합니다.",
                issuanceSteps: [
                    "코빗 웹의 API 관리 페이지를 열고 새 API Key를 생성하세요.",
                    "앱 연동용으로는 HMAC-SHA256 방식의 Key/Secret 조합을 우선 사용하세요.",
                    "조회 또는 주문 권한과 허용 IP를 확인한 뒤 앱에서 연결을 저장하세요."
                ],
                permissionTips: [
                    "조회용 연결: 자산 현황, 주문 조회",
                    "주문 연결: 조회 권한 + 주문하기/취소",
                    "지원 정책 변경 시 HMAC 대신 다른 서명 방식이 필요할 수 있습니다."
                ],
                cautionNotes: [
                    "코빗 문서는 API 키 생성과 관리 페이지를 별도로 안내합니다.",
                    "문서상 HMAC-SHA256과 ED25519 방식이 모두 언급되며, 현재 앱 UX는 HMAC Key/Secret 기준입니다.",
                    "허용 IP와 비밀 키 보관 정책을 발급 시 함께 확인하세요."
                ],
                testDescription: "현재 단계에서는 HMAC Key/Secret 입력 기준으로 형식을 점검하고, 저장 후 서버 상태를 확인합니다."
            )
        case .binance:
            return ExchangeConnectionGuide(
                apiManagementURLString: "https://developers.binance.com",
                documentationURLString: nil,
                permissionGuideURLString: nil,
                issueSummary: "바이낸스 API Management에서 API Key / Secret Key를 생성합니다.",
                issuanceSteps: [
                    "Binance 웹 또는 앱에서 API Management를 열고 Create API를 누르세요.",
                    "읽기 권한만 필요한지, Spot Trading까지 필요한지 먼저 결정하세요.",
                    "발급 직후 Secret Key를 복사하고, 가능하면 허용 IP를 제한하세요."
                ],
                permissionTips: [
                    "조회용 연결: Enable Reading",
                    "주문 연결: Enable Reading + Spot Trading",
                    "출금 권한은 연결하지 않는 것을 강하게 권장"
                ],
                cautionNotes: [
                    "KYC 완료 후에만 API Key를 생성할 수 있습니다.",
                    "계정당 최대 30개의 API Key를 만들 수 있습니다.",
                    "신뢰된 IP만 허용하도록 제한하는 것이 권장됩니다."
                ],
                testDescription: "현재 앱에서는 바이낸스 연결을 가이드와 보안 안내 중심으로 제공하고, 실제 개인 기능 확장은 추후 서버 정책에 맞춰 연결됩니다."
            )
        }
    }
}

struct ExchangeConnectionGuide: Equatable {
    let apiManagementURLString: String
    let documentationURLString: String?
    let permissionGuideURLString: String?
    let issueSummary: String
    let issuanceSteps: [String]
    let permissionTips: [String]
    let cautionNotes: [String]
    let testDescription: String
}
