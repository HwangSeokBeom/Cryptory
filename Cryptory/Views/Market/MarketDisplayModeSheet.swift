import SwiftUI

struct MarketDisplayModeSheet: View {
    let committedMode: MarketListDisplayMode
    let initialPreviewMode: MarketListDisplayMode
    let isGuide: Bool
    let onPreview: (MarketListDisplayMode) -> Void
    let onApply: (MarketListDisplayMode) -> Void
    let onClose: () -> Void

    @State private var previewMode: MarketListDisplayMode

    init(
        committedMode: MarketListDisplayMode,
        initialPreviewMode: MarketListDisplayMode,
        isGuide: Bool = false,
        onPreview: @escaping (MarketListDisplayMode) -> Void,
        onApply: @escaping (MarketListDisplayMode) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.committedMode = committedMode
        self.initialPreviewMode = initialPreviewMode
        self.isGuide = isGuide
        self.onPreview = onPreview
        self.onApply = onApply
        self.onClose = onClose
        _previewMode = State(initialValue: initialPreviewMode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    livePreview
                    modeCards
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(isGuide ? "목록 형식 선택" : "종목 뷰 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        onClose()
                    }
                    .foregroundColor(.themeText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomAction
            }
        }
        .presentationBackground(Color.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isGuide ? "원하는 목록 형식을 고를 수 있어요" : "한눈에 비교하고 원하는 밀도로 볼 수 있어요")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.themeText)

            Text(isGuide ? "카드를 눌러 미리 보고, 마음에 드는 형식만 적용하세요." : "선택하면 뒤의 시세 리스트가 먼저 바뀌고, 적용 전까지 저장값은 유지됩니다.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.themeBorder.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("미리보기")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.themeText)
                Spacer()
                Text(previewMode.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accent.opacity(0.12)))
            }

            previewRows(for: previewMode, maxRows: 3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.bgSecondary)
        )
    }

    private var modeCards: some View {
        VStack(spacing: 10) {
            ForEach(MarketListDisplayMode.allCases, id: \.self) { mode in
                Button {
                    selectPreview(mode)
                } label: {
                    previewCard(for: mode)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 10) {
            Button {
                onApply(previewMode)
            } label: {
                Text(isGuide ? "이 형식으로 볼게요" : "적용")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundColor(applyButtonEnabled ? .white : .textMuted)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(applyButtonEnabled ? Color.accent : Color.bgTertiary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(applyButtonEnabled == false)

            if isGuide {
                Button("나중에 설정할게요") {
                    onClose()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            Color.bg
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.themeBorder.opacity(0.35))
                        .frame(height: 1)
                }
        )
    }

    private var applyButtonEnabled: Bool {
        isGuide || previewMode != committedMode
    }

    private func selectPreview(_ mode: MarketListDisplayMode) {
        guard previewMode != mode else {
            return
        }
        previewMode = mode
        onPreview(mode)
    }

    private func previewCard(for mode: MarketListDisplayMode) -> some View {
        let isSelected = previewMode == mode
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.themeText)
                    Text(shortDescription(for: mode))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isSelected ? .accent : .textMuted.opacity(0.7))
            }

            previewRows(for: mode, maxRows: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? Color.accent.opacity(0.6) : Color.themeBorder.opacity(0.45), lineWidth: 1)
                )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? Color.bgTertiary.opacity(0.86) : Color.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSelected ? Color.accent.opacity(0.9) : Color.themeBorder, lineWidth: isSelected ? 1.5 : 1)
                )
        )
    }

    private func previewRows(for mode: MarketListDisplayMode, maxRows: Int) -> some View {
        let configuration = mode.configuration
        return VStack(spacing: 0) {
            ForEach(Array(MarketDisplayPreviewFactory.rows.prefix(maxRows).enumerated()), id: \.element.id) { index, model in
                MarketRowContent(
                    model: model,
                    configuration: configuration,
                    showsFavoriteControl: false,
                    onToggleFavorite: nil
                )
                .allowsHitTesting(false)

                if index < min(maxRows, MarketDisplayPreviewFactory.rows.count) - 1 {
                    Divider()
                        .background(Color.themeBorder.opacity(0.28))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bg.opacity(0.42))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func shortDescription(for mode: MarketListDisplayMode) -> String {
        switch mode {
        case .chart:
            return "가격, 거래대금, 추이까지 가장 균형 있게 봅니다."
        case .info:
            return "이미지와 텍스트 중심으로 촘촘하게 확인합니다."
        case .emphasis:
            return "등락률을 크게 보고 빠른 변동을 우선 확인합니다."
        }
    }
}

private enum MarketDisplayPreviewFactory {
    static let rows: [MarketRowRenderModel] = [
        row(
            symbol: "BTC",
            name: "비트코인",
            imageURL: "https://assets.coingecko.com/coins/images/1/large/bitcoin.png",
            priceText: "149,820,000",
            changeText: "+2.48%",
            volumeText: "2.3조",
            points: [0.32, 0.36, 0.38, 0.41, 0.44, 0.49, 0.53, 0.58],
            isUp: true
        ),
        row(
            symbol: "ETH",
            name: "이더리움",
            imageURL: "https://assets.coingecko.com/coins/images/279/large/ethereum.png",
            priceText: "5,280,000",
            changeText: "+1.12%",
            volumeText: "8,420억",
            points: [0.55, 0.57, 0.6, 0.59, 0.61, 0.64, 0.66, 0.68],
            isUp: true
        ),
        row(
            symbol: "XRP",
            name: "리플",
            imageURL: "https://assets.coingecko.com/coins/images/44/large/xrp-symbol-white-128.png",
            priceText: "2,940",
            changeText: "-0.82%",
            volumeText: "3,180억",
            points: [0.74, 0.72, 0.69, 0.67, 0.64, 0.63, 0.6, 0.58],
            isUp: false
        ),
        row(
            symbol: "ADA",
            name: "에이다",
            imageURL: "https://assets.coingecko.com/coins/images/975/large/cardano.png",
            priceText: "1,328",
            changeText: "+4.32%",
            volumeText: "1,240억",
            points: [0.22, 0.25, 0.29, 0.33, 0.38, 0.42, 0.47, 0.51],
            isUp: true
        )
    ]

    private static func row(
        symbol: String,
        name: String,
        imageURL: String,
        priceText: String,
        changeText: String,
        volumeText: String,
        points: [Double],
        isUp: Bool
    ) -> MarketRowRenderModel {
        let payload = MarketSparklineRenderPayload(
            bindingKey: "preview:\(symbol)",
            graphRenderIdentity: "preview:\(symbol)",
            renderToken: "preview:\(symbol):\(points.count):\(isUp ? "up" : "down")",
            graphState: .liveVisible,
            points: points,
            pointCount: points.count,
            hasEnoughData: MarketSparklineRenderPolicy.hasHydratedGraph(
                points: points,
                pointCount: points.count
            )
        )
        return MarketRowRenderModel(
            id: "preview:\(symbol)",
            exchange: .upbit,
            sourceExchange: .upbit,
            symbol: symbol,
            displayName: name,
            imageURL: imageURL,
            priceText: priceText,
            changeText: changeText,
            volumeText: volumeText,
            sparklinePayload: payload,
            isUp: isUp,
            sparklinePoints: points.count
        )
    }
}
