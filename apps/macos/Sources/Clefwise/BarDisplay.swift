import Foundation

/// What the staff card draws while a piece is practised in the bar view: one bar of the
/// score, on one staff or on both staves of a grand staff, with the note being asked picked out.
struct BarDisplay: Equatable {
    struct Staff: Equatable {
        /// 1 = upper staff (right hand on piano), 2 = lower.
        let number: Int
        /// In force as the bar starts; a symbol's own `clef` says where it changes partway.
        let clef: Clef
        let keySignature: KeySignature
        /// Lowest to highest staff position of the notes drawn on this staff in every bar the
        /// round goes through, and at least the staff itself (0…8). The view sizes the staff to
        /// fit it, so the staff doesn't change size from bar to bar, and hints name every line
        /// and space in it.
        let positions: ClosedRange<Int>
    }

    /// Top to bottom: one staff, or the upper and lower staff of a grand staff, joined by a brace.
    let staves: [Staff]
    /// The bar. Only its symbols on `staves` are drawn.
    let measure: ScoreMeasure
    /// Index in `measure.symbols` of the note being asked; nil between rounds.
    let current: Int?
    /// Indices in `measure.symbols` of the notes already answered in this bar on this pass
    /// through the piece (in-order rounds; empty when shuffled). Drawn muted.
    let answered: Set<Int>
    /// The part's last bar, which ends with a final bar line.
    let isLastBar: Bool
}
