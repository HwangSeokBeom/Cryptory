import SwiftUI
import UIKit

struct KeyboardDismissOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KeyboardDismissGestureInstaller())
    }
}

extension View {
    func dismissKeyboardOnBackgroundTap() -> some View {
        modifier(KeyboardDismissOnTapModifier())
    }
}

private struct KeyboardDismissGestureInstaller: UIViewRepresentable {
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
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let instanceID = AppLogger.nextInstanceID(scope: "KeyboardDismissCoordinator")
        private weak var installedView: UIView?
        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        override init() {
            super.init()
            AppLogger.debug(.lifecycle, "KeyboardDismissCoordinator init #\(instanceID)")
        }

        deinit {
            AppLogger.debug(.lifecycle, "KeyboardDismissCoordinator deinit #\(instanceID)")
        }

        func installIfNeeded(from anchorView: UIView) {
            guard let targetView = anchorView.superview, installedView !== targetView else { return }
            installedView?.removeGestureRecognizer(recognizer)
            targetView.addGestureRecognizer(recognizer)
            installedView = targetView
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
