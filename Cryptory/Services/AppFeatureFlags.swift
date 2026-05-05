import Foundation

struct AppFeatureFlags: Equatable {
    let isMarketEnabled: Bool
    let isChartEnabled: Bool
    let isNewsEnabled: Bool
    let isReadOnlyPortfolioEnabled: Bool
    let isKimchiPremiumEnabled: Bool
    let isCommunityContentEnabled: Bool

    let isOrderEnabled: Bool
    let isTradingEnabled: Bool
    let isTransferEnabled: Bool
    let isDepositWithdrawEnabled: Bool
    let isWalletEnabled: Bool
    let isPrivateExchangeTradingAPIEnabled: Bool
    let isListSparklineSecondaryHydrationEnabled: Bool

    static var current: AppFeatureFlags {
        resolve(environment: ProcessInfo.processInfo.environment)
    }

    static func resolve(
        environment: [String: String],
        buildConfiguration: BuildConfiguration = .current,
        appEnvironment: AppEnvironment? = nil
    ) -> AppFeatureFlags {
        let resolvedEnvironment = appEnvironment
            ?? AppEnvironment.resolve(environment: environment, buildConfiguration: buildConfiguration)
        let isAppStoreChannel = buildConfiguration == .release || resolvedEnvironment == .production

        return AppFeatureFlags(
            isMarketEnabled: true,
            isChartEnabled: true,
            isNewsEnabled: true,
            isReadOnlyPortfolioEnabled: true,
            isKimchiPremiumEnabled: true,
            isCommunityContentEnabled: true,
            isOrderEnabled: isAppStoreChannel ? false : environment.boolFlag("CRYPTORY_ORDER_ENABLED", defaultValue: true),
            isTradingEnabled: isAppStoreChannel ? false : environment.boolFlag("CRYPTORY_TRADING_ENABLED", defaultValue: true),
            isTransferEnabled: isAppStoreChannel ? false : environment.boolFlag("CRYPTORY_TRANSFER_ENABLED", defaultValue: false),
            isDepositWithdrawEnabled: isAppStoreChannel ? false : environment.boolFlag("CRYPTORY_DEPOSIT_WITHDRAW_ENABLED", defaultValue: false),
            isWalletEnabled: isAppStoreChannel ? false : environment.boolFlag("CRYPTORY_WALLET_ENABLED", defaultValue: false),
            isPrivateExchangeTradingAPIEnabled: isAppStoreChannel ? false : environment.boolFlag("CRYPTORY_PRIVATE_TRADING_API_ENABLED", defaultValue: true),
            isListSparklineSecondaryHydrationEnabled: environment.boolFlag("CRYPTORY_LIST_SPARKLINE_SECONDARY_HYDRATION_ENABLED", defaultValue: true)
        )
    }
}

enum AppRouteGuard {
    private static let blockedRouteKeywords: Set<String> = [
        "order", "orders", "trade", "trading", "buy", "sell",
        "withdraw", "withdrawal", "deposit", "transfer", "wallet",
        "주문", "매수", "매도", "체결", "전송", "송금", "입금", "출금", "지갑"
    ]

    static func isTradingRoute(_ url: URL) -> Bool {
        let routeParts = [
            url.host,
            url.path,
            url.lastPathComponent,
            url.query
        ]
        .compactMap { $0?.removingPercentEncoding?.lowercased() }
        .joined(separator: "/")

        return blockedRouteKeywords.contains { routeParts.contains($0.lowercased()) }
    }

    static func informationalTab(for url: URL) -> Tab? {
        let routeParts = [
            url.host,
            url.path,
            url.lastPathComponent
        ]
        .compactMap { $0?.removingPercentEncoding?.lowercased() }
        .joined(separator: "/")

        if routeParts.contains("chart") || routeParts.contains("차트") {
            return .chart
        }
        if routeParts.contains("news") || routeParts.contains("뉴스") {
            return .news
        }
        if routeParts.contains("portfolio") || routeParts.contains("asset") || routeParts.contains("자산") {
            return .portfolio
        }
        if routeParts.contains("kimchi") || routeParts.contains("premium") || routeParts.contains("김프") {
            return .kimchi
        }
        if routeParts.contains("market") || routeParts.contains("ticker") || routeParts.contains("시세") {
            return .market
        }
        return nil
    }
}

private extension Dictionary where Key == String, Value == String {
    func boolFlag(_ key: String, defaultValue: Bool) -> Bool {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              value.isEmpty == false else {
            return defaultValue
        }

        switch value {
        case "1", "true", "yes", "on", "enabled":
            return true
        case "0", "false", "no", "off", "disabled":
            return false
        default:
            return defaultValue
        }
    }
}
