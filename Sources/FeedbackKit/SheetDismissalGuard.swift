#if os(iOS)
import SwiftUI
import UIKit

struct SheetDismissalGuard: UIViewControllerRepresentable {
    let isDisabled: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.isDisabled = self.isDisabled
        controller.onAttempt = self.onAttempt
        Task { @MainActor [weak controller] in
            await Task.yield()
            controller?.install()
        }
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator _: ()) {
        controller.restore()
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var isDisabled = false
        var onAttempt: (() -> Void)?
        private weak var presentation: UIPresentationController?
        private nonisolated(unsafe) weak var previousDelegate: (any UIAdaptivePresentationControllerDelegate)?

        override func viewDidLoad() {
            super.viewDidLoad()
            self.view.isUserInteractionEnabled = false
            self.view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            self.install()
        }

        func install() {
            var current: UIViewController? = self.parent
            while let controller = current {
                if let presenter = controller.presentingViewController,
                   presenter.presentedViewController === controller,
                   let presentation = controller.presentationController
                {
                    guard presentation.delegate !== self else { return }
                    self.restore()
                    self.presentation = presentation
                    self.previousDelegate = presentation.delegate
                    presentation.delegate = self
                    return
                }
                current = controller.parent
            }
        }

        func restore() {
            if self.presentation?.delegate === self {
                self.presentation?.delegate = self.previousDelegate
            }
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !self.isDisabled
                && (self.previousDelegate?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            self.onAttempt?()
            self.previousDelegate?.presentationControllerDidAttemptToDismiss?(presentationController)
        }

        override nonisolated func responds(to selector: Selector?) -> Bool {
            super.responds(to: selector) || (self.previousDelegate?.responds(to: selector) ?? false)
        }

        override nonisolated func forwardingTarget(for selector: Selector?) -> Any? {
            self.previousDelegate?.responds(to: selector) == true
                ? self.previousDelegate
                : super.forwardingTarget(for: selector)
        }
    }
}
#endif
