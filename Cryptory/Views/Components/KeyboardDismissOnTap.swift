import SwiftUI
import UIKit

struct KeyboardDismissOnTapModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .background(KeyboardDismissGestureInstaller(enabled: enabled))
    }
}

extension View {
    func dismissKeyboardOnBackgroundTap(enabled: Bool = true) -> some View {
        modifier(KeyboardDismissOnTapModifier(enabled: enabled))
    }
}

private final class KeyboardDismissTapGestureRecognizer: UITapGestureRecognizer {}

private struct KeyboardDismissGestureInstaller: UIViewRepresentable {
    let enabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView, enabled: enabled)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let instanceID = AppLogger.nextInstanceID(scope: "KeyboardDismissCoordinator")
        private weak var installedView: UIView?
        private lazy var recognizer: KeyboardDismissTapGestureRecognizer = {
            let recognizer = KeyboardDismissTapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        override init() {
            super.init()
            AppLogger.debug(.lifecycle, "KeyboardDismissCoordinator init #\(instanceID)")
        }

        deinit {
            installedView?.removeGestureRecognizer(recognizer)
            AppLogger.debug(.lifecycle, "KeyboardDismissCoordinator deinit #\(instanceID)")
        }

        func installIfNeeded(from anchorView: UIView, enabled: Bool) {
            guard let targetView = anchorView.superview else { return }
            if installedView !== targetView {
                installedView?.removeGestureRecognizer(recognizer)
                targetView.gestureRecognizers?
                    .compactMap { $0 as? KeyboardDismissTapGestureRecognizer }
                    .filter { $0 !== recognizer }
                    .forEach { targetView.removeGestureRecognizer($0) }
                targetView.addGestureRecognizer(recognizer)
                installedView = targetView
            }
            recognizer.isEnabled = enabled
            AppLogger.debug(.lifecycle, "KeyboardDismissCoordinator install #\(instanceID)")
        }

        @objc private func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = touch.view else { return true }
            return !view.isInteractiveInputDescendant
        }
    }
}

private extension UIView {
    var isInteractiveInputDescendant: Bool {
        sequence(first: self, next: \.superview).contains { view in
            view is UIControl || view is UITextField || view is UITextView
        }
    }
}
