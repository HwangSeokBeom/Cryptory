import Foundation

protocol CalculatorRepositoryProtocol {
    func fetchUSDTRate() async throws -> USDTQuote
}

final class CalculatorAPI {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchUSDTRateJSON() async throws -> Any {
        AppLogger.debug(.network, "DEBUG [USDTCalculator] request rate")
        do {
            return try await client.requestJSON(
                path: "/calculators/usdt-rate",
                accessRequirement: .publicAccess
            )
        } catch let error as NetworkServiceError where error.isNotFound {
            AppLogger.debug(.network, "WARN [USDTCalculator] primary endpoint missing fallback=/api/v1/calculators/usdt-rate")
            return try await client.requestJSON(
                path: "/api/v1/calculators/usdt-rate",
                accessRequirement: .publicAccess
            )
        }
    }
}

final class LiveCalculatorRepository: CalculatorRepositoryProtocol {
    private let api: CalculatorAPI

    init(api: CalculatorAPI = CalculatorAPI()) {
        self.api = api
    }

    func fetchUSDTRate() async throws -> USDTQuote {
        do {
            let json = try await api.fetchUSDTRateJSON()
            let response = try Self.decodeUSDTExchangeRateResponse(json)
            AppLogger.debug(
                .network,
                "DEBUG [USDTCalculator] response success=\(response.success) priceExists=\(response.data.price != nil) source=\(response.data.source) reason=\(response.data.reason ?? "nil")"
            )
            let quote = try USDTExchangeRateMapper.quote(from: response)
            AppLogger.debug(
                .network,
                "DEBUG [USDTCalculator] loaded source=\(quote.source) cacheHit=\(quote.cacheHit.map(String.init) ?? "nil") updatedAt=\(quote.updatedAt.map(String.init(describing:)) ?? "nil")"
            )
            return quote
        } catch {
            AppLogger.debug(.network, "WARN [USDTCalculator] failed reason=\(error.localizedDescription)")
            throw error
        }
    }

    static func decodeUSDTExchangeRateResponse(_ json: Any) throws -> USDTExchangeRateResponseDTO {
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json) else {
            throw NetworkServiceError.parsingFailed("환율 응답을 해석하지 못했습니다.")
        }
        do {
            return try JSONDecoder().decode(USDTExchangeRateResponseDTO.self, from: data)
        } catch {
            AppLogger.debug(.network, "DEBUG [USDTCalculator] response decodeFailed target=USDTExchangeRateResponseDTO error=\(error.localizedDescription)")
            throw NetworkServiceError.parsingFailed("환율 응답 계약을 해석하지 못했습니다.")
        }
    }
}

struct CalculatorUseCase {
    private let repository: CalculatorRepositoryProtocol

    init(repository: CalculatorRepositoryProtocol = LiveCalculatorRepository()) {
        self.repository = repository
    }

    func fetchUSDTRate() async throws -> USDTQuote {
        try await repository.fetchUSDTRate()
    }
}
