import Foundation

enum ExchangeConnectionPermission: String, CaseIterable, Equatable, Hashable {
    case readOnly = "read_only"
    case tradeEnabled = "trade_enabled"

    var title: String {
        switch self {
        case .readOnly:
            return "조회 전용"
        case .tradeEnabled:
            return "주문 가능"
        }
    }

    var description: String {
        switch self {
        case .readOnly:
            return "잔고와 체결 내역만 조회할 수 있어요."
        case .tradeEnabled:
            return "잔고 조회와 주문 실행을 모두 사용할 수 있어요."
        }
    }
}

enum ExchangeConnectionStatus: String, Equatable {
    case connected
    case disconnected
    case validating
    case failed
    case maintenance
    case unknown

    var title: String {
        switch self {
        case .connected:
            return "연결됨"
        case .disconnected:
            return "연결 안 됨"
        case .validating:
            return "검증 중"
        case .failed:
            return "인증 실패"
        case .maintenance:
            return "점검 중"
        case .unknown:
            return "상태 확인 중"
        }
    }
}

enum ExchangeCredentialFieldKey: String, CaseIterable, Identifiable {
    case accessKey
    case secretKey
    case accessToken

    var id: String { rawValue }

    var requestKey: String { rawValue }
}

struct ExchangeCredentialFieldDefinition: Identifiable, Equatable {
    var id: String { fieldKey.rawValue }

    let fieldKey: ExchangeCredentialFieldKey
    let title: String
    let placeholder: String
    let isSecureEntry: Bool
}

struct ExchangeConnection: Identifiable, Equatable {
    let id: String
    let exchange: Exchange
    let permission: ExchangeConnectionPermission
    let nickname: String?
    let isActive: Bool
    let status: ExchangeConnectionStatus
    let statusMessage: String?
    let maskedCredentialSummary: String?
    let lastValidatedAt: Date?
    let updatedAt: Date?

    var displayTitle: String {
        nickname?.isEmpty == false ? nickname! : exchange.displayName
    }
}

struct ExchangeConnectionUpsertRequest: Equatable {
    let exchange: Exchange
    let permission: ExchangeConnectionPermission
    let nickname: String?
    let credentials: [ExchangeCredentialFieldKey: String]
}

struct ExchangeConnectionUpdateRequest: Equatable {
    let id: String
    let permission: ExchangeConnectionPermission?
    let nickname: String?
    let credentials: [ExchangeCredentialFieldKey: String]
}

struct ExchangeConnectionCRUDCapability: Equatable {
    let canCreate: Bool
    let canDelete: Bool
    let canUpdate: Bool

    static let readOnly = ExchangeConnectionCRUDCapability(canCreate: false, canDelete: false, canUpdate: false)
}

struct ExchangeConnectionCardViewState: Identifiable, Equatable {
    let id: String
    let connection: ExchangeConnection
    let statusChips: [String]
    let secondaryMessage: String
    let canEdit: Bool
    let canDelete: Bool
}

struct ExchangeConnectionFormViewState: Equatable {
    enum Mode: Equatable {
        case create
        case edit(connectionID: String)
    }

    let mode: Mode
    let exchange: Exchange
    let credentialFields: [ExchangeCredentialFieldDefinition]
    let submitTitle: String
    let helperMessage: String
    let requiresSecretOnUpdateExplanation: String

    static func create(exchange: Exchange) -> ExchangeConnectionFormViewState {
        ExchangeConnectionFormViewState(
            mode: .create,
            exchange: exchange,
            credentialFields: exchange.credentialFields,
            submitTitle: "추가",
            helperMessage: "실제 거래소 비밀키는 앱에 저장하지 않고 서버 연결 API 에만 전달합니다.",
            requiresSecretOnUpdateExplanation: ""
        )
    }

    static func edit(connection: ExchangeConnection) -> ExchangeConnectionFormViewState {
        ExchangeConnectionFormViewState(
            mode: .edit(connectionID: connection.id),
            exchange: connection.exchange,
            credentialFields: connection.exchange.credentialFields,
            submitTitle: "수정",
            helperMessage: "기존 secret 은 다시 보여주지 않습니다.",
            requiresSecretOnUpdateExplanation: "secret 을 바꾸려면 새 값을 다시 입력하세요."
        )
    }
}
