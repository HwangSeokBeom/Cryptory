import SwiftUI

struct ExchangeConnectionsView: View {
    @ObservedObject var vm: CryptoViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: ActiveSheet?

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

            VStack(spacing: 18) {
                header

                switch vm.exchangeConnectionsState {
                case .idle, .loading:
                    Spacer()
                    ProgressView("거래소 연결을 불러오는 중...")
                        .tint(.accent)
                    Spacer()

                case .failed(let message):
                    errorState(message: message)

                case .empty:
                    emptyState

                case .loaded(let cards):
                    ScrollView {
                        VStack(spacing: 12) {
                            readySoonNotice

                            ForEach(cards) { card in
                                connectionCard(card)
                            }

                            capabilityNotice
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.top, 12)
        }
        .task {
            await vm.loadExchangeConnections()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create(let exchange):
                ConnectionFormSheet(vm: vm, formViewState: vm.makeExchangeConnectionFormViewState(exchange: exchange), connection: nil)
            case .edit(let connection):
                ConnectionFormSheet(vm: vm, formViewState: vm.makeExchangeConnectionFormViewState(exchange: connection.exchange, connection: connection), connection: connection)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("거래소 연결 관리")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.themeText)
                Text(headerDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            if vm.exchangeConnectionCRUDCapability.canCreate {
                Menu {
                    ForEach(Exchange.allCases.filter(\.supportsConnectionManagement)) { exchange in
                        Button(exchange.displayName) {
                            activeSheet = .create(exchange)
                        }
                    }
                } label: {
                    Text("추가")
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

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.bgSecondary)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    private var headerDescription: String {
        "서버 exchange-connections API 로만 credential 연결/수정/삭제를 수행합니다."
    }

    private func connectionCard(_ card: ExchangeConnectionCardViewState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ExchangeIcon(exchange: card.connection.exchange, size: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.connection.displayTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.themeText)
                    Text(card.connection.exchange.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }

                Spacer()

                Text(card.connection.permission.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(card.connection.permission == .tradeEnabled ? .up : .accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill((card.connection.permission == .tradeEnabled ? Color.up : Color.accent).opacity(0.12))
                    )
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

    private var readySoonNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("준비 중")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.themeText)
            Text("바이낸스 연결 UI 는 감추고 서버 reference price provider 로만 사용합니다.")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "link.badge.plus")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.accent)

            Text("연결된 거래소가 없어요")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.themeText)

            Text("거래소 연결이 생기면 자산과 주문 데이터를 서버에서 불러올 수 있어요.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if vm.exchangeConnectionCRUDCapability.canCreate {
                Menu {
                    ForEach(Exchange.allCases.filter(\.supportsConnectionManagement)) { exchange in
                        Button(exchange.displayName) {
                            activeSheet = .create(exchange)
                        }
                    }
                } label: {
                    Text("거래소 연결 추가")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accent.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var capabilityNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("연결 API 상태")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.themeText)
            Text(capabilityDescription)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private var capabilityDescription: String {
        switch (vm.exchangeConnectionCRUDCapability.canCreate, vm.exchangeConnectionCRUDCapability.canUpdate, vm.exchangeConnectionCRUDCapability.canDelete) {
        case (true, true, true):
            return "서버 contract가 생성/수정/삭제를 모두 지원합니다."
        case (true, true, false):
            return "생성/수정 API는 열려 있고 삭제 API는 아직 비활성 상태입니다."
        case (true, false, false):
            return "생성 API만 활성화되어 있고 수정/삭제는 아직 비활성 상태입니다."
        default:
            return "현재 앱은 조회 전용 연결 관리로 동작합니다."
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.down)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
        @State private var isSubmitting = false
        @State private var validationMessage: String?

        var body: some View {
            NavigationStack {
                Form {
                    Section("거래소") {
                        HStack {
                            Text("선택 거래소")
                            Spacer()
                            Text(formViewState.exchange.displayName)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Section("권한") {
                        Picker("권한", selection: $permission) {
                            ForEach(ExchangeConnectionPermission.allCases, id: \.self) { permission in
                                Text(permission.title).tag(permission)
                            }
                        }
                    }

                    Section("표시 정보") {
                        TextField("닉네임(선택)", text: $nickname)
                    }

                    Section("인증 정보") {
                        ForEach(formViewState.credentialFields) { field in
                            if field.isSecureEntry {
                                SecureField(field.placeholder, text: binding(for: field.fieldKey))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                TextField(field.placeholder, text: binding(for: field.fieldKey))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                    }

                    if !formViewState.helperMessage.isEmpty {
                        Section("안내") {
                            Text(formViewState.helperMessage)
                            if !formViewState.requiresSecretOnUpdateExplanation.isEmpty {
                                Text(formViewState.requiresSecretOnUpdateExplanation)
                            }
                        }
                    }

                    if let validationMessage, !validationMessage.isEmpty {
                        Section {
                            Text(validationMessage)
                                .foregroundColor(.down)
                        }
                    }
                }
                .navigationTitle(connection == nil ? "거래소 연결 추가" : "거래소 연결 수정")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("닫기") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSubmitting ? "\(formViewState.submitTitle) 중..." : formViewState.submitTitle) {
                            Task {
                                await submit()
                            }
                        }
                        .disabled(isSubmitting)
                    }
                }
                .onAppear {
                    nickname = connection?.nickname ?? ""
                    permission = connection?.permission ?? .readOnly
                }
            }
        }

        private func binding(for fieldKey: ExchangeCredentialFieldKey) -> Binding<String> {
            Binding(
                get: { credentialValues[fieldKey, default: ""] },
                set: { credentialValues[fieldKey] = $0 }
            )
        }

        private func submit() async {
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
