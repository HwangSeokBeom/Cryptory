import SwiftUI

struct LoginView: View {
    @ObservedObject var vm: CryptoViewModel
    @Environment(\.dismiss) private var dismiss

    private var isSigningIn: Bool {
        if case .signingIn = vm.authState {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 20) {
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

                VStack(spacing: 10) {
                    Text("로그인")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(.themeText)

                    Text("로그인 후 내 자산, 주문, 거래소 연결을 확인할 수 있어요.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    textField(
                        title: "이메일",
                        text: $vm.loginEmail,
                        keyboardType: .emailAddress,
                        secure: false
                    )

                    textField(
                        title: "비밀번호",
                        text: $vm.loginPassword,
                        keyboardType: .default,
                        secure: true
                    )
                }

                if let error = vm.loginErrorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.down)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        await vm.submitLogin()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }

                        Text(isSigningIn ? "로그인 중..." : "로그인")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func textField(title: String, text: Binding<String>, keyboardType: UIKeyboardType, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textMuted)

            Group {
                if secure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.themeText)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
        }
    }
}
