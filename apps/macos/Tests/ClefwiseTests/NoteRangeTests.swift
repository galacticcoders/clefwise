import Foundation
import Testing
@testable import Clefwise

// Where random notes come from: below, on and above the staff in any mix, out to 1–5 ledger lines.

@Suite struct NoteRangeTests {
    @Test func partsAndLedgerLinesGiveThePositions() {
        #expect(NoteRange.staff.positions == Array(0...8))
        #expect(NoteRange(above: true, ledgerLines: 2).positions == Array(0...12))
        #expect(NoteRange(below: true, ledgerLines: 1).positions == Array(-2...8))
        // Off the staff only: the space next to it, then out to the last ledger line.
        #expect(NoteRange(onStaff: false, above: true, ledgerLines: 1).positions == [9, 10])
        #expect(NoteRange(below: true, onStaff: false, ledgerLines: 3).positions == Array(-6 ... -1))
        let outside = NoteRange(below: true, onStaff: false, above: true, ledgerLines: 5)
        #expect(outside.positions == Array(-10 ... -1) + Array(9...18))
        #expect(outside.span == -10...18)
        // Nothing chosen counts as the staff.
        #expect(NoteRange(onStaff: false).positions == Array(0...8))
    }

    @Test func theOldChoicesKeepTheirNotes() throws {
        #expect(NoteRange.staff.span == 0...8)
        #expect(NoteRange.oneLedgerLine.span == -2...10)
        #expect(NoteRange.threeLedgerLines.span == -6...14)
        for (name, span) in [("staff", 0...8), ("oneLedgerLine", -2...10), ("threeLedgerLines", -6...14)] {
            let saved = try JSONDecoder().decode(Game.Settings.self, from: Data(#"{"range":"\#(name)","naming":"solfege"}"#.utf8))
            #expect(saved.range.span == span)
            #expect(saved.range.positions == Array(span))
            #expect(saved.naming == .solfege)
        }
        // A name this version doesn't know falls back to the staff rather than losing every setting.
        let unknown = try JSONDecoder().decode(Game.Settings.self, from: Data(#"{"range":"twoLedgerLines","naming":"solfege"}"#.utf8))
        #expect(unknown.range == .staff && unknown.naming == .solfege)
    }

    @Test func savedAsItsParts() throws {
        let range = NoteRange(below: true, onStaff: false, above: true, ledgerLines: 4)
        #expect(JSONValue(encoding: range) == .object([
            "below": .bool(true), "onStaff": .bool(false), "above": .bool(true), "ledgerLines": .number(4),
        ]))
        #expect(try JSONDecoder().decode(NoteRange.self, from: JSONEncoder().encode(range)) == range)
        // Ledger lines past what the app offers are brought back in.
        let tooFar = try JSONDecoder().decode(NoteRange.self, from: Data(#"{"above":true,"ledgerLines":9}"#.utf8))
        #expect(tooFar == NoteRange(above: true, ledgerLines: 5))
    }

    @Test func theExportKeepsTheOldNames() {
        #expect(NoteRange.staff.key == "staff")
        // The ledger lines don't matter while only the staff is ticked.
        #expect(NoteRange(ledgerLines: 4).key == "staff")
        #expect(NoteRange(below: true, above: true, ledgerLines: 1).key == "oneLedgerLine")
        #expect(NoteRange(below: true, above: true, ledgerLines: 3).key == "threeLedgerLines")
        #expect(NoteRange(below: true, above: true, ledgerLines: 2).key == "below2+staff+above2")
        #expect(NoteRange(above: true, ledgerLines: 3).key == "staff+above3")
        #expect(NoteRange(below: true, onStaff: false, above: true, ledgerLines: 5).key == "below5+above5")
        #expect(NoteRange(below: true, onStaff: false, ledgerLines: 1).key == "below1")
    }

    @Test func labels() {
        #expect(NoteRange.staff.label == "On the staff")
        #expect(NoteRange.oneLedgerLine.label == "+1 ledger line")
        #expect(NoteRange.threeLedgerLines.label == "+3 ledger lines")
        #expect(NoteRange(above: true, ledgerLines: 2).label == "+2 ledger lines above")
        #expect(NoteRange(below: true, ledgerLines: 5).label == "+5 ledger lines below")
        #expect(NoteRange(below: true, onStaff: false, ledgerLines: 1).label == "Below the staff, 1 ledger line")
        #expect(NoteRange(onStaff: false, above: true, ledgerLines: 4).label == "Above the staff, 4 ledger lines")
        #expect(NoteRange(below: true, onStaff: false, above: true, ledgerLines: 3).label == "Above & below the staff, 3 ledger lines")
    }
}

@MainActor
@Suite final class NoteRangeGameTests: GameTestBench {
    /// Staff positions of the notes a practice round asks, answering each right.
    private func positionsAsked(_ count: Int = 300) -> Set<Int> {
        game.start()
        var positions: Set<Int> = []
        for _ in 0..<count {
            guard let question = game.question else { break }
            positions.insert(question.position)
            answerRight()
        }
        game.stop()
        return positions
    }

    @Test func roundsAskOnlyTheChosenParts() {
        game.settings.range = NoteRange(onStaff: false, above: true, ledgerLines: 2)
        #expect(positionsAsked() == [9, 10, 11, 12])

        game.settings.clefChoice = .both
        game.settings.range = NoteRange(below: true, onStaff: false, above: true, ledgerLines: 1)
        #expect(positionsAsked() == [-2, -1, 9, 10])
    }

    @Test func theStaffMakesRoomPastThreeLedgerLines() {
        #expect(game.staffPositionsToFit == nil)
        game.settings.range = .threeLedgerLines
        #expect(game.staffPositionsToFit == nil)
        game.settings.range = NoteRange(above: true, ledgerLines: 5)
        #expect(game.staffPositionsToFit == 0...18)
        game.settings.range = NoteRange(below: true, onStaff: false, ledgerLines: 4)
        #expect(game.staffPositionsToFit == -8 ... -1)
    }

    @Test func thePianoCoversTheRange() {
        game.settings.range = NoteRange(below: true, onStaff: false, above: true, ledgerLines: 5)
        // Treble, five ledger lines: B2 below to B6 above.
        let keys = game.pianoKeys
        #expect(keys.contains(Pitch(.b, 2).diatonicIndex) && keys.contains(Pitch(.b, 6).diatonicIndex))
        game.settings.range = NoteRange(onStaff: false, above: true, ledgerLines: 1)
        // G5 and A5 only: the octave they're in.
        #expect(game.pianoKeys == Pitch(.c, 5).diatonicIndex...Pitch(.b, 5).diatonicIndex)
    }

    @Test func changesAreLoggedPerPart() {
        game.settings.range.above = true
        game.settings.range.ledgerLines = 4
        let changes = recorder.events.compactMap { if case .settingChanged(let e) = $0.event { e } else { nil } }
            .filter { $0.setting.hasPrefix("range") }
        #expect(changes.map(\.setting) == ["range.above", "range.ledgerLines"])
        #expect(changes.last?.to == .number(4))
    }
}
