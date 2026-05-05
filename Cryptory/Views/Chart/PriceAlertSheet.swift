import SwiftUI

struct PriceAlertSheet: View {
    @Binding var draft: PriceAlertDraft
    let isSaving: Bool
    let message: String?
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                conditionPicker
                targetInput
                repeatPicker
                Toggle("활성화", isOn: $draft.isActive)
                    .tint(.accent)
                    .foregroundColor(.themeText)

                if let warning = validationWarning {
                    Text(warning)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accent)
                }
                if let message {
                    Text(message)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }

                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    if draft.alertId != nil {
                        Button(role: .destructive, action: onDelete) {
                            Text("삭제")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSaving)
                    }
                    Button(action: onSave) {
                        if isSaving {
                            ProgressView()
                                .tint(.bg)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("저장")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !isValidTarget)
                }
            }
            .padding(20)
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("가격 알림")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(draft.symbol) · \(draft.exchange.displayName) · \(draft.quoteCurrency.rawValue)")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)
            Text("현재가 \(PriceFormatter.formatMarketPrice(draft.currentPrice, quoteCurrency: draft.quoteCurrency))")
                .font(.mono(13, weight: .semibold))
                .foregroundColor(.textSecondary)
        }
    }

    private var conditionPicker: some View {
        Picker("조건", selection: $draft.condition) {
            ForEach(PriceAlertCondition.allCases) { condition in
                Text(condition.title).tag(condition)
            }
        }
        .pickerStyle(.segmented)
    }

    private var targetInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("목표 가격")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textSecondary)
            TextField("0", text: $draft.targetPriceText)
                .keyboardType(.decimalPad)
                .font(.mono(20, weight: .heavy))
                .foregroundColor(.themeText)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSecondary))
        }
    }

    private var repeatPicker: some View {
        Picker("반복 여부", selection: $draft.repeatPolicy) {
            ForEach(PriceAlertRepeatPolicy.allCases) { policy in
                Text(policy.title).tag(policy)
            }
        }
        .pickerStyle(.segmented)
    }

    private var isValidTarget: Bool {
        (draft.targetPrice ?? 0) > 0
    }

    private var validationWarning: String? {
        guard let target = draft.targetPrice, target > 0, draft.currentPrice > 0 else {
            return nil
        }
        let ratio = target / draft.currentPrice
        if ratio > 5 || ratio < 0.2 {
            return "현재가와 차이가 큽니다. 저장 전 목표 가격을 확인하세요."
        }
        return nil
    }
}
