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

enum ScreenStatusContext: String {
    case market
    case chart
    case trade
    case portfolio
    case kimchi
}

struct ScreenStatusFactory {
    func makeStatusViewState(
        meta: ResponseMeta,
        streamingStatus: StreamingStatus,
        context: ScreenStatusContext,
        warningMessage: String? = nil,
        additionalBadges: [StatusBadgeViewState] = [],
        loadState: SourceAwareLoadState? = nil
    ) -> ScreenStatusViewState {
        var badges = additionalBadges
        let defaultStatusMessage: String?
        let shouldCollapseMessage: Bool

        if let loadState {
            switch loadState.phase {
            case .initialLoading:
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            case .showingCache:
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            case .showingSnapshot:
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            case .streaming:
                badges.append(StatusBadgeViewState(title: "실시간", tone: .success))
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            case .degradedPolling:
                badges.append(StatusBadgeViewState(title: "약간 지연", tone: .warning))
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            case .partialFailure:
                badges.append(StatusBadgeViewState(title: partialFailureBadgeTitle(for: context), tone: .warning))
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            case .hardFailure:
                badges.append(StatusBadgeViewState(title: "데이터 없음", tone: .error))
                defaultStatusMessage = unavailableMessage(for: context)
                shouldCollapseMessage = false
            }
        } else {
            switch streamingStatus {
            case .live:
                badges.append(StatusBadgeViewState(title: "실시간", tone: .success))
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            case .pollingFallback:
                badges.append(StatusBadgeViewState(title: "약간 지연", tone: .warning))
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            case .disconnected:
                badges.append(StatusBadgeViewState(title: "약간 지연", tone: .warning))
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            case .snapshotOnly:
                defaultStatusMessage = nil
                shouldCollapseMessage = true
            }
        }

        if meta.isStale {
            badges.append(StatusBadgeViewState(title: "약간 지연", tone: .warning))
        }

        if loadState?.hasPartialFailure == true, loadState?.phase != .partialFailure {
            badges.append(StatusBadgeViewState(title: partialFailureBadgeTitle(for: context), tone: .warning))
        } else if meta.partialFailureMessage != nil {
            badges.append(StatusBadgeViewState(title: partialFailureBadgeTitle(for: context), tone: .warning))
        }

        let rawPrimaryMessage = warningMessage
            ?? meta.partialFailureMessage
            ?? meta.warningMessage
            ?? defaultStatusMessage
        let primaryMessage = shouldCollapseMessage
            ? nil
            : sanitizedUserFacingMessage(rawPrimaryMessage)
        let resolvedBadges = deduplicatedBadges(badges)
        let shouldShowTimestamp = resolvedBadges.isEmpty == false || primaryMessage != nil
        let lastUpdatedText = shouldShowTimestamp
            ? meta.fetchedAt.map { userFacingRelativeTimestampText($0) }
            : nil
        let refreshMode: DataRefreshMode

        if let loadState {
            switch loadState.phase {
            case .streaming:
                refreshMode = .streaming
            case .degradedPolling:
                refreshMode = .pollingFallback
            case .initialLoading, .showingCache, .showingSnapshot, .partialFailure, .hardFailure:
                refreshMode = .snapshot
            }
        } else {
            switch streamingStatus {
            case .live:
                refreshMode = .streaming
            case .pollingFallback, .disconnected:
                refreshMode = .pollingFallback
            case .snapshotOnly:
                refreshMode = .snapshot
            }
        }

        return ScreenStatusViewState(
            badges: resolvedBadges,
            message: primaryMessage,
            lastUpdatedText: lastUpdatedText,
            refreshMode: refreshMode
        )
    }

    private func loadingMessage(for context: ScreenStatusContext) -> String {
        switch context {
        case .market:
            return "시장 데이터를 불러오고 있어요."
        case .chart:
            return "차트 데이터를 준비하고 있어요."
        case .trade:
            return "주문 정보를 확인하고 있어요."
        case .portfolio:
            return "자산 정보를 확인하고 있어요."
        case .kimchi:
            return "비교 가능한 종목을 불러오고 있어요."
        }
    }

    private func reconnectingMessage(for context: ScreenStatusContext) -> String {
        switch context {
        case .market:
            return "최신 정보를 확인하고 있어요."
        case .chart:
            return "차트 데이터를 다시 확인하고 있어요."
        case .trade:
            return "주문 상태를 다시 확인하고 있어요."
        case .portfolio:
            return "자산 현황을 다시 확인하고 있어요."
        case .kimchi:
            return "비교값을 다시 확인하고 있어요."
        }
    }

    private func partialFailureMessage(for context: ScreenStatusContext) -> String {
        switch context {
        case .market:
            return "일부 데이터가 잠시 늦어지고 있어요."
        case .chart:
            return "일부 차트 데이터가 잠시 늦어지고 있어요."
        case .trade:
            return "일부 주문 데이터가 잠시 늦어지고 있어요."
        case .portfolio:
            return "일부 자산 데이터가 잠시 늦어지고 있어요."
        case .kimchi:
            return "비교 가능한 종목부터 먼저 보여드릴게요."
        }
    }

    private func unavailableMessage(for context: ScreenStatusContext) -> String {
        switch context {
        case .market:
            return "지금은 표시할 시세가 없어요."
        case .chart:
            return "지금은 표시할 차트가 없어요."
        case .trade:
            return "지금은 표시할 주문 정보가 없어요."
        case .portfolio:
            return "지금은 표시할 자산 정보가 없어요."
        case .kimchi:
            return "지금은 비교할 값이 없어요."
        }
    }

    private func partialFailureBadgeTitle(for context: ScreenStatusContext) -> String {
        _ = context
        return "일부 지연"
    }

    private func sanitizedUserFacingMessage(_ message: String?) -> String? {
        guard var message, !message.isEmpty else {
            return nil
        }

        let replacements = [
            ("REST", "최신"),
            ("rest", "최신"),
            ("캐시", ""),
            ("cache", ""),
            ("스냅샷", ""),
            ("snapshot", ""),
            ("폴링", "다시 확인"),
            ("polling", "다시 확인"),
            ("스트림", "연결"),
            ("stream", "연결"),
            ("웹소켓", "실시간 연결"),
            ("websocket", "실시간 연결"),
            ("canonical", ""),
            ("Canonical", ""),
            ("fx_rate_delayed", "약간 지연"),
            ("timestamp_skew_detected", "약간 지연"),
            ("freshness_threshold_exceeded", "약간 지연"),
            ("fallback_source", ""),
            ("sourceExchange", ""),
            ("source_exchange", ""),
            ("raw reason", ""),
            ("freshness", "")
        ]

        replacements.forEach { source, target in
            message = message.replacingOccurrences(of: source, with: target)
        }

        message = message
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: ",", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return message.isEmpty ? nil : message
    }

    private func deduplicatedBadges(_ badges: [StatusBadgeViewState]) -> [StatusBadgeViewState] {
        var seenTitles = Set<String>()
        return badges.filter { badge in
            seenTitles.insert(badge.title).inserted
        }
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

struct SignUpFormValidationResult: Equatable {
    let emailMessage: String?
    let passwordMessage: String?
    let passwordConfirmMessage: String?
    let nicknameMessage: String?
    let termsMessage: String?

    var primaryMessage: String? {
        emailMessage
            ?? passwordMessage
            ?? passwordConfirmMessage
            ?? nicknameMessage
            ?? termsMessage
    }

    var isValid: Bool {
        primaryMessage == nil
    }
}

struct AuthInputValidator {
    func loginValidationMessage(email: String, password: String) -> String? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty || password.isEmpty {
            return "이메일과 비밀번호를 입력해주세요."
        }
        if isValidEmail(trimmedEmail) == false {
            return "올바른 이메일 형식을 입력해주세요."
        }
        return nil
    }

    func signUpValidation(
        email: String,
        password: String,
        passwordConfirm: String,
        nickname: String,
        acceptedTerms: Bool
    ) -> SignUpFormValidationResult {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)

        let emailMessage: String? = {
            guard trimmedEmail.isEmpty == false else {
                return "이메일을 입력해주세요."
            }
            guard isValidEmail(trimmedEmail) else {
                return "올바른 이메일 형식을 입력해주세요."
            }
            return nil
        }()

        let passwordMessage: String? = {
            guard password.isEmpty == false else {
                return "비밀번호를 입력해주세요."
            }
            guard password.count >= 8 else {
                return "비밀번호는 8자 이상이어야 해요."
            }
            let containsLetter = password.rangeOfCharacter(from: .letters) != nil
            let containsDigit = password.rangeOfCharacter(from: .decimalDigits) != nil
            guard containsLetter && containsDigit else {
                return "비밀번호는 영문과 숫자를 함께 포함해야 해요."
            }
            return nil
        }()

        let passwordConfirmMessage: String? = {
            guard passwordConfirm.isEmpty == false else {
                return "비밀번호 확인을 입력해주세요."
            }
            guard password == passwordConfirm else {
                return "비밀번호가 일치하지 않아요."
            }
            return nil
        }()

        let nicknameMessage: String? = {
            guard trimmedNickname.isEmpty == false else {
                return "닉네임을 입력해주세요."
            }
            guard trimmedNickname.count >= 2 else {
                return "닉네임은 2자 이상이어야 해요."
            }
            guard trimmedNickname.count <= 20 else {
                return "닉네임은 20자 이내로 입력해주세요."
            }
            return nil
        }()

        let termsMessage = acceptedTerms ? nil : "약관 동의가 필요해요."

        return SignUpFormValidationResult(
            emailMessage: emailMessage,
            passwordMessage: passwordMessage,
            passwordConfirmMessage: passwordConfirmMessage,
            nicknameMessage: nicknameMessage,
            termsMessage: termsMessage
        )
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return email.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

struct KimchiPremiumViewStateUseCase {
    enum PresentationPhase {
        case responsePending
        case settled
    }

    nonisolated init() {}

    nonisolated func makeCoinViewStates(
        from snapshot: KimchiPremiumSnapshot,
        comparableSymbols: [String],
        selectedDomesticExchange: Exchange,
        phase: PresentationPhase = .responsePending
    ) -> [KimchiPremiumCoinViewState] {
        let groupedRows = Dictionary(
            grouping: snapshot.rows.filter {
                $0.exchange == selectedDomesticExchange
                    && $0.sourceExchange == selectedDomesticExchange
            }
        ) { $0.symbol }
        let orderedSymbols = orderedKimchiSymbols(
            requestedSymbols: comparableSymbols,
            availableSymbols: groupedRows.keys.map { $0 }
        )
        let failedSymbols = Set(snapshot.failedSymbols)

        let shouldPreserveMissingSymbols = groupedRows.isEmpty

        return orderedSymbols.compactMap { symbol in
            let coin = CoinCatalog.coin(symbol: symbol)
            let rows = groupedRows[symbol, default: []]
            let preferredRow = preferredRow(from: rows)
            if preferredRow == nil && shouldPreserveMissingSymbols == false {
                return nil
            }
            let cell = makeCellViewState(
                from: preferredRow,
                exchange: selectedDomesticExchange,
                hasSnapshotPartialFailure: snapshot.partialFailureMessage != nil || failedSymbols.contains(symbol),
                phase: phase
            )

            let referenceLabel = "\(snapshot.referenceExchange.displayName) 기준가"
            return KimchiPremiumCoinViewState(
                symbol: symbol,
                displayName: coin.name,
                selectedExchange: selectedDomesticExchange,
                sourceExchange: cell.sourceExchange,
                referenceLabel: referenceLabel,
                cells: [cell],
                status: coinStatus(for: cell),
                freshnessState: cell.freshnessState,
                freshnessReason: cell.freshnessReason,
                updatedAt: cell.updatedAt,
                isPreviousSnapshot: cell.isPreviousSnapshot
            )
        }
    }

    private nonisolated func makeCellViewState(
        from row: KimchiPremiumRow?,
        exchange: Exchange,
        hasSnapshotPartialFailure: Bool,
        phase: PresentationPhase
    ) -> KimchiPremiumExchangeCellViewState {
        guard let row else {
            let freshnessState: KimchiPremiumFreshnessState = hasSnapshotPartialFailure
                ? .partialUpdate
                : (phase == .settled ? .unavailable : .loading)
            let warningMessage = hasSnapshotPartialFailure
                ? "일부 지연"
                : (phase == .settled ? "비교 가능한 기준 가격이 아직 없어요." : nil)
            return KimchiPremiumExchangeCellViewState(
                selectedExchange: exchange,
                exchange: exchange,
                sourceExchange: exchange,
                premiumText: phase == .settled ? "데이터 없음" : "확인 중",
                domesticPriceText: phase == .settled ? "데이터 없음" : "가격 확인 중",
                referencePriceText: phase == .settled ? "데이터 없음" : "기준가 확인 중",
                premiumIsPlaceholder: true,
                domesticPriceIsPlaceholder: true,
                referencePriceIsPlaceholder: true,
                warningMessage: warningMessage,
                isStale: false,
                status: hasSnapshotPartialFailure ? .failed : (phase == .settled ? .unavailable : .loading),
                freshnessState: freshnessState,
                freshnessReason: warningMessage,
                updatedAt: nil,
                updatedAgoText: nil,
                isPreviousSnapshot: false,
                isSourceExchangeMismatch: false
            )
        }

        let resolvedReferencePrice = resolvedReferencePrice(for: row)
        let resolvedPremium = resolvedPremiumPercent(for: row, referencePrice: resolvedReferencePrice)
        let premiumIsPlaceholder = resolvedPremium == nil
        let domesticPriceIsPlaceholder = row.domesticPrice == nil
        let referencePriceIsPlaceholder = resolvedReferencePrice == nil
        let status = cellStatus(
            row: row,
            premiumIsPlaceholder: premiumIsPlaceholder,
            domesticPriceIsPlaceholder: domesticPriceIsPlaceholder,
            referencePriceIsPlaceholder: referencePriceIsPlaceholder,
            phase: phase
        )
        let freshnessState = resolvedFreshnessState(
            row: row,
            premiumIsPlaceholder: premiumIsPlaceholder,
            domesticPriceIsPlaceholder: domesticPriceIsPlaceholder,
            referencePriceIsPlaceholder: referencePriceIsPlaceholder,
            hasSnapshotPartialFailure: hasSnapshotPartialFailure,
            phase: phase
        )
        let freshnessReason = resolvedFreshnessReason(
            row: row,
            freshnessState: freshnessState,
            premiumIsPlaceholder: premiumIsPlaceholder,
            domesticPriceIsPlaceholder: domesticPriceIsPlaceholder,
            referencePriceIsPlaceholder: referencePriceIsPlaceholder,
            phase: phase
        )
        let updatedAt = row.updatedAt ?? row.timestamp ?? row.sourceExchangeTimestamp ?? row.referenceTimestamp

        return KimchiPremiumExchangeCellViewState(
            selectedExchange: exchange,
            exchange: row.exchange,
            sourceExchange: row.sourceExchange,
            premiumText: resolvedPremium.map {
                String(format: "%@%.2f%%", $0 >= 0 ? "+" : "", $0)
            } ?? premiumPlaceholderText(
                row: row,
                referencePrice: resolvedReferencePrice,
                phase: phase
            ),
            domesticPriceText: row.domesticPrice.map { PriceFormatter.formatPrice($0) } ?? domesticPlaceholderText(phase: phase),
            referencePriceText: resolvedReferencePrice.map { PriceFormatter.formatPrice($0) } ?? referencePlaceholderText(phase: phase),
            premiumIsPlaceholder: premiumIsPlaceholder,
            domesticPriceIsPlaceholder: domesticPriceIsPlaceholder,
            referencePriceIsPlaceholder: referencePriceIsPlaceholder,
            warningMessage: resolvedWarningMessage(
                row: row,
                premiumIsPlaceholder: premiumIsPlaceholder,
                domesticPriceIsPlaceholder: domesticPriceIsPlaceholder,
                referencePriceIsPlaceholder: referencePriceIsPlaceholder,
                phase: phase
            ) ?? freshnessReason,
            isStale: row.isStale,
            status: status,
            freshnessState: freshnessState,
            freshnessReason: freshnessReason,
            updatedAt: updatedAt,
            updatedAgoText: updatedAt.map { userFacingRelativeTimestampText($0) },
            isPreviousSnapshot: false,
            isSourceExchangeMismatch: exchange != row.sourceExchange
        )
    }

    private nonisolated func preferredRow(from rows: [KimchiPremiumRow]) -> KimchiPremiumRow? {
        rows.max { leftRow, rightRow in
            kimchiRowPriority(leftRow) < kimchiRowPriority(rightRow)
        }
    }

    private nonisolated func orderedKimchiSymbols(
        requestedSymbols: [String],
        availableSymbols: [String]
    ) -> [String] {
        var ordered = [String]()
        var seen = Set<String>()

        for symbol in requestedSymbols + availableSymbols.sorted() {
            guard seen.insert(symbol).inserted else {
                continue
            }
            ordered.append(symbol)
        }

        return ordered
    }

    private nonisolated func kimchiRowPriority(_ row: KimchiPremiumRow) -> Int {
        var score = 0
        if row.domesticPrice != nil {
            score += 4
        }
        if resolvedReferencePrice(for: row) != nil {
            score += 3
        }
        if row.premiumPercent != nil {
            score += 2
        }
        if row.isStale == false {
            score += 1
        }
        return score
    }

    private nonisolated func cellStatus(
        row: KimchiPremiumRow,
        premiumIsPlaceholder: Bool,
        domesticPriceIsPlaceholder: Bool,
        referencePriceIsPlaceholder: Bool,
        phase: PresentationPhase
    ) -> KimchiPremiumCellStatus {
        if row.isStale {
            return .stale
        }

        if !premiumIsPlaceholder, !domesticPriceIsPlaceholder, !referencePriceIsPlaceholder {
            return .loaded
        }

        if phase == .responsePending {
            return .loading
        }

        if row.staleReason?.isEmpty == false {
            return .failed
        }

        return .unavailable
    }

    private nonisolated func resolvedFreshnessState(
        row: KimchiPremiumRow,
        premiumIsPlaceholder: Bool,
        domesticPriceIsPlaceholder: Bool,
        referencePriceIsPlaceholder: Bool,
        hasSnapshotPartialFailure: Bool,
        phase: PresentationPhase
    ) -> KimchiPremiumFreshnessState {
        if row.isStale || row.freshnessState == .stale {
            return .stale
        }

        if hasSnapshotPartialFailure || row.freshnessState == .partialUpdate {
            return .partialUpdate
        }

        if domesticPriceIsPlaceholder == false,
           row.referenceExchangePrice != nil,
           row.krwConvertedReference == nil,
           row.usdKrwRate == nil {
            return .exchangeRateDelayed
        }

        if domesticPriceIsPlaceholder == false, referencePriceIsPlaceholder {
            return .referencePriceDelayed
        }

        if domesticPriceIsPlaceholder || premiumIsPlaceholder {
            if phase == .responsePending {
                return row.domesticPrice == nil && row.referenceExchangePrice == nil ? .loading : .partialUpdate
            }
            return .unavailable
        }

        return row.freshnessState ?? .available
    }

    private nonisolated func coinStatus(for cell: KimchiPremiumExchangeCellViewState) -> KimchiPremiumCoinStatus {
        switch cell.status {
        case .loading:
            return .loading
        case .loaded:
            return .loaded
        case .unavailable:
            return .unavailable
        case .stale:
            return .stale
        case .failed:
            return .failed
        }
    }

    private nonisolated func timestampGapMessage(row: KimchiPremiumRow) -> String? {
        guard let localTimestamp = row.sourceExchangeTimestamp, let referenceTimestamp = row.referenceTimestamp else {
            return nil
        }

        let gapSeconds = abs(localTimestamp.timeIntervalSince(referenceTimestamp))
        guard gapSeconds >= 30 else {
            return nil
        }

        return "시차 \(Int(gapSeconds))초"
    }

    private nonisolated func resolvedReferencePrice(for row: KimchiPremiumRow) -> Double? {
        if let krwConvertedReference = row.krwConvertedReference {
            return krwConvertedReference
        }

        guard let referenceExchangePrice = row.referenceExchangePrice, let usdKrwRate = row.usdKrwRate else {
            return nil
        }

        return referenceExchangePrice * usdKrwRate
    }

    private nonisolated func resolvedPremiumPercent(for row: KimchiPremiumRow, referencePrice: Double?) -> Double? {
        if let premiumPercent = row.premiumPercent {
            return premiumPercent
        }

        guard let domesticPrice = row.domesticPrice,
              let referencePrice,
              referencePrice > 0 else {
            return nil
        }

        return ((domesticPrice - referencePrice) / referencePrice) * 100
    }

    private nonisolated func premiumPlaceholderText(
        row: KimchiPremiumRow,
        referencePrice: Double?,
        phase: PresentationPhase
    ) -> String {
        if phase == .settled {
            return "데이터 없음"
        }

        if referencePrice != nil, row.domesticPrice == nil {
            return "가격 확인 중"
        }

        return "기준가 확인 중"
    }

    private nonisolated func domesticPlaceholderText(phase: PresentationPhase) -> String {
        phase == .settled ? "데이터 없음" : "가격 확인 중"
    }

    private nonisolated func referencePlaceholderText(phase: PresentationPhase) -> String {
        phase == .settled ? "데이터 없음" : "기준가 확인 중"
    }

    private nonisolated func resolvedWarningMessage(
        row: KimchiPremiumRow,
        premiumIsPlaceholder: Bool,
        domesticPriceIsPlaceholder: Bool,
        referencePriceIsPlaceholder: Bool,
        phase: PresentationPhase
    ) -> String? {
        if let timestampGapMessage = timestampGapMessage(row: row) {
            return userFacingFreshnessMessage(from: timestampGapMessage)
        }

        if let staleReason = row.staleReason, !staleReason.isEmpty {
            return userFacingFreshnessMessage(from: staleReason)
        }

        if row.isStale {
            return "약간 지연"
        }

        guard phase == .settled else {
            return nil
        }

        if domesticPriceIsPlaceholder {
            return nil
        }

        if referencePriceIsPlaceholder || premiumIsPlaceholder {
            return "데이터 없음"
        }

        return nil
    }

    private nonisolated func resolvedFreshnessReason(
        row: KimchiPremiumRow,
        freshnessState: KimchiPremiumFreshnessState,
        premiumIsPlaceholder: Bool,
        domesticPriceIsPlaceholder: Bool,
        referencePriceIsPlaceholder: Bool,
        phase: PresentationPhase
    ) -> String? {
        if let explicitReason = row.freshnessReason, !explicitReason.isEmpty {
            return userFacingFreshnessMessage(from: explicitReason)
        }

        if let warningMessage = resolvedWarningMessage(
            row: row,
            premiumIsPlaceholder: premiumIsPlaceholder,
            domesticPriceIsPlaceholder: domesticPriceIsPlaceholder,
            referencePriceIsPlaceholder: referencePriceIsPlaceholder,
            phase: phase
        ) {
            return warningMessage
        }

        switch freshnessState {
        case .loading:
            return nil
        case .partialUpdate:
            return "일부 지연"
        case .referencePriceDelayed:
            return "약간 지연"
        case .exchangeRateDelayed:
            return "약간 지연"
        case .stale:
            return "약간 지연"
        case .available:
            return nil
        case .unavailable:
            return "데이터 없음"
        }
    }

    private func userFacingFreshnessMessage(from rawMessage: String?) -> String? {
        guard let rawMessage else {
            return nil
        }
        let trimmedMessage = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return nil }

        let normalized = trimmedMessage
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalized.contains(",") {
            for token in normalized.split(separator: ",") {
                if let mapped = userFacingFreshnessMessage(from: String(token)) {
                    return mapped
                }
            }
        }

        if normalized.contains("partial")
            || normalized.contains("fallback_source")
            || normalized.contains("failed")
            || normalized.contains("일부") {
            return "일부 지연"
        }

        if normalized.contains("fx_rate_delayed")
            || normalized.contains("timestamp_skew_detected")
            || normalized.contains("freshness_threshold_exceeded")
            || normalized.contains("reference")
            || normalized.contains("exchange_rate")
            || normalized.contains("stale")
            || normalized.contains("지연")
            || normalized.contains("늦")
            || normalized.contains("시차") {
            return "약간 지연"
        }

        if normalized.contains("unavailable")
            || normalized.contains("missing")
            || normalized.contains("없")
            || normalized.contains("불가") {
            return "데이터 없음"
        }

        return nil
    }
}

private let relativeStatusFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.unitsStyle = .short
    return formatter
}()

private func userFacingRelativeTimestampText(_ date: Date) -> String {
    let now = Date()
    let clampedDate = date > now ? now : date

    if now.timeIntervalSince(clampedDate) < 1 {
        return "업데이트 방금 전"
    }

    let relative = relativeStatusFormatter.localizedString(for: clampedDate, relativeTo: now)
    if relative == "0초 전" || relative == "0초 후" {
        return "업데이트 방금 전"
    }

    return "업데이트 \(relative)"
}
