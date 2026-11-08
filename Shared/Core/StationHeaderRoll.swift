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

    /// External next/previous commands also cross the saved-order seam by the
    /// shortest route instead of resetting or rolling through the catalogue.
    static func position(selecting index: Int, from current: Double, count: Int) -> Double? {
        guard count > 0, (0..<count).contains(index), current.isFinite else { return nil }
        let wrapped = current.truncatingRemainder(dividingBy: Double(count))
        let forward = (Double(index) - wrapped).truncatingRemainder(dividingBy: Double(count))
        let positive = forward < 0 ? forward + Double(count) : forward
        let delta = positive <= Double(count) / 2 ? positive : positive - Double(count)
        return current + delta
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
