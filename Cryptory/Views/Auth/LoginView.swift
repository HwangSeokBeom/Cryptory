import SwiftUI
import AuthenticationServices
import UIKit

struct LoginView: View {
    @ObservedObject var vm: CryptoViewModel
    @FocusState private var focusedField: Field?
    @State private var safariDestination: SafariDestination?
    @State private var didAttemptSignUpSubmit = false

    private enum Field: Hashable {
        case loginEmail
        case loginPassword
        case signupNickname
        case signupEmail
        case signupPassword
        case signupPasswordConfirm
    }

    private let footerLinks: [AppExternalLink] = [
        .termsOfService,
        .privacyPolicy,
        .communityPolicy,
        .support,
        .deleteAccount,
        .investmentDisclaimer,
        .home
    ]

    private var validation: SignUpFormValidationResult {
        vm.signUpValidation
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    sheetGrabber
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
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnBackgroundTap()
        .sheet(item: $safariDestination) { destination in
            SafariSheet(destination: destination)
                .ignoresSafeArea()
        }
        .onChange(of: vm.authFlowMode) { _, _ in
            focusedField = nil
            didAttemptSignUpSubmit = false
        }
        .onChange(of: vm.signupNickname) { _, _ in clearSignUpServerErrorIfNeeded() }
        .onChange(of: vm.signupEmail) { _, _ in clearSignUpServerErrorIfNeeded() }
        .onChange(of: vm.signupPassword) { _, _ in clearSignUpServerErrorIfNeeded() }
        .onChange(of: vm.signupPasswordConfirm) { _, _ in clearSignUpServerErrorIfNeeded() }
        .task {
            await LegalLinksConfigurationCenter.shared.refreshIfNeeded()
        }
    }

    private var sheetGrabber: some View {
        Capsule()
            .fill(Color.themeBorder)
            .frame(width: 42, height: 5)
            .padding(.top, 2)
            .accessibilityHidden(true)
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
                 ? "로그인 후 내 자산과 읽기 전용 거래소 연결을 바로 이어서 사용할 수 있어요."
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

            socialAuthSection
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
                serverErrorMessage(error)
            }

            submitButton(
                title: vm.isSigningUp ? "가입 중..." : "회원가입하고 시작하기",
                isLoading: vm.isSigningUp,
                isEnabled: vm.canSubmitSignUp,
                action: {
                    didAttemptSignUpSubmit = true
                    Task {
                        await vm.submitSignUp()
                    }
                }
            )

            socialAuthSection
        }
    }

    private var socialAuthSection: some View {
        VStack(spacing: 12) {
            dividerLabel("또는")

            socialButton(
                title: vm.isSigningIn(with: .google) ? "Google 로그인 중..." : "Google로 계속하기",
                systemImage: "g.circle.fill",
                isLoading: vm.isSigningIn(with: .google),
                action: {
                    Task {
                        await vm.submitGoogleSignIn(presenting: UIApplication.shared.cryptoryTopViewController())
                    }
                }
            )

            appleSignInButton
        }
        .padding(.top, 2)
    }

    private func dividerLabel(_ title: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.themeBorder)
                .frame(height: 1)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textMuted)

            Rectangle()
                .fill(Color.themeBorder)
                .frame(height: 1)
        }
    }

    private func socialButton(
        title: String,
        systemImage: String,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.themeText)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(.themeText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(AuthPressableButtonStyle())
        .disabled(vm.isAuthenticationBusy)
    }

    private var appleSignInButton: some View {
        ZStack {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task {
                    await vm.submitAppleSignIn(result: result)
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(!vm.isAuthenticationBusy)
            .opacity(vm.isAuthenticationBusy && !vm.isSigningIn(with: .apple) ? 0.55 : 1)

            if vm.isSigningIn(with: .apple) {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)

                    Text("Apple 로그인 중...")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                )
            }
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
                legalLinkButton(title: "이용약관 보기", link: .termsOfService)
                legalLinkButton(title: "개인정보처리방침 보기", link: .privacyPolicy)
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

    private func legalLinkButton(title: String, link: AppExternalLink) -> some View {
        Button {
            openExternalLink(link)
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
        .buttonStyle(AuthPressableButtonStyle())
    }

    private var footerPrompt: some View {
        VStack(spacing: 10) {
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

            footerExternalLinks
        }
        .padding(.top, 4)
    }

    private var footerExternalLinks: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(footerLinks) { link in
                footerLinkButton(link)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgSecondary.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.themeBorder.opacity(0.9), lineWidth: 1)
                )
        )
    }

    private func footerLinkButton(_ link: AppExternalLink) -> some View {
        Button {
            openExternalLink(link)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: link.systemImageName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accent)
                    .frame(width: 15)

                Text(link.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.themeText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgTertiary.opacity(0.82))
            )
        }
        .buttonStyle(AuthPressableButtonStyle())
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

    private func serverErrorMessage(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.danger)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.danger)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.danger.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.danger.opacity(0.45), lineWidth: 1)
                )
        )
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

    private func clearSignUpServerErrorIfNeeded() {
        if vm.signupErrorMessage != nil {
            vm.clearSignUpServerError()
        }
    }

    private func openExternalLink(_ link: AppExternalLink) {
        AppLogger.debug(.auth, "DEBUG [LegalLink] open type=\(link.policyDebugName) urlExists=\(link.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)")
        guard let destination = SafariDestination(link: link) else {
            AppLogger.debug(.auth, "WARN [LegalLink] invalid type=\(link.policyDebugName) reason=invalidURL")
            vm.showNotification("링크를 열 수 없습니다.", type: .error)
            return
        }
        safariDestination = destination
    }
}

private enum MessageTone {
    case error
    case secondary
}

private struct AuthPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension UIApplication {
    func cryptoryTopViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    ) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return cryptoryTopViewController(base: navigationController.visibleViewController)
        }
        if let tabBarController = base as? UITabBarController {
            return cryptoryTopViewController(base: tabBarController.selectedViewController)
        }
        if let presentedViewController = base?.presentedViewController {
            return cryptoryTopViewController(base: presentedViewController)
        }
        return base
    }
}
