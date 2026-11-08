import SwiftUI

/// Keep system transitions in charge. The bespoke player reveal and header use
/// the same native, critically damped interpolating spring as before.
enum NativeMotion {
    static func player(initialVelocity: Double = 0) -> Animation {
        .interpolatingSpring(mass: 1, stiffness: 380, damping: 2 * sqrt(380),
                             initialVelocity: initialVelocity)
    }
}

/// The public SF Symbol replacement can fall back to replacing whole glyphs.
/// This app-specific transport shape instead changes the actual two outlines.
struct TransportPlayPauseGlyph: Shape {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let geometry = TransportGlyphGeometry(progress: progress)
        func point(_ value: TransportGlyphGeometry.Point) -> CGPoint {
            .init(x: rect.minX + CGFloat(value.x) * rect.width, y: rect.minY + CGFloat(value.y) * rect.height)
        }
        var path = Path()
        for outline in geometry.outlines {
            for index in outline.indices {
                let vertex = outline[index]
                let previous = outline[(index + outline.count - 1) % outline.count]
                let next = outline[(index + 1) % outline.count]
                let incoming = point(vertex.toward(previous, by: geometry.rounding))
                let outgoing = point(vertex.toward(next, by: geometry.rounding))
                if index == 0 { path.move(to: incoming) } else { path.addLine(to: incoming) }
                path.addQuadCurve(to: outgoing, control: point(vertex))
            }
            path.closeSubpath()
        }
        return path
    }
}

/// Native symbol replacement animates glyphs in place, leaving the surrounding
/// transport geometry fixed. Older systems retain the existing static glyph.
struct NativeSymbolReplacement<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    @ViewBuilder func body(content: Content) -> some View {
        if !reduceMotion, #available(iOS 18.0, *) {
            content.contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .animation(.default, value: value)
        } else if !reduceMotion, #available(iOS 17.0, *) {
            content.contentTransition(.symbolEffect(.replace))
                .animation(.default, value: value)
        } else {
            content
        }
    }
}

struct NativeNumberTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double

    @ViewBuilder func body(content: Content) -> some View {
        if !reduceMotion, #available(iOS 17.0, *) {
            content.contentTransition(.numericText(value: value))
                .animation(.default, value: value)
        } else {
            content
        }
    }
}
