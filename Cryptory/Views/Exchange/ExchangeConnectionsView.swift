import SwiftUI

struct ExchangeConnectionsView: View {
    @ObservedObject var vm: CryptoViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isCreateSheetPresented = false

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

                case .loaded(let connections):
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(connections) { connection in
                                connectionCard(connection)
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
        .sheet(isPresented: $isCreateSheetPresented) {
            CreateConnectionSheet(vm: vm)
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
                Button {
                    isCreateSheetPresented = true
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
        if vm.exchangeConnectionCRUDCapability.canCreate || vm.exchangeConnectionCRUDCapability.canDelete {
            return "읽기 전용/주문 가능 연결 정책과 생성/삭제 기능을 함께 관리할 수 있어요"
        }
        return "읽기 전용/주문 가능 연결 정책을 확인할 수 있어요"
    }

    private func connectionCard(_ connection: ExchangeConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ExchangeIcon(exchange: connection.exchange, size: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.nickname ?? connection.exchange.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.themeText)
                    Text(connection.exchange.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }

                Spacer()

                Text(connection.permission.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(connection.permission == .tradeEnabled ? .up : .accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill((connection.permission == .tradeEnabled ? Color.up : Color.accent).opacity(0.12))
                    )
            }

            Text(connection.permission.description)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            HStack {
                statusChip(connection.isActive ? "연결됨" : "비활성")
                if let updatedAt = connection.updatedAt, !updatedAt.isEmpty {
                    statusChip("업데이트 \(updatedAt)")
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if vm.exchangeConnectionCRUDCapability.canDelete {
                Button(role: .destructive) {
                    Task {
                        await vm.deleteExchangeConnection(id: connection.id)
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
                Button {
                    isCreateSheetPresented = true
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
        switch (vm.exchangeConnectionCRUDCapability.canCreate, vm.exchangeConnectionCRUDCapability.canDelete) {
        case (true, true):
            return "서버 contract가 생성/삭제를 모두 지원합니다."
        case (true, false):
            return "생성 API만 활성화되어 있고 삭제 API는 아직 비활성 상태입니다."
        case (false, true):
            return "삭제 API만 활성화되어 있고 생성 API는 아직 비활성 상태입니다."
        case (false, false):
            return "현재 앱은 조회 전용 연결 관리로 동작합니다. 서버 CRUD contract가 열리면 추가/삭제 UI를 그대로 활성화할 수 있습니다."
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
    private struct CreateConnectionSheet: View {
        @ObservedObject var vm: CryptoViewModel
        @Environment(\.dismiss) private var dismiss

        @State private var exchange: Exchange = .upbit
        @State private var apiKey = ""
        @State private var secret = ""
        @State private var nickname = ""
        @State private var permission: ExchangeConnectionPermission = .readOnly
        @State private var isSubmitting = false

        var body: some View {
            NavigationStack {
                Form {
                    Section("거래소") {
                        Picker("거래소", selection: $exchange) {
                            ForEach(Exchange.allCases) { exchange in
                                Text(exchange.displayName).tag(exchange)
                            }
                        }
                    }

                    Section("권한") {
                        Picker("권한", selection: $permission) {
                            ForEach(ExchangeConnectionPermission.allCases, id: \.self) { permission in
                                Text(permission.title).tag(permission)
                            }
                        }
                    }

                    Section("인증 정보") {
                        TextField("닉네임(선택)", text: $nickname)
                        TextField("API Key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Secret", text: $secret)
                    }
                }
                .navigationTitle("거래소 연결 추가")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("닫기") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSubmitting ? "추가 중..." : "추가") {
                            Task {
                                isSubmitting = true
                                let created = await vm.createExchangeConnection(
                                    ExchangeConnectionCreateRequest(
                                        exchange: exchange,
                                        apiKey: apiKey,
                                        secret: secret,
                                        permission: permission,
                                        nickname: nickname.isEmpty ? nil : nickname
                                    )
                                )
                                isSubmitting = false
                                if created {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(isSubmitting || apiKey.isEmpty || secret.isEmpty)
                    }
                }
            }
        }
    }
}
