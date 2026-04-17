import SwiftUI

struct PeriodSelector: View {
    @ObservedObject var vm: CryptoViewModel

    var body: some View {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
