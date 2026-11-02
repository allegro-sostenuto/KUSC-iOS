import SwiftUI
import UIKit

/// One recognizer attached to the stationary viewport, independent of its
/// moving ScrollViews. Native failure ordering gives vertical scrolling and
/// refresh their gesture when the touch is vertical, without disabling either.
struct PanelPanGesture: UIViewRepresentable {
    let enabled: Bool
    let opening: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.moved = { [weak coordinator = context.coordinator] in coordinator?.attach(to: $0) }
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {
        context.coordinator.configuration = self
        context.coordinator.attach(to: view)
    }

    static func dismantleUIView(_ view: AttachmentView, coordinator: Coordinator) {
        view.moved = nil
        coordinator.detach()
    }

    final class AttachmentView: UIView {
        var moved: ((AttachmentView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            moved?(self)
        }
        // This view supplies bounds only; controls and refresh keep their touches.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var configuration: PanelPanGesture
        private weak var marker: AttachmentView?
        private weak var attachedWindow: UIWindow?
        private weak var touchedScroll: UIScrollView?
        private var active = false
        private lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.maximumNumberOfTouches = 1
            recognizer.delegate = self
            recognizer.delaysTouchesBegan = false
            return recognizer
        }()

        init(_ configuration: PanelPanGesture) { self.configuration = configuration }

        func attach(to view: AttachmentView) {
            marker = view
            guard attachedWindow !== view.window else { return }
            attachedWindow?.removeGestureRecognizer(pan)
            attachedWindow = view.window
            view.window?.addGestureRecognizer(pan)
        }

        func detach() {
            attachedWindow?.removeGestureRecognizer(pan)
            attachedWindow = nil
            marker = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard configuration.enabled, let marker, marker.window != nil,
                  marker.bounds.contains(touch.location(in: marker)) else { return false }
            var ancestor = touch.view
            touchedScroll = nil
            while let view = ancestor {
                if let scroll = view as? UIScrollView { touchedScroll = scroll; break }
                ancestor = view.superview
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard configuration.enabled else { return false }
            let distance = pan.translation(in: marker)
            let velocity = pan.velocity(in: marker)
            let intent = abs(distance.x) + abs(distance.y) > 1 ? distance : velocity
            return abs(intent.x) > abs(intent.y) * 1.15 &&
                (configuration.opening ? intent.x > 0 : intent.x < 0)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let scroll = other.view as? UIScrollView else { return false }
            return other === scroll.panGestureRecognizer
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            let x = recognizer.translation(in: marker).x
            switch recognizer.state {
            case .began:
                active = true
                // Stop any existing vertical deceleration before dragging sideways.
                if let scroll = touchedScroll { scroll.setContentOffset(scroll.contentOffset, animated: false) }
                configuration.changed(x)
            case .changed:
                configuration.changed(x)
            case .ended, .cancelled, .failed:
                guard active else { return }
                active = false
                configuration.ended(x, recognizer.velocity(in: marker).x, recognizer.state != .ended)
            default: break
            }
        }
    }
}
