import ObjectiveC
import SwiftUI
import UIKit

/// Tab switches use the shared fade: the incoming tab fades in over the outgoing
/// one for `GymMotion.fadeDuration` (150 ms ease-out), the same cross-fade the
/// Android and PWA clients play. SwiftUI's `TabView` has no API for this, so
/// `.gymTabTransition()` attaches a `UITabBarControllerDelegate` to the backing
/// `UITabBarController`. The fade is opacity-only, so it is also what Reduce
/// Motion gets; it never slides. Selection stays owned by SwiftUI: any delegate
/// SwiftUI (or UIKit) already installed keeps receiving every delegate call, and
/// when the tab bar controller cannot be found the tabs simply switch without
/// animation.
extension View {
    func gymTabTransition() -> some View {
        background { GymTabTransitionInstaller().frame(width: 0, height: 0).accessibilityHidden(true) }
    }
}

private struct GymTabTransitionInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GymTabTransitionInstallerController {
        GymTabTransitionInstallerController()
    }

    func updateUIViewController(_ controller: GymTabTransitionInstallerController, context: Context) {
        controller.installDeferred()
    }
}

/// Finds the enclosing (or window-level) `UITabBarController` once attached and
/// installs the fade delegate. Retries on each layout pass until it succeeds.
private final class GymTabTransitionInstallerController: UIViewController {
    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.isHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installDeferred()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installDeferred()
    }

    func installDeferred() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let tabBarController = self.findTabBarController() else { return }
            GymTabTransitionDelegate.install(on: tabBarController)
        }
    }

    private func findTabBarController() -> UITabBarController? {
        var ancestor: UIViewController? = self
        while let current = ancestor {
            if let tabBarController = current as? UITabBarController { return tabBarController }
            ancestor = current.parent
        }
        // The installer sits behind the TabView, so the tab bar controller is
        // usually a descendant of the window's root rather than an ancestor.
        guard let root = view.window?.rootViewController else { return nil }
        return Self.firstTabBarController(in: root)
    }

    private static func firstTabBarController(in controller: UIViewController) -> UITabBarController? {
        if let tabBarController = controller as? UITabBarController { return tabBarController }
        for child in controller.children {
            if let found = firstTabBarController(in: child) { return found }
        }
        return nil
    }
}

private var gymTabTransitionDelegateKey: UInt8 = 0

/// Forwards every delegate call to the delegate that was installed before it,
/// and only adds the cross-fade animation controller.
@MainActor
private final class GymTabTransitionDelegate: NSObject, UITabBarControllerDelegate {
    nonisolated(unsafe) weak var forwarded: (any UITabBarControllerDelegate)?

    static func install(on tabBarController: UITabBarController) {
        // Already installed and still the active delegate.
        if tabBarController.delegate is GymTabTransitionDelegate { return }
        let proxy: GymTabTransitionDelegate
        if let owned = objc_getAssociatedObject(tabBarController, &gymTabTransitionDelegateKey)
            as? GymTabTransitionDelegate {
            proxy = owned
        } else {
            proxy = GymTabTransitionDelegate()
            objc_setAssociatedObject(
                tabBarController, &gymTabTransitionDelegateKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
        // Delegate replaced after install: keep the replacement reachable.
        proxy.forwarded = tabBarController.delegate
        tabBarController.delegate = proxy
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        animationControllerForTransitionFrom fromVC: UIViewController,
        to toVC: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        // A delegate that supplies its own animation wins.
        if let custom = forwarded?.tabBarController?(
            tabBarController, animationControllerForTransitionFrom: fromVC, to: toVC
        ) {
            return custom
        }
        guard fromVC !== toVC else { return nil }
        return GymTabFadeAnimator()
    }

    // Forward every other (optional) delegate method untouched.
    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (forwarded?.responds(to: aSelector) ?? false)
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let forwarded, forwarded.responds(to: aSelector) { return forwarded }
        return super.forwardingTarget(for: aSelector)
    }
}

/// Non-interactive cross-fade: the incoming view fades in over the outgoing one.
@MainActor
private final class GymTabFadeAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        GymMotion.fadeDuration
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard transitionContext.isAnimated,
              let toView = transitionContext.view(forKey: .to)
                ?? transitionContext.viewController(forKey: .to)?.view else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }
        let container = transitionContext.containerView
        if let toController = transitionContext.viewController(forKey: .to) {
            toView.frame = transitionContext.finalFrame(for: toController)
        }
        if toView.superview !== container { container.addSubview(toView) }
        toView.alpha = 0
        UIView.animate(
            withDuration: GymMotion.fadeDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            toView.alpha = 1
        } completion: { _ in
            toView.alpha = 1
            let cancelled = transitionContext.transitionWasCancelled
            if cancelled { toView.removeFromSuperview() }
            transitionContext.completeTransition(!cancelled)
        }
    }
}
