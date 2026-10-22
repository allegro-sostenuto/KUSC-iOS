/// Direction locking and release thresholds shared by both player panels.
/// Coordinates belong to the stationary viewport, not the moving panel.
struct PanelSwipeState {
    enum Axis { case horizontal, vertical }
    private(set) var axis: Axis?

    mutating func translation(x: Double, y: Double, width: Double) -> Double? {
        guard width > 0, x.isFinite, y.isFinite else { return nil }
        if axis == nil {
            guard max(abs(x), abs(y)) >= 12 else { return nil }
            axis = abs(x) > abs(y) * 1.6 ? .horizontal : .vertical
        }
        guard axis == .horizontal else { return nil }
        return min(width, max(-width, x))
    }

    /// Either sign switches panels. Small movements must not become a page
    /// change solely because a recognizer predicts a large release velocity.
    func releaseDirection(x: Double, predictedX: Double, width: Double) -> Int? {
        guard axis == .horizontal, width > 0, x.isFinite, predictedX.isFinite else { return nil }
        let threshold = min(120, max(65, width * 0.24))
        let farEnough = abs(x) >= threshold
        let flick = abs(x) >= 24 && abs(predictedX) >= threshold
            && (x > 0) == (predictedX > 0)
        guard farEnough || flick else { return nil }
        return x > 0 ? 1 : -1
    }
}
