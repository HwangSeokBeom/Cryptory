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
            return String(format: "%.1f조", value / 1_000_000_000_000)
        } else if value >= 100_000_000 {
            return String(format: "%.1f억", value / 100_000_000)
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

    /// Format quantity to 4 decimal places
    nonisolated static func formatQty(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    /// Format quantity to 6 decimal places
    nonisolated static func formatQty6(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    /// Integer with comma formatting
    nonisolated static func formatInteger(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}
