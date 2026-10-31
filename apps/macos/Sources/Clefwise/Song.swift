import Foundation

/// A piece read from a MusicXML file.
struct Score {
    let title: String
    /// Parts that have at least one note we can practise ("Piano", "Voice"…), in score order.
    let parts: [ScorePart]
}

struct ScorePart {
    let name: String
    /// Every note to read, in reading order: by onset, then lower staff first, then low to high.
    let notes: [ScoreNote]
    /// Every bar as it's drawn, for the bar view: `measures[n - 1]` is bar n, one for each
    /// `<measure>`. Empty for scores built without one (tests), which show one note at a time.
    var measures: [ScoreMeasure] = []
    let measureCount: Int
    /// 1 for a single staff, 2 for a piano-style grand staff.
    let staffCount: Int
    /// Notes left out because we can't show them (other clefs, double sharps, microtones…).
    let skippedNoteCount: Int

    /// The bar `note` is in and the index of its symbol there; nil when the part has no bar
    /// layout or the note has no symbol.
    func symbol(for note: ScoreNote) -> (measure: ScoreMeasure, index: Int)? {
        guard let index = note.symbolIndex, measures.indices.contains(note.measure - 1) else { return nil }
        let measure = measures[note.measure - 1]
        return measure.symbols.indices.contains(index) ? (measure, index) : nil
    }
}

struct ScoreNote: Hashable {
    /// As played: an 8va passage is already an octave up here.
    let pitch: Pitch
    let clef: Clef
    let keySignature: KeySignature
    /// Sign to print before the note when it's shown on its own: the score's own, or one added
    /// because an accidental earlier in the bar changed this note from the key signature (that
    /// bar context isn't on screen). The bar view prints its symbol's `accidental` instead.
    let printedAccidental: Accidental?
    /// Octaves the note is written below how it sounds: 1 under 8va, -1 under 8vb, 0 normally.
    let octaveShift: Int
    /// 1 = upper staff (right hand on piano), 2 = lower staff.
    let staff: Int
    /// Bar number counted from the start of the piece, 1-based (not the printed number).
    let measure: Int
    /// When the note starts, in quarter notes from the beginning of the piece.
    let onset: Double
    /// Notes struck together on one staff share a chord id; a single note has one of its own.
    let chord: Int
    /// Where the note is drawn: its index in `ScorePart.measures[measure - 1].symbols`. nil
    /// when the part has no bar layout.
    var symbolIndex: Int? = nil

    var question: Question {
        Question(clef: clef, pitch: pitch, keySignature: keySignature,
                 printedAccidental: printedAccidental, octaveShift: octaveShift)
    }
}

// MARK: - Bars as drawn

/// One bar of a part as the bar view draws it: every note and rest on every staff.
struct ScoreMeasure: Hashable {
    /// What a staff starts the bar with.
    struct StaffStart: Hashable {
        /// nil for a clef Clefwise can't draw (alto, tenor…): the bar view can't show this staff.
        let clef: Clef?
        let keySignature: KeySignature
    }

    /// 1-based, counted from the start of the part like `ScoreNote.measure` (not the printed number).
    let number: Int
    /// When the bar starts, in quarter notes from the beginning of the piece (as `ScoreNote.onset`).
    let start: Double
    /// How long it lasts, in quarter notes: as long as its longest voice, so a pickup bar is short.
    let length: Double
    /// Clef and key in force on each staff as the bar starts: `staves[0]` is staff 1. One entry
    /// for every staff the part has.
    let staves: [StaffStart]
    /// Every note and rest drawn in the bar, on all staves: by offset, then staff, then voice,
    /// then low to high (rests before notes at the same offset and voice).
    let symbols: [BarSymbol]
}

/// A note or rest as drawn in a bar. Notes the bar view can't draw are left out, like the
/// questions: double sharps and flats, notes under a clef Clefwise can't show, grace and cue
/// notes, and anything the score hides.
struct BarSymbol: Hashable {
    /// As played (an 8va passage is already an octave up); nil for a rest.
    let pitch: Pitch?
    /// The clef in force where it stands on its staff; a bar can change clef partway.
    let clef: Clef
    /// 1 = upper staff, 2 = lower.
    let staff: Int
    /// The score's voice (1 when it names none). Each voice on a staff has its own stems and rests.
    let voice: Int
    /// When it starts, in quarter notes from the start of the bar.
    let offset: Double
    /// How long it lasts, in quarter notes (a triplet eighth is 1/3, though it's written as an eighth).
    let duration: Double
    /// How it's written: the note's shape and its dots.
    let value: NoteValue
    /// Octaves written below how it sounds: 1 under 8va, -1 under 8vb, 0 normally.
    let octaveShift: Int
    /// The sign printed before the note in the bar: the score's own, or failing that the one
    /// the usual rule needs (a sign holds for that letter and octave on its staff until the bar
    /// line; tied-over notes keep theirs without printing it). nil for none, and for rests.
    let accidental: Accidental?
    /// The score's stem direction; nil when it gives none (or none applies): work it out.
    let stemUp: Bool?
    /// Notes struck together on one staff and voice share a chord id (the same id as their
    /// `ScoreNote`s); a single note or rest has one of its own.
    let chord: Int
    /// Tied over to the next note of the same pitch, possibly in the next bar.
    let tiedToNext: Bool
    /// The held-over end of a tie: drawn, but not asked, since it isn't played again.
    let tiedFromPrevious: Bool
    /// Rests only: the staff position the score puts it on (`<display-step>` and
    /// `<display-octave>`); nil for the usual place.
    let restPosition: Int?
    /// A rest that fills the whole bar, drawn as a whole rest in the middle of the bar whatever
    /// the time signature (`<rest measure="yes">`, or a rest lasting the whole bar with no type).
    let isWholeBarRest: Bool

    var isRest: Bool { pitch == nil }

    /// As played but moved down by `octaveShift` octaves: where the note sits on the staff.
    var writtenPitch: Pitch? {
        pitch.map { Pitch($0.letter, $0.octave - octaveShift, $0.accidental) }
    }

    /// Staff position of the note (0 = bottom line, as `Question.position`); nil for a rest.
    var position: Int? { writtenPitch.map(clef.position(of:)) }
}

/// How a note or rest is written: its shape (whole, half, quarter, eighth…) and its dots.
struct NoteValue: Hashable {
    /// The value as a fraction of a whole note: a quarter is 4. Longer notes (breves) are
    /// written as wholes, shorter than 64ths as 64ths. Longer values compare greater.
    enum Kind: Int, CaseIterable, Comparable {
        case whole = 1, half = 2, quarter = 4, eighth = 8, sixteenth = 16, thirtySecond = 32, sixtyFourth = 64

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue > rhs.rawValue }

        /// From a MusicXML `<type>` ("quarter", "16th"…); nil for anything else.
        init?(musicXMLType type: String) {
            switch type {
            case "maxima", "long", "breve", "whole": self = .whole
            case "half": self = .half
            case "quarter": self = .quarter
            case "eighth": self = .eighth
            case "16th": self = .sixteenth
            case "32nd": self = .thirtySecond
            case "64th", "128th", "256th", "512th", "1024th": self = .sixtyFourth
            default: return nil
            }
        }

        /// Length in quarter notes, undotted.
        var quarters: Double { 4 / Double(rawValue) }
    }

    let kind: Kind
    let dots: Int

    init(_ kind: Kind, dots: Int = 0) {
        self.kind = kind
        self.dots = dots
    }

    /// Written length in quarter notes, dots included: a dotted half is 3. Tuplets sound
    /// shorter than written; `BarSymbol.duration` has that.
    var quarters: Double { kind.quarters * (2 - pow(0.5, Double(dots))) }
    /// Whole and half notes have hollow heads.
    var isHollow: Bool { kind >= .half }
    var hasStem: Bool { kind != .whole }
    /// Eighths have one flag (or beam), sixteenths two…
    var flags: Int {
        switch kind {
        case .whole, .half, .quarter: 0
        case .eighth: 1
        case .sixteenth: 2
        case .thirtySecond: 3
        case .sixtyFourth: 4
        }
    }

    /// For notes and rests the score gives no `<type>` for: the value with the fewest dots (up
    /// to two) lasting exactly `quarters`, otherwise the longest plain value that fits in it
    /// (64th for anything shorter).
    static func nearest(toQuarters quarters: Double) -> NoteValue {
        for dots in 0...2 {
            for kind in Kind.allCases where abs(NoteValue(kind, dots: dots).quarters - quarters) < 1e-6 {
                return NoteValue(kind, dots: dots)
            }
        }
        return NoteValue(Kind.allCases.first { $0.quarters <= quarters + 1e-6 } ?? .sixtyFourth)
    }
}
