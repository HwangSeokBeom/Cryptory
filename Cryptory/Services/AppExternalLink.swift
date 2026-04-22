import SafariServices
import SwiftUI

enum AppExternalLink: String, CaseIterable, Identifiable {
    case home
    case privacyPolicy
    case termsOfService
    case support
    case deleteAccount
    case investmentDisclaimer

    private static var baseURLString: String {
        let rawValue = AppRuntimeConfiguration.live.webBaseURL.absoluteString
        return rawValue.hasSuffix("/") ? rawValue : rawValue + "/"
    }

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
        }
    }

    var urlString: String {
        switch self {
        case .home:
            return Self.baseURLString
        case .privacyPolicy:
            return Self.baseURLString + "privacy.html"
        case .termsOfService:
            return Self.baseURLString + "terms.html"
        case .support:
            return Self.baseURLString + "support.html"
        case .deleteAccount:
            return Self.baseURLString + "delete-account.html"
        case .investmentDisclaimer:
            return Self.baseURLString + "disclaimer.html"
        }
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
        }
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
              ["http", "https"].contains(scheme) else {
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
