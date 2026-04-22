import SwiftUI

struct PeriodSelector: View {
    @ObservedObject var vm: CryptoViewModel
    let onSettingsTap: () -> Void

    init(vm: CryptoViewModel, onSettingsTap: @escaping () -> Void = {}) {
        self.vm = vm
        self.onSettingsTap = onSettingsTap
    }

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(vm.availableChartIntervals) { option in
                        Button {
                            vm.setChartInterval(option.value)
                        } label: {
                            Text(option.title)
                                .font(.system(size: 10, weight: vm.chartPeriod == option.value ? .bold : .regular))
                                .foregroundColor(vm.chartPeriod == option.value ? .black : .textMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(vm.chartPeriod == option.value ? Color.accent : Color.bgSecondary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 36, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.bgSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.themeBorder, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("차트 설정")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
    }
}
