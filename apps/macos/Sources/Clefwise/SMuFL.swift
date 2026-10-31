import CoreGraphics

/// What Clefwise uses of SMuFL, the Standard Music Font Layout: the code points of the glyphs it
/// draws, and the engraving defaults and anchors from the metadata of Bravura 1.482 (the font in
/// `Resources/Fonts`). Every length is in staff spaces; anchors are as SMuFL gives them, y up from
/// the glyph's origin.
enum SMuFL {
    /// The glyphs Clefwise draws, by code point.
    enum Glyph: UInt32, CaseIterable {
        case brace = 0xE000

        case gClef = 0xE050
        case fClef = 0xE062
        /// The smaller clefs of a change partway through a bar.
        case gClefChange = 0xE07A
        case fClefChange = 0xE07C

        case timeSig0 = 0xE080, timeSig1, timeSig2, timeSig3, timeSig4, timeSig5, timeSig6, timeSig7, timeSig8, timeSig9
        case timeSigCommon = 0xE08A
        case timeSigCutCommon = 0xE08B

        case noteheadWhole = 0xE0A2
        case noteheadHalf = 0xE0A3
        case noteheadBlack = 0xE0A4

        case augmentationDot = 0xE1E7

        case flag8thUp = 0xE240, flag8thDown, flag16thUp, flag16thDown, flag32ndUp, flag32ndDown, flag64thUp, flag64thDown

        case accidentalFlat = 0xE260
        case accidentalNatural = 0xE261
        case accidentalSharp = 0xE262

        case restWhole = 0xE4E3, restHalf, restQuarter, rest8th, rest16th, rest32nd, rest64th

        /// "8va", "15ma", and "8vb" and "15mb" (Bravura's `ottavaBassa` reads "8va", for "8va bassa").
        case ottavaAlta = 0xE511
        case quindicesimaAlta = 0xE515
        case ottavaBassaVb = 0xE51C
        case quindicesimaBassaMb = 0xE51D

        /// A digit of a time signature.
        static func timeSignatureDigit(_ digit: Int) -> Glyph {
            Glyph(rawValue: Glyph.timeSig0.rawValue + UInt32(min(max(digit, 0), 9)))!
        }

        static func notehead(_ kind: NoteValue.Kind) -> Glyph {
            switch kind {
            case .whole: .noteheadWhole
            case .half: .noteheadHalf
            default: .noteheadBlack
            }
        }

        /// The flag glyph for `count` flags (1 for an eighth… 4 for a 64th), up or down; nil for none.
        static func flag(_ count: Int, up: Bool) -> Glyph? {
            guard count > 0 else { return nil }
            return Glyph(rawValue: Glyph.flag8thUp.rawValue + UInt32(2 * (min(count, 4) - 1) + (up ? 0 : 1)))
        }

        static func rest(_ kind: NoteValue.Kind) -> Glyph {
            switch kind {
            case .whole: .restWhole
            case .half: .restHalf
            case .quarter: .restQuarter
            case .eighth: .rest8th
            case .sixteenth: .rest16th
            case .thirtySecond: .rest32nd
            case .sixtyFourth: .rest64th
            }
        }

        static func accidental(_ accidental: Accidental) -> Glyph {
            switch accidental {
            case .sharp: .accidentalSharp
            case .flat: .accidentalFlat
            case .natural: .accidentalNatural
            }
        }

        static func clef(_ clef: Clef, change: Bool = false) -> Glyph {
            switch clef {
            case .treble: change ? .gClefChange : .gClef
            case .bass: change ? .fClefChange : .fClef
            }
        }

        /// The octave mark for a shift of 1 or 2 octaves up (positive) or down.
        static func octave(_ shift: Int) -> Glyph {
            switch shift {
            case 2...: .quindicesimaAlta
            case 1: .ottavaAlta
            case -1: .ottavaBassaVb
            default: .quindicesimaBassaMb
            }
        }
    }

    // MARK: - Engraving defaults (Bravura 1.482 `engravingDefaults`)

    static let staffLineThickness: CGFloat = 0.13
    static let stemThickness: CGFloat = 0.12
    static let legerLineThickness: CGFloat = 0.16
    static let legerLineExtension: CGFloat = 0.4
    static let thinBarlineThickness: CGFloat = 0.16
    static let thickBarlineThickness: CGFloat = 0.5
    static let thinThickBarlineSeparation: CGFloat = 0.4
    static let beamThickness: CGFloat = 0.5
    static let beamSpacing: CGFloat = 0.25
    static let tieEndpointThickness: CGFloat = 0.1
    static let tieMidpointThickness: CGFloat = 0.22
    static let octaveLineThickness: CGFloat = 0.16

    // MARK: - Anchors (Bravura 1.482 `glyphsWithAnchors`)

    /// Where an up stem's bottom right corner meets a black or half notehead (`stemUpSE`), from the
    /// head's origin (its left edge, on its line or space). A down stem's top left corner
    /// (`stemDownNW`, at 0, -0.168) mirrors it.
    static let noteheadStemUpSE = CGPoint(x: 1.18, y: 0.168)

    /// Where the stem ends, from the flag's origin (the stem's left edge at its nominal end): up
    /// flags give the top left corner (`stemUpNW`), down flags the bottom left (`stemDownSW`).
    /// A positive y lengthens an up stem past the flag's origin; for a down stem it shortens it.
    static func flagStemAnchor(_ count: Int, up: Bool) -> CGFloat {
        switch (min(max(count, 1), 4), up) {
        case (1, true): -0.04
        case (1, false): 0.132
        case (2, true): -0.088
        case (2, false): 0.128
        case (3, true): 0.376
        case (3, false): -0.448
        case (4, true): 1.172
        default: -1.244
        }
    }

    // MARK: - Bounding boxes (Bravura 1.482 `glyphBBoxes`), to check the font against

    /// South-west and north-east corners, y up.
    static let boundingBoxes: [Glyph: (sw: CGPoint, ne: CGPoint)] = [
        .brace: (CGPoint(x: 0, y: -0.002531), CGPoint(x: 0.277415, y: 4.00244)),
        .gClef: (CGPoint(x: 0, y: -2.632), CGPoint(x: 2.684, y: 4.392)),
        .fClef: (CGPoint(x: -0.02, y: -2.54), CGPoint(x: 2.736, y: 1.048)),
        .gClefChange: (CGPoint(x: 0, y: -1.82), CGPoint(x: 1.76, y: 2.828)),
        .fClefChange: (CGPoint(x: -0.06, y: -1.656), CGPoint(x: 1.852, y: 0.68)),
        .timeSig4: (CGPoint(x: 0.08, y: -1), CGPoint(x: 1.8, y: 1.004)),
        .timeSigCommon: (CGPoint(x: 0.02, y: -0.996), CGPoint(x: 1.696, y: 1.004)),
        .timeSigCutCommon: (CGPoint(x: 0, y: -1.436), CGPoint(x: 1.672, y: 1.444)),
        .noteheadWhole: (CGPoint(x: 0, y: -0.5), CGPoint(x: 1.688, y: 0.5)),
        .noteheadHalf: (CGPoint(x: 0, y: -0.5), CGPoint(x: 1.18, y: 0.5)),
        .noteheadBlack: (CGPoint(x: 0, y: -0.5), CGPoint(x: 1.18, y: 0.5)),
        .augmentationDot: (CGPoint(x: 0, y: -0.2), CGPoint(x: 0.4, y: 0.2)),
        .flag8thUp: (CGPoint(x: 0, y: -3.24), CGPoint(x: 1.056, y: 0.036)),
        .flag8thDown: (CGPoint(x: 0, y: -0.056), CGPoint(x: 1.224, y: 3.232)),
        .flag16thUp: (CGPoint(x: 0, y: -3.252), CGPoint(x: 1.116, y: 0.008)),
        .flag64thDown: (CGPoint(x: 0, y: -1.504), CGPoint(x: 1.092, y: 3.248)),
        .accidentalFlat: (CGPoint(x: 0, y: -0.7), CGPoint(x: 0.904, y: 1.756)),
        .accidentalNatural: (CGPoint(x: 0, y: -1.34), CGPoint(x: 0.672, y: 1.364)),
        .accidentalSharp: (CGPoint(x: 0, y: -1.392), CGPoint(x: 0.996, y: 1.4)),
        .restWhole: (CGPoint(x: 0, y: -0.54), CGPoint(x: 1.128, y: 0.036)),
        .restQuarter: (CGPoint(x: 0.004, y: -1.5), CGPoint(x: 1.08, y: 1.492)),
        .rest8th: (CGPoint(x: 0, y: -1.004), CGPoint(x: 0.988, y: 0.696)),
        .rest64th: (CGPoint(x: 0, y: -3.012), CGPoint(x: 1.692, y: 1.72)),
        .ottavaAlta: (CGPoint(x: 0, y: -0.04), CGPoint(x: 3.54, y: 1.852)),
        .ottavaBassaVb: (CGPoint(x: 0, y: -0.04), CGPoint(x: 3.184, y: 1.852)),
        .quindicesimaBassaMb: (CGPoint(x: 0, y: -0.04), CGPoint(x: 4.928, y: 1.844)),
    ]
}
