import SwiftUI

struct ScreenStatusBannerView: View {
    let viewState: ScreenStatusViewState

    var body: some View {
        if viewState.badges.isEmpty && viewState.message == nil && viewState.lastUpdatedText == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !viewState.badges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewState.badges) { badge in
                                Text(badge.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(foregroundColor(for: badge.tone))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(backgroundColor(for: badge.tone))
                                    )
                            }
                        }
                    }
                }

                if let message = viewState.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }

                if let lastUpdatedText = viewState.lastUpdatedText, !lastUpdatedText.isEmpty {
                    Text(lastUpdatedText)
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted)
                }
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
    }

    private func backgroundColor(for tone: StatusBadgeTone) -> Color {
        switch tone {
        case .neutral:
            return Color.bgTertiary
        case .success:
            return Color.up.opacity(0.12)
        case .warning:
            return Color.accent.opacity(0.14)
        case .error:
            return Color.down.opacity(0.14)
        }
    }

    private func foregroundColor(for tone: StatusBadgeTone) -> Color {
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
}
