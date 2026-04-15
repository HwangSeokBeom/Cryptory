import SwiftUI

struct PeriodSelector: View {
    @ObservedObject var vm: CryptoViewModel
    let periods = ["1M", "5M", "15M", "1H", "4H", "1D", "1W"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(periods, id: \.self) { period in
                Button {
                    vm.chartPeriod = period
                    Task {
                        await vm.loadChartData()
                    }
                } label: {
                    Text(period)
                        .font(.system(size: 10, weight: vm.chartPeriod == period ? .bold : .regular))
                        .foregroundColor(vm.chartPeriod == period ? .black : .textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(vm.chartPeriod == period ? Color.accent : Color.bgSecondary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
