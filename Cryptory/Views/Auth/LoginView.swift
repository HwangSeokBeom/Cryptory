import SwiftUI

struct LoginView: View {
    @ObservedObject var vm: CryptoViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var activeLegalSheet: LegalSheet?
    @State private var didAttemptSignUpSubmit = false

    private enum Field: Hashable {
        case loginEmail
        case loginPassword
        case signupNickname
        case signupEmail
        case signupPassword
        case signupPasswordConfirm
    }

    private enum LegalSheet: Identifiable {
        case terms
        case privacy

        var id: String {
            switch self {
            case .terms:
                return "terms"
            case .privacy:
                return "privacy"
            }
        }

        var title: String {
            switch self {
            case .terms:
                return "서비스 이용약관"
            case .privacy:
                return "개인정보 처리방침"
            }
        }

        var summaryLines: [String] {
            switch self {
            case .terms:
                return [
                    "회원가입 시 이메일 기반 계정을 생성하고 거래소 연결, 주문, 자산 조회 기능을 이용할 수 있습니다.",
                    "거래소 API 키는 사용자가 명시적으로 연결한 경우에만 서버 연결 API로 전달됩니다.",
                    "출금 권한은 기본적으로 권장하지 않으며, 앱에서도 조회/거래 권한 중심으로 안내합니다."
                ]
            case .privacy:
                return [
                    "로그인 세션은 기기 보안 저장소를 우선 사용해 보관합니다.",
                    "입력 중인 민감한 키 값은 화면에서 마스킹하고, 전체 값을 다시 노출하지 않습니다.",
                    "문제가 발생하면 사용성 개선과 보안 점검을 위해 최소한의 오류 로그만 남깁니다."
                ]
            }
        }
    }

    private var validation: SignUpFormValidationResult {
        vm.signUpValidation
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    modeSelector
                    heroCopy

                    if vm.authFlowMode == .login {
                        loginForm
                    } else {
                        signUpForm
                    }

                    footerPrompt
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnBackgroundTap()
        .sheet(item: $activeLegalSheet) { sheet in
            legalSheet(sheet)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: vm.authFlowMode) { _, _ in
            focusedField = nil
            didAttemptSignUpSubmit = false
        }
    }

    private var header: some View {
        HStack {
            Spacer()

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
    }

    private var modeSelector: some View {
        HStack(spacing: 8) {
            authModeButton(.login)
            authModeButton(.signUp)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        )
    }

    private func authModeButton(_ mode: AuthFlowMode) -> some View {
        let isSelected = vm.authFlowMode == mode

        return Button {
            selectAuthFlowMode(mode)
        } label: {
            Text(mode.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isSelected ? .white : .textMuted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accent : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                selectAuthFlowMode(mode)
            }
        )
    }

    private var heroCopy: some View {
        VStack(spacing: 10) {
            Text(vm.authFlowMode == .login ? "로그인" : "회원가입")
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(.themeText)

            Text(vm.authFlowMode == .login
                 ? "로그인 후 내 자산, 주문, 거래소 연결을 바로 이어서 사용할 수 있어요."
                 : "이메일로 계정을 만들고 약관 동의 후 바로 로그인 상태로 진입합니다.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 8)
    }

    private var loginForm: some View {
        return VStack(spacing: 14) {
            formField(
                title: "이메일",
                text: $vm.loginEmail,
                placeholder: "name@example.com",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                secure: false
            )
            .focused($focusedField, equals: .loginEmail)

            formField(
                title: "비밀번호",
                text: $vm.loginPassword,
                placeholder: "비밀번호 입력",
                keyboardType: .default,
                textContentType: .password,
                secure: true
            )
            .focused($focusedField, equals: .loginPassword)

            if let error = vm.loginErrorMessage, !error.isEmpty {
                inlineMessage(error, tone: .error)
            }

            submitButton(
                title: vm.isSigningIn ? "로그인 중..." : "로그인",
                isLoading: vm.isSigningIn,
                isEnabled: vm.canSubmitLogin,
                action: {
                    Task {
                        await vm.submitLogin()
                    }
                }
            )
        }
    }

    private var signUpForm: some View {
        let shouldShowNicknameError = shouldShowSignUpFieldError(
            message: validation.nicknameMessage,
            value: vm.signupNickname
        )
        let shouldShowEmailError = shouldShowSignUpFieldError(
            message: validation.emailMessage,
            value: vm.signupEmail
        )
        let shouldShowPasswordError = shouldShowSignUpFieldError(
            message: validation.passwordMessage,
            value: vm.signupPassword
        )
        let shouldShowPasswordConfirmError = shouldShowSignUpFieldError(
            message: validation.passwordConfirmMessage,
            value: vm.signupPasswordConfirm
        )

        return VStack(spacing: 14) {
            formField(
                title: "닉네임",
                text: $vm.signupNickname,
                placeholder: "표시할 닉네임",
                keyboardType: .default,
                textContentType: .nickname,
                secure: false,
                isInvalid: shouldShowNicknameError
            )
            .focused($focusedField, equals: .signupNickname)

            validationRow(message: validation.nicknameMessage, shouldShow: shouldShowNicknameError)

            formField(
                title: "이메일",
                text: $vm.signupEmail,
                placeholder: "name@example.com",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                secure: false,
                isInvalid: shouldShowEmailError
            )
            .focused($focusedField, equals: .signupEmail)

            validationRow(message: validation.emailMessage, shouldShow: shouldShowEmailError)

            formField(
                title: "비밀번호",
                text: $vm.signupPassword,
                placeholder: "영문+숫자 8자 이상",
                keyboardType: .default,
                textContentType: .newPassword,
                secure: true,
                isInvalid: shouldShowPasswordError
            )
            .focused($focusedField, equals: .signupPassword)

            validationRow(message: validation.passwordMessage, shouldShow: shouldShowPasswordError)

            formField(
                title: "비밀번호 확인",
                text: $vm.signupPasswordConfirm,
                placeholder: "비밀번호 다시 입력",
                keyboardType: .default,
                textContentType: .newPassword,
                secure: true,
                isInvalid: shouldShowPasswordConfirmError
            )
            .focused($focusedField, equals: .signupPasswordConfirm)

            validationRow(
                message: validation.passwordConfirmMessage,
                shouldShow: shouldShowPasswordConfirmError
            )

            agreementCard

            if let error = vm.signupErrorMessage, !error.isEmpty {
                inlineMessage(error, tone: .error)
            }

            submitButton(
                title: vm.isSigningUp ? "가입 중..." : "회원가입하고 시작하기",
                isLoading: vm.isSigningUp,
                isEnabled: !vm.isSigningUp,
                action: {
                    didAttemptSignUpSubmit = true
                    focusedField = nil
                    Task {
                        await vm.submitSignUp()
                    }
                }
            )
        }
    }

    private var agreementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                vm.signupAcceptedTerms.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: vm.signupAcceptedTerms ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(vm.signupAcceptedTerms ? .accent : .textMuted)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("서비스 이용약관과 개인정보 처리방침에 동의합니다.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.themeText)

                        Text("필수 동의 항목이며, 동의 후 회원가입과 거래소 연결 기능을 사용할 수 있어요.")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(2)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                legalLinkButton(title: "이용약관 보기", sheet: .terms)
                legalLinkButton(title: "개인정보 처리방침", sheet: .privacy)
            }

            validationRow(
                message: validation.termsMessage,
                shouldShow: didAttemptSignUpSubmit && validation.termsMessage != nil
            )
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

    private func legalLinkButton(title: String, sheet: LegalSheet) -> some View {
        Button {
            activeLegalSheet = sheet
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
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

    private var footerPrompt: some View {
        HStack(spacing: 6) {
            Text(vm.authFlowMode == .login ? "아직 계정이 없나요?" : "이미 계정이 있나요?")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            Button(vm.authFlowMode == .login ? "회원가입" : "로그인") {
                selectAuthFlowMode(vm.authFlowMode == .login ? .signUp : .login)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.accent)
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func validationRow(message: String?, shouldShow: Bool) -> some View {
        if shouldShow, let message, !message.isEmpty {
            inlineMessage(message, tone: .error)
        }
    }

    private func inlineMessage(_ message: String, tone: MessageTone) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(tone == .error ? .danger : .textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submitButton(
        title: String,
        isLoading: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }

                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? Color.accent : Color.bgTertiary)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func formField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType,
        textContentType: UITextContentType,
        secure: Bool,
        isInvalid: Bool = false
    ) -> some View {
        let borderColor = isInvalid ? Color.danger : Color.themeBorder
        let labelColor = isInvalid ? Color.danger : Color.textMuted

        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(labelColor)

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                        .textContentType(textContentType)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.themeText)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isInvalid ? Color.danger.opacity(0.08) : Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(borderColor, lineWidth: isInvalid ? 1.4 : 1)
                    )
            )
        }
    }

    private func shouldShowSignUpFieldError(message: String?, value: String) -> Bool {
        guard let message, !message.isEmpty else { return false }
        return didAttemptSignUpSubmit || !value.isEmpty
    }

    private func selectAuthFlowMode(_ mode: AuthFlowMode) {
        focusedField = nil
        if vm.authFlowMode != mode {
            didAttemptSignUpSubmit = false
        }
        vm.switchAuthFlowMode(mode)
    }

    private func legalSheet(_ sheet: LegalSheet) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sheet.summaryLines, id: \.self) { line in
                        Text("• \(line)")
                            .font(.system(size: 13))
                            .foregroundColor(.themeText)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(sheet.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        activeLegalSheet = nil
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private enum MessageTone {
    case error
    case secondary
}
