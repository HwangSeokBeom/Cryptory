import SwiftUI

struct SparklineView: View {
    let data: [Double]
    let isUp: Bool
    let width: CGFloat
    let height: CGFloat

    init(data: [Double], isUp: Bool, width: CGFloat = 55, height: CGFloat = 20) {
        self.data = data
        self.isUp = isUp
        self.width = width
        self.height = height
    }

    var body: some View {
        if data.count >= 2 {
            Canvas { context, size in
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = maxVal - minVal
                guard range > 0 else { return }

                let stepX = size.width / CGFloat(data.count - 1)
                var path = Path()

                for (i, val) in data.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = size.height - ((val - minVal) / range) * size.height
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                context.stroke(
                    path,
                    with: .color(isUp ? .up : .down),
                    lineWidth: 1.5
                )
            }
            .frame(width: width, height: height)
        } else {
            Rectangle()
                .fill(Color.clear)
                .frame(width: width, height: height)
        }
    }
}
