import SwiftUI

struct ExchangeConnectionsView: View {
    @ObservedObject var vm: CryptoViewModel
    @State private var activeSheet: ActiveSheet?
    @State private var safariDestination: SafariDestination?

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

            VStack(spacing: 14) {
                header

                if let noticeState = vm.exchangeConnectionsNoticeState,
                   shouldShowNotice(for: vm.exchangeConnectionsState) {
                    noticeCard(noticeState)
                        .padding(.horizontal, 20)
                }

                content
            }
            .padding(.top, 8)
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
        .sheet(item: $safariDestination) { destination in
            SafariSheet(destination: destination)
                .ignoresSafeArea()
        }
    }

    private var content: some View {
        Group {
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("거래소 연결 관리")
                .font(.system(size: 23, weight: .heavy))
                .foregroundColor(.themeText)

            Text("연결된 거래소를 확인하고, 필요한 경우 본문에서 새 API 키를 추가할 수 있어요.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var primaryAddExchangeMenu: some View {
        Menu {
            ForEach(Exchange.allCases.filter(\.supportsConnectionManagement)) { exchange in
                Button(exchange.displayName) {
                    activeSheet = .create(exchange)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))

                Text("추가")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accent)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .tint(.accent)
                .scaleEffect(1.08)

            Text("거래소 연결 상태를 확인하고 있어요")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.themeText)

            Text("기존 연결 정보가 있으면 그대로 유지한 채 최신 상태를 다시 확인할게요.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func loadedState(_ cards: [ExchangeConnectionCardViewState]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                managementGuideCard
                supportLinksCard

                ForEach(cards) { card in
                    connectionCard(card)
                }

                securityNoticeCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    private var managementGuideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("처음 연결할 때")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.themeText)

            Text("거래소 웹사이트에서 직접 발급한 API 키만 연결할 수 있어요. 가능하면 조회 권한부터 시작하고, 출금 권한은 켜지 않는 것을 권장해요.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "link.badge.plus")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.accent)

            Text("아직 연결된 거래소가 없어요")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.themeText)

            Text("거래소를 연결하면 자산, 잔고, 주문 상태를 한 곳에서 확인할 수 있어요.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            managementGuideCard
                .padding(.horizontal, 20)

            supportLinksCard
                .padding(.horizontal, 20)

            if vm.exchangeConnectionCRUDCapability.canCreate {
                primaryAddExchangeMenu
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(message: String) -> some View {
        let isRetryingState = vm.isExchangeConnectionsRetrying || message.contains("다시 확인")

        return VStack(spacing: 14) {
            Spacer()

            Image(systemName: isRetryingState ? "clock.arrow.circlepath" : "exclamationmark.triangle")
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(isRetryingState ? .accent : .down)

            Text(isRetryingState ? "연결 상태를 다시 확인하고 있어요" : "연결 상태를 불러오지 못했어요")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.themeText)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

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

            Spacer()
        }
        .frame(maxWidth: .infinity)
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

            Text("거래소 비밀번호는 요구하지 않으며, API 키는 연결 확인과 기능 제공을 위해서만 사용해요. 가능하면 조회 권한부터 시작하고 출금 권한은 비활성화해 주세요.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    private var supportLinksCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("도움말 및 정책")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.themeText)

            policyLinkRow(
                .support,
                subtitle: "문의, 문제 신고, 앱 사용 지원 페이지를 엽니다."
            )
            policyLinkRow(
                .deleteAccount,
                subtitle: "계정삭제 및 회원탈퇴 안내를 확인합니다."
            )
            policyLinkRow(
                .investmentDisclaimer,
                subtitle: "거래와 자산 정보 이용 전 유의사항을 확인합니다."
            )

            Divider()
                .background(Color.themeBorder)

            HStack(spacing: 12) {
                compactPolicyLink(.privacyPolicy)
                compactPolicyLink(.termsOfService)
                compactPolicyLink(.home)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    private func policyLinkRow(_ link: AppExternalLink, subtitle: String) -> some View {
        Button {
            openExternalLink(link)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "safari")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accent)
                    .frame(width: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(link.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accent)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func compactPolicyLink(_ link: AppExternalLink) -> some View {
        Button {
            openExternalLink(link)
        } label: {
            Text(link.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
        return Text(permission.title)
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

    private func openExternalLink(_ link: AppExternalLink) {
        safariDestination = SafariDestination(link: link)
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

        private var guide: ExchangeConnectionGuide {
            formViewState.exchange.connectionGuide
        }

        private var isTradePermissionSelectable: Bool {
            formViewState.exchange.supportsOrder
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
            !isSubmitting && submitValidationMessage == nil
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
                                description: "자산, 잔고, 보유 코인 정보를 불러올 수 있어요.",
                                footnote: "최소 권한으로 시작할 수 있어요.",
                                isRecommended: true,
                                isDisabled: false
                            )

                            permissionOptionCard(
                                permission: .tradeEnabled,
                                title: "주문 가능",
                                description: "조회 기능에 더해 주문/취소 기능에 사용할 수 있어요.",
                                footnote: isTradePermissionSelectable
                                    ? "거래소에서 주문 권한을 추가로 켜야 해요."
                                    : "현재 앱에서는 이 거래소의 주문 기능 연결을 아직 권장하지 않아요.",
                                isRecommended: false,
                                isDisabled: !isTradePermissionSelectable
                            )
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
                .navigationTitle(connection == nil ? "거래소 연결 추가" : "거래소 연결 수정")
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
                    permission = connection?.permission ?? .readOnly
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

                        Text(connection == nil ? "외부 거래소에서 발급한 API 키를 연결합니다." : "저장된 연결 정보를 안전하게 수정합니다.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()
                }

                Text("API 키가 이미 있다면 아래 인증 정보에 바로 붙여넣어 연결할 수 있어요.")
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
                    Text(permission == .readOnly ? "필요 권한 안내" : "주문 권한 안내")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.themeText)

                    Text(permission == .readOnly
                         ? "조회 전용 연결은 자산과 주문 조회에 필요한 권한만 확인하면 돼요."
                         : "주문 기능을 쓰려면 조회 권한에 주문 권한만 추가하고, 출금 권한은 제외하세요.")
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
                    securityBullet("입력한 API 키는 연결 검증과 자산/주문 기능 제공을 위해 서버의 연결 API로 전달돼요.")
                    securityBullet("조회 전용 연결을 기본으로 권장하며, 주문 권한은 필요할 때만 추가하세요.")

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
                        subtitle: "주문 권한, 출금 권한 제외, 허용 IP 등록 기준을 확인하세요.",
                        urlString: permissionGuideURLString
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("빠른 체크")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.themeText)

                    ForEach(Array(guide.issuanceSteps.enumerated()), id: \.offset) { index, step in
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

                        Text(isSubmitting ? "\(formViewState.submitTitle) 중..." : formViewState.submitTitle)
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

                Text("필수 키를 입력하면 \(formViewState.submitTitle)할 수 있어요.")
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
            let filteredTips: [String]
            switch permission {
            case .readOnly:
                filteredTips = guide.permissionTips.filter {
                    $0.contains("조회") || $0.contains("Reading")
                }
            case .tradeEnabled:
                filteredTips = guide.permissionTips.filter {
                    $0.contains("조회")
                        || $0.contains("주문")
                        || $0.contains("Trading")
                        || $0.contains("Reading")
                }
            }

            return filteredTips.isEmpty ? guide.permissionTips : filteredTips
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
                    permission: permission,
                    credentials: credentialValues
                )
            } else {
                didSucceed = await vm.createExchangeConnection(
                    exchange: formViewState.exchange,
                    nickname: nickname,
                    permission: permission,
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
