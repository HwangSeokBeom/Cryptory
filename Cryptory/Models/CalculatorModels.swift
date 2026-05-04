import Foundation

struct USDTQuote: Equatable {
    let symbol: String
    let name: String?
    let convert: String
    let price: Double
    let source: String
    let cacheHit: Bool?
    let updatedAt: Date?
    let expiresAt: Date?
    let reason: String?
}

struct USDTExchangeRateResponseDTO: Decodable, Equatable {
    let success: Bool
    let data: USDTExchangeRateDTO
}

struct USDTExchangeRateDTO: Decodable, Equatable {
    let symbol: String
    let name: String?
    let convert: String
    let price: Double?
    let source: String
    let cacheHit: Bool?
    let updatedAt: String?
    let expiresAt: String?
    let reason: String?
}

enum USDTExchangeRateMapper {
    static func quote(from response: USDTExchangeRateResponseDTO) throws -> USDTQuote {
        guard response.success else {
            throw NetworkServiceError.parsingFailed("USDT 환율 응답이 실패로 반환됐습니다.")
        }
        guard let price = response.data.price, price.isFinite, price > 0 else {
            throw NetworkServiceError.parsingFailed("USDT 환율 가격이 비어 있습니다.")
        }
        return USDTQuote(
            symbol: response.data.symbol,
            name: response.data.name,
            convert: response.data.convert,
            price: price,
            source: response.data.source,
            cacheHit: response.data.cacheHit,
            updatedAt: parseDate(response.data.updatedAt),
            expiresAt: parseDate(response.data.expiresAt),
            reason: response.data.reason
        )
    }

    static func krwAmount(usdt: Double, rate: Double) -> Double? {
        guard usdt.isFinite, rate.isFinite, rate > 0 else { return nil }
        let value = usdt * rate
        return value.isFinite ? value : nil
    }

    static func usdtAmount(krw: Double, rate: Double) -> Double? {
        guard krw.isFinite, rate.isFinite, rate > 0 else { return nil }
        let value = krw / rate
        return value.isFinite ? value : nil
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        if let timestamp = Double(value) {
            let seconds = timestamp > 1_000_000_000_000 ? timestamp / 1000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        if let date = iso8601WithFraction.date(from: value) {
            return date
        }
        return iso8601.date(from: value)
    }

    private static let iso8601WithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()
}
