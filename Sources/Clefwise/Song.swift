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
    let measureCount: Int
    /// 1 for a single staff, 2 for a piano-style grand staff.
    let staffCount: Int
    /// Notes left out because we can't show them (other clefs, double sharps, microtones…).
    let skippedNoteCount: Int
}

struct ScoreNote: Hashable {
    /// As played: an 8va passage is already an octave up here.
    let pitch: Pitch
    let clef: Clef
    let keySignature: KeySignature
    /// Sign to print before the note: the score's own, or one added because an accidental earlier
    /// in the bar changed this note from the key signature (that bar context isn't on screen).
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

    var question: Question {
        Question(clef: clef, pitch: pitch, keySignature: keySignature,
                 printedAccidental: printedAccidental, octaveShift: octaveShift)
    }
}
