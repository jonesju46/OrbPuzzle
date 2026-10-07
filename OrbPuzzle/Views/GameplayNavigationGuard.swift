import SwiftUI
import UIKit

/// Disables only the UINavigationController edge-pop recognizer while GameView is visible.
/// The navigation bar's Back button remains fully functional.
struct GameplayNavigationGuard: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.disableInteractivePopWhenAttached()
    }

    final class Controller: UIViewController {
        private weak var guardedNavigationController: UINavigationController?
        private var priorEnabledState: Bool?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil {
                DispatchQueue.main.async { [weak self] in
                    self?.disableInteractivePopWhenAttached()
                }
            } else {
                restoreInteractivePop()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            disableInteractivePopWhenAttached()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restoreInteractivePop()
        }

        func disableInteractivePopWhenAttached() {
            guard guardedNavigationController == nil,
                  let navigationController = self.navigationController ?? parent?.navigationController,
                  let recognizer = navigationController.interactivePopGestureRecognizer else { return }
            guardedNavigationController = navigationController
            priorEnabledState = recognizer.isEnabled
            recognizer.isEnabled = false
        }

        private func restoreInteractivePop() {
            guard let recognizer = guardedNavigationController?.interactivePopGestureRecognizer,
                  let priorEnabledState else { return }
            recognizer.isEnabled = priorEnabledState
            guardedNavigationController = nil
            self.priorEnabledState = nil
        }
    }
}
