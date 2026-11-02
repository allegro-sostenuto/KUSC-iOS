import UIKit

/// Program is a portrait-only list; the artwork player supports both orientations.
@MainActor enum PlayerOrientation {
    private static var programmeVisible = false
    static var supported: UIInterfaceOrientationMask {
        programmeVisible ? .portrait : .allButUpsideDown
    }

    static func setProgrammeVisible(_ visible: Bool) {
        guard programmeVisible != visible else { return }
        programmeVisible = visible
        refresh()
    }

    static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            where scene.activationState == .foregroundActive &&
                scene.session.role == .windowApplication {
            scene.windows.first(where: { $0.isKeyWindow })?.rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: supported)) { error in
                #if DEBUG
                print("Player orientation request: \(error.localizedDescription)")
                #endif
            }
        }
    }
}
