import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var onFocusChanged: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isFocused ? .accent : .textSecondary)
                .frame(width: 18, height: 18)

            TextField(
                "",
                text: $text,
                prompt: Text("코인명/심볼 검색")
                    .foregroundColor(.textMuted)
            )
                .font(.system(size: 15))
                .foregroundColor(.themeText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgSecondary.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isFocused ? Color.accent.opacity(0.55) : Color.themeBorder, lineWidth: 1)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.02), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .onChange(of: isFocused) { _, newValue in
            onFocusChanged(newValue)
        }
    }
}
