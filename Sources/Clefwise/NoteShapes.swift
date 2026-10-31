import SwiftUI

/// Outlines Apple Symbols doesn't have (note heads, flags, rests, the brace, ties), drawn in staff
/// spaces: x to the right, y down, and the origin where each one is placed. `BarLayout` measures
/// the same paths `BarStaffView` draws, so what's laid out is what's inked.
enum NoteShapes {
    // MARK: - Note heads

    /// Black and half-note heads: `StaffView`'s slightly tilted oval.
    static let headWidth: CGFloat = 1.32
    static let headHeight: CGFloat = 0.94
    static let headTilt: CGFloat = -.pi / 9
    static let wholeWidth: CGFloat = 1.62
    static let wholeHeight: CGFloat = 0.98

    static let stemWidth: CGFloat = 0.12
    /// From the head's centre to the stem's centre, as `StaffView` sets it.
    static var stemOffset: CGFloat { headWidth / 2 - stemWidth / 2 - 0.02 }

    /// A head centred on the origin. Halves are hollow, with a narrower, steeper counter; wholes are
    /// wider and upright, with a counter tilted the other way.
    static func head(_ kind: NoteValue.Kind) -> Path { heads[kind]! }

    /// The width a head takes on the staff.
    static func headInkWidth(_ kind: NoteValue.Kind) -> CGFloat { headInkWidths[kind]! }

    // Built once: hollow heads, rests and flags take path operations.
    private static let heads = Dictionary(uniqueKeysWithValues: NoteValue.Kind.allCases.map { ($0, makeHead($0)) })
    private static let headInkWidths = heads.mapValues { $0.cgPath.boundingBoxOfPath.width }
    private static let rests = Dictionary(uniqueKeysWithValues: NoteValue.Kind.allCases.map { ($0, makeRest($0)) })
    private static let flagPaths = (0...4).map(makeFlags)

    private static func makeHead(_ kind: NoteValue.Kind) -> Path {
        switch kind {
        case .whole:
            let outline = Path(ellipseIn: CGRect(x: -wholeWidth / 2, y: -wholeHeight / 2, width: wholeWidth, height: wholeHeight))
            let counter = Path(ellipseIn: CGRect(x: -0.4, y: -0.25, width: 0.8, height: 0.5))
                .applying(CGAffineTransform(rotationAngle: .pi / 3.4))
            return outline.subtracting(counter)
        case .half:
            let counter = Path(ellipseIn: CGRect(x: -0.52, y: -0.2, width: 1.04, height: 0.4))
                .applying(CGAffineTransform(rotationAngle: -.pi / 5.2))
            return blackHead.subtracting(counter)
        default:
            return blackHead
        }
    }

    private static let blackHead = Path(ellipseIn: CGRect(x: -headWidth / 2, y: -headHeight / 2, width: headWidth, height: headHeight))
        .applying(CGAffineTransform(rotationAngle: headTilt))

    // MARK: - Flags

    /// Flags for a stem going up (y down from the stem's tip), starting at the stem's left edge so
    /// they merge with it; mirror them vertically for a stem going down. `count` flags, each further
    /// down the stem.
    static func flags(_ count: Int) -> Path { flagPaths[min(max(count, 0), 4)] }

    private static func makeFlags(_ count: Int) -> Path {
        var path = Path()
        guard count > 0 else { return path }
        for index in 0..<count {
            let flag = count == 1 ? eighthFlag : compactFlag
            path.addPath(flag.applying(CGAffineTransform(translationX: 0, y: CGFloat(index) * flagSpacing)))
        }
        return path
    }

    /// How far a stem needs to reach past the head for `count` flags, before the middle-line rule.
    static func stemLength(flags count: Int) -> CGFloat {
        count <= 1 ? 3.5 : max(3.5, CGFloat(count - 1) * flagSpacing + compactFlagHeight + 0.75)
    }

    /// The least a stem may be shortened to where room runs out: its flags still clear the head.
    static func shortestStem(flags count: Int) -> CGFloat {
        switch count {
        case 0: 2.5
        case 1: 2.75
        default: CGFloat(count - 1) * flagSpacing + compactFlagHeight + 0.2
        }
    }

    static let flagSpacing: CGFloat = 0.78
    private static let compactFlagHeight: CGFloat = 2.25

    private static let eighthFlag: Path = {
        var path = Path()
        let s = -stemWidth
        path.move(to: CGPoint(x: s, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 0.98, y: 1.95), control1: CGPoint(x: 0.1, y: 0.9), control2: CGPoint(x: 1.1, y: 1.05))
        path.addCurve(to: CGPoint(x: 0.6, y: 3.0), control1: CGPoint(x: 0.92, y: 2.45), control2: CGPoint(x: 0.8, y: 2.75))
        path.addCurve(to: CGPoint(x: 0.76, y: 2.0), control1: CGPoint(x: 0.74, y: 2.66), control2: CGPoint(x: 0.82, y: 2.35))
        path.addCurve(to: CGPoint(x: 0, y: 0.95), control1: CGPoint(x: 0.68, y: 1.5), control2: CGPoint(x: 0.25, y: 1.22))
        path.addLine(to: CGPoint(x: s, y: 0.95))
        path.closeSubpath()
        return path
    }()

    private static let compactFlag: Path = {
        var path = Path()
        let s = -stemWidth
        path.move(to: CGPoint(x: s, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 0.95, y: 1.45), control1: CGPoint(x: 0.12, y: 0.7), control2: CGPoint(x: 1.05, y: 0.82))
        path.addCurve(to: CGPoint(x: 0.66, y: compactFlagHeight), control1: CGPoint(x: 0.92, y: 1.8), control2: CGPoint(x: 0.82, y: 2.05))
        path.addCurve(to: CGPoint(x: 0.76, y: 1.5), control1: CGPoint(x: 0.76, y: 1.98), control2: CGPoint(x: 0.82, y: 1.72))
        path.addCurve(to: CGPoint(x: 0, y: 0.72), control1: CGPoint(x: 0.68, y: 1.15), control2: CGPoint(x: 0.25, y: 0.95))
        path.addLine(to: CGPoint(x: s, y: 0.72))
        path.closeSubpath()
        return path
    }()

    // MARK: - Rests

    /// A rest with the origin at its reference: the line a whole rest hangs from, the line a half
    /// rest sits on, the middle of the others (the staff's middle line in the usual place).
    static func rest(_ kind: NoteValue.Kind) -> Path { rests[kind]! }

    private static func makeRest(_ kind: NoteValue.Kind) -> Path {
        switch kind {
        case .whole: Path(CGRect(x: -0.6, y: 0, width: 1.2, height: 0.5))
        case .half: Path(CGRect(x: -0.6, y: -0.5, width: 1.2, height: 0.5))
        case .quarter: quarterRest
        case .eighth: hookedRest(1)
        case .sixteenth: hookedRest(2)
        case .thirtySecond: hookedRest(3)
        case .sixtyFourth: hookedRest(4)
        }
    }

    private static let quarterRest: Path = {
        // A thin stroke down to the right, a heavy one back down to the left, a thin one down to the
        // right again, and a hook curling back underneath: one outline, clockwise from the top.
        var path = Path()
        path.move(to: CGPoint(x: -0.3, y: -1.5))
        path.addLine(to: CGPoint(x: 0.5, y: -0.6))
        path.addQuadCurve(to: CGPoint(x: 0.02, y: 0.1), control: CGPoint(x: 0.1, y: -0.24))
        path.addLine(to: CGPoint(x: 0.44, y: 0.68))
        path.addCurve(to: CGPoint(x: -0.34, y: 0.78), control1: CGPoint(x: 0.12, y: 0.5), control2: CGPoint(x: -0.32, y: 0.48))
        path.addCurve(to: CGPoint(x: 0.14, y: 1.5), control1: CGPoint(x: -0.36, y: 1.06), control2: CGPoint(x: -0.1, y: 1.32))
        path.addCurve(to: CGPoint(x: -0.04, y: 0.98), control1: CGPoint(x: 0.0, y: 1.32), control2: CGPoint(x: -0.1, y: 1.14))
        path.addCurve(to: CGPoint(x: 0.26, y: 0.9), control1: CGPoint(x: 0.0, y: 0.86), control2: CGPoint(x: 0.14, y: 0.84))
        path.addLine(to: CGPoint(x: -0.48, y: -0.04))
        path.addQuadCurve(to: CGPoint(x: 0.06, y: -0.82), control: CGPoint(x: 0.0, y: -0.36))
        path.addLine(to: CGPoint(x: -0.42, y: -1.4))
        path.addQuadCurve(to: CGPoint(x: -0.3, y: -1.5), control: CGPoint(x: -0.4, y: -1.48))
        path.closeSubpath()
        return path
    }()

    /// Eighth to 64th rests: a slanted stem with a hook and a blob for each flag. Wider values
    /// add hooks upwards, so the lowest blob stays in the space below the middle line.
    private static func hookedRest(_ hooks: Int) -> Path {
        let lowest: CGFloat = hooks == 1 ? -0.5 : 0.5
        let bottom = lowest + 1.55
        let topBlob = lowest - CGFloat(hooks - 1)
        let stemTop = CGPoint(x: 0.45 + 0.24 * CGFloat(hooks - 1), y: topBlob - 0.22)
        let slope = (stemTop.x - (-0.1)) / (bottom - stemTop.y)
        func stemX(at y: CGFloat) -> CGFloat { stemTop.x - (y - stemTop.y) * slope }

        var stem = Path()
        stem.move(to: stemTop)
        stem.addLine(to: CGPoint(x: -0.1, y: bottom))
        var path = stem.strokedPath(StrokeStyle(lineWidth: 0.15, lineCap: .round))
        for index in 0..<hooks {
            let blobY = lowest - CGFloat(index)
            let joinY = blobY - 0.22
            let join = CGPoint(x: stemX(at: joinY), y: joinY)
            let blob = CGPoint(x: join.x - 0.74, y: blobY)
            var hook = Path()
            hook.move(to: CGPoint(x: blob.x + 0.08, y: blob.y + 0.2))
            hook.addCurve(to: join, control1: CGPoint(x: blob.x + 0.4, y: blob.y + 0.26),
                          control2: CGPoint(x: join.x - 0.18, y: join.y + 0.05))
            path = path.union(hook.strokedPath(StrokeStyle(lineWidth: 0.13, lineCap: .round)))
            path = path.union(Path(ellipseIn: CGRect(x: blob.x - 0.24, y: blob.y - 0.22, width: 0.48, height: 0.46)))
        }
        return path
    }

    // MARK: - Brace, ties, dots

    /// The brace before a grand staff, `height` spaces tall with its right edge at the origin and
    /// its top at y = 0.
    static func brace(height: CGFloat) -> Path {
        let w: CGFloat = 1.0
        let h = height
        var path = Path()
        // The upper half, then the lower half mirrored about the middle, where it comes to a point.
        func half(_ y: (CGFloat) -> CGFloat) {
            path.move(to: CGPoint(x: 0, y: y(0)))
            path.addCurve(to: CGPoint(x: -w * 0.68, y: y(0.2)), control1: CGPoint(x: -w * 0.66, y: y(0.02)),
                          control2: CGPoint(x: -w * 0.7, y: y(0.1)))
            path.addCurve(to: CGPoint(x: -w, y: y(0.5)), control1: CGPoint(x: -w * 0.66, y: y(0.36)),
                          control2: CGPoint(x: -w * 0.66, y: y(0.47)))
            path.addCurve(to: CGPoint(x: -w * 0.26, y: y(0.22)), control1: CGPoint(x: -w * 0.38, y: y(0.46)),
                          control2: CGPoint(x: -w * 0.24, y: y(0.36)))
            path.addCurve(to: CGPoint(x: 0, y: y(0)), control1: CGPoint(x: -w * 0.28, y: y(0.08)),
                          control2: CGPoint(x: -w * 0.18, y: y(0.015)))
            path.closeSubpath()
        }
        half { $0 * h }
        half { (1 - $0) * h }
        return path
    }

    /// A tie from `start` to `end` (points), bowing up or down by about a third of a space plus a
    /// little for its length, thickest in the middle.
    static func tie(from start: CGPoint, to end: CGPoint, up: Bool, space: CGFloat) -> Path {
        let length = abs(end.x - start.x)
        let height = min(space * 0.75, space * 0.28 + length * 0.07) * (up ? -1 : 1)
        let thickness = space * 0.13 * (up ? -1 : 1)
        func control(_ t: CGFloat, _ lift: CGFloat) -> CGPoint {
            CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t + lift * 4 / 3)
        }
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control(0.2, height), control2: control(0.8, height))
        path.addCurve(to: start, control1: control(0.8, height - thickness), control2: control(0.2, height - thickness))
        path.closeSubpath()
        return path
    }

    static let dotRadius: CGFloat = 0.2
}
