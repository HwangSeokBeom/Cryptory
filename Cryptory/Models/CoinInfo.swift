import Foundation

struct CoinInfo: Identifiable, Equatable {
    var id: String { symbol }

    let symbol: String
    let name: String
    let nameEn: String
}

enum CoinCatalog {
    static let fallbackTopSymbols = ["BTC", "ETH", "XRP", "SOL", "DOGE", "ADA", "AVAX", "LINK"]

    private static let knownCoins: [String: CoinInfo] = {
        let coins = [
            CoinInfo(symbol: "BTC", name: "비트코인", nameEn: "Bitcoin"),
            CoinInfo(symbol: "ETH", name: "이더리움", nameEn: "Ethereum"),
            CoinInfo(symbol: "XRP", name: "리플", nameEn: "Ripple"),
            CoinInfo(symbol: "SOL", name: "솔라나", nameEn: "Solana"),
            CoinInfo(symbol: "DOGE", name: "도지코인", nameEn: "Dogecoin"),
            CoinInfo(symbol: "ADA", name: "에이다", nameEn: "Cardano"),
            CoinInfo(symbol: "AVAX", name: "아발란체", nameEn: "Avalanche"),
            CoinInfo(symbol: "DOT", name: "폴카닷", nameEn: "Polkadot"),
            CoinInfo(symbol: "MATIC", name: "폴리곤", nameEn: "Polygon"),
            CoinInfo(symbol: "LINK", name: "체인링크", nameEn: "Chainlink"),
            CoinInfo(symbol: "ATOM", name: "코스모스", nameEn: "Cosmos"),
            CoinInfo(symbol: "UNI", name: "유니스왑", nameEn: "Uniswap"),
            CoinInfo(symbol: "SAND", name: "샌드박스", nameEn: "Sandbox"),
            CoinInfo(symbol: "SHIB", name: "시바이누", nameEn: "Shiba Inu"),
            CoinInfo(symbol: "APT", name: "앱토스", nameEn: "Aptos")
        ]

        return Dictionary(uniqueKeysWithValues: coins.map { ($0.symbol, $0) })
    }()

    static var allKnownCoins: [CoinInfo] {
        knownCoins.values.sorted { $0.symbol < $1.symbol }
    }

    static func coin(
        symbol: String,
        displayName: String? = nil,
        englishName: String? = nil
    ) -> CoinInfo {
        let normalizedSymbol = symbol.uppercased()

        if let knownCoin = knownCoins[normalizedSymbol] {
            return CoinInfo(
                symbol: normalizedSymbol,
                name: displayName ?? knownCoin.name,
                nameEn: englishName ?? knownCoin.nameEn
            )
        }

        return CoinInfo(
            symbol: normalizedSymbol,
            name: displayName ?? normalizedSymbol,
            nameEn: englishName ?? normalizedSymbol
        )
    }
}

let COINS: [CoinInfo] = CoinCatalog.allKnownCoins
