import SwiftUI

/// Guitar answer input wired to the game: click where you'd play the note, on any string that has
/// it (`Game.answer(at:)`). Contract placeholder: the view agent draws the fretboard.
struct GuitarPad: View {
    let game: Game

    var body: some View {
        Text("Guitar fretboard")
            .frame(maxWidth: .infinity)
            .frame(height: PianoKeyboard.height)
    }
}
