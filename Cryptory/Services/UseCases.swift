import Foundation

struct CandleIntervalOption: Identifiable, Equatable {
    var id: String { value }

    let value: String
    let title: String
}

enum CandleIntervalCatalog {
    static let defaultOptions: [CandleIntervalOption] = [
        CandleIntervalOption(value: "1m", title: "1M"),
        CandleIntervalOption(value: "5m", title: "5M"),
        CandleIntervalOption(value: "15m", title: "15M"),
        CandleIntervalOption(value: "1h", title: "1H"),
        CandleIntervalOption(value: "4h", title: "4H"),
        CandleIntervalOption(value: "1d", title: "1D"),
        CandleIntervalOption(value: "1w", title: "1W")
    ]

    static func options(supportedIntervals: [String]) -> [CandleIntervalOption] {
        guard !supportedIntervals.isEmpty else {
            return defaultOptions
        }

        let supportedIntervalSet = Set(supportedIntervals.map { $0.lowercased() })
        let matchedOptions = defaultOptions.filter { supportedIntervalSet.contains($0.value.lowercased()) }
        return matchedOptions.isEmpty ? defaultOptions : matchedOptions
    }
}

struct ExchangeCapabilityResolver {
    func supportsTrading(on exchange: Exchange) -> Bool {
        exchange.supportsOrder
    }

    func supportsPortfolio(on exchange: Exchange) -> Bool {
        exchange.supportsAsset
    }

    func supportsChart(on exchange: Exchange) -> Bool {
        exchange.supportsChart
    }

    func supportsKimchiPremium(on exchange: Exchange) -> Bool {
        exchange.supportsKimchiPremium
    }

    func supportsConnectionManagement(on exchange: Exchange) -> Bool {
        exchange.supportsConnectionManagement
    }
}

struct ScreenStatusFactory {
    func makeStatusViewState(
        meta: ResponseMeta,
        streamingStatus: StreamingStatus,
        warningMessage: String? = nil,
        additionalBadges: [StatusBadgeViewState] = []
    ) -> ScreenStatusViewState {
        var badges = additionalBadges

        switch streamingStatus {
        case .live:
            badges.append(StatusBadgeViewState(title: "실시간", tone: .success))
        case .pollingFallback:
            badges.append(StatusBadgeViewState(title: "Polling Fallback", tone: .warning))
        case .disconnected:
            badges.append(StatusBadgeViewState(title: "스트림 끊김", tone: .warning))
        case .snapshotOnly:
            badges.append(StatusBadgeViewState(title: "Snapshot", tone: .neutral))
        }

        if meta.isStale {
            badges.append(StatusBadgeViewState(title: "Stale", tone: .warning))
        }

        if meta.partialFailureMessage != nil {
            badges.append(StatusBadgeViewState(title: "Partial", tone: .warning))
        }

        let lastUpdatedText = meta.fetchedAt.map { "업데이트 \(relativeStatusFormatter.localizedString(for: $0, relativeTo: Date()))" }
        let primaryMessage = warningMessage ?? meta.partialFailureMessage ?? meta.warningMessage
        let refreshMode: DataRefreshMode

        switch streamingStatus {
        case .live:
            refreshMode = .streaming
        case .pollingFallback, .disconnected:
            refreshMode = .pollingFallback
        case .snapshotOnly:
            refreshMode = .snapshot
        }

        return ScreenStatusViewState(
            badges: badges,
            message: primaryMessage,
            lastUpdatedText: lastUpdatedText,
            refreshMode: refreshMode
        )
    }
}

struct ExchangeConnectionsUseCase {
    func makeCardViewStates(
        connections: [ExchangeConnection],
        crudCapability: ExchangeConnectionCRUDCapability
    ) -> [ExchangeConnectionCardViewState] {
        connections.map { connection in
            var statusChips = [connection.status.title]

            if let lastValidatedAt = connection.lastValidatedAt {
                statusChips.append("검증 \(relativeStatusFormatter.localizedString(for: lastValidatedAt, relativeTo: Date()))")
            }

            if let updatedAt = connection.updatedAt {
                statusChips.append("수정 \(relativeStatusFormatter.localizedString(for: updatedAt, relativeTo: Date()))")
            }

            let secondaryMessage = connection.statusMessage
                ?? connection.maskedCredentialSummary
                ?? connection.permission.description

            return ExchangeConnectionCardViewState(
                id: connection.id,
                connection: connection,
                statusChips: statusChips,
                secondaryMessage: secondaryMessage,
                canEdit: crudCapability.canUpdate && connection.exchange.supportsConnectionManagement,
                canDelete: crudCapability.canDelete
            )
        }
    }
}

struct ExchangeConnectionFormValidator {
    func validationMessage(
        exchange: Exchange,
        nickname: String,
        credentials: [ExchangeCredentialFieldKey: String],
        mode: ExchangeConnectionFormViewState.Mode
    ) -> String? {
        guard exchange.supportsConnectionManagement else {
            return "현재 이 거래소는 앱 내 연결을 지원하지 않아요."
        }

        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNickname.count > 30 {
            return "닉네임은 30자 이내로 입력해주세요."
        }

        for field in exchange.credentialFields {
            let value = credentials[field.fieldKey, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            switch mode {
            case .create:
                if value.isEmpty {
                    return "\(field.title)을 입력해주세요."
                }
            case .edit:
                continue
            }
        }

        if let accessKey = credentials[.accessKey], accessKey.contains(" ") {
            return "Access Key에는 공백을 넣을 수 없어요."
        }

        if let accessToken = credentials[.accessToken], accessToken.contains(" ") {
            return "Access Token에는 공백을 넣을 수 없어요."
        }

        return nil
    }
}

struct KimchiPremiumViewStateUseCase {
    func makeCoinViewStates(from snapshot: KimchiPremiumSnapshot) -> [KimchiPremiumCoinViewState] {
        let groupedRows = Dictionary(grouping: snapshot.rows) { $0.symbol }

        return groupedRows.keys.sorted().map { symbol in
            let coin = CoinCatalog.coin(symbol: symbol)
            let cells = groupedRows[symbol, default: []]
                .sorted { $0.exchange.displayName < $1.exchange.displayName }
                .map { row in
                    let premiumText: String
                    if let premiumPercent = row.premiumPercent {
                        premiumText = String(format: "%@%.2f%%", premiumPercent >= 0 ? "+" : "", premiumPercent)
                    } else {
                        premiumText = "—"
                    }

                    let domesticPriceText = row.domesticPrice.map { PriceFormatter.formatPrice($0) } ?? "—"
                    let referencePriceText = row.krwConvertedReference.map { PriceFormatter.formatPrice($0) } ?? "—"
                    let warningMessage = timestampGapMessage(row: row) ?? row.staleReason

                    return KimchiPremiumExchangeCellViewState(
                        exchange: row.exchange,
                        premiumText: premiumText,
                        domesticPriceText: domesticPriceText,
                        referencePriceText: referencePriceText,
                        warningMessage: warningMessage,
                        isStale: row.isStale
                    )
                }

            let referenceLabel = "\(snapshot.referenceExchange.displayName) 환산가 기준"
            return KimchiPremiumCoinViewState(
                symbol: symbol,
                displayName: coin.name,
                referenceLabel: referenceLabel,
                cells: cells
            )
        }
    }

    private func timestampGapMessage(row: KimchiPremiumRow) -> String? {
        guard let localTimestamp = row.sourceExchangeTimestamp, let referenceTimestamp = row.referenceTimestamp else {
            return nil
        }

        let gapSeconds = abs(localTimestamp.timeIntervalSince(referenceTimestamp))
        guard gapSeconds >= 30 else {
            return nil
        }

        return "시차 \(Int(gapSeconds))초"
    }
}

private let relativeStatusFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.unitsStyle = .short
    return formatter
}()
