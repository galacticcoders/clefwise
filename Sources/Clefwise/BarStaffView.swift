import SwiftUI

/// Draws one bar of a piece: its staff (or a grand staff) with clefs and key signatures, every
/// note and rest with its real note value, and the note being asked picked out.
///
/// Placeholder until the bar layout lands: the first staff with the current note on its own.
struct BarStaffView: View {
    let bar: BarDisplay
    /// The note being asked: the accent colour, or `Theme.wrong` while a miss is shown.
    var currentColor: Color = Theme.accent
    /// Shown in a pill by the note being asked, e.g. the answer after a miss.
    var currentLabel: String?
    /// Names every line and space of each staff over its `positions`, like `StaffView`'s hints.
    var showsHints = false
    var naming = NamingSystem.letters

    var body: some View {
        if let staff = bar.staves.first {
            StaffView(clef: staff.clef, keySignature: staff.keySignature, note: currentQuestion(on: staff),
                      positionsToFit: staff.positions, noteColor: currentColor, noteLabel: currentLabel,
                      hintPositions: showsHints ? staff.positions : nil, naming: naming)
        }
    }

    private func currentQuestion(on staff: BarDisplay.Staff) -> Question? {
        guard let current = bar.current else { return nil }
        let symbol = bar.measure.symbols[current]
        guard let pitch = symbol.pitch else { return nil }
        return Question(clef: symbol.clef, pitch: pitch, keySignature: staff.keySignature,
                        printedAccidental: symbol.accidental, octaveShift: symbol.octaveShift)
    }
}
