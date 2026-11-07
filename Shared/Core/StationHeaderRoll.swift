import Foundation

/// An unwrapped catalogue position keeps successive and reversed button taps
/// continuous, including crossing the last/first station boundary.
struct StationHeaderRoll {
    struct Layout {
        let upperIndex: Int
        let lowerIndex: Int
        let upperOffset: Double
        let lowerOffset: Double
    }

    static func layout(position: Double, count: Int, height: Double = 44) -> Layout? {
        guard count > 0, position.isFinite, height.isFinite, height > 0 else { return nil }
        let wrapped = position.truncatingRemainder(dividingBy: Double(count))
        let whole = floor(wrapped)
        let index = (Int(whole) + count) % count
        let roll = PanelSwipeState.headerProgress(wrapped - whole)
        return Layout(upperIndex: index, lowerIndex: (index + 1) % count,
                      upperOffset: -roll * height, lowerOffset: (1 - roll) * height)
    }
}
