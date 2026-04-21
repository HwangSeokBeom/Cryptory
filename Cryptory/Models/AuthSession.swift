import Foundation
import Security

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let userID: String?
    let email: String?
}

enum AuthFlowMode: String, CaseIterable, Equatable {
    case login
    case signUp

    var title: String {
        switch self {
        case .login:
            return "로그인"
        case .signUp:
            return "회원가입"
        }
    }
}

protocol AuthSessionStoring {
    func loadSession() -> AuthSession?
    func saveSession(_ session: AuthSession)
    func clearSession()
}

struct KeychainAuthSessionStore: AuthSessionStoring {
    private let service = "com.cryptory.auth.session"
    private let account = "default"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadSession() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? decoder.decode(AuthSession.self, from: data)
    }

    func saveSession(_ session: AuthSession) {
        guard let data = try? encoder.encode(session) else {
            return
        }

        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertQuery = baseQuery
            insertQuery[kSecValueData as String] = data
            insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }

    func clearSession() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
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
