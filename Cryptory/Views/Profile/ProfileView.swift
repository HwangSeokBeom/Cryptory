import SwiftUI
import UIKit
import UserNotifications

struct ProfileView: View {
    @ObservedObject var vm: CryptoViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var safariDestination: SafariDestination?
    @State private var confirmationAction: ConfirmationAction?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private enum ConfirmationAction: Identifiable {
        case logout
        case withdraw

        var id: String {
            switch self {
            case .logout:
                return "logout"
            case .withdraw:
                return "withdraw"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    accountSummaryCard
                    quickActionCard
                    supportAndPolicyCard
                    accountActionCard

                    Text("앱 버전 \(appVersionText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("프로필")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .task {
                await refreshNotificationStatus()
                if vm.isAuthenticated,
                   case .idle = vm.exchangeConnectionsState {
                    await vm.loadExchangeConnections(reason: "profile_sheet_appear")
                }
            }
            .sheet(item: $safariDestination) { destination in
                SafariSheet(destination: destination)
                    .ignoresSafeArea()
            }
            .alert(item: $confirmationAction) { action in
                switch action {
                case .logout:
                    return Alert(
                        title: Text("로그아웃할까요?"),
                        message: Text("현재 기기에서 로그인 세션을 해제합니다."),
                        primaryButton: .destructive(Text("로그아웃")) {
                            vm.logout()
                            dismiss()
                        },
                        secondaryButton: .cancel(Text("취소"))
                    )
                case .withdraw:
                    return Alert(
                        title: Text("회원탈퇴 안내를 열까요?"),
                        message: Text("앱에서는 안내 페이지로 이동해 탈퇴 절차를 확인할 수 있어요."),
                        primaryButton: .destructive(Text("안내 열기")) {
                            openExternalLink(.deleteAccount)
                        },
                        secondaryButton: .cancel(Text("취소"))
                    )
                }
            }
        }
    }

    private var accountSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accent.opacity(0.16))
                        .frame(width: 54, height: 54)

                    Image(systemName: vm.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle.badge.questionmark")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(.accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(accountIdentifier)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(.themeText)
                        .lineLimit(2)

                    Text(accountSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                summaryChip(
                    title: vm.isAuthenticated ? "로그인됨" : "게스트",
                    foregroundColor: .themeText,
                    backgroundColor: vm.isAuthenticated ? Color.accent.opacity(0.18) : Color.bgTertiary
                )
                summaryChip(
                    title: connectionSummary,
                    foregroundColor: .textSecondary,
                    backgroundColor: Color.textSecondary.opacity(0.12)
                )
                summaryChip(
                    title: notificationSummary,
                    foregroundColor: .textSecondary,
                    backgroundColor: Color.textSecondary.opacity(0.12)
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("보안 안내")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.themeText)

                Text(vm.isAuthenticated
                     ? "현재 로그인 세션이 활성화되어 있으며, 거래소 API 연결과 정책/지원 관리를 이 화면에서 정리할 수 있어요."
                     : "로그인 후 거래소 연결, 자산 확인, 주문 기능 같은 개인화 기능을 사용할 수 있어요.")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(2)
            }

            if !vm.isAuthenticated {
                Button {
                    dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        vm.presentLogin(for: .portfolio)
                    }
                } label: {
                    Text("로그인하기")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var quickActionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("빠른 설정")

            actionRow(
                icon: "bell.badge",
                iconColor: .accent,
                title: "알림 설정",
                subtitle: notificationSettingsSubtitle
            ) {
                openAppSettings()
            }

            actionRow(
                icon: "link",
                iconColor: .accent,
                title: "연결 거래소 관리",
                subtitle: exchangeConnectionsSubtitle
            ) {
                dismiss()
                Task { @MainActor in
                    await Task.yield()
                    vm.openExchangeConnections()
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var supportAndPolicyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("고객지원 및 정책")

            policyRow(.support, subtitle: "문의, 문제 신고, 앱 사용 지원 페이지를 엽니다.")
            policyRow(.privacyPolicy, subtitle: "개인정보 수집과 처리 기준을 확인합니다.")
            policyRow(.termsOfService, subtitle: "서비스 이용 조건과 책임 범위를 확인합니다.")
            policyRow(.investmentDisclaimer, subtitle: "투자 유의사항과 면책 범위를 확인합니다.")
            policyRow(.home, subtitle: "공식 홈페이지를 엽니다.")
        }
        .padding(16)
        .background(cardBackground)
    }

    private var accountActionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("계정")

            if vm.isAuthenticated {
                actionRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    iconColor: .textSecondary,
                    title: "로그아웃",
                    subtitle: "현재 기기에서 로그인 세션을 종료합니다.",
                    usesDestructiveTint: true
                ) {
                    confirmationAction = .logout
                }
            }

            actionRow(
                icon: "person.crop.circle.badge.minus",
                iconColor: .down,
                title: "회원탈퇴",
                subtitle: "탈퇴 절차와 계정삭제 안내 페이지를 엽니다.",
                usesDestructiveTint: true
            ) {
                confirmationAction = .withdraw
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.themeText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryChip(
        title: String,
        foregroundColor: Color,
        backgroundColor: Color
    ) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
    }

    private func actionRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        usesDestructiveTint: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(usesDestructiveTint ? .themeText : .themeText)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func policyRow(_ link: AppExternalLink, subtitle: String) -> some View {
        actionRow(
            icon: "safari",
            iconColor: .accent,
            title: link.title,
            subtitle: subtitle
        ) {
            openExternalLink(link)
        }
    }

    private var accountIdentifier: String {
        vm.authState.session?.email
            ?? vm.authState.session?.userID
            ?? "게스트 사용자"
    }

    private var accountSubtitle: String {
        vm.isAuthenticated
            ? "로그인 상태가 유지되고 있어요."
            : "로그인하면 내 자산, 연결 거래소, 계정 설정을 함께 관리할 수 있어요."
    }

    private var connectionSummary: String {
        switch vm.exchangeConnectionsState {
        case .loaded(let cards):
            return "연결 \(cards.count)개"
        case .empty:
            return "연결 없음"
        case .idle, .loading:
            return vm.isAuthenticated ? "연결 확인 중" : "로그인 필요"
        case .failed:
            return "연결 확인 필요"
        }
    }

    private var notificationSummary: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "알림 허용됨"
        case .denied:
            return "알림 꺼짐"
        case .notDetermined:
            return "알림 미설정"
        @unknown default:
            return "알림 확인 필요"
        }
    }

    private var notificationSettingsSubtitle: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "시스템 알림 권한이 켜져 있어요. 세부 설정은 기기 설정에서 변경할 수 있어요."
        case .denied:
            return "시스템 설정에서 알림이 꺼져 있어요. 탭하면 설정 화면으로 이동합니다."
        case .notDetermined:
            return "아직 알림 권한이 정해지지 않았어요. 설정 화면에서 상태를 확인할 수 있어요."
        @unknown default:
            return "알림 권한 상태를 확인하려면 설정 화면을 열어주세요."
        }
    }

    private var exchangeConnectionsSubtitle: String {
        switch vm.exchangeConnectionsState {
        case .loaded(let cards):
            return "현재 \(cards.count)개의 연결을 관리하고 있어요."
        case .empty:
            return "아직 연결된 거래소가 없어요. 추가 화면으로 바로 이동할 수 있어요."
        case .idle, .loading:
            return "거래소 연결 상태를 확인하거나 새 연결을 추가할 수 있어요."
        case .failed:
            return "연결 상태를 다시 확인하고 관리 화면으로 이동할 수 있어요."
        }
    }

    private var appVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
    }

    private func openExternalLink(_ link: AppExternalLink) {
        safariDestination = SafariDestination(link: link)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationStatus = settings.authorizationStatus
        }
    }
}
