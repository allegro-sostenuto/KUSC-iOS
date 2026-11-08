import Foundation

/// Direction locking and release thresholds shared by both player panels.
/// Coordinates belong to the stationary viewport, not the moving panel.
struct PanelSwipeState {
    enum Axis { case horizontal, vertical }
    private(set) var axis: Axis?

    mutating func translation(x: Double, y: Double, width: Double) -> Double? {
        guard width > 0, x.isFinite, y.isFinite else { return nil }
        if axis == nil {
            guard max(abs(x), abs(y)) >= 6 else { return nil }
            axis = abs(x) > abs(y) * 1.15 ? .horizontal : .vertical
        }
        guard axis == .horizontal else { return nil }
        return min(width, max(-width, x))
    }

    /// Odd analytic hand coupling, x - a*tanh(x/l), normalized at the bounds.
    /// Its interior is C-infinity through zero, with initial slope near 5/6.
    /// Resistance costs at most 3 pt; only the viewport endpoints clamp.
    static func resistedTranslation(_ x: Double, width: Double) -> Double {
        guard width > 0, width.isFinite, x.isFinite else { return 0 }
        let distance = min(width, abs(x))
        let amplitude = min(3, width * 0.01)
        let length = max(amplitude * 6, 1)
        let full = width - amplitude * tanh(width / length)
        let position = (distance - amplitude * tanh(distance / length)) * width / full
        return x < 0 ? -position : position
    }

    /// Convert native finger velocity to the resisted panel's velocity before
    /// handing the interaction to Apple's spring. Endpoint clamping is allowed.
    static func resistedVelocity(_ velocity: Double, at x: Double, width: Double) -> Double {
        guard width > 0, width.isFinite, x.isFinite, velocity.isFinite else { return 0 }
        let amplitude = min(3, width * 0.01)
        let length = max(amplitude * 6, 1)
        let normalization = width / (width - amplitude * tanh(width / length))
        let slope = (1 - amplitude / length * (1 - pow(tanh(x / length), 2))) * normalization
        return velocity * slope
    }

    /// C-infinity on the real line, including its flat endpoint extensions:
    /// b(t) = exp(-1/t) for t > 0, otherwise 0; h = b(p)/(b(p)+b(1-p)).
    /// Equivalently, Boltzmann weights smoothly favor the two label positions.
    /// Evaluate via log odds so very small distances cannot produce 0/0.
    static func headerProgress(_ p: Double) -> Double {
        guard p.isFinite, p > 0 else { return 0 }
        guard p < 1 else { return 1 }
        let odds = 1 / p - 1 / (1 - p)
        if odds >= 0 {
            let weight = exp(-odds)
            return weight / (1 + weight)
        }
        return 1 / (1 + exp(odds))
    }

    /// Either sign switches panels. Small movements must not become a page
    /// change solely because a recognizer predicts a large release velocity.
    func releaseDirection(x: Double, predictedX: Double, width: Double) -> Int? {
        guard axis == .horizontal, width > 0, x.isFinite, predictedX.isFinite else { return nil }
        let threshold = min(90, max(52, width * 0.20))
        let farEnough = abs(x) >= threshold
        let flick = abs(x) >= 18 && abs(predictedX) >= threshold
            && (x > 0) == (predictedX > 0)
        guard farEnough || flick else { return nil }
        return x > 0 ? 1 : -1
    }
}
