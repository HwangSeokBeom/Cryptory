import SwiftUI

struct ExchangeConnectionsView: View {
    @ObservedObject var vm: CryptoViewModel
    @State private var activeSheet: ActiveSheet?
    @State private var isAddExchangeSheetPresented = false
    @State private var pendingCreateExchange: Exchange?

    private let horizontalPadding: CGFloat = 20
    private let contentSpacing: CGFloat = 14

    private enum ActiveSheet: Identifiable {
        case create(Exchange)
        case edit(ExchangeConnection)

        var id: String {
            switch self {
            case .create(let exchange):
                return "create-\(exchange.rawValue)"
            case .edit(let connection):
                return "edit-\(connection.id)"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let noticeState = vm.exchangeConnectionsNoticeState,
                   shouldShowNotice(for: vm.exchangeConnectionsState) {
                    noticeCard(noticeState)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, 12)
                }

                ScrollView {
                    VStack(spacing: contentSpacing) {
                        content
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, bottomContentInset)
                }
                .scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if vm.exchangeConnectionCRUDCapability.canCreate {
                addExchangeBar
            }
        }
        .sheet(
            isPresented: $isAddExchangeSheetPresented,
            onDismiss: handleAddExchangeSheetDismiss
        ) {
            ExchangeAddSheet(
                exchanges: Exchange.allCases.filter(\.supportsConnectionManagement),
                onSelect: handleAddExchangeSelection
            )
            .presentationDetents([.height(356), .medium])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationCornerRadius(28)
            .presentationBackground(Color.bg)
            .preferredColorScheme(.dark)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create(let exchange):
                ConnectionFormSheet(
                    vm: vm,
                    formViewState: vm.makeExchangeConnectionFormViewState(exchange: exchange),
                    connection: nil
                )
            case .edit(let connection):
                ConnectionFormSheet(
                    vm: vm,
                    formViewState: vm.makeExchangeConnectionFormViewState(
                        exchange: connection.exchange,
                        connection: connection
                    ),
                    connection: connection
                )
            }
        }
        .onAppear {
            AppLogger.debug(
                .lifecycle,
                "[ExchangeConnectionSheetDebug] presentation_reason=sheet_appear render_reason=initial_state state_transition=\(sheetStateDescription)"
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.exchangeConnectionsState {
        case .idle, .loading:
            loadingState
        case .failed(let message):
            errorState(message: message)
        case .empty:
            emptyState
        case .loaded(let cards):
            loadedState(cards)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("거래소 연결 관리")
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.themeText)

            Text("읽기 전용 거래소 연동 상태를 확인하고, 자산 조회 전용 API 키를 안전하게 관리할 수 있어요.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var addExchangeBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.themeBorder.opacity(0.68))
                .frame(height: 1)

            Button {
                presentAddExchangeSheet(reason: "bottom_cta")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))

                    Text("추가")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accent)
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(
                    Rectangle()
                        .fill(Color.bg.opacity(0.98))
                        .ignoresSafeArea()
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingState: some View {
        VStack(spacing: contentSpacing) {
            managementGuideCard

            stateCard(
                icon: "clock.arrow.circlepath",
                iconColor: .accent,
                title: "거래소 연결 상태를 확인하고 있어요",
                detail: "기존 연결 정보가 있으면 그대로 유지하고, 최신 상태만 다시 맞춰둘게요."
            ) {
                ProgressView()
                    .tint(.accent)
                    .padding(.top, 2)
            }
        }
    }

    private func loadedState(_ cards: [ExchangeConnectionCardViewState]) -> some View {
        VStack(spacing: contentSpacing) {
            managementGuideCard

            ForEach(cards) { card in
                connectionCard(card)
            }

            securityNoticeCard
        }
    }

    private var managementGuideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("처음 연결할 때")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.themeText)

            Text("자산 조회 전용 API Key만 등록할 수 있습니다. 주문 권한 또는 출금 권한이 포함된 API Key는 등록하지 마세요.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    private var emptyState: some View {
        VStack(spacing: contentSpacing) {
            stateCard(
                icon: "link.badge.plus",
                iconColor: .accent,
                title: "아직 연결된 거래소가 없어요",
                detail: "읽기 전용 API Key를 연결하면 자산과 보유 코인을 한 곳에서 확인할 수 있어요."
            )

            managementGuideCard
            securityNoticeCard
        }
    }

    private func errorState(message: String) -> some View {
        let isRetryingState = vm.isExchangeConnectionsRetrying || message.contains("다시 확인")

        return VStack(spacing: contentSpacing) {
            stateCard(
                icon: isRetryingState ? "clock.arrow.circlepath" : "exclamationmark.triangle",
                iconColor: isRetryingState ? .accent : .down,
                title: isRetryingState ? "연결 상태를 다시 확인하고 있어요" : "연결 상태를 불러오지 못했어요",
                detail: message
            ) {
                Button {
                    Task {
                        await vm.loadExchangeConnections(reason: "connections_retry_tap")
                    }
                } label: {
                    HStack(spacing: 8) {
                        if vm.isExchangeConnectionsRetrying {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.accent)
                        }

                        Text(vm.isExchangeConnectionsRetrying ? "확인 중..." : "다시 확인")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(vm.isExchangeConnectionsRetrying ? .textMuted : .accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isExchangeConnectionsRetrying)
            }

            managementGuideCard
        }
    }

    private func connectionCard(_ card: ExchangeConnectionCardViewState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ExchangeIcon(exchange: card.connection.exchange, size: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.connection.displayTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.themeText)

                    Text(card.connection.exchange.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }

                Spacer()

                permissionBadge(for: card.connection.permission)
            }

            Text(card.secondaryMessage)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            if !card.statusChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(card.statusChips, id: \.self) { chip in
                            statusChip(chip)
                        }
                    }
                }
            }

            HStack {
                if card.canEdit {
                    Button {
                        activeSheet = .edit(card.connection)
                    } label: {
                        Text("연결 수정")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accent.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(cardBackground)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if card.canDelete {
                Button(role: .destructive) {
                    Task {
                        await vm.deleteExchangeConnection(id: card.connection.id)
                    }
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
    }

    private var securityNoticeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("보안 안내")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.themeText)

            Text("거래소 비밀번호는 요구하지 않으며, API 키는 읽기 전용 자산 조회를 위해서만 사용해요. 주문/출금 권한이 포함된 키는 등록하지 마세요.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)

            Text("고객지원과 정책 링크는 프로필에서 확인할 수 있어요.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    private func noticeCard(_ noticeState: ExchangeConnectionsNoticeState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(noticeForegroundColor(for: noticeState.tone))
                    .frame(width: 8, height: 8)

                Text(noticeState.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.themeText)
            }

            Text(noticeState.message)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(noticeBackgroundColor(for: noticeState.tone))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(noticeForegroundColor(for: noticeState.tone).opacity(0.28), lineWidth: 1)
                )
        )
    }

    private func permissionBadge(for permission: ExchangeConnectionPermission) -> some View {
        let isTradingEnabled = permission == .tradeEnabled
        return Text(isTradingEnabled ? "읽기 전용으로 제한됨" : permission.title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(isTradingEnabled ? .up : .accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill((isTradingEnabled ? Color.up : Color.accent).opacity(0.12))
            )
    }

    private func statusChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.bgTertiary)
            )
    }

    private func shouldShowNotice(for state: Loadable<[ExchangeConnectionCardViewState]>) -> Bool {
        switch state {
        case .loaded, .empty:
            return true
        case .idle, .loading, .failed:
            return false
        }
    }

    private func noticeBackgroundColor(for tone: StatusBadgeTone) -> Color {
        switch tone {
        case .neutral:
            return Color.bgSecondary
        case .success:
            return Color.up.opacity(0.12)
        case .warning:
            return Color.accent.opacity(0.1)
        case .error:
            return Color.down.opacity(0.12)
        }
    }

    private func noticeForegroundColor(for tone: StatusBadgeTone) -> Color {
        switch tone {
        case .neutral:
            return .textSecondary
        case .success:
            return .up
        case .warning:
            return .accent
        case .error:
            return .down
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
    }

    private var bottomContentInset: CGFloat {
        vm.exchangeConnectionCRUDCapability.canCreate ? 112 : 24
    }

    private var sheetStateDescription: String {
        switch vm.exchangeConnectionsState {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded(let cards):
            return "loaded(count:\(cards.count))"
        case .empty:
            return "empty"
        case .failed:
            return "failed"
        }
    }

    private func stateCard<Accessory: View>(
        icon: String,
        iconColor: Color,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(iconColor)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.themeText)

                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
            }

            accessory()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
        .background(cardBackground)
    }

    private func presentAddExchangeSheet(reason: String) {
        guard !isAddExchangeSheetPresented else {
            return
        }
        AppLogger.debug(
            .lifecycle,
            "[ExchangeAddSheetDebug] presentation_reason=\(reason) state_transition=false->true"
        )
        isAddExchangeSheetPresented = true
    }

    private func handleAddExchangeSelection(_ exchange: Exchange) {
        pendingCreateExchange = exchange
        AppLogger.debug(
            .lifecycle,
            "[ExchangeAddSheetDebug] presentation_reason=exchange_selected state_transition=true->false exchange=\(exchange.rawValue)"
        )
        isAddExchangeSheetPresented = false
    }

    private func handleAddExchangeSheetDismiss() {
        guard let exchange = pendingCreateExchange else {
            AppLogger.debug(
                .lifecycle,
                "[ExchangeAddSheetDebug] presentation_reason=dismiss_without_selection state_transition=true->false"
            )
            return
        }

        pendingCreateExchange = nil
        Task { @MainActor in
            await Task.yield()
            AppLogger.debug(
                .lifecycle,
                "[ExchangeConnectionSheetDebug] presentation_reason=add_sheet_selection state_transition=form:nil->create-\(exchange.rawValue)"
            )
            activeSheet = .create(exchange)
        }
    }
}

private struct ExchangeAddSheet: View {
    let exchanges: [Exchange]
    let onSelect: (Exchange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("거래소 선택")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.themeText)

                Text("추가할 거래소를 선택하면 다음 단계에서 API 키를 바로 등록할 수 있어요.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(exchanges) { exchange in
                        Button {
                            onSelect(exchange)
                        } label: {
                            HStack(spacing: 12) {
                                ExchangeIcon(exchange: exchange, size: 18)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exchange.displayName)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.themeText)

                                    Text("읽기 전용 자산 조회 연결에 사용할 수 있어요.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 12)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textMuted)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.bgSecondary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.themeBorder, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color.bg)
    }
}

extension ExchangeConnectionsView {
    private struct ConnectionFormSheet: View {
        @ObservedObject var vm: CryptoViewModel
        let formViewState: ExchangeConnectionFormViewState
        let connection: ExchangeConnection?

        @Environment(\.dismiss) private var dismiss

        @State private var nickname = ""
        @State private var permission: ExchangeConnectionPermission = .readOnly
        @State private var credentialValues: [ExchangeCredentialFieldKey: String] = [:]
        @State private var revealedCredentialFields: Set<ExchangeCredentialFieldKey> = []
        @State private var isSubmitting = false
        @State private var validationMessage: String?
        @State private var safariDestination: SafariDestination?
        @State private var confirmedReadOnlyPermission = false
        @State private var confirmedNoOrderWithdrawPermission = false

        private var guide: ExchangeConnectionGuide {
            formViewState.exchange.connectionGuide
        }

        private var isTradePermissionSelectable: Bool {
            AppFeatureFlags.current.isTradingEnabled && formViewState.exchange.supportsOrder
        }

        private var submitValidationMessage: String? {
            vm.validationMessageForExchangeConnectionForm(
                exchange: formViewState.exchange,
                nickname: nickname,
                credentials: credentialValues,
                mode: formViewState.mode
            )
        }

        private var canSubmit: Bool {
            !isSubmitting
                && submitValidationMessage == nil
                && confirmedReadOnlyPermission
                && confirmedNoOrderWithdrawPermission
        }

        private var developerCenterLinkTitle: String {
            formViewState.exchange == .upbit
                ? "업비트 개발자센터 열기"
                : "\(formViewState.exchange.displayName) API 안내 열기"
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        exchangeSummaryCard
                    }
                    .listRowBackground(Color.clear)

                    Section("연결 목적") {
                        VStack(spacing: 12) {
                            permissionOptionCard(
                                permission: .readOnly,
                                title: "조회 전용",
                                description: "자산 조회 전용 API Key만 등록할 수 있습니다.",
                                footnote: "Cryptory는 읽기 전용 포트폴리오 조회 목적으로만 사용합니다.",
                                isRecommended: true,
                                isDisabled: false
                            )

                            readOnlyConfirmationCard
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        credentialInputCard
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        securityScopeCard
                    }
                    .listRowBackground(Color.clear)

                    Section("도움말") {
                        apiHelpCard
                    }
                    .listRowBackground(Color.clear)

                    if let validationMessage, !validationMessage.isEmpty {
                        Section {
                            Text(validationMessage)
                                .font(.system(size: 12))
                                .foregroundColor(.down)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.bg)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("읽기 전용 거래소 연동")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("닫기") {
                            dismiss()
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    submitBar
                }
                .onAppear {
                    nickname = connection?.nickname ?? ""
                    permission = .readOnly
                }
                .sheet(item: $safariDestination) { destination in
                    SafariSheet(destination: destination)
                        .ignoresSafeArea()
                }
            }
        }

        private var exchangeSummaryCard: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ExchangeIcon(exchange: formViewState.exchange, size: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(formViewState.exchange.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.themeText)

                        Text(connection == nil ? "외부 거래소에서 발급한 읽기 전용 API 키를 연결합니다." : "저장된 읽기 전용 연결 정보를 안전하게 수정합니다.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()
                }

                Text("주문 권한 또는 출금 권한이 포함된 API Key는 등록하지 마세요.")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
        }

        private var credentialInputCard: some View {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("인증 정보 입력")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.themeText)

                    Text("거래소 웹사이트에서 직접 발급한 키를 그대로 붙여넣어 주세요.")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                }

                credentialInputRow(
                    title: "닉네임",
                    helper: "선택 입력입니다. 여러 연결을 구분할 때만 사용하세요."
                ) {
                    TextField("닉네임(선택)", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onChange(of: nickname) { _, _ in
                            validationMessage = nil
                        }
                }

                ForEach(formViewState.credentialFields) { field in
                    credentialInputRow(
                        title: field.title,
                        helper: credentialHelperText(for: field)
                    ) {
                        credentialField(for: field)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.accent.opacity(0.28), lineWidth: 1)
                    )
            )
        }

        private var securityScopeCard: some View {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("권한 안내")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.themeText)

                    Text("자산 조회 전용 API Key만 등록할 수 있습니다. 주문/출금 권한이 감지되거나 의심되는 키는 사용하지 마세요.")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(relevantPermissionTips, id: \.self) { tip in
                        permissionTipRow(tip)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.down)
                            .frame(width: 22, alignment: .center)
                            .padding(.top, 1)

                        Text("가능하면 출금 권한은 부여하지 마세요.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.down)
                            .lineSpacing(2)
                    }
                }

                Divider()
                    .background(Color.themeBorder)

                VStack(alignment: .leading, spacing: 10) {
                    securityBullet("앱은 거래소 계정 비밀번호를 요구하지 않아요.")
                    securityBullet("입력한 API 키는 연결 검증과 읽기 전용 자산 조회를 위해 서버의 연결 API로 전달돼요.")
                    securityBullet("주문 권한 또는 출금 권한이 포함된 API Key는 등록하지 마세요.")

                    if connection != nil {
                        securityBullet("기존 Secret Key는 다시 보여주지 않아요. 변경이 필요하면 새 값을 다시 입력해 주세요.")
                    }

                    ForEach(guide.cautionNotes, id: \.self) { note in
                        securityBullet(note)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
        }

        private var apiHelpCard: some View {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("API 발급 안내")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.themeText)

                    Text(guide.issueSummary)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                }

                guideLinkButton(
                    title: developerCenterLinkTitle,
                    subtitle: "공식 API 문서를 앱 안 Safari로 열어 확인할 수 있어요.",
                    urlString: guide.apiManagementURLString
                )

                if let documentationURLString = guide.documentationURLString {
                    guideLinkButton(
                        title: "Open API 안내 보기",
                        subtitle: "API 키 사용 조건과 기본 안내를 공식 문서에서 확인하세요.",
                        urlString: documentationURLString
                    )
                }

                if let permissionGuideURLString = guide.permissionGuideURLString {
                    guideLinkButton(
                        title: "권한 및 허용 IP 설정 방법 보기",
                        subtitle: "읽기 권한만 허용하고 출금 권한 제외, 허용 IP 등록 기준을 확인하세요.",
                        urlString: permissionGuideURLString
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("빠른 체크")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.themeText)

                    ForEach(Array(readOnlyIssuanceSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.accent)
                                .frame(width: 18, alignment: .leading)

                            Text(step)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .lineSpacing(2)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
        }

        private var submitBar: some View {
            VStack(spacing: 8) {
                Button {
                    Task {
                        await submit()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }

                        Text(isSubmitting ? "연결 중..." : (connection == nil ? "읽기 전용 API Key 연결" : "읽기 전용 API Key 수정"))
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor((canSubmit || isSubmitting) ? .white : .textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill((canSubmit || isSubmitting) ? Color.accent : Color.bgTertiary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)

                Text("필수 키와 읽기 전용 확인을 완료하면 연결할 수 있어요.")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
                    .opacity(canSubmit ? 0 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(
                Rectangle()
                    .fill(Color.bg.opacity(0.96))
                    .ignoresSafeArea()
            )
        }

        private var relevantPermissionTips: [String] {
            [
                "자산 조회와 보유 코인 확인 권한만 허용하세요.",
                "읽기 권한 외 기능 권한은 비활성화하세요.",
                "출금 권한은 반드시 제외하세요."
            ]
        }

        private var readOnlyConfirmationCard: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("필수 확인")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.themeText)

                confirmationRow(
                    isOn: $confirmedReadOnlyPermission,
                    text: "이 API Key가 읽기 전용 권한임을 확인했습니다."
                )

                confirmationRow(
                    isOn: $confirmedNoOrderWithdrawPermission,
                    text: "주문/출금 권한이 포함된 API Key를 등록하지 않겠습니다."
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.accent.opacity(0.28), lineWidth: 1)
                    )
            )
        }

        private var readOnlyIssuanceSteps: [String] {
            [
                "거래소 웹사이트에서 API Key를 발급할 때 읽기 권한만 선택하세요.",
                "출금 권한은 선택하지 말고, 가능하면 허용 IP를 제한하세요.",
                "발급된 키를 붙여넣기 전 읽기 전용 권한인지 다시 확인하세요."
            ]
        }

        private func confirmationRow(isOn: Binding<Bool>, text: String) -> some View {
            Button {
                isOn.wrappedValue.toggle()
                validationMessage = nil
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isOn.wrappedValue ? .accent : .textMuted)
                        .padding(.top, 1)

                    Text(text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }

        private func credentialInputRow<Content: View>(
            title: String,
            helper: String,
            @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.themeText)

                content()
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.themeText)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.bgTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.themeBorder, lineWidth: 1)
                            )
                    )

                Text(helper)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
            }
        }

        private func permissionTipRow(_ text: String) -> some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(permission == .tradeEnabled ? .up : .accent)
                    .frame(width: 22, alignment: .center)
                    .padding(.top, 1)

                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func guideLinkButton(
            title: String,
            subtitle: String,
            urlString: String
        ) -> some View {
            Button {
                safariDestination = SafariDestination(id: title, title: title, urlString: urlString)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accent)
                        Spacer()
                        Image(systemName: "safari")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accent)
                    }

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.bgSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.themeBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }

        private func permissionOptionCard(
            permission option: ExchangeConnectionPermission,
            title: String,
            description: String,
            footnote: String,
            isRecommended: Bool,
            isDisabled: Bool
        ) -> some View {
            let isSelected = permission == option

            return Button {
                guard !isDisabled else { return }
                permission = option
                validationMessage = nil
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? .accent : .textMuted)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isDisabled ? .textMuted : .themeText)

                            if isRecommended {
                                Text("권장")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.accent.opacity(0.12))
                                    )
                            } else {
                                Text("추가 권한")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.up)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.up.opacity(0.12))
                                    )
                            }
                        }

                        Text(description)
                            .font(.system(size: 12))
                            .foregroundColor(isDisabled ? .textMuted : .textSecondary)

                        Text(footnote)
                            .font(.system(size: 11))
                            .foregroundColor(isDisabled ? .textMuted : .textSecondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Color.accent.opacity(0.1) : Color.bgSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    isSelected ? Color.accent : Color.themeBorder,
                                    lineWidth: 1
                                )
                        )
                )
                .opacity(isDisabled ? 0.72 : 1)
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder
        private func credentialField(for field: ExchangeCredentialFieldDefinition) -> some View {
            if field.isSecureEntry {
                HStack(spacing: 8) {
                    Group {
                        if revealedCredentialFields.contains(field.fieldKey) {
                            TextField(field.placeholder, text: binding(for: field.fieldKey))
                        } else {
                            SecureField(field.placeholder, text: binding(for: field.fieldKey))
                                .privacySensitive()
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.password)
                    .submitLabel(.done)

                    Button {
                        if revealedCredentialFields.contains(field.fieldKey) {
                            revealedCredentialFields.remove(field.fieldKey)
                        } else {
                            revealedCredentialFields.insert(field.fieldKey)
                        }
                    } label: {
                        Image(systemName: revealedCredentialFields.contains(field.fieldKey) ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealedCredentialFields.contains(field.fieldKey) ? "Secret Key 가리기" : "Secret Key 보기")
                }
            } else {
                TextField(field.placeholder, text: binding(for: field.fieldKey))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.next)
            }
        }

        private func credentialHelperText(for field: ExchangeCredentialFieldDefinition) -> String {
            switch field.fieldKey {
            case .accessKey:
                return "거래소에서 발급한 Access Key를 그대로 붙여넣어 주세요."
            case .secretKey:
                return connection == nil
                    ? "발급 직후 한 번만 보이는 Secret Key를 정확히 붙여넣어 주세요."
                    : "변경할 때만 새 Secret Key를 입력하면 돼요."
            case .accessToken:
                return "코인원에서 발급한 Access Token을 그대로 붙여넣어 주세요."
            }
        }

        private func securityBullet(_ text: String) -> some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accent)
                    .padding(.top, 2)

                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
        }

        private func binding(for fieldKey: ExchangeCredentialFieldKey) -> Binding<String> {
            Binding(
                get: { credentialValues[fieldKey, default: ""] },
                set: {
                    credentialValues[fieldKey] = $0
                    validationMessage = nil
                }
            )
        }

        private func submit() async {
            guard !isSubmitting else { return }

            validationMessage = vm.validationMessageForExchangeConnectionForm(
                exchange: formViewState.exchange,
                nickname: nickname,
                credentials: credentialValues,
                mode: formViewState.mode
            )

            guard validationMessage == nil else { return }

            isSubmitting = true

            let didSucceed: Bool
            if let connection {
                didSucceed = await vm.updateExchangeConnection(
                    connection: connection,
                    nickname: nickname,
                    permission: .readOnly,
                    credentials: credentialValues
                )
            } else {
                didSucceed = await vm.createExchangeConnection(
                    exchange: formViewState.exchange,
                    nickname: nickname,
                    permission: .readOnly,
                    credentials: credentialValues
                )
            }

            isSubmitting = false

            if didSucceed {
                dismiss()
            }
        }
    }
}
