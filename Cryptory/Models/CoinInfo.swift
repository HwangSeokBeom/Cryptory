import Foundation

struct CoinInfo: Identifiable, Equatable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let nameEn: String
    let basePrice: Double
}

let COINS: [CoinInfo] = [
    CoinInfo(symbol: "BTC",   name: "비트코인",  nameEn: "Bitcoin",    basePrice: 143_250_000),
    CoinInfo(symbol: "ETH",   name: "이더리움",  nameEn: "Ethereum",   basePrice: 5_120_000),
    CoinInfo(symbol: "XRP",   name: "리플",     nameEn: "Ripple",     basePrice: 3_280),
    CoinInfo(symbol: "SOL",   name: "솔라나",   nameEn: "Solana",     basePrice: 298_000),
    CoinInfo(symbol: "DOGE",  name: "도지코인",  nameEn: "Dogecoin",   basePrice: 520),
    CoinInfo(symbol: "ADA",   name: "에이다",   nameEn: "Cardano",    basePrice: 1_240),
    CoinInfo(symbol: "AVAX",  name: "아발란체",  nameEn: "Avalanche",  basePrice: 52_000),
    CoinInfo(symbol: "DOT",   name: "폴카닷",   nameEn: "Polkadot",   basePrice: 12_800),
    CoinInfo(symbol: "MATIC", name: "폴리곤",   nameEn: "Polygon",    basePrice: 1_580),
    CoinInfo(symbol: "LINK",  name: "체인링크",  nameEn: "Chainlink",  basePrice: 28_500),
    CoinInfo(symbol: "ATOM",  name: "코스모스",  nameEn: "Cosmos",     basePrice: 18_200),
    CoinInfo(symbol: "UNI",   name: "유니스왑",  nameEn: "Uniswap",    basePrice: 16_800),
    CoinInfo(symbol: "SAND",  name: "샌드박스",  nameEn: "Sandbox",    basePrice: 890),
    CoinInfo(symbol: "SHIB",  name: "시바이누",  nameEn: "Shiba Inu",  basePrice: 0.038),
    CoinInfo(symbol: "APT",   name: "앱토스",   nameEn: "Aptos",      basePrice: 18_500),
]
