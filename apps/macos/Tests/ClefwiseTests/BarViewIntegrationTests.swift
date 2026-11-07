import Foundation
import Testing
@testable import Clefwise

// The importer and the game together: "Lantern at Dusk" (bar-view.musicxml) played through in the
// whole-bar view, checking each step against the bar the importer laid out.

@MainActor
@Suite final class BarViewIntegrationTests: GameTestBench {
    private func openLantern(hand: Game.PieceSettings.Hand) throws {
        let url = try #require(Fixtures.url("bar-view.musicxml"))
        game.openPiece(at: url)
        #expect(game.pieceError == nil)
        game.settings.piece.hand = hand
    }

    @Test func bothHandsPlayThroughOnTheGrandStaff() throws {
        try openLantern(hand: .both)
        let part = try #require(game.piecePart)
        game.start()
        var asked = 0
        var bar = 0
        var doneInBar: Set<Int> = []
        while game.phase == .playing, asked < 500 {
            let display = try #require(game.barDisplay, "no bar on screen at note \(asked)")
            let question = try #require(game.question)
            let index = try #require(display.current)
            let symbol = display.measure.symbols[index]
            #expect(display.staves.map(\.number) == [1, 2])
            #expect(display.measure == part.measures[display.measure.number - 1])
            // The note asked is the one drawn there, with the sign the bar prints.
            #expect(symbol.pitch == question.pitch && symbol.clef == question.clef)
            #expect(symbol.octaveShift == question.octaveShift)
            #expect(symbol.accidental == question.printedAccidental)
            #expect(!symbol.tiedFromPrevious)
            // Notes done so far in this bar are the ones drawn muted.
            if display.measure.number != bar {
                bar = display.measure.number
                doneInBar = []
            }
            #expect(display.answered == doneInBar)
            #expect(display.isLastBar == (bar == part.measureCount))
            for staff in display.staves {
                let positions = display.measure.symbols.filter { $0.staff == staff.number }.compactMap(\.position)
                #expect(positions.allSatisfy(staff.positions.contains))
            }
            doneInBar.insert(index)
            answerRight()
            asked += 1
        }
        #expect(asked == part.notes.count)
        #expect(game.summary?.finishedPiece == true)
    }

    @Test func signsFollowTheBarRule() throws {
        try openLantern(hand: .right)
        game.start()
        var shown: [(bar: Int, pitch: Pitch, sign: Accidental?)] = []
        while game.phase == .playing, shown.count < 500 {
            let display = try #require(game.barDisplay)
            let question = try #require(game.question)
            #expect(display.staves.map(\.number) == [1])
            shown.append((display.measure.number, question.pitch, question.printedAccidental))
            answerRight()
        }
        let dSharp5 = Pitch(.d, 5, .sharp)
        // Bar 4: D♯5 prints its sharp, the second D♯5 in the bar doesn't; bar 5 states it again.
        #expect(shown.filter { $0.bar == 4 && $0.pitch == dSharp5 }.map(\.sign) == [.sharp, nil])
        #expect(shown.first { $0.bar == 5 && $0.pitch == dSharp5 }?.sign == .sharp)
        // Bar 9: F♮ cancels the key's F♯, which is then printed again.
        #expect(shown.filter { $0.bar == 9 && $0.pitch.letter == .f }.map(\.sign) == [.natural, .sharp])
        // The key's F♯ elsewhere isn't printed.
        #expect(shown.first { $0.bar == 2 && $0.pitch == Pitch(.f, 5, .sharp) }?.sign == nil)
    }

    @Test func wholeBarOffShowsOneNoteWithItsOwnSign() throws {
        try openLantern(hand: .right)
        game.settings.piece.showsWholeBar = false
        game.start()
        #expect(game.barDisplay == nil)
        var signs: [Accidental?] = []
        while game.phase == .playing, signs.count < 500 {
            if let question = game.question, question.pitch == Pitch(.d, 5, .sharp) {
                signs.append(question.printedAccidental)
            }
            answerRight()
        }
        // On its own every D♯ carries its sharp.
        #expect(!signs.isEmpty && signs.allSatisfy { $0 == .sharp })
    }
}
