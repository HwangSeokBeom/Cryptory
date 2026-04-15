import Foundation

struct AuthSession {
    let accessToken: String
    let refreshToken: String?
    let userID: String?
    let email: String?
}

enum AuthState {
    case guest
    case signingIn
    case authenticated(AuthSession)
}

extension AuthState {
    var session: AuthSession? {
        guard case .authenticated(let session) = self else { return nil }
        return session
    }

    var isAuthenticated: Bool {
        session != nil
    }
}

enum ProtectedFeature: String, Identifiable, Equatable {
    case portfolio
    case trade
    case exchangeConnections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portfolio:
            return "자산"
        case .trade:
            return "주문"
        case .exchangeConnections:
            return "거래소 연결"
        }
    }

    var message: String {
        switch self {
        case .portfolio:
            return "이 기능은 로그인 후 사용할 수 있어요"
        case .trade:
            return "주문은 로그인과 거래소 연결이 필요한 개인 기능이에요"
        case .exchangeConnections:
            return "거래소 API 키 연결과 관리는 로그인 후 사용할 수 있어요"
        }
    }

    var detail: String {
        switch self {
        case .portfolio:
            return "로그인 후 내 자산과 거래소 연결을 관리할 수 있어요."
        case .trade:
            return "거래소 연결 후 내 주문과 체결 내역을 확인할 수 있어요."
        case .exchangeConnections:
            return "읽기 전용 연결과 주문 가능 연결 정책을 확인하고 관리할 수 있어요."
        }
    }
}
