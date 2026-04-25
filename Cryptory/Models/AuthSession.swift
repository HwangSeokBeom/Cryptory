import Foundation
import Security

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let refreshTokenExpiresAt: String?
    let sessionID: String?
    let userID: String?
    let email: String?

    init(
        accessToken: String,
        refreshToken: String?,
        tokenType: String? = nil,
        expiresIn: Int? = nil,
        refreshTokenExpiresAt: String? = nil,
        sessionID: String? = nil,
        userID: String?,
        email: String?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.sessionID = sessionID
        self.userID = userID
        self.email = email
    }

    var hasRefreshToken: Bool {
        refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func replacingRefreshTokenIfMissing(with fallbackRefreshToken: String?) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken?.authTrimmedNonEmpty ?? fallbackRefreshToken?.authTrimmedNonEmpty,
            tokenType: tokenType,
            expiresIn: expiresIn,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            sessionID: sessionID,
            userID: userID,
            email: email
        )
    }
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
    private let legacyAccount = "default"
    private let accessTokenAccount = "accessToken"
    private let refreshTokenAccount = "refreshToken"
    private let metadataAccount = "metadata"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadSession() -> AuthSession? {
        if let accessToken = loadString(account: accessTokenAccount) {
            let metadata = loadMetadata()
            return AuthSession(
                accessToken: accessToken,
                refreshToken: loadString(account: refreshTokenAccount),
                tokenType: metadata?.tokenType,
                expiresIn: metadata?.expiresIn,
                refreshTokenExpiresAt: metadata?.refreshTokenExpiresAt,
                sessionID: metadata?.sessionID,
                userID: metadata?.userID,
                email: metadata?.email
            )
        }

        if let legacySession = loadLegacySession() {
            saveSession(legacySession)
            delete(account: legacyAccount)
            return legacySession
        }

        return nil
    }

    func saveSession(_ session: AuthSession) {
        saveString(session.accessToken, account: accessTokenAccount)

        if let refreshToken = session.refreshToken?.authTrimmedNonEmpty {
            saveString(refreshToken, account: refreshTokenAccount)
        } else {
            delete(account: refreshTokenAccount)
        }

        saveMetadata(
            AuthSessionMetadata(
                tokenType: session.tokenType,
                expiresIn: session.expiresIn,
                refreshTokenExpiresAt: session.refreshTokenExpiresAt,
                sessionID: session.sessionID,
                userID: session.userID,
                email: session.email
            )
        )
        delete(account: legacyAccount)
    }

    func clearSession() {
        [
            legacyAccount,
            accessTokenAccount,
            refreshTokenAccount,
            metadataAccount
        ].forEach(delete(account:))
    }

    private func loadLegacySession() -> AuthSession? {
        guard let data = loadData(account: legacyAccount) else { return nil }
        return try? decoder.decode(AuthSession.self, from: data)
    }

    private func loadMetadata() -> AuthSessionMetadata? {
        guard let data = loadData(account: metadataAccount) else { return nil }
        return try? decoder.decode(AuthSessionMetadata.self, from: data)
    }

    private func saveMetadata(_ metadata: AuthSessionMetadata) {
        guard let data = try? encoder.encode(metadata) else { return }
        saveData(data, account: metadataAccount)
    }

    private func loadString(account: String) -> String? {
        guard let data = loadData(account: account),
              let value = String(data: data, encoding: .utf8),
              let trimmedValue = value.authTrimmedNonEmpty else {
            return nil
        }
        return trimmedValue
    }

    private func saveString(_ value: String, account: String) {
        saveData(Data(value.utf8), account: account)
    }

    private func loadData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func saveData(_ data: Data, account: String) {
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertQuery = baseQuery(account: account)
            insertQuery[kSecValueData as String] = data
            insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }

    private func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct AuthSessionMetadata: Codable, Equatable {
    let tokenType: String?
    let expiresIn: Int?
    let refreshTokenExpiresAt: String?
    let sessionID: String?
    let userID: String?
    let email: String?
}

private extension String {
    var authTrimmedNonEmpty: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
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
