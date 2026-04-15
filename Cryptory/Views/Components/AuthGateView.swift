import SwiftUI

struct AuthGateView: View {
    let feature: ProtectedFeature
    let primaryAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.accent)

            VStack(spacing: 8) {
                Text(feature.message)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.themeText)
                    .multilineTextAlignment(.center)

                Text(feature.detail)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button(action: primaryAction) {
                Text("로그인하기")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
