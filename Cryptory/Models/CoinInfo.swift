import Foundation

struct MarketIdentity: Hashable, Codable {
    let exchange: Exchange
    let marketId: String?
    let symbol: String

    nonisolated init(exchange: Exchange, marketId: String? = nil, symbol: String) {
        self.exchange = exchange
        self.marketId = Self.normalizedComponent(marketId)
        self.symbol = Self.normalizedComponent(symbol) ?? symbol.uppercased()
    }

    nonisolated var cacheKey: String {
        if let marketId {
            return "\(exchange.rawValue)|\(marketId)"
        }
        return "\(exchange.rawValue)|\(symbol)"
    }

    nonisolated var logFields: String {
        "exchange=\(exchange.rawValue) marketId=\(marketId ?? "-") symbol=\(symbol)"
    }

    private nonisolated static func normalizedComponent(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let normalizedValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalizedValue.isEmpty ? nil : normalizedValue
    }
}

enum SymbolNormalization {
    private nonisolated static var quoteCurrencies: Set<String> {
        Set(["KRW", "USD", "USDT", "BTC", "ETH"])
    }

    private nonisolated static var separators: CharacterSet {
        CharacterSet(charactersIn: "-_:/")
    }

    nonisolated static func canonicalAssetCode(
        exchange: Exchange? = nil,
        rawSymbol: String,
        marketId: String? = nil,
        baseAsset: String? = nil,
        quoteAsset: String? = nil,
        canonicalSymbol: String? = nil
    ) -> String {
        if let canonicalSymbol = normalizedToken(canonicalSymbol) {
            return canonicalSymbol
        }

        if let baseAsset = normalizedToken(baseAsset), quoteCurrencies.contains(baseAsset) == false {
            return baseAsset
        }

        if let parsedRawSymbol = normalizedPairCode(rawSymbol) {
            return parsedRawSymbol
        }

        if let parsedMarketId = normalizedPairCode(marketId) {
            return parsedMarketId
        }

        if let baseAsset = normalizedToken(baseAsset) {
            return baseAsset
        }

        if let quoteAsset = normalizedToken(quoteAsset), quoteCurrencies.contains(quoteAsset) == false {
            return quoteAsset
        }

        return normalizedToken(rawSymbol) ?? rawSymbol.uppercased()
    }

    nonisolated static func localAssetName(for canonicalSymbol: String) -> String {
        "coin.\(canonicalSymbol.lowercased())"
    }

    private nonisolated static func normalizedPairCode(_ rawValue: String?) -> String? {
        guard let normalizedValue = normalizedToken(rawValue) else {
            return nil
        }

        let parts = normalizedValue
            .components(separatedBy: separators)
            .filter { $0.isEmpty == false }

        if parts.count >= 2 {
            if quoteCurrencies.contains(parts[0]) {
                return parts[1]
            }
            if let lastPart = parts.last, quoteCurrencies.contains(lastPart) {
                return parts[0]
            }
            return parts[0]
        }

        for quoteCurrency in ["KRW", "USDT", "USD", "BTC", "ETH"] {
            if normalizedValue.hasPrefix(quoteCurrency), normalizedValue.count > quoteCurrency.count {
                return String(normalizedValue.dropFirst(quoteCurrency.count))
            }
            if normalizedValue.hasSuffix(quoteCurrency), normalizedValue.count > quoteCurrency.count {
                return String(normalizedValue.dropLast(quoteCurrency.count))
            }
        }

        return normalizedValue
    }

    private nonisolated static func normalizedToken(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let normalizedValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalizedValue.isEmpty ? nil : normalizedValue
    }
}

struct CoinDisplayMetadata: Equatable, Codable {
    let marketId: String?
    let baseAsset: String?
    let quoteAsset: String?
    let canonicalSymbol: String
    let displaySymbol: String
    let koreanName: String?
    let englishName: String?
    let iconURL: String?
    let hasImage: Bool?
    let localAssetName: String?
    let isChartAvailable: Bool?
    let isOrderBookAvailable: Bool?
    let isTradesAvailable: Bool?
    let unavailableReason: String?

    nonisolated var normalizedMarketId: String? {
        marketId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.uppercased()
    }

    nonisolated init(
        exchange: Exchange? = nil,
        rawSymbol: String,
        marketId: String? = nil,
        baseAsset: String? = nil,
        quoteAsset: String? = nil,
        canonicalSymbol: String? = nil,
        displaySymbol: String? = nil,
        koreanName: String? = nil,
        englishName: String? = nil,
        iconURL: String? = nil,
        hasImage: Bool? = nil,
        localAssetName: String? = nil,
        isChartAvailable: Bool? = nil,
        isOrderBookAvailable: Bool? = nil,
        isTradesAvailable: Bool? = nil,
        unavailableReason: String? = nil
    ) {
        let resolvedCanonicalSymbol = SymbolNormalization.canonicalAssetCode(
            exchange: exchange,
            rawSymbol: rawSymbol,
            marketId: marketId,
            baseAsset: baseAsset,
            quoteAsset: quoteAsset,
            canonicalSymbol: canonicalSymbol
        )
        self.marketId = marketId
        self.baseAsset = baseAsset?.uppercased()
        self.quoteAsset = quoteAsset?.uppercased()
        self.canonicalSymbol = resolvedCanonicalSymbol
        self.displaySymbol = displaySymbol?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.uppercased()
            ?? resolvedCanonicalSymbol
        self.koreanName = koreanName
        self.englishName = englishName
        self.iconURL = iconURL
        self.hasImage = hasImage
        self.localAssetName = localAssetName ?? SymbolNormalization.localAssetName(for: resolvedCanonicalSymbol)
        self.isChartAvailable = isChartAvailable
        self.isOrderBookAvailable = isOrderBookAvailable
        self.isTradesAvailable = isTradesAvailable
        self.unavailableReason = unavailableReason
    }

    nonisolated func marketIdentity(exchange: Exchange, symbol: String) -> MarketIdentity {
        MarketIdentity(
            exchange: exchange,
            marketId: normalizedMarketId,
            symbol: symbol
        )
    }

    nonisolated func merged(with supplementary: CoinDisplayMetadata?) -> CoinDisplayMetadata {
        guard let supplementary else {
            return self
        }

        let primary: CoinDisplayMetadata
        let secondary: CoinDisplayMetadata
        if Self.metadataScore(self) >= Self.metadataScore(supplementary) {
            primary = self
            secondary = supplementary
        } else {
            primary = supplementary
            secondary = self
        }

        return CoinDisplayMetadata(
            rawSymbol: primary.displaySymbol,
            marketId: primary.normalizedMarketId ?? secondary.normalizedMarketId,
            baseAsset: primary.baseAsset ?? secondary.baseAsset,
            quoteAsset: primary.quoteAsset ?? secondary.quoteAsset,
            canonicalSymbol: primary.canonicalSymbol,
            displaySymbol: primary.displaySymbol,
            koreanName: primary.koreanName ?? secondary.koreanName,
            englishName: primary.englishName ?? secondary.englishName,
            iconURL: secondary.hasImage == false
                ? nil
                : (primary.iconURL ?? secondary.iconURL),
            hasImage: secondary.hasImage ?? primary.hasImage,
            localAssetName: primary.localAssetName ?? secondary.localAssetName,
            isChartAvailable: primary.isChartAvailable ?? secondary.isChartAvailable,
            isOrderBookAvailable: primary.isOrderBookAvailable ?? secondary.isOrderBookAvailable,
            isTradesAvailable: primary.isTradesAvailable ?? secondary.isTradesAvailable,
            unavailableReason: primary.unavailableReason ?? secondary.unavailableReason
        )
    }

    private nonisolated static func metadataScore(_ metadata: CoinDisplayMetadata) -> Int {
        var score = 0
        if metadata.normalizedMarketId != nil { score += 8 }
        if metadata.koreanName != nil { score += 2 }
        if metadata.englishName != nil { score += 2 }
        if metadata.iconURL != nil { score += 3 }
        if metadata.localAssetName != nil { score += 1 }
        if metadata.baseAsset != nil { score += 1 }
        if metadata.quoteAsset != nil { score += 1 }
        if metadata.isChartAvailable != nil { score += 1 }
        if metadata.isOrderBookAvailable != nil { score += 1 }
        if metadata.isTradesAvailable != nil { score += 1 }
        if metadata.unavailableReason != nil { score += 1 }
        return score
    }
}

struct CoinInfo: Identifiable, Equatable, Codable {
    nonisolated var id: String { symbol }

    let symbol: String
    let name: String
    let nameEn: String
    let imageURL: String?
    let hasImage: Bool?
    let displayMetadata: CoinDisplayMetadata?
    let isTradable: Bool
    let isKimchiComparable: Bool

    nonisolated var canonicalSymbol: String {
        displayMetadata?.canonicalSymbol ?? SymbolNormalization.canonicalAssetCode(rawSymbol: symbol)
    }

    nonisolated var displaySymbol: String {
        displayMetadata?.displaySymbol ?? canonicalSymbol
    }

    nonisolated var resolvedHasImage: Bool? {
        displayMetadata?.hasImage ?? hasImage
    }

    nonisolated var iconURL: String? {
        if resolvedHasImage == false {
            return nil
        }
        return displayMetadata?.iconURL ?? imageURL
    }

    nonisolated var localAssetName: String {
        displayMetadata?.localAssetName ?? SymbolNormalization.localAssetName(for: canonicalSymbol)
    }

    nonisolated var marketId: String? {
        displayMetadata?.normalizedMarketId
    }

    nonisolated init(
        symbol: String,
        name: String,
        nameEn: String,
        imageURL: String? = nil,
        hasImage: Bool? = nil,
        displayMetadata: CoinDisplayMetadata? = nil,
        isTradable: Bool = true,
        isKimchiComparable: Bool = true
    ) {
        self.symbol = symbol
        self.name = name
        self.nameEn = nameEn
        self.imageURL = imageURL
        self.hasImage = hasImage
        self.displayMetadata = displayMetadata
        self.isTradable = isTradable
        self.isKimchiComparable = isKimchiComparable
    }

    nonisolated func merged(with supplementary: CoinInfo?) -> CoinInfo {
        guard let supplementary, supplementary.symbol == symbol else {
            return self
        }

        let mergedMetadata = if let displayMetadata {
            displayMetadata.merged(with: supplementary.displayMetadata)
        } else {
            supplementary.displayMetadata
        }
        let mergedHasImage = supplementary.resolvedHasImage ?? resolvedHasImage

        return CoinInfo(
            symbol: symbol,
            name: name.isEmpty ? supplementary.name : name,
            nameEn: nameEn.isEmpty ? supplementary.nameEn : nameEn,
            imageURL: mergedHasImage == false
                ? nil
                : (imageURL ?? supplementary.imageURL ?? mergedMetadata?.iconURL),
            hasImage: mergedHasImage,
            displayMetadata: mergedMetadata,
            isTradable: isTradable || supplementary.isTradable,
            isKimchiComparable: isKimchiComparable || supplementary.isKimchiComparable
        )
    }

    nonisolated func marketIdentity(exchange: Exchange) -> MarketIdentity {
        if let displayMetadata {
            return displayMetadata.marketIdentity(exchange: exchange, symbol: symbol)
        }
        return MarketIdentity(exchange: exchange, symbol: symbol)
    }
}

enum CoinCatalog {
    nonisolated static let fallbackTopSymbols = ["BTC", "ETH", "XRP", "SOL", "DOGE", "ADA", "AVAX", "LINK"]

    nonisolated private static let knownCoins: [String: CoinInfo] = {
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

    nonisolated static var allKnownCoins: [CoinInfo] {
        knownCoins.values.sorted { $0.symbol < $1.symbol }
    }

    nonisolated static func coin(
        symbol: String,
        exchange: Exchange? = nil,
        marketId: String? = nil,
        baseAsset: String? = nil,
        quoteAsset: String? = nil,
        canonicalSymbol: String? = nil,
        displaySymbol: String? = nil,
        displayName: String? = nil,
        englishName: String? = nil,
        imageURL: String? = nil,
        hasImage: Bool? = nil,
        localAssetName: String? = nil,
        isChartAvailable: Bool? = nil,
        isOrderBookAvailable: Bool? = nil,
        isTradesAvailable: Bool? = nil,
        unavailableReason: String? = nil,
        isTradable: Bool = true,
        isKimchiComparable: Bool = true
    ) -> CoinInfo {
        let normalizedSymbol = SymbolNormalization.canonicalAssetCode(
            exchange: exchange,
            rawSymbol: symbol,
            marketId: marketId,
            baseAsset: baseAsset,
            quoteAsset: quoteAsset,
            canonicalSymbol: canonicalSymbol
        )
        let metadata = CoinDisplayMetadata(
            exchange: exchange,
            rawSymbol: symbol,
            marketId: marketId,
            baseAsset: baseAsset,
            quoteAsset: quoteAsset,
            canonicalSymbol: normalizedSymbol,
            displaySymbol: displaySymbol,
            koreanName: displayName,
            englishName: englishName,
            iconURL: imageURL,
            hasImage: hasImage,
            localAssetName: localAssetName,
            isChartAvailable: isChartAvailable,
            isOrderBookAvailable: isOrderBookAvailable,
            isTradesAvailable: isTradesAvailable,
            unavailableReason: unavailableReason
        )

        if let knownCoin = knownCoins[normalizedSymbol] {
            return CoinInfo(
                symbol: normalizedSymbol,
                name: displayName ?? knownCoin.name,
                nameEn: englishName ?? knownCoin.nameEn,
                imageURL: imageURL ?? knownCoin.imageURL,
                hasImage: hasImage,
                displayMetadata: metadata,
                isTradable: isTradable,
                isKimchiComparable: isKimchiComparable
            )
        }

        return CoinInfo(
            symbol: normalizedSymbol,
            name: displayName ?? normalizedSymbol,
            nameEn: englishName ?? normalizedSymbol,
            imageURL: imageURL,
            hasImage: hasImage,
            displayMetadata: metadata,
            isTradable: isTradable,
            isKimchiComparable: isKimchiComparable
        )
    }
}

let COINS: [CoinInfo] = CoinCatalog.allKnownCoins

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
