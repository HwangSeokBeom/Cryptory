import SwiftUI

struct MarketSegmentedControl: View {
    @Binding var selection: MarketFilter
    @State private var segmentFrames: [MarketFilter: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 28) {
                ForEach(MarketFilter.allCases, id: \.self) { filter in
                    segmentButton(for: filter)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 9)

            ZStack(alignment: .bottomLeading) {
                Color.clear.frame(height: 3)

                if let frame = segmentFrames[selection] {
                    Capsule()
                        .fill(Color.accent)
                        .frame(width: max(frame.width + 12, 42), height: 2.5)
                        .offset(x: frame.minX - 6)
                        .transition(.opacity)
                }
            }
        }
        .coordinateSpace(name: "MarketSegmentedControl")
        .onPreferenceChange(MarketSegmentFramePreferenceKey.self) { segmentFrames = $0 }
        .animation(.easeInOut(duration: 0.18), value: selection)
    }

    private func segmentButton(for filter: MarketFilter) -> some View {
        Button {
            guard selection != filter else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                selection = filter
            }
        } label: {
            Text(filter.title)
                .font(.system(size: 17, weight: selection == filter ? .semibold : .medium))
                .foregroundColor(selection == filter ? .accent : .textSecondary)
                .frame(height: 22, alignment: .center)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MarketSegmentFramePreferenceKey.self,
                            value: [filter: proxy.frame(in: .named("MarketSegmentedControl"))]
                        )
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MarketSegmentFramePreferenceKey: PreferenceKey {
    static var defaultValue: [MarketFilter: CGRect] = [:]

    static func reduce(value: inout [MarketFilter: CGRect], nextValue: () -> [MarketFilter: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
