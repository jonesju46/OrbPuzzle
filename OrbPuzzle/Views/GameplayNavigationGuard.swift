import SpriteKit
import SwiftUI
import UIKit

/// Keeps the pushed gameplay screen fixed by disabling navigation-container pan
/// recognizers only while GameView is attached and visible. Tap-based navigation
/// bar buttons remain enabled, and every recognizer's prior state is restored.
struct GameplayNavigationGuard: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.scheduleGuardInstallation()
    }

    final class Controller: UIViewController {
        private final class GestureState {
            weak var recognizer: UIGestureRecognizer?
            let wasEnabled: Bool

            init(recognizer: UIGestureRecognizer) {
                self.recognizer = recognizer
                wasEnabled = recognizer.isEnabled
            }
        }

        private final class AttachmentView: UIView {
            var windowChanged: (() -> Void)?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                windowChanged?()
            }
        }

        private weak var guardedNavigationController: UINavigationController?
        private var gestureStates: [ObjectIdentifier: GestureState] = [:]
#if DEBUG
        private var reportedMovement = false
#endif

        override func loadView() {
            let attachmentView = AttachmentView(frame: .zero)
            attachmentView.isUserInteractionEnabled = false
            attachmentView.windowChanged = { [weak self] in self?.scheduleGuardInstallation() }
            view = attachmentView
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent == nil {
                restoreNavigationGestures()
            } else {
                scheduleGuardInstallation()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            scheduleGuardInstallation()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            installNavigationGuardIfPossible()
            reportUnexpectedGameplayMovementIfNeeded()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restoreNavigationGestures()
        }

        func scheduleGuardInstallation() {
            DispatchQueue.main.async { [weak self] in
                self?.installNavigationGuardIfPossible()
            }
        }

        private func installNavigationGuardIfPossible() {
            guard view.window != nil, let navigationController = findNavigationController() else { return }
            guardedNavigationController = navigationController

            // SwiftUI NavigationStack can install more than the public interactive-pop
            // recognizer. Inspect the actual navigation view hierarchy after attachment.
            for candidateView in allViews(startingAt: navigationController.view) {
                guard !(candidateView is SKView) else { continue }
                for recognizer in candidateView.gestureRecognizers ?? [] where shouldDisable(recognizer) {
                    disable(recognizer)
                }
            }

            if let interactivePop = navigationController.interactivePopGestureRecognizer {
                disable(interactivePop)
            }
        }

        private func shouldDisable(_ recognizer: UIGestureRecognizer) -> Bool {
            recognizer is UIScreenEdgePanGestureRecognizer || recognizer is UIPanGestureRecognizer
        }

        private func disable(_ recognizer: UIGestureRecognizer) {
            let identifier = ObjectIdentifier(recognizer)
            if gestureStates[identifier] == nil {
                gestureStates[identifier] = GestureState(recognizer: recognizer)
#if DEBUG
                print("[NAV-GUARD] disabled \(String(describing: type(of: recognizer)))")
#endif
            }
            // Re-assert after layout in case the navigation container re-enabled it.
            recognizer.isEnabled = false
        }

        private func restoreNavigationGestures() {
            for state in gestureStates.values {
                state.recognizer?.isEnabled = state.wasEnabled
            }
            gestureStates.removeAll()
            guardedNavigationController = nil
#if DEBUG
            reportedMovement = false
#endif
        }

        private func findNavigationController() -> UINavigationController? {
            if let navigationController { return navigationController }
            var ancestor = parent
            while let current = ancestor {
                if let navigationController = current as? UINavigationController { return navigationController }
                if let navigationController = current.navigationController { return navigationController }
                ancestor = current.parent
            }
            return nil
        }

        private func allViews(startingAt root: UIView) -> [UIView] {
            var result: [UIView] = []
            var pending = [root]
            while let current = pending.popLast() {
                result.append(current)
                pending.append(contentsOf: current.subviews)
            }
            return result
        }

        private func reportUnexpectedGameplayMovementIfNeeded() {
#if DEBUG
            guard !reportedMovement,
                  let gameplayView = guardedNavigationController?.topViewController?.view else { return }
            let xMovement = gameplayView.frame.minX + gameplayView.transform.tx
            if abs(xMovement) > 1 {
                reportedMovement = true
                print("[NAV-BUG] navigation transition detected")
                print("[NAV-BUG] gameplay moved x=\(xMovement)")
            }
#endif
        }
    }
}
