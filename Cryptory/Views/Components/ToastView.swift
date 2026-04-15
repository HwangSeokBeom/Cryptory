import SwiftUI

struct ToastView: View {
    let message: String
    let type: NotifType

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(type == .success
                          ? Color.success.opacity(0.95)
                          : Color.danger.opacity(0.95))
            )
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
