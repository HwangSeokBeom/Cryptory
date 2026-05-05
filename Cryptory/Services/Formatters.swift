import Foundation

struct PriceFormatter {
    /// formatPrice: ≥1000 → 정수+콤마, ≥1 → 소수1자리, <1 → 소수4자리
    nonisolated static func formatPrice(_ value: Double) -> String {
        if value >= 1000 {
            return value.formatted(.number.precision(.fractionLength(0)))
        } else if value >= 1 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.4f", value)
        }
    }

    /// formatVol: ≥1조 → "X.X조", ≥1억 → "X.X억", ≥1만 → "X만", 나머지 콤마
    nonisolated static func formatVolume(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.2f조", value / 1_000_000_000_000)
        } else if value >= 100_000_000 {
            return String(format: "%.2f억", value / 100_000_000)
        } else if value >= 10_000 {
            return String(format: "%.0f만", value / 10_000)
        } else {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    /// Format with ₩ prefix
    nonisolated static func formatKRW(_ value: Double) -> String {
        "₩" + formatPrice(value)
    }

    /// Format with KRW suffix
    nonisolated static func formatKRWSuffix(_ value: Double) -> String {
        formatPrice(value) + " KRW"
    }

    nonisolated static func formatBTC(_ value: Double) -> String {
        let text = value.formatted(.number.precision(.fractionLength(0...8)))
        return "\(text) BTC"
    }

    nonisolated static func formatMarketPrice(_ value: Double, quoteCurrency: MarketQuoteCurrency) -> String {
        switch quoteCurrency {
        case .krw:
            return formatKRWPrice(value)
        case .btc:
            return "\(formatCryptoQuotePrice(value, maxFractionDigits: 8)) BTC"
        case .usdt:
            return "\(formatUSDTPrice(value)) USDT"
        case .eth:
            return "\(formatCryptoQuotePrice(value, maxFractionDigits: 8)) ETH"
        }
    }

    nonisolated static func formatMarketListPrice(_ value: Double, quoteCurrency: MarketQuoteCurrency) -> String {
        let formattedPrice: String
        let rule: String
        switch quoteCurrency {
        case .krw:
            formattedPrice = formatKRWPrice(value)
            rule = "krw_integer_or_2_fraction"
        case .usdt:
            formattedPrice = formatUSDTPrice(value)
            rule = value >= 1 ? "usdt_2_to_4_decimals" : "usdt_significant_4_to_6"
        case .btc:
            formattedPrice = formatCryptoQuotePrice(value, maxFractionDigits: 8)
            rule = "btc_significant_4_to_6_max_8_fraction"
        case .eth:
            formattedPrice = formatCryptoQuotePrice(value, maxFractionDigits: 8)
            rule = "eth_significant_4_to_6_max_8_fraction"
        }
        AppLogger.debug(
            .lifecycle,
            "[PriceFormatDebug] quoteCurrency=\(quoteCurrency.rawValue) rawPrice=\(value) formattedPrice=\(formattedPrice) formatterRule=\(rule) symbol=\(quoteCurrency.rawValue)"
        )
        return formattedPrice
    }

    nonisolated static func formatMarketVolume(_ value: Double, quoteCurrency: MarketQuoteCurrency) -> String {
        switch quoteCurrency {
        case .krw:
            return formatVolume(value)
        case .usdt:
            return formatCompactDecimalAmount(value)
        case .btc:
            return formatCryptoVolume(value)
        case .eth:
            return formatCryptoVolume(value)
        }
    }

    /// Format quantity to 4 decimal places
    nonisolated static func formatQty(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
    }

    /// Format quantity to 6 decimal places
    nonisolated static func formatQty6(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    /// Integer with comma formatting
    nonisolated static func formatInteger(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    nonisolated static func formatCompactKRWAmount(_ value: Double) -> String {
        if abs(value) >= 1_000_000_000_000 {
            return String(format: "%.2f조", value / 1_000_000_000_000)
        }
        if abs(value) >= 100_000_000 {
            return String(format: "%.2f억", value / 100_000_000)
        }
        if abs(value) >= 1_000 {
            return "₩" + formatInteger(value)
        }
        return formatKRW(value)
    }

    nonisolated private static func formatKRWPrice(_ value: Double) -> String {
        if value >= 1_000 {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        if value >= 1 {
            return value.formatted(.number.precision(.fractionLength(0...2)))
        }
        return value.formatted(.number.precision(.fractionLength(0...4)))
    }

    nonisolated private static func formatUSDTPrice(_ value: Double) -> String {
        if value >= 1 {
            return value.formatted(.number.precision(.fractionLength(0...4)))
        }
        return formatSignificantDecimal(value, significantDigits: 5, maxFractionDigits: 8)
    }

    nonisolated private static func formatCryptoQuotePrice(_ value: Double, maxFractionDigits: Int) -> String {
        guard value.isFinite else { return "—" }
        if value == 0 { return "0" }
        let absoluteValue = abs(value)
        if absoluteValue < 0.000_000_01 {
            return formatScientific(value, significantDigits: 2)
        }
        return formatSignificantDecimal(value, significantDigits: 5, maxFractionDigits: maxFractionDigits)
    }

    nonisolated private static func formatCryptoVolume(_ value: Double) -> String {
        let absoluteValue = abs(value)
        if absoluteValue >= 1_000 {
            return formatCompactDecimalAmount(value)
        }
        if absoluteValue >= 0.1 {
            return String(format: "%.2f", value)
        }
        return formatSignificantDecimal(value, significantDigits: 3, maxFractionDigits: 4)
    }

    nonisolated private static func formatCompactDecimalAmount(_ value: Double) -> String {
        let absoluteValue = abs(value)
        if absoluteValue >= 1_000_000_000 {
            return formatCompactSuffixed(value / 1_000_000_000, suffix: "B")
        }
        if absoluteValue >= 1_000_000 {
            return formatCompactSuffixed(value / 1_000_000, suffix: "M")
        }
        if absoluteValue >= 1_000 {
            return formatCompactSuffixed(value / 1_000, suffix: "K")
        }
        return formatSignificantDecimal(value, significantDigits: 4, maxFractionDigits: 4)
    }

    nonisolated private static func formatSignificantDecimal(
        _ value: Double,
        significantDigits: Int,
        maxFractionDigits: Int
    ) -> String {
        guard value.isFinite else { return "—" }
        guard value != 0 else { return "0" }

        let absoluteValue = abs(value)
        let exponent = Int(floor(log10(absoluteValue)))
        let fractionDigits = min(max(significantDigits - exponent - 1, 0), maxFractionDigits)
        return trimTrailingZeros(String(format: "%.\(fractionDigits)f", value))
    }

    nonisolated private static func trimTrailingZeros(_ value: String) -> String {
        var trimmed = value
        while trimmed.contains(".") && trimmed.last == "0" {
            trimmed.removeLast()
        }
        if trimmed.last == "." {
            trimmed.removeLast()
        }
        return trimmed
    }

    nonisolated private static func formatCompactSuffixed(_ value: Double, suffix: String) -> String {
        "\(trimTrailingZeros(String(format: "%.2f", value)))\(suffix)"
    }

    nonisolated private static func formatScientific(_ value: Double, significantDigits: Int) -> String {
        let fractionDigits = max(significantDigits - 1, 0)
        let parts = String(format: "%.\(fractionDigits)e", value).split(separator: "e", maxSplits: 1)
        guard parts.count == 2, let exponent = Int(parts[1]) else {
            return String(format: "%.\(fractionDigits)e", value)
        }
        return "\(trimTrailingZeros(String(parts[0])))e\(exponent)"
    }

    nonisolated static func formatPercent(_ value: Double) -> String {
        String(format: "%+.2f%%", value)
    }

    nonisolated static func formatRank(_ value: Int) -> String {
        "#\(value)"
    }

    nonisolated static func formatReferenceDate(_ value: Date) -> String {
        referenceDateFormatter.string(from: value) + " 기준"
    }

    nonisolated private static let referenceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter
    }()
}
