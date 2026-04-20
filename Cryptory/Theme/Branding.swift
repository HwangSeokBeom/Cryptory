import Foundation

enum BrandIdentity {
    static let koreanName = "크립토리"
    static let englishName = "Cryptory"
    static let countryLabel = "대한민국"
    static let tagline = "Digital Asset Trading"

    static var accessibilityLabel: String {
        "\(koreanName), \(englishName)"
    }
}
