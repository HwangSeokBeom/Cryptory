import Foundation

protocol PriceAlertRepositoryProtocol {
    func fetchPriceAlerts(session: AuthSession, exchange: Exchange, symbol: String, quoteCurrency: MarketQuoteCurrency) async throws -> [PriceAlert]
    func savePriceAlert(session: AuthSession, draft: PriceAlertDraft) async throws -> PriceAlert
    func deletePriceAlert(session: AuthSession, alertId: String) async throws
}

final class LivePriceAlertRepository: PriceAlertRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchPriceAlerts(session: AuthSession, exchange: Exchange, symbol: String, quoteCurrency: MarketQuoteCurrency) async throws -> [PriceAlert] {
        AppLogger.debug(.network, "[PriceAlert] load symbol=\(symbol) quote=\(quoteCurrency.rawValue)")
        let json = try await client.requestJSON(
            path: client.configuration.priceAlertsPath,
            queryItems: [
                URLQueryItem(name: "exchange", value: exchange.rawValue),
                URLQueryItem(name: "symbol", value: symbol),
                URLQueryItem(name: "quoteCurrency", value: quoteCurrency.rawValue)
            ],
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
        return parseAlerts(from: unwrapAlertPayload(json))
    }

    func savePriceAlert(session: AuthSession, draft: PriceAlertDraft) async throws -> PriceAlert {
        guard let targetPrice = draft.targetPrice, targetPrice > 0 else {
            throw NetworkServiceError.parsingFailed("목표 가격은 0보다 커야 합니다.")
        }
        AppLogger.debug(.network, "[PriceAlert] save condition=\(draft.condition.rawValue) target=\(targetPrice)")
        let body: JSONObject = [
            "exchange": draft.exchange.rawValue,
            "symbol": draft.symbol,
            "quoteCurrency": draft.quoteCurrency.rawValue,
            "condition": draft.condition.rawValue,
            "targetPrice": targetPrice,
            "repeatPolicy": draft.repeatPolicy.rawValue,
            "isActive": draft.isActive
        ]
        let path = draft.alertId.map { client.configuration.priceAlertPath(id: $0) } ?? client.configuration.priceAlertsPath
        let json = try await client.requestJSON(
            path: path,
            method: draft.alertId == nil ? "POST" : "PATCH",
            body: body,
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
        guard let alert = parseAlerts(from: unwrapAlertPayload(json)).first else {
            throw NetworkServiceError.parsingFailed("가격 알림 응답을 해석하지 못했어요.")
        }
        return alert
    }

    func deletePriceAlert(session: AuthSession, alertId: String) async throws {
        _ = try await client.requestJSON(
            path: client.configuration.priceAlertPath(id: alertId),
            method: "DELETE",
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
    }

    private func unwrapAlertPayload(_ json: Any) -> Any {
        guard let dictionary = json as? JSONObject else { return json }
        return dictionary["data"] ?? dictionary["result"] ?? dictionary["payload"] ?? json
    }

    private func parseAlerts(from payload: Any) -> [PriceAlert] {
        let items: [Any]
        if let array = payload as? [Any] {
            items = array
        } else if let dictionary = payload as? JSONObject,
                  let array = (dictionary["items"] ?? dictionary["alerts"]) as? [Any] {
            items = array
        } else if let dictionary = payload as? JSONObject {
            items = [dictionary]
        } else {
            items = []
        }

        return items.compactMap { item in
            guard let dictionary = item as? JSONObject else { return nil }
            guard let id = dictionary["id"] as? String ?? dictionary["alertId"] as? String,
                  let exchangeRaw = dictionary["exchange"] as? String,
                  let exchange = Exchange(rawValue: exchangeRaw.lowercased()),
                  let symbol = dictionary["symbol"] as? String,
                  let target = dictionary["targetPrice"] as? Double ?? (dictionary["targetPrice"] as? NSNumber)?.doubleValue
            else { return nil }
            let quote = MarketQuoteCurrency(rawValue: (dictionary["quoteCurrency"] as? String ?? "KRW").uppercased()) ?? .krw
            let condition = PriceAlertCondition(rawValue: dictionary["condition"] as? String ?? "") ?? .above
            let repeatPolicy = PriceAlertRepeatPolicy(rawValue: dictionary["repeatPolicy"] as? String ?? "") ?? .once
            let isActive = dictionary["isActive"] as? Bool ?? true
            return PriceAlert(
                id: id,
                exchange: exchange,
                symbol: symbol.uppercased(),
                quoteCurrency: quote,
                condition: condition,
                targetPrice: target,
                repeatPolicy: repeatPolicy,
                isActive: isActive
            )
        }
    }
}
