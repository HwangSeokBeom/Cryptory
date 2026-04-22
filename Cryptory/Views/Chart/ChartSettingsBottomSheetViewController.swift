import SwiftUI
import UIKit

struct ChartSettingsSheetPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let state: ChartSettingsState
    let currentSymbol: String?
    let comparisonCandidates: [ChartComparisonCandidate]
    let onStateChange: (ChartSettingsState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> ChartSettingsPresenterHostViewController {
        ChartSettingsPresenterHostViewController()
    }

    func updateUIViewController(_ host: ChartSettingsPresenterHostViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.host = host

        if isPresented {
            host.presentSettings(
                state: state,
                currentSymbol: currentSymbol,
                comparisonCandidates: comparisonCandidates,
                onStateChange: onStateChange,
                delegate: context.coordinator,
                onDismiss: { [weak coordinator = context.coordinator] in
                    coordinator?.handleDismissedPresentation()
                }
            )
        } else {
            host.dismissSettingsIfNeeded()
        }
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var parent: ChartSettingsSheetPresenter
        weak var host: ChartSettingsPresenterHostViewController?

        init(parent: ChartSettingsSheetPresenter) {
            self.parent = parent
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            handleDismissedPresentation()
        }

        func handleDismissedPresentation() {
            parent.isPresented = false
            host?.cleanupPresentedState()
        }
    }
}

final class ChartSettingsPresenterHostViewController: UIViewController {
    var presentedNavigationController: UINavigationController?
    var isPresentationPending = false

    func presentSettings(
        state: ChartSettingsState,
        currentSymbol: String?,
        comparisonCandidates: [ChartComparisonCandidate],
        onStateChange: @escaping (ChartSettingsState) -> Void,
        delegate: UIAdaptivePresentationControllerDelegate,
        onDismiss: @escaping () -> Void
    ) {
        if let presentedNavigationController,
           let sheet = presentedNavigationController.viewControllers.first as? ChartSettingsBottomSheetViewController {
            sheet.applyExternalState(
                state,
                currentSymbol: currentSymbol,
                comparisonCandidates: comparisonCandidates,
                onStateChange: onStateChange
            )
            return
        }

        guard !isPresentationPending else {
            return
        }

        isPresentationPending = true
        let sheetViewController = ChartSettingsBottomSheetViewController(
            state: state,
            currentSymbol: currentSymbol,
            comparisonCandidates: comparisonCandidates,
            onDismiss: onDismiss,
            onStateChange: onStateChange
        )
        let navigationController = UINavigationController(rootViewController: sheetViewController)
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.modalPresentationStyle = .pageSheet
        navigationController.presentationController?.delegate = delegate

        if let sheetPresentationController = navigationController.sheetPresentationController {
            sheetPresentationController.detents = [.large()]
            sheetPresentationController.prefersGrabberVisible = false
            sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = false
            sheetPresentationController.preferredCornerRadius = 28
        }

        let presentBlock = { [weak self, weak navigationController] in
            guard let self,
                  let navigationController,
                  self.presentedNavigationController == nil,
                  self.presentedViewController == nil else {
                self?.cleanupPresentedState()
                return
            }
            self.presentedNavigationController = navigationController
            self.present(navigationController, animated: true) {
                self.isPresentationPending = false
            }
        }

        if view.window == nil {
            DispatchQueue.main.async(execute: presentBlock)
        } else {
            presentBlock()
        }
    }

    func dismissSettingsIfNeeded() {
        guard let navigationController = presentedNavigationController else {
            return
        }

        navigationController.dismiss(animated: true) { [weak self] in
            self?.cleanupPresentedState()
        }
    }

    func cleanupPresentedState() {
        presentedNavigationController = nil
        isPresentationPending = false
    }
}

final class ChartSettingsBottomSheetViewController: UIViewController {
    private var state: ChartSettingsState
    private var currentSymbol: String?
    private var comparisonCandidates: [ChartComparisonCandidate]
    private let onDismiss: () -> Void
    private var onStateChange: (ChartSettingsState) -> Void
    private var activeTab: ChartSettingsTab = .indicators

    private let rootStack = UIStackView()
    private let tabsStack = UIStackView()
    private let contentContainer = UIView()
    private let indicatorScrollView = UIScrollView()
    private let styleScrollView = UIScrollView()
    private let viewOptionsScrollView = UIScrollView()
    private let bottomCTAContainer = UIView()
    private let detailButton = UIButton(type: .system)
    private let toastLabel = UILabel()

    private var bottomCTAHeightConstraint: NSLayoutConstraint?
    private var tabButtons: [ChartSettingsTab: ChartSettingsTabButton] = [:]
    private var indicatorCards: [ChartIndicatorID: ChartSettingsSelectableCardView] = [:]
    private var styleCards: [ChartStyleID: ChartSettingsSelectableCardView] = [:]
    private var topSectionLabel: UILabel?
    private var bottomSectionLabel: UILabel?
    private var bestBidAskRow: ChartSettingsToggleRow?
    private var globalColorRow: ChartSettingsToggleRow?
    private var utcRow: ChartSettingsToggleRow?
    private var comparisonRow: ChartSettingsNavigationRow?

    init(
        state: ChartSettingsState,
        currentSymbol: String?,
        comparisonCandidates: [ChartComparisonCandidate],
        onDismiss: @escaping () -> Void,
        onStateChange: @escaping (ChartSettingsState) -> Void
    ) {
        self.state = state.normalized
        self.currentSymbol = currentSymbol
        self.comparisonCandidates = comparisonCandidates
        self.onDismiss = onDismiss
        self.onStateChange = onStateChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .chartSheetBackground
        setupRoot()
        buildHeader()
        buildContent()
        buildBottomCTA()
        buildToast()
        setActiveTab(.indicators, animated: false)
        refreshAllState()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            onDismiss()
        }
    }

    func applyExternalState(
        _ newState: ChartSettingsState,
        currentSymbol: String?,
        comparisonCandidates: [ChartComparisonCandidate],
        onStateChange: @escaping (ChartSettingsState) -> Void
    ) {
        self.onStateChange = onStateChange
        self.currentSymbol = currentSymbol
        self.comparisonCandidates = comparisonCandidates
        let normalizedState = newState.normalized
        guard state != normalizedState else { return }
        state = normalizedState
        if isViewLoaded {
            refreshAllState()
        }
    }

    private func setupRoot() {
        rootStack.axis = .vertical
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func buildHeader() {
        let grabberContainer = UIView()
        grabberContainer.translatesAutoresizingMaskIntoConstraints = false
        attachHeaderDismissPan(to: grabberContainer)

        let grabber = UIView()
        grabber.backgroundColor = .chartGrabber
        grabber.layer.cornerRadius = 3
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabberContainer.addSubview(grabber)

        NSLayoutConstraint.activate([
            grabberContainer.heightAnchor.constraint(equalToConstant: 30),
            grabber.centerXAnchor.constraint(equalTo: grabberContainer.centerXAnchor),
            grabber.topAnchor.constraint(equalTo: grabberContainer.topAnchor, constant: 14),
            grabber.widthAnchor.constraint(equalToConstant: 58),
            grabber.heightAnchor.constraint(equalToConstant: 6)
        ])

        let titleLabel = UILabel()
        titleLabel.text = "차트 설정"
        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 30, weight: .heavy)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleContainer = UIView()
        attachHeaderDismissPan(to: titleContainer)
        titleContainer.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleContainer.trailingAnchor, constant: -24),
            titleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor, constant: -30)
        ])

        tabsStack.axis = .horizontal
        tabsStack.alignment = .fill
        tabsStack.distribution = .fillEqually
        tabsStack.spacing = 0
        tabsStack.translatesAutoresizingMaskIntoConstraints = false

        for tab in ChartSettingsTab.allCases {
            let button = ChartSettingsTabButton(tab: tab)
            button.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
            tabButtons[tab] = button
            tabsStack.addArrangedSubview(button)
        }

        let tabsContainer = UIView()
        tabsContainer.addSubview(tabsStack)
        NSLayoutConstraint.activate([
            tabsStack.topAnchor.constraint(equalTo: tabsContainer.topAnchor),
            tabsStack.leadingAnchor.constraint(equalTo: tabsContainer.leadingAnchor, constant: 18),
            tabsStack.trailingAnchor.constraint(equalTo: tabsContainer.trailingAnchor, constant: -18),
            tabsStack.bottomAnchor.constraint(equalTo: tabsContainer.bottomAnchor),
            tabsContainer.heightAnchor.constraint(equalToConstant: 58)
        ])

        rootStack.addArrangedSubview(grabberContainer)
        rootStack.addArrangedSubview(titleContainer)
        rootStack.addArrangedSubview(tabsContainer)
    }

    private func attachHeaderDismissPan(to targetView: UIView) {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(headerDismissPanChanged(_:)))
        recognizer.cancelsTouchesInView = false
        targetView.addGestureRecognizer(recognizer)
    }

    @objc private func headerDismissPanChanged(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        let translation = recognizer.translation(in: view)
        let velocity = recognizer.velocity(in: view)
        guard translation.y > 28,
              translation.y > abs(translation.x),
              velocity.y >= 0 else {
            return
        }

        dismiss(animated: true)
    }

    private func buildContent() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(contentContainer)

        buildIndicatorContent()
        buildStyleContent()
        buildViewOptionsContent()
    }

    private func buildIndicatorContent() {
        configureScrollView(indicatorScrollView)
        let stack = contentStack(bottomInset: 26)
        install(stack: stack, in: indicatorScrollView)

        let topLabel = makeSectionLabel(for: .top)
        let bottomLabel = makeSectionLabel(for: .bottom)
        topSectionLabel = topLabel
        bottomSectionLabel = bottomLabel

        stack.addArrangedSubview(topLabel)
        stack.addArrangedSubview(makeIndicatorGrid(items: ChartSettingsState.topIndicatorItems))
        stack.setCustomSpacing(26, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(bottomLabel)
        stack.addArrangedSubview(makeIndicatorGrid(items: ChartSettingsState.bottomIndicatorItems))
    }

    private func buildStyleContent() {
        configureScrollView(styleScrollView)
        let stack = contentStack(bottomInset: 34)
        install(stack: stack, in: styleScrollView)
        stack.addArrangedSubview(makeStyleGrid(items: ChartSettingsState.chartStyleItems))
    }

    private func buildViewOptionsContent() {
        configureScrollView(viewOptionsScrollView)
        let stack = contentStack(bottomInset: 36)
        install(stack: stack, in: viewOptionsScrollView)
        stack.spacing = 4

        let bestBidAskRow = ChartSettingsToggleRow(
            title: "최유리지정가호가 표시",
            subtitle: nil
        )
        bestBidAskRow.onToggle = { [weak self] isOn in
            self?.mutateState(source: "best_bid_ask_toggle") {
                $0.showBestBidAskLine = isOn
            }
        }

        let globalColorRow = ChartSettingsToggleRow(
            title: "해외거래소 차트 색상 적용",
            subtitle: "매수/상승은 초록색, 매도/하락은 빨간색으로 표시합니다."
        )
        globalColorRow.onToggle = { [weak self] isOn in
            self?.mutateState(source: "global_color_toggle") {
                $0.useGlobalExchangeColorScheme = isOn
            }
        }

        let utcRow = ChartSettingsToggleRow(
            title: "협정 세계시(UTC) 적용",
            subtitle: "차트 시간대를 한국 표준시(KST)에서 협정 세계시(UTC)로 변경합니다."
        )
        utcRow.onToggle = { [weak self] isOn in
            self?.mutateState(source: "utc_toggle") {
                $0.useUTC = isOn
            }
        }

        let comparisonRow = ChartSettingsNavigationRow(
            title: "종목 비교",
            subtitle: "최대 5개 종목까지 동시에 비교해볼 수 있습니다."
        )
        comparisonRow.addTarget(self, action: #selector(compareSymbolsTapped), for: .touchUpInside)

        self.bestBidAskRow = bestBidAskRow
        self.globalColorRow = globalColorRow
        self.utcRow = utcRow
        self.comparisonRow = comparisonRow

        stack.addArrangedSubview(bestBidAskRow)
        stack.addArrangedSubview(globalColorRow)
        stack.addArrangedSubview(utcRow)
        stack.addArrangedSubview(makeDivider())
        stack.addArrangedSubview(comparisonRow)
    }

    private func buildBottomCTA() {
        bottomCTAContainer.translatesAutoresizingMaskIntoConstraints = false
        detailButton.translatesAutoresizingMaskIntoConstraints = false
        detailButton.setTitle("지표 상세 설정", for: .normal)
        detailButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .heavy)
        detailButton.setTitleColor(.chartButtonText, for: .normal)
        detailButton.setTitleColor(.chartDisabledText, for: .disabled)
        detailButton.backgroundColor = .chartCTA
        detailButton.layer.cornerRadius = 14
        detailButton.addTarget(self, action: #selector(detailSettingsTapped), for: .touchUpInside)
        detailButton.accessibilityLabel = "지표 상세 설정"

        bottomCTAContainer.addSubview(detailButton)
        rootStack.addArrangedSubview(bottomCTAContainer)

        bottomCTAHeightConstraint = bottomCTAContainer.heightAnchor.constraint(equalToConstant: 96)
        bottomCTAHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            detailButton.topAnchor.constraint(equalTo: bottomCTAContainer.topAnchor, constant: 14),
            detailButton.leadingAnchor.constraint(equalTo: bottomCTAContainer.leadingAnchor, constant: 24),
            detailButton.trailingAnchor.constraint(equalTo: bottomCTAContainer.trailingAnchor, constant: -24),
            detailButton.heightAnchor.constraint(equalToConstant: 58)
        ])
    }

    private func buildToast() {
        toastLabel.alpha = 0
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 2
        toastLabel.textColor = .white
        toastLabel.font = .systemFont(ofSize: 13, weight: .bold)
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        toastLabel.layer.cornerRadius = 12
        toastLabel.layer.masksToBounds = true
        toastLabel.isAccessibilityElement = true
        toastLabel.accessibilityIdentifier = "chart_settings_limit_toast"
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastLabel)

        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            toastLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
            toastLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -104),
            toastLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 42)
        ])
    }

    private func configureScrollView(_ scrollView: UIScrollView) {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = true
        scrollView.indicatorStyle = .white
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        contentContainer.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    private func install(stack: UIStackView, in scrollView: UIScrollView) {
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func contentStack(bottomInset: CGFloat) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 24, bottom: bottomInset, trailing: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeSectionLabel(for placement: ChartIndicatorPlacement) -> UILabel {
        let label = UILabel()
        label.textColor = .chartTextPrimary
        label.font = .systemFont(ofSize: 17, weight: .heavy)
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityTraits = .header
        label.text = sectionTitle(for: placement)
        return label
    }

    private func makeIndicatorGrid(items: [ChartIndicatorItem]) -> UIStackView {
        makeGrid(items: items) { [weak self] item in
            let card = ChartSettingsSelectableCardView(accessory: .checkbox)
            card.configure(title: item.title, isSelected: state.isIndicatorSelected(item.id), isEnabled: true)
            card.accessibilityLabel = item.title
            card.accessibilityHint = "선택 또는 해제"
            card.onTap = { [weak self] in
                self?.toggleIndicator(item.id)
            }
            self?.indicatorCards[item.id] = card
            return card
        }
    }

    private func makeStyleGrid(items: [ChartStyleItem]) -> UIStackView {
        makeGrid(items: items) { [weak self] item in
            let card = ChartSettingsSelectableCardView(accessory: .icon(systemName: item.iconSystemName))
            card.configure(
                title: item.title,
                isSelected: state.selectedChartStyle == item.id,
                isEnabled: item.isSupported
            )
            card.accessibilityLabel = item.title
            card.accessibilityHint = item.isSupported ? "차트 형식 선택" : "현재 차트 엔진에서 지원하지 않는 형식"
            card.onTap = { [weak self] in
                guard item.isSupported else { return }
                self?.selectChartStyle(item.id)
            }
            self?.styleCards[item.id] = card
            return card
        }
    }

    private func makeGrid<Item>(
        items: [Item],
        makeCard: (Item) -> ChartSettingsSelectableCardView
    ) -> UIStackView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 10

        var index = 0
        while index < items.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually

            let left = makeCard(items[index])
            left.heightAnchor.constraint(equalToConstant: 62).isActive = true
            row.addArrangedSubview(left)

            if index + 1 < items.count {
                let right = makeCard(items[index + 1])
                right.heightAnchor.constraint(equalToConstant: 62).isActive = true
                row.addArrangedSubview(right)
            } else {
                let spacer = UIView()
                row.addArrangedSubview(spacer)
            }

            grid.addArrangedSubview(row)
            index += 2
        }

        return grid
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = .chartBorder
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    @objc private func tabButtonTapped(_ sender: ChartSettingsTabButton) {
        setActiveTab(sender.tab, animated: true)
    }

    private func setActiveTab(_ tab: ChartSettingsTab, animated: Bool) {
        activeTab = tab
        for (buttonTab, button) in tabButtons {
            button.setActive(buttonTab == tab)
        }

        let updates = {
            self.indicatorScrollView.isHidden = tab != .indicators
            self.styleScrollView.isHidden = tab != .chartStyle
            self.viewOptionsScrollView.isHidden = tab != .viewOptions
            self.bottomCTAHeightConstraint?.constant = tab == .indicators ? 96 : 0
            self.bottomCTAContainer.isHidden = tab != .indicators
            self.detailButton.isHidden = tab != .indicators
            self.view.layoutIfNeeded()
        }

        if animated {
            UIView.transition(
                with: contentContainer,
                duration: 0.16,
                options: [.transitionCrossDissolve, .allowUserInteraction],
                animations: updates
            )
        } else {
            updates()
        }

        currentScrollView(for: tab).setContentOffset(.zero, animated: false)
    }

    private func currentScrollView(for tab: ChartSettingsTab) -> UIScrollView {
        switch tab {
        case .indicators:
            return indicatorScrollView
        case .chartStyle:
            return styleScrollView
        case .viewOptions:
            return viewOptionsScrollView
        }
    }

    private func toggleIndicator(_ id: ChartIndicatorID) {
        var nextState = state
        let result = nextState.toggleIndicator(id)
        switch result {
        case .applied:
            applyState(nextState, source: "indicator_toggle_\(id.rawValue)")
        case .maximumSelectionReached:
            if let message = result.userMessage {
                showToast(message)
            }
        }
    }

    private func selectChartStyle(_ style: ChartStyleID) {
        guard state.selectedChartStyle != style else {
            return
        }
        mutateState(source: "chart_style_select") {
            $0.selectChartStyle(style)
        }
        refreshStyleState()
    }

    private func mutateState(
        source: String,
        mutation: (inout ChartSettingsState) -> Void
    ) {
        var nextState = state
        mutation(&nextState)
        applyState(nextState, source: source)
    }

    private func applyState(_ nextState: ChartSettingsState, source: String) {
        let normalizedState = nextState.normalized
        guard normalizedState != state else {
            return
        }
        state = normalizedState
        onStateChange(normalizedState)
        refreshAllState()
        AppLogger.debug(.route, "[ChartSettingsSheet] local_state_changed source=\(source)")
    }

    private func refreshAllState() {
        refreshIndicatorState()
        refreshStyleState()
        refreshViewOptionsState()
    }

    private func refreshIndicatorState() {
        topSectionLabel?.text = sectionTitle(for: .top)
        bottomSectionLabel?.text = sectionTitle(for: .bottom)
        for item in ChartIndicatorID.allCases {
            indicatorCards[item]?.setSelected(state.isIndicatorSelected(item), animated: true)
        }
        let hasConfigurableSelection = state.selectedConfigurableIndicators.contains {
            state.indicatorConfiguration(for: $0) != nil
        }
        detailButton.isEnabled = hasConfigurableSelection
        detailButton.backgroundColor = hasConfigurableSelection ? .chartCTA : .chartDisabledCTA
        detailButton.accessibilityHint = hasConfigurableSelection
            ? "선택한 지표의 상세 설정으로 이동"
            : "설정 가능한 활성 지표를 먼저 선택해주세요"
    }

    private func refreshStyleState() {
        for item in ChartStyleID.allCases {
            styleCards[item]?.setSelected(state.selectedChartStyle == item, animated: true)
        }
    }

    private func refreshViewOptionsState() {
        bestBidAskRow?.setOn(state.showBestBidAskLine, animated: true)
        globalColorRow?.setOn(state.useGlobalExchangeColorScheme, animated: true)
        utcRow?.setOn(state.useUTC, animated: true)
        comparisonRow?.setSubtitle(comparisonSubtitle)
    }

    private func sectionTitle(for placement: ChartIndicatorPlacement) -> String {
        switch placement {
        case .top:
            return "상단지표 (\(state.selectedIndicatorCount(for: .top))/\(ChartSettingsState.maximumTopIndicatorCount))"
        case .bottom:
            return "하단지표 (\(state.selectedIndicatorCount(for: .bottom))/\(ChartSettingsState.maximumBottomIndicatorCount))"
        }
    }

    private func showToast(_ message: String) {
        toastLabel.text = "  \(message)  "
        toastLabel.accessibilityLabel = message
        UIAccessibility.post(notification: .announcement, argument: message)
        UIView.animate(withDuration: 0.16) {
            self.toastLabel.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            UIView.animate(withDuration: 0.2) {
                self?.toastLabel.alpha = 0
            }
        }
    }

    @objc private func detailSettingsTapped() {
        let hasDetailIndicator = state.selectedConfigurableIndicators.contains {
            state.indicatorConfiguration(for: $0) != nil
        }
        guard hasDetailIndicator else {
            showToast("상세 설정할 지표를 먼저 선택해주세요")
            return
        }

        let detailViewController = ChartIndicatorSettingsListViewController(
            stateProvider: { [weak self] in
                self?.state ?? .default
            },
            onStateChange: { [weak self] nextState, source in
                self?.applyState(nextState, source: source)
            }
        )
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    @objc private func compareSymbolsTapped() {
        let comparisonViewController = ChartCompareSymbolsViewController(
            currentSymbol: currentSymbol,
            candidates: comparisonCandidates,
            stateProvider: { [weak self] in
                self?.state ?? .default
            },
            onStateChange: { [weak self] nextState, source in
                self?.applyState(nextState, source: source)
            },
            onMessage: { [weak self] message in
                self?.showToast(message)
            }
        )
        navigationController?.pushViewController(comparisonViewController, animated: true)
    }

    private var comparisonSubtitle: String {
        if state.comparedSymbols.isEmpty {
            return "현재 거래소 종목을 검색해서 최대 5개까지 비교할 수 있습니다."
        }
        let joinedSymbols = state.comparedSymbols.prefix(3).joined(separator: ", ")
        let suffix = state.comparedSymbols.count > 3 ? " 외 \(state.comparedSymbols.count - 3)개" : ""
        return "\(joinedSymbols)\(suffix) 선택됨"
    }
}

private final class ChartSettingsTabButton: UIControl {
    let tab: ChartSettingsTab

    private let titleLabel = UILabel()
    private let underlineView = UIView()

    init(tab: ChartSettingsTab) {
        self.tab = tab
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        titleLabel.text = tab.title
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 18, weight: .heavy)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        underlineView.backgroundColor = .chartAccent
        underlineView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(underlineView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            titleLabel.heightAnchor.constraint(equalToConstant: 38),
            underlineView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            underlineView.centerXAnchor.constraint(equalTo: centerXAnchor),
            underlineView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.72),
            underlineView.heightAnchor.constraint(equalToConstant: 2),
            underlineView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        accessibilityTraits = .button
        accessibilityLabel = tab.title
        setActive(false)
    }

    func setActive(_ isActive: Bool) {
        titleLabel.textColor = isActive ? .chartAccent : .chartTextMuted
        underlineView.alpha = isActive ? 1 : 0
        accessibilityTraits = isActive ? [.button, .selected] : .button
    }
}

private final class ChartSettingsSelectableCardView: UIControl {
    enum Accessory {
        case checkbox
        case icon(systemName: String)
    }

    var onTap: (() -> Void)?

    private let accessory: Accessory
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let accessoryContainer = UIView()
    private let accessoryImageView = UIImageView()
    private(set) var isCardSelected = false

    init(accessory: Accessory) {
        self.accessory = accessory
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            updateAppearance(animated: true)
        }
    }

    private func setup() {
        layer.cornerRadius = 8
        layer.borderWidth = 1
        clipsToBounds = true

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 10
        contentStack.isUserInteractionEnabled = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        accessoryContainer.translatesAutoresizingMaskIntoConstraints = false
        accessoryContainer.layer.cornerRadius = 6
        accessoryContainer.layer.borderWidth = 1.4
        accessoryContainer.isUserInteractionEnabled = false

        accessoryImageView.contentMode = .scaleAspectFit
        accessoryImageView.tintColor = .chartTextPrimary
        accessoryImageView.isUserInteractionEnabled = false
        accessoryImageView.translatesAutoresizingMaskIntoConstraints = false
        accessoryContainer.addSubview(accessoryImageView)

        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isUserInteractionEnabled = false

        addSubview(contentStack)
        contentStack.addArrangedSubview(accessoryContainer)
        contentStack.addArrangedSubview(titleLabel)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            accessoryContainer.widthAnchor.constraint(equalToConstant: 24),
            accessoryContainer.heightAnchor.constraint(equalToConstant: 24),
            accessoryImageView.centerXAnchor.constraint(equalTo: accessoryContainer.centerXAnchor),
            accessoryImageView.centerYAnchor.constraint(equalTo: accessoryContainer.centerYAnchor),
            accessoryImageView.widthAnchor.constraint(equalToConstant: 17),
            accessoryImageView.heightAnchor.constraint(equalToConstant: 17)
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    func configure(title: String, isSelected: Bool, isEnabled: Bool) {
        titleLabel.text = title
        self.isEnabled = isEnabled
        setSelected(isSelected, animated: false)
    }

    func setSelected(_ isSelected: Bool, animated: Bool) {
        isCardSelected = isSelected
        updateAppearance(animated: animated)
    }

    @objc private func tapped() {
        guard isEnabled else { return }
        onTap?()
    }

    override func accessibilityActivate() -> Bool {
        tapped()
        return true
    }

    private func updateAppearance(animated: Bool) {
        let updates = {
            let isDisabled = self.isEnabled == false
            let isPressed = self.isHighlighted && isDisabled == false

            self.alpha = isDisabled ? 0.44 : 1
            self.transform = isPressed ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
            self.backgroundColor = self.isCardSelected ? .chartSelectedCard : .chartCard
            self.layer.borderColor = (self.isCardSelected ? UIColor.chartAccent : UIColor.chartBorder).cgColor
            self.layer.borderWidth = self.isCardSelected ? 1.3 : 1
            self.titleLabel.textColor = isDisabled ? .chartTextMuted : .chartTextPrimary
            self.accessibilityTraits = self.isCardSelected ? [.button, .selected] : .button
            self.accessibilityValue = self.isCardSelected ? "선택됨" : "선택 안 됨"

            switch self.accessory {
            case .checkbox:
                self.accessoryContainer.backgroundColor = self.isCardSelected ? .chartAccent : .clear
                self.accessoryContainer.layer.borderColor = (self.isCardSelected ? UIColor.chartAccent : UIColor.chartCheckboxBorder).cgColor
                self.accessoryImageView.image = self.isCardSelected
                    ? UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
                    : nil
                self.accessoryImageView.tintColor = .chartButtonText
            case .icon(let systemName):
                self.accessoryContainer.backgroundColor = self.isCardSelected ? .chartSelectedAccentBackground : .clear
                self.accessoryContainer.layer.borderColor = (self.isCardSelected ? UIColor.chartAccent : UIColor.clear).cgColor
                self.accessoryImageView.image = UIImage(
                    systemName: systemName,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
                )
                self.accessoryImageView.tintColor = self.isCardSelected ? .chartAccent : .chartTextPrimary
            }
        }

        if animated {
            UIView.animate(withDuration: 0.14, animations: updates)
        } else {
            updates()
        }
    }
}

private final class ChartSettingsToggleRow: UIControl {
    var onToggle: ((Bool) -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let switchView = UISwitch()
    private let touchButton = UIButton(type: .custom)

    init(title: String, subtitle: String?) {
        super.init(frame: .zero)
        setup(title: title, subtitle: subtitle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(title: String, subtitle: String?) {
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .button

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 7
        textStack.isUserInteractionEnabled = false
        textStack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.82

        subtitleLabel.text = subtitle
        subtitleLabel.textColor = .chartTextMuted
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isHidden = subtitle == nil

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        switchView.onTintColor = .chartAccent
        switchView.isUserInteractionEnabled = false
        switchView.translatesAutoresizingMaskIntoConstraints = false
        switchView.addTarget(self, action: #selector(switchChanged), for: .valueChanged)

        addSubview(textStack)
        addSubview(switchView)
        addSubview(touchButton)

        touchButton.backgroundColor = .clear
        touchButton.isAccessibilityElement = false
        touchButton.translatesAutoresizingMaskIntoConstraints = false
        touchButton.addTarget(self, action: #selector(rowTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 74 : 100),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: switchView.leadingAnchor, constant: -18),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),
            switchView.trailingAnchor.constraint(equalTo: trailingAnchor),
            switchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            touchButton.topAnchor.constraint(equalTo: topAnchor),
            touchButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            touchButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            touchButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        addTarget(self, action: #selector(rowTapped), for: .touchUpInside)
        accessibilityLabel = title
    }

    func setOn(_ isOn: Bool, animated: Bool) {
        switchView.setOn(isOn, animated: animated)
        accessibilityValue = isOn ? "켬" : "끔"
    }

    @objc private func rowTapped() {
        let nextValue = !switchView.isOn
        setOn(nextValue, animated: true)
        onToggle?(nextValue)
    }

    @objc private func switchChanged() {
        setOn(switchView.isOn, animated: true)
        onToggle?(switchView.isOn)
    }

    override func accessibilityActivate() -> Bool {
        rowTapped()
        return true
    }
}

private final class ChartSettingsNavigationRow: UIControl {
    private let subtitleLabel = UILabel()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        setup(title: title, subtitle: subtitle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(title: String, subtitle: String) {
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 7
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        subtitleLabel.text = subtitle
        subtitleLabel.textColor = .chartTextMuted
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        subtitleLabel.numberOfLines = 2

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .chartTextMuted
        chevron.translatesAutoresizingMaskIntoConstraints = false

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        addSubview(textStack)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -18),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 18),
            chevron.heightAnchor.constraint(equalToConstant: 24)
        ])

        accessibilityTraits = .button
        accessibilityLabel = title
        accessibilityHint = "상세 화면으로 이동"
    }

    func setSubtitle(_ subtitle: String) {
        subtitleLabel.text = subtitle
    }
}

private final class ChartIndicatorSettingsListViewController: UIViewController {
    private let stateProvider: () -> ChartSettingsState
    private let onStateChange: (ChartSettingsState, String) -> Void
    private let contentStack = UIStackView()

    init(
        stateProvider: @escaping () -> ChartSettingsState,
        onStateChange: @escaping (ChartSettingsState, String) -> Void
    ) {
        self.stateProvider = stateProvider
        self.onStateChange = onStateChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .chartSheetBackground
        navigationController?.setNavigationBarHidden(true, animated: false)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 28, leading: 24, bottom: 28, trailing: 24)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.setTitle("  차트 설정", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        backButton.tintColor = .chartTextPrimary
        backButton.contentHorizontalAlignment = .leading
        backButton.accessibilityIdentifier = "chartSettingsDetailListBackButton"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = "지표 상세 설정"
        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 27, weight: .heavy)

        let subtitleLabel = UILabel()
        subtitleLabel.text = "현재 활성화된 지표만 편집할 수 있습니다."
        subtitleLabel.textColor = .chartTextSecondary
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.numberOfLines = 0

        contentStack.addArrangedSubview(backButton)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(subtitleLabel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadRows()
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func reloadRows() {
        while contentStack.arrangedSubviews.count > 3 {
            guard let view = contentStack.arrangedSubviews.last else { break }
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let activeIndicators = stateProvider().selectedConfigurableIndicators.filter {
            stateProvider().indicatorConfiguration(for: $0) != nil
        }

        guard activeIndicators.isEmpty == false else {
            let emptyLabel = UILabel()
            emptyLabel.text = "상세 설정 가능한 활성 지표가 없습니다."
            emptyLabel.textColor = .chartTextMuted
            emptyLabel.font = .systemFont(ofSize: 15, weight: .bold)
            emptyLabel.textAlignment = .center
            emptyLabel.backgroundColor = .chartCard
            emptyLabel.layer.cornerRadius = 10
            emptyLabel.layer.masksToBounds = true
            emptyLabel.heightAnchor.constraint(equalToConstant: 56).isActive = true
            contentStack.addArrangedSubview(emptyLabel)
            return
        }

        for indicator in activeIndicators {
            let row = ChartSettingsNavigationRow(
                title: indicator.title,
                subtitle: summary(for: indicator, state: stateProvider())
            )
            row.addTarget(self, action: #selector(indicatorTapped(_:)), for: .touchUpInside)
            row.tag = indicatorTag(for: indicator)
            contentStack.addArrangedSubview(row)
        }
    }

    private func summary(for indicator: ChartIndicatorID, state: ChartSettingsState) -> String {
        guard let configuration = state.indicatorConfiguration(for: indicator) else {
            return "세부 설정을 편집할 수 있습니다."
        }

        switch indicator {
        case .movingAverage:
            return "기간 \(configuration.period) · 선 두께 \(String(format: "%.1f", configuration.lineWidth))"
        case .bollingerBand:
            return "기간 \(configuration.period) · 승수 \(String(format: "%.1f", configuration.multiplier ?? 2))"
        case .volumeOverlay:
            return "강조 색상과 막대 두께를 조정할 수 있습니다."
        case .volume:
            return "막대 두께 \(String(format: "%.1f", configuration.lineWidth))"
        case .momentum:
            return "기간 \(configuration.period) · 기준값 \(Int(configuration.primaryLevel ?? 100))"
        case .stochastic:
            return "K \(configuration.period) · D \(configuration.secondaryPeriod ?? 3)"
        case .parabolicSAR:
            return "점 간격 \(configuration.period) · 점 크기 \(String(format: "%.1f", configuration.lineWidth))"
        default:
            return "세부 설정을 편집할 수 있습니다."
        }
    }

    @objc private func indicatorTapped(_ sender: UIControl) {
        guard let indicator = indicator(for: sender.tag) else {
            return
        }
        let editor = ChartIndicatorDetailEditorViewController(
            indicator: indicator,
            stateProvider: stateProvider,
            onStateChange: onStateChange
        )
        navigationController?.pushViewController(editor, animated: true)
    }

    private func indicatorTag(for indicator: ChartIndicatorID) -> Int {
        ChartIndicatorID.allCases.firstIndex(of: indicator) ?? 0
    }

    private func indicator(for tag: Int) -> ChartIndicatorID? {
        guard ChartIndicatorID.allCases.indices.contains(tag) else {
            return nil
        }
        return ChartIndicatorID.allCases[tag]
    }
}

private final class ChartIndicatorDetailEditorViewController: UIViewController {
    private let indicator: ChartIndicatorID
    private let stateProvider: () -> ChartSettingsState
    private let onStateChange: (ChartSettingsState, String) -> Void
    private let formStack = UIStackView()

    init(
        indicator: ChartIndicatorID,
        stateProvider: @escaping () -> ChartSettingsState,
        onStateChange: @escaping (ChartSettingsState, String) -> Void
    ) {
        self.indicator = indicator
        self.stateProvider = stateProvider
        self.onStateChange = onStateChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .chartSheetBackground
        navigationController?.setNavigationBarHidden(true, animated: false)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        formStack.axis = .vertical
        formStack.spacing = 16
        formStack.isLayoutMarginsRelativeArrangement = true
        formStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 28, leading: 24, bottom: 32, trailing: 24)
        formStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(formStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            formStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            formStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            formStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            formStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            formStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.setTitle("  지표 상세 설정", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        backButton.tintColor = .chartTextPrimary
        backButton.contentHorizontalAlignment = .leading
        backButton.accessibilityIdentifier = "chartSettingsIndicatorDetailBackButton"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        formStack.addArrangedSubview(backButton)

        let titleLabel = UILabel()
        titleLabel.text = indicator.title
        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 27, weight: .heavy)
        formStack.addArrangedSubview(titleLabel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadForm()
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func reloadForm() {
        while formStack.arrangedSubviews.count > 2 {
            guard let view = formStack.arrangedSubviews.last else { break }
            formStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let state = stateProvider()
        guard let configuration = state.indicatorConfiguration(for: indicator) else {
            let messageLabel = UILabel()
            messageLabel.text = "이 지표는 아직 상세 편집을 지원하지 않습니다."
            messageLabel.textColor = .chartTextMuted
            messageLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            messageLabel.numberOfLines = 0
            formStack.addArrangedSubview(messageLabel)
            return
        }

        let visibilityRow = ChartSettingsToggleRow(
            title: "표시",
            subtitle: "해제하면 상위 지표 선택 상태와 차트 렌더에서 함께 제외됩니다."
        )
        visibilityRow.setOn(state.isIndicatorSelected(indicator), animated: false)
        visibilityRow.onToggle = { [weak self] isOn in
            self?.applyMutation(source: "detail_visibility_\(self?.indicator.rawValue ?? "")") {
                _ = $0.setIndicatorSelected(self?.indicator ?? .movingAverage, isSelected: isOn)
            }
        }
        formStack.addArrangedSubview(visibilityRow)

        switch indicator {
        case .movingAverage:
            addIntStepper(title: "기간", value: configuration.period, range: 2...240, step: 1, source: "ma_period") { $0.period = $1 }
            addDoubleStepper(title: "선 두께", value: configuration.lineWidth, range: 0.8...4, step: 0.2, source: "ma_width") { $0.lineWidth = $1 }
            addColorPalette(title: "선 색상", selectedHex: configuration.primaryColorHex, source: "ma_color") { $0.primaryColorHex = $1 }
        case .bollingerBand:
            addIntStepper(title: "기간", value: configuration.period, range: 5...120, step: 1, source: "bb_period") { $0.period = $1 }
            addDoubleStepper(title: "표준편차 승수", value: configuration.multiplier ?? 2, range: 1...4, step: 0.5, source: "bb_multiplier") { $0.multiplier = $1 }
            addDoubleStepper(title: "선 두께", value: configuration.lineWidth, range: 0.8...4, step: 0.2, source: "bb_width") { $0.lineWidth = $1 }
            addColorPalette(title: "밴드 색상", selectedHex: configuration.primaryColorHex, source: "bb_color") { configuration, hex in
                configuration.primaryColorHex = hex
                configuration.fillColorHex = hex
            }
        case .volumeOverlay:
            addDoubleStepper(title: "막대 두께", value: configuration.lineWidth, range: 0.7...1.8, step: 0.1, source: "volume_overlay_width") { $0.lineWidth = $1 }
            addColorPalette(title: "강조 색상", selectedHex: configuration.primaryColorHex, source: "volume_overlay_color") { $0.primaryColorHex = $1 }
        case .volume:
            addDoubleStepper(title: "막대 두께", value: configuration.lineWidth, range: 0.8...1.8, step: 0.1, source: "volume_width") { $0.lineWidth = $1 }
        case .momentum:
            addIntStepper(title: "기간", value: configuration.period, range: 2...120, step: 1, source: "momentum_period") { $0.period = $1 }
            addDoubleStepper(title: "기준값", value: configuration.primaryLevel ?? 100, range: 80...120, step: 1, source: "momentum_baseline") { $0.primaryLevel = $1 }
            addDoubleStepper(title: "선 두께", value: configuration.lineWidth, range: 0.8...4, step: 0.2, source: "momentum_width") { $0.lineWidth = $1 }
            addColorPalette(title: "선 색상", selectedHex: configuration.primaryColorHex, source: "momentum_color") { $0.primaryColorHex = $1 }
        case .stochastic:
            addIntStepper(title: "K 기간", value: configuration.period, range: 5...60, step: 1, source: "stochastic_k") { $0.period = $1 }
            addIntStepper(title: "D 기간", value: configuration.secondaryPeriod ?? 3, range: 1...20, step: 1, source: "stochastic_d") { $0.secondaryPeriod = $1 }
            addDoubleStepper(title: "과매수 기준", value: configuration.primaryLevel ?? 80, range: 50...95, step: 1, source: "stochastic_upper") { $0.primaryLevel = $1 }
            addDoubleStepper(title: "과매도 기준", value: configuration.secondaryLevel ?? 20, range: 5...50, step: 1, source: "stochastic_lower") { $0.secondaryLevel = $1 }
            addDoubleStepper(title: "선 두께", value: configuration.lineWidth, range: 0.8...4, step: 0.2, source: "stochastic_width") { $0.lineWidth = $1 }
            addColorPalette(title: "K 색상", selectedHex: configuration.primaryColorHex, source: "stochastic_k_color") { $0.primaryColorHex = $1 }
            addColorPalette(title: "D 색상", selectedHex: configuration.secondaryColorHex ?? "#60A5FA", source: "stochastic_d_color") { $0.secondaryColorHex = $1 }
        case .parabolicSAR:
            addIntStepper(title: "점 간격", value: configuration.period, range: 1...8, step: 1, source: "psar_spacing") { $0.period = $1 }
            addDoubleStepper(title: "점 크기", value: configuration.lineWidth, range: 1...4, step: 0.2, source: "psar_size") { $0.lineWidth = $1 }
            addColorPalette(title: "점 색상", selectedHex: configuration.primaryColorHex, source: "psar_color") { $0.primaryColorHex = $1 }
        default:
            let messageLabel = UILabel()
            messageLabel.text = "이 지표는 현재 상세 편집을 지원하지 않습니다."
            messageLabel.textColor = .chartTextMuted
            messageLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            messageLabel.numberOfLines = 0
            formStack.addArrangedSubview(messageLabel)
        }
    }

    private func applyMutation(
        source: String,
        mutation: (inout ChartSettingsState) -> Void
    ) {
        var nextState = stateProvider()
        mutation(&nextState)
        onStateChange(nextState.normalized, "indicator_detail_\(source)")
        reloadForm()
    }

    private func addIntStepper(
        title: String,
        value: Int,
        range: ClosedRange<Int>,
        step: Int,
        source: String,
        mutation: @escaping (inout ChartIndicatorConfiguration, Int) -> Void
    ) {
        let row = ChartSettingsStepperRow(title: title, valueText: "\(value)")
        row.onDecrease = { [weak self] in
            guard let self else { return }
            let nextValue = max(range.lowerBound, value - step)
            self.applyMutation(source: source) { state in
                state.updateIndicatorConfiguration(for: self.indicator) { mutation(&$0, nextValue) }
            }
        }
        row.onIncrease = { [weak self] in
            guard let self else { return }
            let nextValue = min(range.upperBound, value + step)
            self.applyMutation(source: source) { state in
                state.updateIndicatorConfiguration(for: self.indicator) { mutation(&$0, nextValue) }
            }
        }
        formStack.addArrangedSubview(row)
    }

    private func addDoubleStepper(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        source: String,
        mutation: @escaping (inout ChartIndicatorConfiguration, Double) -> Void
    ) {
        let row = ChartSettingsStepperRow(title: title, valueText: formattedDouble(value))
        row.onDecrease = { [weak self] in
            guard let self else { return }
            let nextValue = max(range.lowerBound, value - step)
            self.applyMutation(source: source) { state in
                state.updateIndicatorConfiguration(for: self.indicator) { mutation(&$0, nextValue) }
            }
        }
        row.onIncrease = { [weak self] in
            guard let self else { return }
            let nextValue = min(range.upperBound, value + step)
            self.applyMutation(source: source) { state in
                state.updateIndicatorConfiguration(for: self.indicator) { mutation(&$0, nextValue) }
            }
        }
        formStack.addArrangedSubview(row)
    }

    private func addColorPalette(
        title: String,
        selectedHex: String,
        source: String,
        mutation: @escaping (inout ChartIndicatorConfiguration, String) -> Void
    ) {
        let row = ChartSettingsColorPaletteRow(
            title: title,
            colors: ["#F59E0B", "#F97316", "#34D399", "#60A5FA", "#A78BFA", "#F472B6"],
            selectedHex: selectedHex
        )
        row.onColorSelected = { [weak self] hex in
            guard let self else { return }
            self.applyMutation(source: source) { state in
                state.updateIndicatorConfiguration(for: self.indicator) { mutation(&$0, hex) }
            }
        }
        formStack.addArrangedSubview(row)
    }

    private func formattedDouble(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

private final class ChartCompareSymbolsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let currentSymbol: String?
    private let candidates: [ChartComparisonCandidate]
    private let stateProvider: () -> ChartSettingsState
    private let onStateChange: (ChartSettingsState, String) -> Void
    private let onMessage: (String) -> Void
    private let selectedStack = UIStackView()
    private let recommendationStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchField = UITextField()

    init(
        currentSymbol: String?,
        candidates: [ChartComparisonCandidate],
        stateProvider: @escaping () -> ChartSettingsState,
        onStateChange: @escaping (ChartSettingsState, String) -> Void,
        onMessage: @escaping (String) -> Void
    ) {
        self.currentSymbol = currentSymbol
        self.candidates = candidates
        self.stateProvider = stateProvider
        self.onStateChange = onStateChange
        self.onMessage = onMessage
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .chartSheetBackground
        navigationController?.setNavigationBarHidden(true, animated: false)

        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.setTitle("  차트 설정", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        backButton.tintColor = .chartTextPrimary
        backButton.contentHorizontalAlignment = .leading
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.accessibilityIdentifier = "chartSettingsCompareBackButton"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = "종목 비교"
        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 27, weight: .heavy)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholder = "현재 거래소 종목 검색"
        searchField.textColor = .chartTextPrimary
        searchField.font = .systemFont(ofSize: 16, weight: .semibold)
        searchField.backgroundColor = .chartCard
        searchField.layer.cornerRadius = 12
        searchField.layer.borderWidth = 1
        searchField.layer.borderColor = UIColor.chartBorder.cgColor
        searchField.setLeftPadding(14)
        searchField.clearButtonMode = .whileEditing
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        searchField.delegate = self

        let selectedTitle = UILabel()
        selectedTitle.text = "선택된 비교 종목"
        selectedTitle.textColor = .chartTextPrimary
        selectedTitle.font = .systemFont(ofSize: 17, weight: .heavy)
        selectedTitle.translatesAutoresizingMaskIntoConstraints = false

        let recommendationTitle = UILabel()
        recommendationTitle.text = "추천 비교 종목"
        recommendationTitle.textColor = .chartTextPrimary
        recommendationTitle.font = .systemFont(ofSize: 17, weight: .heavy)
        recommendationTitle.translatesAutoresizingMaskIntoConstraints = false

        recommendationStack.axis = .vertical
        recommendationStack.spacing = 8
        recommendationStack.translatesAutoresizingMaskIntoConstraints = false

        selectedStack.axis = .vertical
        selectedStack.spacing = 10
        selectedStack.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorColor = .chartBorder
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "candidate")

        view.addSubview(backButton)
        view.addSubview(titleLabel)
        view.addSubview(searchField)
        view.addSubview(recommendationTitle)
        view.addSubview(recommendationStack)
        view.addSubview(selectedTitle)
        view.addSubview(selectedStack)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            backButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            searchField.heightAnchor.constraint(equalToConstant: 48),
            recommendationTitle.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 22),
            recommendationTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            recommendationTitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            recommendationStack.topAnchor.constraint(equalTo: recommendationTitle.bottomAnchor, constant: 10),
            recommendationStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            recommendationStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            selectedTitle.topAnchor.constraint(equalTo: recommendationStack.bottomAnchor, constant: 22),
            selectedTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            selectedTitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            selectedStack.topAnchor.constraint(equalTo: selectedTitle.bottomAnchor, constant: 12),
            selectedStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            selectedStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            tableView.topAnchor.constraint(equalTo: selectedStack.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSelectedSymbols()
        reloadRecommendations()
        tableView.reloadData()
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func searchTextChanged() {
        tableView.reloadData()
    }

    private func reloadRecommendations() {
        recommendationStack.removeAllArrangedSubviews()

        let quickCandidates = effectiveCandidates
            .filter { $0.symbol != currentSymbol && stateProvider().comparedSymbols.contains($0.symbol) == false }
            .prefix(5)
        AppLogger.debug(
            .route,
            "[ChartSettings] compare_quick_candidates current=\(currentSymbol ?? "nil") base=\(candidates.map(\.symbol).joined(separator: ",")) effective=\(effectiveCandidates.map(\.symbol).joined(separator: ",")) quick=\(quickCandidates.map(\.symbol).joined(separator: ","))"
        )

        guard quickCandidates.isEmpty == false else {
            let emptyLabel = UILabel()
            emptyLabel.text = "추천 가능한 비교 종목이 없습니다."
            emptyLabel.textColor = .chartTextMuted
            emptyLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            emptyLabel.numberOfLines = 0
            recommendationStack.addArrangedSubview(emptyLabel)
            return
        }

        for candidate in quickCandidates {
            let button = UIButton(type: .system)
            button.setTitle("\(candidate.symbol) 추가", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            button.tintColor = .chartButtonText
            button.backgroundColor = .chartCTA
            button.layer.cornerRadius = 12
            button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
            button.contentHorizontalAlignment = .left
            button.accessibilityIdentifier = "quickCompare_\(candidate.symbol)"
            button.addAction(UIAction { [weak self] _ in
                self?.toggleCandidateSelection(candidate)
            }, for: .touchUpInside)
            recommendationStack.addArrangedSubview(button)
        }
    }

    private func reloadSelectedSymbols() {
        selectedStack.removeAllArrangedSubviews()
        let selectedSymbols = stateProvider().comparedSymbols

        if selectedSymbols.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "아직 선택된 비교 종목이 없습니다. 아래 목록에서 추가해보세요."
            emptyLabel.textColor = .chartTextMuted
            emptyLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            emptyLabel.numberOfLines = 0
            emptyLabel.backgroundColor = .chartCard
            emptyLabel.layer.cornerRadius = 10
            emptyLabel.layer.masksToBounds = true
            emptyLabel.heightAnchor.constraint(equalToConstant: 64).isActive = true
            emptyLabel.textAlignment = .center
            selectedStack.addArrangedSubview(emptyLabel)
            return
        }

        for symbol in selectedSymbols {
            let button = ChartSelectedSymbolRow(symbol: symbol)
            button.onRemove = { [weak self] in
                guard let self else { return }
                var nextState = self.stateProvider()
                nextState.removeComparedSymbol(symbol)
                self.onStateChange(nextState.normalized, "compare_remove_\(symbol)")
                self.reloadSelectedSymbols()
                self.reloadRecommendations()
                self.tableView.reloadData()
            }
            selectedStack.addArrangedSubview(button)
        }
    }

    private var filteredCandidates: [ChartComparisonCandidate] {
        let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard query.isEmpty == false else {
            return effectiveCandidates
        }
        return effectiveCandidates.filter {
            $0.symbol.lowercased().contains(query)
                || $0.name.lowercased().contains(query)
                || $0.nameEn.lowercased().contains(query)
        }
    }

    private var effectiveCandidates: [ChartComparisonCandidate] {
        var orderedCandidates = [ChartComparisonCandidate]()
        var seenSymbols = Set<String>()

        func append(_ candidate: ChartComparisonCandidate) {
            guard seenSymbols.insert(candidate.symbol).inserted else {
                return
            }
            orderedCandidates.append(candidate)
        }

        candidates.forEach(append)
        CoinCatalog.fallbackTopSymbols.forEach { symbol in
            let coin = CoinCatalog.coin(symbol: symbol)
            append(
                ChartComparisonCandidate(
                    symbol: coin.symbol,
                    name: coin.name,
                    nameEn: coin.nameEn,
                    isFavorite: false
                )
            )
        }

        return orderedCandidates
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredCandidates.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "candidate", for: indexPath)
        let candidate = filteredCandidates[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = candidate.symbol + (candidate.isFavorite ? "  ★" : "")
        content.secondaryText = candidate.nameEn == candidate.name ? candidate.name : "\(candidate.name) · \(candidate.nameEn)"
        content.textProperties.color = .chartTextPrimary
        content.secondaryTextProperties.color = .chartTextSecondary
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = "comparisonCandidate_\(candidate.symbol)"
        cell.accessibilityLabel = candidate.symbol

        if candidate.symbol == currentSymbol {
            cell.accessoryType = .none
            cell.isUserInteractionEnabled = false
            cell.contentView.alpha = 0.45
        } else if stateProvider().comparedSymbols.contains(candidate.symbol) {
            cell.accessoryType = .checkmark
            cell.tintColor = .chartAccent
            cell.isUserInteractionEnabled = true
            cell.contentView.alpha = 1
        } else {
            cell.accessoryType = .disclosureIndicator
            cell.tintColor = .chartTextMuted
            cell.isUserInteractionEnabled = true
            cell.contentView.alpha = 1
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        toggleCandidateSelection(filteredCandidates[indexPath.row])
    }

    private func toggleCandidateSelection(_ candidate: ChartComparisonCandidate) {
        guard candidate.symbol != currentSymbol else {
            onMessage("현재 보고 있는 종목은 비교 목록에 추가할 수 없어요")
            return
        }

        var nextState = stateProvider()
        if nextState.comparedSymbols.contains(candidate.symbol) {
            nextState.removeComparedSymbol(candidate.symbol)
            onStateChange(nextState.normalized, "compare_remove_\(candidate.symbol)")
        } else {
            let result = nextState.addComparedSymbol(candidate.symbol)
            switch result {
            case .applied:
                onStateChange(nextState.normalized, "compare_add_\(candidate.symbol)")
            case .duplicate, .limitReached:
                if let message = result.userMessage {
                    onMessage(message)
                }
            }
        }

        reloadSelectedSymbols()
        reloadRecommendations()
        tableView.reloadData()
    }
}

private final class ChartSettingsStepperRow: UIView {
    var onDecrease: (() -> Void)?
    var onIncrease: (() -> Void)?

    init(title: String, valueText: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .chartCard
        layer.cornerRadius = 14
        layer.borderWidth = 1
        layer.borderColor = UIColor.chartBorder.cgColor

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = valueText
        valueLabel.textColor = .chartAccent
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .bold)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let minusButton = makeButton(title: "−", action: #selector(decreaseTapped))
        let plusButton = makeButton(title: "+", action: #selector(increaseTapped))

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(minusButton)
        addSubview(plusButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 64),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            plusButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            plusButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            plusButton.widthAnchor.constraint(equalToConstant: 36),
            plusButton.heightAnchor.constraint(equalToConstant: 36),
            valueLabel.trailingAnchor.constraint(equalTo: plusButton.leadingAnchor, constant: -12),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            minusButton.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -12),
            minusButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            minusButton.widthAnchor.constraint(equalToConstant: 36),
            minusButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 20, weight: .heavy)
        button.tintColor = .chartButtonText
        button.backgroundColor = .chartCTA
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func decreaseTapped() {
        onDecrease?()
    }

    @objc private func increaseTapped() {
        onIncrease?()
    }
}

private final class ChartSettingsColorPaletteRow: UIView {
    var onColorSelected: ((String) -> Void)?
    private let selectedHex: String

    init(title: String, colors: [String], selectedHex: String) {
        self.selectedHex = selectedHex
        super.init(frame: .zero)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        let colorsStack = UIStackView()
        colorsStack.axis = .horizontal
        colorsStack.spacing = 10
        colorsStack.distribution = .fillEqually
        stack.addArrangedSubview(colorsStack)

        for hex in colors {
            let button = UIButton(type: .custom)
            button.backgroundColor = UIColor(hex: hex)
            button.layer.cornerRadius = 14
            button.layer.borderWidth = hex == selectedHex ? 2 : 1
            button.layer.borderColor = (hex == selectedHex ? UIColor.chartTextPrimary : UIColor.chartBorder).cgColor
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            button.accessibilityLabel = hex
            button.addAction(UIAction { [weak self] _ in
                self?.onColorSelected?(hex)
            }, for: .touchUpInside)
            colorsStack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ChartSelectedSymbolRow: UIView {
    var onRemove: (() -> Void)?

    init(symbol: String) {
        super.init(frame: .zero)
        backgroundColor = .chartSelectedCard
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.chartAccent.cgColor
        isAccessibilityElement = true
        accessibilityIdentifier = "selectedComparedSymbol_\(symbol)"
        accessibilityLabel = symbol

        let label = UILabel()
        label.text = symbol
        label.textColor = .chartTextPrimary
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false

        let removeButton = UIButton(type: .system)
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.tintColor = .chartAccent
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.addAction(UIAction { [weak self] _ in
            self?.onRemove?()
        }, for: .touchUpInside)

        addSubview(label)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension UIStackView {
    func removeAllArrangedSubviews() {
        let views = arrangedSubviews
        views.forEach { view in
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

private extension UITextField {
    func setLeftPadding(_ value: CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        leftView = paddingView
        leftViewMode = .always
    }
}

private final class ChartSettingsPlaceholderViewController: UIViewController {
    private let placeholderTitle: String
    private let message: String
    private let rows: [String]

    init(title: String, message: String, rows: [String]) {
        self.placeholderTitle = title
        self.message = message
        self.rows = rows
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .chartSheetBackground
        navigationController?.setNavigationBarHidden(true, animated: false)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 18
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 28, leading: 24, bottom: 28, trailing: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.setTitle("  차트 설정", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        backButton.tintColor = .chartTextPrimary
        backButton.contentHorizontalAlignment = .leading
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = placeholderTitle
        titleLabel.textColor = .chartTextPrimary
        titleLabel.font = .systemFont(ofSize: 27, weight: .heavy)
        titleLabel.numberOfLines = 2

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.textColor = .chartTextSecondary
        messageLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        messageLabel.numberOfLines = 0

        stack.addArrangedSubview(backButton)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(messageLabel)

        if rows.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "선택된 항목이 없습니다."
            emptyLabel.textColor = .chartTextMuted
            emptyLabel.font = .systemFont(ofSize: 15, weight: .bold)
            emptyLabel.textAlignment = .center
            emptyLabel.backgroundColor = .chartCard
            emptyLabel.layer.cornerRadius = 10
            emptyLabel.layer.masksToBounds = true
            emptyLabel.heightAnchor.constraint(equalToConstant: 56).isActive = true
            stack.addArrangedSubview(emptyLabel)
        } else {
            for row in rows {
                let label = UILabel()
                label.text = row
                label.textColor = .chartTextPrimary
                label.font = .systemFont(ofSize: 16, weight: .semibold)
                label.backgroundColor = .chartCard
                label.layer.cornerRadius = 10
                label.layer.borderWidth = 1
                label.layer.borderColor = UIColor.chartBorder.cgColor
                label.layer.masksToBounds = true
                label.heightAnchor.constraint(equalToConstant: 54).isActive = true
                label.setContentCompressionResistancePriority(.required, for: .vertical)
                label.textAlignment = .center
                stack.addArrangedSubview(label)
            }
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }
}

private extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&int)
        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch hexString.count {
        case 6:
            red = int >> 16
            green = int >> 8 & 0xFF
            blue = int & 0xFF
        default:
            red = 0
            green = 0
            blue = 0
        }

        self.init(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: alpha
        )
    }

    static let chartSheetBackground = UIColor(hex: "#1B222D")
    static let chartCard = UIColor(hex: "#1B222D")
    static let chartAccent = UIColor(Color.accent)
    static let chartSelectedCard = UIColor(Color.accent.opacity(0.14))
    static let chartSelectedAccentBackground = UIColor(Color.accent.opacity(0.18))
    static let chartBorder = UIColor(hex: "#465265")
    static let chartCheckboxBorder = UIColor(hex: "#A0A8B6")
    static let chartTextPrimary = UIColor(hex: "#F1F4FA")
    static let chartTextSecondary = UIColor(hex: "#A7B0BE")
    static let chartTextMuted = UIColor(hex: "#637083")
    static let chartBlue = UIColor(Color.accent)
    static let chartCTA = UIColor(Color.accent)
    static let chartDisabledCTA = UIColor(hex: "#2A3550")
    static let chartButtonText = UIColor(hex: "#111827")
    static let chartDisabledText = UIColor(hex: "#637083")
    static let chartGrabber = UIColor(hex: "#667284")
}
