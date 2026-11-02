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
        #if DEBUG
        let previous = context.coordinator.configuration
        if previous.enabled != enabled || previous.opening != opening {
            PanelGestureTrace.record("configuration enabled=\(enabled), opening=\(opening)")
        }
        #endif
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
        #if DEBUG
        private var tracedBounds: CGRect?
        override func layoutSubviews() {
            super.layoutSubviews()
            if tracedBounds != bounds {
                tracedBounds = bounds
                PanelGestureTrace.record("marker layout bounds=\(bounds), window=\(window != nil)")
            }
        }
        #endif
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
            #if DEBUG
            PanelGestureTrace.snapshot = { [weak self] in
                guard let self else { return "coordinator unavailable" }
                return "snapshot enabled=\(self.configuration.enabled), opening=\(self.configuration.opening), nativeEnabled=\(self.pan.isEnabled), nativeAttached=\(self.pan.view != nil), sameWindow=\(self.pan.view === self.attachedWindow), state=\(self.pan.state.rawValue), active=\(self.active), bounds=\(String(describing: self.marker?.bounds))"
            }
            #endif
            guard attachedWindow !== view.window else { return }
            attachedWindow?.removeGestureRecognizer(pan)
            attachedWindow = view.window
            view.window?.addGestureRecognizer(pan)
            #if DEBUG
            PanelGestureTrace.record("attach window=\(view.window != nil), nativeAttached=\(pan.view === view.window), enabled=\(configuration.enabled), opening=\(configuration.opening), bounds=\(view.bounds)")
            #endif
        }

        func detach() {
            attachedWindow?.removeGestureRecognizer(pan)
            attachedWindow = nil
            marker = nil
            #if DEBUG
            PanelGestureTrace.record("detach")
            #endif
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            #if DEBUG
            let point = marker.map { touch.location(in: $0) }
            let eligible = configuration.enabled && marker?.window != nil &&
                point.map { marker?.bounds.contains($0) == true } == true
            PanelGestureTrace.record("receive=\(eligible), enabled=\(configuration.enabled), point=\(String(describing: point)), bounds=\(String(describing: marker?.bounds)), touch=\(String(describing: touch.view.map { type(of: $0) }))")
            #endif
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
            guard configuration.enabled else {
                #if DEBUG
                PanelGestureTrace.record("shouldBegin=false: disabled")
                #endif
                return false
            }
            let distance = pan.translation(in: marker)
            let velocity = pan.velocity(in: marker)
            let intent = abs(distance.x) + abs(distance.y) > 1 ? distance : velocity
            let begin = abs(intent.x) > abs(intent.y) * 1.15 &&
                (configuration.opening ? intent.x > 0 : intent.x < 0)
            #if DEBUG
            PanelGestureTrace.record("shouldBegin=\(begin), opening=\(configuration.opening), distance=\(distance), velocity=\(velocity), intent=\(intent)")
            #endif
            return begin
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let scroll = other.view as? UIScrollView else {
                #if DEBUG
                PanelGestureTrace.record("dynamic priority=false: \(type(of: other)), view=\(String(describing: other.view.map { type(of: $0) }))")
                #endif
                return false
            }
            let required = other === scroll.panGestureRecognizer
            #if DEBUG
            PanelGestureTrace.record("dynamic priority=\(required): \(type(of: other)), scroll=\(type(of: scroll))")
            #endif
            return required
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            let x = recognizer.translation(in: marker).x
            switch recognizer.state {
            case .began:
                active = true
                #if DEBUG
                PanelGestureTrace.record("began x=\(x)")
                #endif
                // Stop any existing vertical deceleration before dragging sideways.
                if let scroll = touchedScroll { scroll.setContentOffset(scroll.contentOffset, animated: false) }
                configuration.changed(x)
            case .changed:
                configuration.changed(x)
            case .ended, .cancelled, .failed:
                #if DEBUG
                PanelGestureTrace.record("finish state=\(recognizer.state.rawValue), active=\(active), x=\(x), velocity=\(recognizer.velocity(in: marker))")
                #endif
                guard active else { return }
                active = false
                configuration.ended(x, recognizer.velocity(in: marker).x, recognizer.state != .ended)
            default: break
            }
        }
    }
}

#if DEBUG
/// A native accessibility value queried on demand, with no published changes or
/// gesture-time SwiftUI invalidations. It is absent from Release builds.
enum PanelGestureTrace {
    private static var events: [String] = []
    static var snapshot: (() -> String)?
    static var value: String { ([snapshot?() ?? "snapshot unavailable"] + events).joined(separator: "\n") }
    static func record(_ event: String) {
        guard ProcessInfo.processInfo.environment["PHILHARMONIC_UI_STATE"] != nil else { return }
        events.append(event)
        if events.count > 80 { events.removeFirst(events.count - 80) }
    }
}

struct PanelGestureTraceProbe: UIViewRepresentable {
    final class Probe: UIView {
        override var accessibilityValue: String? {
            get { PanelGestureTrace.value }
            set { }
        }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "panel-gesture-trace"
        view.accessibilityLabel = "Panel gesture trace"
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { }
}
#endif
