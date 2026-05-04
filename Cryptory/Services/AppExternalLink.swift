import SafariServices
import SwiftUI

enum AppExternalLink: String, CaseIterable, Identifiable {
    case home
    case privacyPolicy
    case termsOfService
    case support
    case deleteAccount
    case investmentDisclaimer
    case communityPolicy

    static let profilePolicyLinks: [AppExternalLink] = [
        .support,
        .privacyPolicy,
        .termsOfService,
        .communityPolicy,
        .deleteAccount,
        .investmentDisclaimer,
        .home
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "홈페이지"
        case .privacyPolicy:
            return "개인정보처리방침"
        case .termsOfService:
            return "이용약관"
        case .support:
            return "고객지원"
        case .deleteAccount:
            return "계정삭제 안내"
        case .investmentDisclaimer:
            return "투자 유의 및 면책"
        case .communityPolicy:
            return "커뮤니티 운영 정책"
        }
    }

    var profileSubtitle: String {
        switch self {
        case .home:
            return "공식 홈페이지를 엽니다."
        case .privacyPolicy:
            return "개인정보 수집과 처리 기준을 확인합니다."
        case .termsOfService:
            return "서비스 이용 조건과 책임 범위를 확인합니다."
        case .support:
            return "문의, 문제 신고, 앱 사용 지원 페이지를 엽니다."
        case .deleteAccount:
            return "계정 삭제 절차와 데이터 처리 범위를 확인합니다."
        case .investmentDisclaimer:
            return "투자 유의사항과 면책 범위를 확인합니다."
        case .communityPolicy:
            return "커뮤니티 게시글, 댓글, 신고 및 차단 처리 기준을 확인합니다."
        }
    }

    var urlString: String {
        LegalLinksConfigurationCenter.shared.configuration.urlString(for: self)
    }

    var url: URL? {
        SafariDestination.makeURL(from: urlString)
    }

    var analyticsName: String {
        "external_link_\(rawValue)"
    }

    var policyDebugName: String {
        switch self {
        case .home:
            return "homepage"
        case .privacyPolicy:
            return "privacy"
        case .termsOfService:
            return "terms"
        case .support:
            return "support"
        case .deleteAccount:
            return "delete_account"
        case .investmentDisclaimer:
            return "disclaimer"
        case .communityPolicy:
            return "communityPolicy"
        }
    }

    var systemImageName: String {
        switch self {
        case .home:
            return "house"
        case .privacyPolicy:
            return "hand.raised"
        case .termsOfService:
            return "doc.text"
        case .support:
            return "questionmark.circle"
        case .deleteAccount:
            return "person.crop.circle.badge.minus"
        case .investmentDisclaimer:
            return "exclamationmark.triangle"
        case .communityPolicy:
            return "shield.lefthalf.filled"
        }
    }
}

struct LegalLinksConfiguration: Equatable {
    let homepageUrl: String
    let termsUrl: String
    let privacyPolicyUrl: String
    let supportUrl: String
    let accountDeletionUrl: String
    let investmentDisclaimerUrl: String
    let communityPolicyUrl: String

    static let fallback = LegalLinksConfiguration(
        homepageUrl: "https://hwangseokbeom.github.io/Cryptory-legal/",
        termsUrl: "https://hwangseokbeom.github.io/Cryptory-legal/terms.html",
        privacyPolicyUrl: "https://hwangseokbeom.github.io/Cryptory-legal/privacy.html",
        supportUrl: "https://hwangseokbeom.github.io/Cryptory-legal/support.html",
        accountDeletionUrl: "https://hwangseokbeom.github.io/Cryptory-legal/delete-account.html",
        investmentDisclaimerUrl: "https://hwangseokbeom.github.io/Cryptory-legal/disclaimer.html",
        communityPolicyUrl: "https://hwangseokbeom.github.io/Cryptory-legal/community-policy.html"
    )

    init(
        homepageUrl: String,
        termsUrl: String,
        privacyPolicyUrl: String,
        supportUrl: String,
        accountDeletionUrl: String,
        investmentDisclaimerUrl: String,
        communityPolicyUrl: String
    ) {
        self.homepageUrl = homepageUrl
        self.termsUrl = termsUrl
        self.privacyPolicyUrl = privacyPolicyUrl
        self.supportUrl = supportUrl
        self.accountDeletionUrl = accountDeletionUrl
        self.investmentDisclaimerUrl = investmentDisclaimerUrl
        self.communityPolicyUrl = communityPolicyUrl
    }

    init(remote: RemoteLegalLinksConfiguration, fallback: LegalLinksConfiguration = .fallback) {
        self.homepageUrl = Self.validHTTPSString(remote.homepageUrl) ?? fallback.homepageUrl
        self.termsUrl = Self.validHTTPSString(remote.termsUrl) ?? fallback.termsUrl
        self.privacyPolicyUrl = Self.validHTTPSString(remote.privacyPolicyUrl) ?? fallback.privacyPolicyUrl
        self.supportUrl = Self.validHTTPSString(remote.supportUrl) ?? fallback.supportUrl
        self.accountDeletionUrl = Self.validHTTPSString(remote.accountDeletionUrl) ?? fallback.accountDeletionUrl
        self.investmentDisclaimerUrl = Self.validHTTPSString(remote.investmentDisclaimerUrl) ?? fallback.investmentDisclaimerUrl
        self.communityPolicyUrl = Self.validHTTPSString(remote.communityPolicyUrl) ?? fallback.communityPolicyUrl
    }

    func urlString(for link: AppExternalLink) -> String {
        switch link {
        case .home:
            return homepageUrl
        case .privacyPolicy:
            return privacyPolicyUrl
        case .termsOfService:
            return termsUrl
        case .support:
            return supportUrl
        case .deleteAccount:
            return accountDeletionUrl
        case .investmentDisclaimer:
            return investmentDisclaimerUrl
        case .communityPolicy:
            return communityPolicyUrl
        }
    }

    static func decodeServerResponse(from json: Any) throws -> LegalLinksConfiguration? {
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder().decode(PublicAppConfigResponse.self, from: data)
        guard let legal = response.data?.legal else {
            return nil
        }
        return LegalLinksConfiguration(remote: legal)
    }

    private static func validHTTPSString(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false,
              SafariDestination.makeURL(from: rawValue) != nil else {
            return nil
        }
        return rawValue
    }
}

struct PublicAppConfigResponse: Decodable {
    let success: Bool?
    let data: PublicAppConfigData?
}

struct PublicAppConfigData: Decodable {
    let legal: RemoteLegalLinksConfiguration?
}

struct RemoteLegalLinksConfiguration: Decodable {
    let homepageUrl: String?
    let termsUrl: String?
    let privacyPolicyUrl: String?
    let supportUrl: String?
    let accountDeletionUrl: String?
    let investmentDisclaimerUrl: String?
    let communityPolicyUrl: String?

    enum CodingKeys: String, CodingKey {
        case homepageUrl
        case termsUrl
        case privacyPolicyUrl
        case supportUrl
        case accountDeletionUrl
        case accountDeletionGuideUrl
        case investmentDisclaimerUrl
        case communityPolicyUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homepageUrl = try container.decodeIfPresent(String.self, forKey: .homepageUrl)
        termsUrl = try container.decodeIfPresent(String.self, forKey: .termsUrl)
        privacyPolicyUrl = try container.decodeIfPresent(String.self, forKey: .privacyPolicyUrl)
        supportUrl = try container.decodeIfPresent(String.self, forKey: .supportUrl)
        accountDeletionUrl = try container.decodeIfPresent(String.self, forKey: .accountDeletionUrl)
            ?? container.decodeIfPresent(String.self, forKey: .accountDeletionGuideUrl)
        investmentDisclaimerUrl = try container.decodeIfPresent(String.self, forKey: .investmentDisclaimerUrl)
        communityPolicyUrl = try container.decodeIfPresent(String.self, forKey: .communityPolicyUrl)
    }
}

@MainActor
final class LegalLinksConfigurationCenter {
    static let shared = LegalLinksConfigurationCenter()

    private var storedConfiguration: LegalLinksConfiguration
    private var didAttemptRemoteFetch = false

    init(configuration: LegalLinksConfiguration? = nil) {
        self.storedConfiguration = configuration ?? .fallback
    }

    var configuration: LegalLinksConfiguration {
        storedConfiguration
    }

    func refreshIfNeeded(repository: LegalLinksConfigurationRepository? = nil) async {
        guard didAttemptRemoteFetch == false else {
            return
        }
        didAttemptRemoteFetch = true
        let repository = repository ?? LiveLegalLinksConfigurationRepository()

        do {
            let configuration = try await repository.fetchConfiguration()
            storedConfiguration = configuration
            AppLogger.debug(.network, "DEBUG [LegalLink] config source=server")
        } catch {
            AppLogger.debug(.network, "WARN [LegalLink] config source=fallback reason=\(error.localizedDescription)")
        }
    }

    func replaceForTesting(_ configuration: LegalLinksConfiguration, didAttemptRemoteFetch: Bool = false) {
        storedConfiguration = configuration
        self.didAttemptRemoteFetch = didAttemptRemoteFetch
    }
}

@MainActor
protocol LegalLinksConfigurationRepository {
    func fetchConfiguration() async throws -> LegalLinksConfiguration
}

struct LiveLegalLinksConfigurationRepository: LegalLinksConfigurationRepository {
    private let client: APIClient
    private let endpointCandidates: [String]

    init(
        client: APIClient = APIClient(),
        endpointCandidates: [String] = ["/api/v1/app/config", "/api/v1/legal/config", "/app/config", "/public/config"]
    ) {
        self.client = client
        self.endpointCandidates = endpointCandidates
    }

    func fetchConfiguration() async throws -> LegalLinksConfiguration {
        var lastError: Error?

        for endpoint in endpointCandidates {
            do {
                let json = try await client.requestJSON(
                    path: endpoint,
                    accessRequirement: .publicAccess
                )
                if let configuration = try LegalLinksConfiguration.decodeServerResponse(from: json) {
                    return configuration
                }
                AppLogger.debug(.network, "WARN [LegalLink] config endpoint=\(endpoint) reason=missingLegal")
            } catch {
                lastError = error
                AppLogger.debug(.network, "WARN [LegalLink] config endpoint=\(endpoint) reason=\(error.localizedDescription)")
            }
        }

        throw lastError ?? NetworkServiceError.parsingFailed("공개 설정 응답에 링크 정보가 없습니다.")
    }
}

struct SafariDestination: Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL

    init?(link: AppExternalLink) {
        self.init(id: link.analyticsName, title: link.title, urlString: link.urlString)
    }

    init?(id: String? = nil, title: String, urlString: String) {
        guard let url = Self.makeURL(from: urlString) else {
            return nil
        }

        self.id = id ?? "\(title)-\(url.absoluteString)"
        self.title = title
        self.url = url
    }

    static func makeURL(from rawValue: String?) -> URL? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" else {
            return nil
        }

        return url
    }
}

struct SafariSheet: UIViewControllerRepresentable {
    let destination: SafariDestination

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: destination.url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
