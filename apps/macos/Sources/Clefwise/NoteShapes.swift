import SwiftUI

/// Note heads, flags, rests, dots and the brace from Bravura, and the ties drawn by hand, in staff
/// spaces: x to the right, y down, and the origin where each one is placed. `BarLayout` measures
/// the same paths `BarStaffView` draws, so what's laid out is what's inked.
enum NoteShapes {
    // MARK: - Note heads

    /// A black (or half) head's width.
    static let headWidth: CGFloat = 1.18

    static let stemWidth = SMuFL.stemThickness
    /// From the head's centre to the stem's centre: Bravura's stem anchors put the stem's outer edge
    /// on the head's edge.
    static var stemOffset: CGFloat { SMuFL.noteheadStemUpSE.x - headWidth / 2 - stemWidth / 2 }
    /// How far from the head's centre (along the stem) the stem starts.
    static var stemStart: CGFloat { SMuFL.noteheadStemUpSE.y }

    /// A head centred on the origin.
    static func head(_ kind: NoteValue.Kind) -> Path { heads[kind]! }

    /// The width a head takes on the staff.
    static func headInkWidth(_ kind: NoteValue.Kind) -> CGFloat { headInkWidths[kind]! }

    private static let heads = Dictionary(uniqueKeysWithValues: NoteValue.Kind.allCases.map { kind in
        let glyph = SMuFL.Glyph.notehead(kind)
        let box = MusicFont.bounds(glyph)
        return (kind, Path(MusicFont.outline(glyph)).offsetBy(dx: -box.midX, dy: 0))
    })
    private static let headInkWidths = heads.mapValues { $0.cgPath.boundingBoxOfPath.width }

    // MARK: - Flags and stems

    /// The flags for `count` flags on a stem going up or down, with the origin at the stem's left
    /// edge where its flag starts (SMuFL's flag origin). Empty for none.
    static func flags(_ count: Int, up: Bool) -> Path {
        guard let glyph = SMuFL.Glyph.flag(count, up: up) else { return Path() }
        return Path(MusicFont.outline(glyph))
    }

    /// Where `flags(count, up:)` is inked; nil for none.
    static func flagBounds(_ count: Int, up: Bool) -> CGRect? {
        count > 0 ? flagBoxes[2 * min(count, 4) + (up ? 1 : 0)] : nil
    }

    private static let flagBoxes = Dictionary(uniqueKeysWithValues: (1...4).flatMap { count in
        [true, false].map { up in
            (2 * count + (up ? 1 : 0), SMuFL.Glyph.flag(count, up: up).map(MusicFont.bounds) ?? .zero)
        }
    })

    /// How far a stem needs to reach past the head (to its flag's origin), before the middle-line rule.
    /// Bravura's flag anchors then lengthen 32nds' and 64ths' stems, whose flags reach past it.
    static func stemLength(flags count: Int) -> CGFloat { 3.5 }

    /// The least a stem may be shortened to where room runs out: its flags still clear the head.
    static func shortestStem(flags count: Int) -> CGFloat {
        switch count {
        case 0: 2.5
        case 1: 2.75
        default: 3
        }
    }

    // MARK: - Rests

    /// A rest centred on x = 0, with the origin on its reference line: the line a whole rest hangs
    /// from, the line a half rest sits on, the staff's middle line for the others in the usual place.
    static func rest(_ kind: NoteValue.Kind) -> Path { rests[kind]! }

    private static let rests = Dictionary(uniqueKeysWithValues: NoteValue.Kind.allCases.map { kind in
        let glyph = SMuFL.Glyph.rest(kind)
        let box = MusicFont.bounds(glyph)
        return (kind, Path(MusicFont.outline(glyph)).offsetBy(dx: -box.midX, dy: 0))
    })

    // MARK: - Dots, brace, ties

    static let dotRadius: CGFloat = 0.2

    /// An augmentation dot centred on the origin.
    static let dot: Path = {
        let box = MusicFont.bounds(.augmentationDot)
        return Path(MusicFont.outline(.augmentationDot)).offsetBy(dx: -box.midX, dy: -box.midY)
    }()

    /// The brace before a grand staff, `height` spaces tall with its right edge at the origin and
    /// its top at y = 0. Bravura's brace is one staff tall; it's stretched to the height, and widened
    /// less, so it stays slender.
    static func brace(height: CGFloat) -> Path {
        let box = MusicFont.bounds(.brace)
        guard box.height > 0 else { return Path() }
        let scaleY = height / box.height
        let scaleX = scaleY.squareRoot() * 1.6
        return Path(MusicFont.outline(.brace)).applying(CGAffineTransform(translationX: -box.maxX, y: -box.minY)
            .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY)))
    }

    /// A tie from `start` to `end` (points), bowing up or down by about a third of a space plus a
    /// little for its length: 0.22 spaces thick in the middle and 0.1 at its rounded ends, as
    /// Bravura's engraving defaults have it.
    static func tie(from start: CGPoint, to end: CGPoint, up: Bool, space: CGFloat) -> Path {
        let length = abs(end.x - start.x)
        let height = min(space * 0.75, space * 0.28 + length * 0.07) * (up ? -1 : 1)
        let endpoint = SMuFL.tieEndpointThickness * space
        // The crescent is drawn thinner by the end thickness, then outlined with it.
        let thickness = (SMuFL.tieMidpointThickness * space - endpoint) * (up ? -1 : 1)
        func control(_ t: CGFloat, _ lift: CGFloat) -> CGPoint {
            CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t + lift * 4 / 3)
        }
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control(0.2, height), control2: control(0.8, height))
        path.addCurve(to: start, control1: control(0.8, height - thickness), control2: control(0.2, height - thickness))
        path.closeSubpath()
        return path.union(path.strokedPath(StrokeStyle(lineWidth: endpoint, lineCap: .round, lineJoin: .round)))
    }
}
