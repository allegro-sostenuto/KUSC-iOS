import Foundation

/// Two corresponding convex outlines split a play triangle into pause bars.
/// Every interior vertex/control point varies smoothly, with no alpha blend.
struct TransportGlyphGeometry {
    struct Point: Equatable {
        let x: Double
        let y: Double
        func toward(_ other: Self, by fraction: Double) -> Self {
            .init(x: x + (other.x - x) * fraction, y: y + (other.y - y) * fraction)
        }
    }
    let outlines: [[Point]]
    let rounding: Double

    init(progress: Double) {
        let amount = PanelSwipeState.headerProgress(progress)
        let play: [[Point]] = [
            [.init(x: 0.2, y: 0.08), .init(x: 0.58, y: 0.29),
             .init(x: 0.58, y: 0.71), .init(x: 0.2, y: 0.92)],
            [.init(x: 0.58, y: 0.29), .init(x: 0.96, y: 0.5),
             .init(x: 0.96, y: 0.5), .init(x: 0.58, y: 0.71)]
        ]
        let pause: [[Point]] = [
            [.init(x: 0.2, y: 0.08), .init(x: 0.42, y: 0.08),
             .init(x: 0.42, y: 0.92), .init(x: 0.2, y: 0.92)],
            [.init(x: 0.58, y: 0.08), .init(x: 0.8, y: 0.08),
             .init(x: 0.8, y: 0.92), .init(x: 0.58, y: 0.92)]
        ]
        outlines = zip(play, pause).map { pair in
            zip(pair.0, pair.1).map { vertex in vertex.0.toward(vertex.1, by: amount) }
        }
        rounding = 0.14 * amount
    }
}
