import Foundation
import Testing
@testable import Clefwise

// Answering on the guitar: random notes in the guitar clef within the tuning's reach, the frets the
// board shows, judging a place by the pitch it sounds, notes named together, pieces (notes out of
// reach, the tuning per piece), the log and its export, and a round coming back after a crash.

private let b1 = Pitch(.b, 1), c2 = Pitch(.c, 2), d2 = Pitch(.d, 2), e2 = Pitch(.e, 2), a2 = Pitch(.a, 2)
private let c3 = Pitch(.c, 3), d3 = Pitch(.d, 3), e3 = Pitch(.e, 3), f3 = Pitch(.f, 3), g3 = Pitch(.g, 3)
private let b3 = Pitch(.b, 3), e4 = Pitch(.e, 4), e5 = Pitch(.e, 5), a5 = Pitch(.a, 5)

/// Places on the neck, as guitarists name them.
private func place(_ string: Int, _ fret: Int) -> GuitarPosition { GuitarPosition(string: string, fret: fret) }

/// A one-staff guitar piece in C major, one note a beat, a bar of four; no bar layout, so its notes
/// are asked one at a time.
private func guitarTune(_ pitches: [Pitch], tuning: GuitarTuning? = nil, bars: Int? = nil) -> Score {
    let notes = pitches.enumerated().map { index, pitch in
        ScoreNote(pitch: pitch, clef: .treble8vb, keySignature: .cMajor, printedAccidental: nil, octaveShift: 0,
                  staff: 1, measure: index / 4 + 1, onset: Double(index), chord: index)
    }
    return Score(title: "Guitar tune", parts: [ScorePart(name: "Guitar", notes: notes,
                                                          measureCount: bars ?? (pitches.count + 3) / 4, staffCount: 1,
                                                          skippedNoteCount: 0, guitarTuning: tuning)])
}

/// A note as the importer lays it out on a guitar staff.
private func guitarSymbol(_ pitch: Pitch, at offset: Double, lasting duration: Double = 1, chord: Int) -> BarSymbol {
    BarSymbol(pitch: pitch, clef: .treble8vb, staff: 1, voice: 1, offset: offset, duration: duration,
              value: NoteValue(duration == 2 ? .half : .quarter), octaveShift: 0, accidental: nil, stemUp: nil,
              chord: chord, tiedToNext: false, tiedFromPrevious: false, restPosition: nil, isWholeBarRest: false)
}

/// Bar 1: E3 B3 E4 together; G3; C3 and E4; A2. Bar 2: D2 and D3 for two beats (D2 is below a
/// standard guitar's low E), then E2.
///
/// Symbols: bar 1 is E3 B3 E4 · G3 · C3 E4 · A2 (indices 0–6); bar 2 is D2 D3 · E2.
private func guitarChords(tuning: GuitarTuning? = nil) -> Score {
    let bars: [[BarSymbol]] = [
        [guitarSymbol(e3, at: 0, chord: 1), guitarSymbol(b3, at: 0, chord: 1), guitarSymbol(e4, at: 0, chord: 1),
         guitarSymbol(g3, at: 1, chord: 2),
         guitarSymbol(c3, at: 2, chord: 3), guitarSymbol(e4, at: 2, chord: 3),
         guitarSymbol(a2, at: 3, chord: 4)],
        [guitarSymbol(d2, at: 0, lasting: 2, chord: 5), guitarSymbol(d3, at: 0, lasting: 2, chord: 5),
         guitarSymbol(e2, at: 2, lasting: 2, chord: 6)],
    ]
    var measures: [ScoreMeasure] = []
    var notes: [ScoreNote] = []
    for (offset, symbols) in bars.enumerated() {
        let number = offset + 1, start = Double(offset * 4)
        measures.append(ScoreMeasure(number: number, start: start, length: 4,
                                     staves: [.init(clef: .treble8vb, keySignature: .cMajor)], symbols: symbols))
        for (index, symbol) in symbols.enumerated() {
            guard let pitch = symbol.pitch else { continue }
            notes.append(ScoreNote(pitch: pitch, clef: .treble8vb, keySignature: .cMajor, printedAccidental: nil,
                                   octaveShift: 0, staff: 1, measure: number, onset: start + symbol.offset,
                                   chord: symbol.chord, symbolIndex: index))
        }
    }
    return Score(title: "Guitar chords", parts: [ScorePart(name: "Guitar", notes: notes, measures: measures,
                                                           measureCount: bars.count, staffCount: 1,
                                                           skippedNoteCount: 0, guitarTuning: tuning)])
}

private let tuneURL = URL(fileURLWithPath: "/tmp/clefwise-tests/guitar-tune.musicxml")
private let chordsURL = URL(fileURLWithPath: "/tmp/clefwise-tests/guitar-chords.musicxml")

@MainActor
@Suite final class GuitarGameTests: GameTestBench {
    // MARK: - Helpers

    private func onGuitar(_ tuning: GuitarTuning = .standard) {
        game.settings.answerInput = .guitar
        game.settings.guitarTuning = tuning
    }

    private func logged<T>(_ type: T.Type, in recorder: MemoryUsageRecorder? = nil) -> [T] {
        (recorder ?? self.recorder).events.compactMap { $0.event.payload as? T }
    }

    /// The first place on `game`'s board that sounds `pitch`.
    private func spot(for pitch: Pitch, on game: Game? = nil) throws -> GuitarPosition {
        try #require((game ?? self.game).fretboard.positions(sounding: pitch.midiNumber).first, "\(pitch.name)")
    }

    /// The notes asked now: the group's, or the one note's.
    private func asked(on game: Game? = nil) -> [Pitch] {
        let game = game ?? self.game
        return game.group?.questions.map(\.pitch) ?? game.question.map { [$0.pitch] } ?? []
    }

    /// Answers what's asked right on the guitar: the note, or one place for each pitch asked together.
    @discardableResult
    private func playRight(on game: Game? = nil) throws -> [Pitch] {
        let game = game ?? self.game
        let pitches = asked(on: game)
        var chosen = Set<Int>()
        for pitch in pitches where chosen.insert(pitch.midiNumber).inserted {
            game.answer(at: try spot(for: pitch, on: game))
        }
        return pitches
    }

    /// Starts a round and answers everything right on the guitar until it ends, noting what was asked.
    private func playThrough(limit: Int = 100) throws -> [[Pitch]] {
        game.start()
        var asked: [[Pitch]] = []
        while game.phase == .playing, asked.count < limit {
            asked.append(try playRight())
        }
        return asked
    }

    private func press(_ characters: String, keyCode: UInt16 = 0) -> Bool {
        game.handleKey(characters: characters, keyCode: keyCode)
    }

    // MARK: - Random notes

    @Test func randomNotesAreAskedInTheGuitarClefWithinReach() throws {
        onGuitar()
        game.settings.clefChoice = .both
        for lines in 1...NoteRange.maxLedgerLines {
            game.settings.range = NoteRange(below: true, above: true, ledgerLines: lines)
            game.start()
            for _ in 0..<(lines >= 4 ? 120 : 40) {
                let question = try #require(game.question)
                #expect(question.clef == .treble8vb)
                #expect(question.octaveShift == 0)
                #expect(Fretboard.canPlay(question.pitch.midiNumber, in: .standard), "\(question.pitch.name)")
                try playRight()
            }
            #expect(game.score == game.attempts)
            game.stop()
        }
        // The toolbar's choice is left as it was, for the other inputs.
        #expect(game.settings.clefChoice == .both)
    }

    /// Written D3, four ledger lines below the guitar staff, sounds D2: only drop D's low string has it.
    @Test func lowNotesAreAskedOnlyWhenTheTuningReachesThem() throws {
        game.settings.range = NoteRange(below: true, onStaff: false, ledgerLines: 5)
        for tuning in [GuitarTuning.standard, .dropD] {
            onGuitar(tuning)
            game.start()
            var asked = Set<Pitch>()
            for _ in 0..<150 {
                asked.insert(try #require(game.question).pitch)
                try playRight()
            }
            game.stop()
            #expect(!asked.contains(c2) && !asked.contains(b1))
            #expect(asked.contains(e2))
            #expect(asked.contains(d2) == (tuning == .dropD), "\(tuning.name)")
        }
    }

    @Test func aTuningThatReachesNothingStillAsks() throws {
        onGuitar(GuitarTuning(strings: Array(repeating: Pitch(.c, 7), count: 6)))
        for _ in 0..<5 {
            game.start()
            #expect(game.question?.clef == .treble8vb)
            game.answer(at: place(1, 0))
            #expect(game.attempts == 1 && game.score == 0)
            game.stop()
        }
    }

    @Test func theGuitarClefShowsOnlyWhileAnsweringOnTheGuitar() throws {
        game.settings.clefChoice = .bass
        #expect(game.displayedClef == .bass)
        onGuitar()
        #expect(game.displayedClef == .treble8vb)
        game.settings.clefChoice = .both
        game.start()
        try playRight()
        game.stop()
        // One clef, whatever the toolbar says.
        #expect(game.summary?.mixedClefs == false)
        game.dismissSummary()
        game.settings.answerInput = .buttons
        #expect(game.displayedClef == .treble && game.randomClefs == [.treble, .bass])
    }

    @Test func theBoardHasTheFretsTheNotesNeed() throws {
        onGuitar()
        #expect(game.fretboard == Fretboard(tuning: .standard, frets: 12))
        // Five ledger lines above the guitar staff reach B5, the 1st string's 19th fret.
        game.settings.range = NoteRange(above: true, ledgerLines: 5)
        #expect(game.fretboard.frets == 19)
        game.start()
        #expect(game.fretboard.frets == 19)
        game.stop()
        // Signs added and random keys reach no further up.
        game.settings.addsAccidentals = true
        game.settings.key = .random
        #expect(game.fretboard.frets == 19)
        // Far below the staff needs no more frets: what's out of reach isn't asked.
        game.settings.range = NoteRange(below: true, ledgerLines: 5)
        #expect(game.fretboard.frets == 12)
        game.settings.guitarTuning = .dropD
        #expect(game.fretboard == Fretboard(tuning: .dropD, frets: 12))
    }

    @Test func aPieceBoardReachesItsHighestNote() {
        onGuitar()
        game.open(guitarTune([e3, a5]), from: tuneURL)
        // A5 is the 1st string's 17th fret.
        #expect(game.fretboard.frets == 17)
        game.start()
        #expect(game.fretboard.frets == 17)
    }

    // MARK: - Answering

    @Test func everyPlaceThatSoundsTheNoteIsRight() async throws {
        onGuitar()
        game.open(guitarTune([e3, e3, e3, e3]), from: tuneURL)
        game.start()
        for (number, spot) in [place(4, 2), place(5, 7), place(6, 12)].enumerated() {
            game.answer(at: spot)
            let flash = try #require(game.flash)
            #expect(flash.isCorrect && flash.position == spot && flash.pitch == e3)
            #expect(game.score == number + 1)
        }
        game.answer(at: place(4, 3))
        let flash = try #require(game.flash)
        #expect(!flash.isCorrect && flash.position == place(4, 3) && flash.pitch == f3)
        #expect(game.score == 3 && game.attempts == 4 && game.isShowingMiss)

        let answers = logged(AnswerGiven.self)
        #expect(answers.map(\.source) == Array(repeating: .guitar, count: 4))
        #expect(answers.map(\.guitarString) == [4, 5, 6, 4] && answers.map(\.guitarFret) == [2, 7, 12, 3])
        #expect(answers.map { $0.pitch?.name } == ["E3", "E3", "E3", "F3"])
        #expect(answers.map(\.correct) == [true, true, true, false])
        #expect(answers.map(\.wrongOctave) == [false, false, false, false])
        #expect(answers.allSatisfy { $0.keystrokes.isEmpty })
    }

    @Test func aWrongOctaveIsToldApart() async throws {
        onGuitar()
        game.open(guitarTune([e3, e3]), from: tuneURL)
        game.start()
        game.answer(at: place(1, 0))
        #expect(game.flash?.pitch == e4 && game.flash?.isCorrect == false)
        #expect(game.missLabel(for: e3, answeredWith: game.flash?.pitch) == "E · wrong octave")
        try await waitUntil { !game.isShowingMiss }
        game.answer(at: place(6, 1))
        #expect(logged(AnswerGiven.self).map(\.wrongOctave) == [true, false])
    }

    @Test func spellingDoesNotMatterOnlyTheSound() throws {
        onGuitar()
        // E♭3 is asked; the board calls that place D♯3.
        game.open(guitarTune([Pitch(.e, 3, .flat), e3]), from: tuneURL)
        game.start()
        game.answer(at: place(4, 1))
        #expect(game.flash?.pitch == Pitch(.d, 3, .sharp) && game.flash?.isCorrect == true)
        #expect(game.score == 1)
    }

    @Test func noteButtonShortcutsDoNotAnswerOnTheGuitar() {
        onGuitar()
        game.settings.addsAccidentals = true
        game.start()
        for key in ["c", "1", "e", "#", "-"] { _ = press(key) }
        #expect(game.attempts == 0 && game.flash == nil && game.armedAccidental == .natural)
        #expect(logged(AnswerGiven.self).isEmpty)
    }

    @Test func kShowsNoteNamesOnTheGuitar() throws {
        game.settings.answerInput = .buttons
        #expect(!press("k") && !game.settings.showKeyNames)
        onGuitar()
        #expect(press("k") && game.settings.showKeyNames)
        game.start()
        #expect(logged(QuestionShown.self).last?.keyNamesVisible == true)
        #expect(press("k") && !game.settings.showKeyNames)
    }

    @Test func answersThatCantCountAreIgnoredWithThePlace() async throws {
        onGuitar()
        game.answer(at: place(6, 0))
        game.open(guitarTune([e3, e3]), from: tuneURL)
        game.start()
        let round = try #require(logged(RoundStarted.self).last?.round)
        game.answer(at: place(4, 3))
        game.answer(at: place(4, 2))
        try await waitUntil { !game.isShowingMiss }
        game.pause()
        game.answer(at: place(5, 7))
        #expect(logged(InputIgnored.self) == [
            InputIgnored(round: nil, reason: "noRound", source: .guitar, detail: "guitar E2 string 6 fret 0"),
            InputIgnored(round: round, reason: "missPause", source: .guitar, detail: "guitar E3 string 4 fret 2"),
            InputIgnored(round: round, reason: "paused", source: .guitar, detail: "guitar E3 string 5 fret 7"),
        ])
        #expect(game.attempts == 1)
    }

    @Test func aPlaceOffTheNeckIsIgnored() {
        onGuitar()
        game.start()
        game.answer(at: place(7, 0))
        game.answer(at: place(1, 25))
        game.answer(at: place(0, -1))
        #expect(game.attempts == 0 && game.flash == nil)
        #expect(logged(InputIgnored.self).map(\.reason) == ["noPlace", "noPlace", "noPlace"])
        #expect(logged(InputIgnored.self).first?.detail == "string 7 fret 0")
    }

    // MARK: - Notes asked together

    private func together(_ tuning: GuitarTuning? = nil) {
        onGuitar()
        game.settings.piece.chords = .together
        game.open(guitarChords(tuning: tuning), from: chordsURL)
    }

    @Test func placesToggleAndMoveByPosition() throws {
        together()
        game.start()
        #expect(asked() == [e3, b3, e4])
        #expect(game.groupEntriesNeeded == 3)
        game.answer(at: place(4, 2))
        #expect(game.group?.entries.map(\.position) == [place(4, 2)])
        game.answer(at: place(4, 2)) // clicked again: taken back
        #expect(game.group?.entries.isEmpty == true)
        game.answer(at: place(4, 2))
        game.answer(at: place(5, 7)) // the same E3 elsewhere: the choice moves there
        #expect(game.group?.entries.map(\.position) == [place(5, 7)])
        #expect(game.group?.entries.map(\.pitch) == [e3])
        game.answer(at: place(2, 0))
        #expect(game.group?.entries.count == 2 && game.group?.result == nil)
        game.answer(at: place(1, 0))
        #expect(game.score == 3 && game.attempts == 3)
        #expect(game.groupFlash?.entries.map(\.position) == [place(5, 7), place(2, 0), place(1, 0)])
        #expect(asked() == [g3])

        let answers = logged(AnswerGiven.self)
        try #require(answers.count == 3)
        #expect(Set(answers.map(\.group)).count == 1 && answers[0].groupSize == 3)
        #expect(answers.map(\.source) == [.guitar, .guitar, .guitar])
        #expect(answers.map(\.guitarString) == [5, 2, 1] && answers.map(\.guitarFret) == [7, 0, 0])
        #expect(answers.map { $0.pitch?.name } == ["E3", "B3", "E4"])
        #expect(answers[0].keystrokes.map(\.key) == [
            "guitar E3 string 4 fret 2", "guitar E3 string 4 fret 2", "guitar E3 string 4 fret 2",
            "guitar E3 string 5 fret 7", "guitar B3 string 2 fret 0", "guitar E4 string 1 fret 0",
        ])
        #expect(answers[0].keystrokes.map(\.result) == [.typed, .deleted, .typed, .typed, .typed, .submitted])
        #expect(answers.dropFirst().allSatisfy { $0.keystrokes.isEmpty })
    }

    @Test func eachNoteIsJudgedBySound() throws {
        together()
        game.start()
        try playRight() // E3 B3 E4
        try playRight() // G3
        #expect(asked() == [c3, e4])
        game.answer(at: place(5, 3)) // C3
        game.answer(at: place(1, 12)) // E5: an octave too high
        let result = try #require(game.group?.result)
        #expect(result.isRight == [true, false])
        #expect(game.score == 5 && game.attempts == 6 && game.isShowingMiss)
        #expect(game.barDisplay?.marks == [4: .right, 5: .wrong(name: "E · wrong octave")])
        let answers = logged(AnswerGiven.self).suffix(2)
        #expect(answers.map(\.wrongOctave) == [false, true])
        #expect(answers.map(\.guitarString) == [5, 1] && answers.map(\.guitarFret) == [3, 12])
        #expect(answers.map { $0.pitch?.name } == ["C3", "E5"])
    }

    @Test func deleteTakesBackTheLastPlace() {
        together()
        game.start()
        game.answer(at: place(4, 2))
        game.answer(at: place(2, 0))
        #expect(press("\u{7f}", keyCode: 51))
        #expect(game.group?.entries.map(\.pitch) == [e3])
        game.stop()
        let unanswered = logged(RoundEnded.self).last?.unansweredQuestion
        #expect(unanswered?.keystrokes.map(\.key) == ["guitar E3 string 4 fret 2", "guitar B3 string 2 fret 0", "Delete"])
        #expect(unanswered?.keystrokes.map(\.result) == [.typed, .typed, .deleted])
    }

    /// The low D of the chord in bar 2 is out of a standard guitar's reach: the D3 above it is asked
    /// on its own. In drop D both are asked together.
    @Test func aNoteOutOfReachLeavesItsChord() throws {
        together()
        #expect(game.guitarNotesOutOfReach == 1 && game.pieceRoundNoteCount == 9)
        #expect(try playThrough() == [[e3, b3, e4], [g3], [c3, e4], [a2], [d3], [e2]])
        #expect(game.summary?.attempts == 9 && game.summary?.score == 9)
        game.dismissSummary()

        game.guitarTuning = .dropD
        #expect(game.guitarNotesOutOfReach == 0 && game.pieceRoundNoteCount == 10)
        #expect(try playThrough() == [[e3, b3, e4], [g3], [c3, e4], [a2], [d2, d3], [e2]])
    }

    // MARK: - Pieces

    @Test func notesOutOfReachAreLeftOutAndCounted() throws {
        game.open(guitarTune([c2, e2, d2, g3, b1]), from: tuneURL)
        #expect(game.pieceRoundNoteCount == 5 && game.guitarNotesOutOfReach == 0)
        // Switching to the guitar leaves out what it can't play.
        game.settings.answerInput = .guitar
        #expect(game.pieceRoundNoteCount == 2 && game.guitarNotesOutOfReach == 3)
        #expect(try playThrough() == [[e2], [g3]])
        #expect(game.summary?.finishedPiece == true && game.summary?.attempts == 2)
        game.dismissSummary()
        // The global tuning counts while neither the piece nor its score has one.
        game.settings.guitarTuning = .dropD
        #expect(game.pieceRoundNoteCount == 3 && game.guitarNotesOutOfReach == 2)
        // The piece's own choice comes first.
        game.guitarTuning = .standard
        #expect(game.settings.piece.guitarTuning == .standard && game.settings.guitarTuning == .dropD)
        #expect(game.pieceRoundNoteCount == 2 && game.guitarNotesOutOfReach == 3)
        // And back to another input: every note.
        game.settings.answerInput = .piano
        #expect(game.pieceRoundNoteCount == 5 && game.guitarNotesOutOfReach == 0)
    }

    @Test func aPieceWithNoNoteInReachSaysSo() throws {
        onGuitar()
        game.open(guitarTune([b1, c2, d2]), from: tuneURL)
        #expect(game.guitarNotesOutOfReach == 3)
        game.start()
        #expect(game.pieceError == "None of these notes can be played in Standard tuning. Choose another tuning.")
        #expect(game.phase == .idle && logged(RoundStarted.self).isEmpty)
        game.guitarTuning = .dropD
        game.start()
        #expect(game.pieceError == nil && game.phase == .playing && asked() == [d2])
        game.stop()

        game.open(guitarTune([b1, c2]), from: otherTuneURL)
        game.guitarTuning = .dropD
        game.start()
        #expect(game.pieceError == "None of these notes can be played in Drop D tuning. Choose another tuning.")
    }

    @Test func aSelectionWithNoNotesSaysWhyAsBefore() {
        onGuitar()
        // Notes only in bar 1 of 2, practised from bar 2.
        game.open(guitarTune([e3, g3], bars: 2), from: tuneURL)
        game.settings.piece.startBar = 2
        game.start()
        #expect(game.pieceError == "This part has no notes from bar 2 on. Choose an earlier start bar.")
    }

    @Test func theScoresTuningCountsUnlessThePieceHasItsOwn() {
        onGuitar()
        game.open(guitarTune([d2, e2], tuning: .dropD), from: tuneURL)
        #expect(game.guitarTuning == .dropD && game.fretboard.tuning == .dropD)
        #expect(game.pieceRoundNoteCount == 2 && game.guitarNotesOutOfReach == 0)
        game.guitarTuning = .standard
        #expect(game.guitarNotesOutOfReach == 1 && game.fretboard.tuning == .standard)
        game.settings.piece.guitarTuning = nil
        #expect(game.guitarTuning == .dropD)
        game.closePiece()
        #expect(game.guitarTuning == .standard && game.guitarNotesOutOfReach == 0)
    }

    @Test func aPiecesTuningIsKeptWithIt() throws {
        onGuitar()
        game.openPiece(at: try #require(Fixtures.url("clarinet-tune.musicxml")))
        let entryID = try #require(game.pieceEntryID)
        #expect(game.settings.piece.guitarTuning == nil && game.guitarTuning == .standard)
        game.guitarTuning = .dadgad
        #expect(library.entry(id: entryID)?.settings?.guitarTuning == .dadgad)
        // The global tuning, for random notes, stays.
        #expect(game.settings.guitarTuning == .standard)

        // Another piece, new to the library, starts from its score's tuning, not the last one's choice.
        game.openPiece(at: try #require(Fixtures.url("grand-staff.musicxml")))
        #expect(game.settings.piece.guitarTuning == nil && game.guitarTuning == .standard)

        // The first one comes back with its own, also after a relaunch.
        game.open(try #require(library.entry(id: entryID)))
        #expect(game.guitarTuning == .dadgad)
        let again = relaunch()
        #expect(again.pieceEntryID == entryID && again.guitarTuning == .dadgad)
        #expect(again.settings.answerInput == .guitar)
    }

    // MARK: - The log

    @Test func questionsOnTheGuitarLogTheTuningAndFrets() throws {
        onGuitar(.dropD)
        game.settings.range = NoteRange(above: true, ledgerLines: 5)
        game.start()
        let shown = try #require(logged(QuestionShown.self).last)
        #expect(shown.clef == "treble8vb" && shown.input == "guitar")
        #expect(shown.guitarTuning == "dropD" && shown.guitarFrets == 19)
        #expect(!shown.keyNamesVisible && shown.octaveShift == 0)
        #expect(shown.written == shown.pitch)
        try playRight()
        let answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.source == .guitar && answer.correct && answer.pitch?.midi == shown.pitch.midi)
        #expect(answer.guitarString != nil && answer.guitarFret != nil)
        #expect(answer.name == game.settings.naming.name(of: try #require(answer.pitch.flatMap(RoundReplay.pitch))))
    }

    @Test func otherInputsLogNoGuitarFields() throws {
        for input in [Game.AnswerInput.buttons, .piano, .keyboard] {
            game.settings.answerInput = input
            game.settings.showKeyNames = true
            game.start()
            if let question = game.question { game.answer(question.pitch) }
            game.stop()
            game.dismissSummary()
        }
        let shown = logged(QuestionShown.self)
        #expect(shown.allSatisfy { $0.guitarTuning == nil && $0.guitarFrets == nil && $0.clef == "treble" })
        #expect(shown.map(\.keyNamesVisible).contains(true))
        #expect(logged(AnswerGiven.self).allSatisfy { $0.guitarString == nil && $0.guitarFret == nil })
        // Not a word of the guitar in their lines.
        for event in recorder.events where ["questionShown", "answerGiven", "roundStarted"].contains(event.event.type) {
            let line = String(decoding: try event.encodedLine(), as: UTF8.self)
            #expect(!line.contains("guitarFrets") && !line.contains("guitarString") && !line.contains("treble8vb"))
        }
    }

    @Test func tuningChangesAreLoggedAsStrings() {
        game.settings.guitarTuning = .dropD
        game.open(guitarTune([e3]), from: tuneURL)
        game.guitarTuning = .openG
        let changes = logged(SettingChanged.self).filter { $0.setting.contains("guitarTuning") }
        #expect(changes == [
            SettingChanged(setting: "guitarTuning", from: .string("standard"), to: .string("dropD")),
            SettingChanged(setting: "piece.guitarTuning", from: .null, to: .string("openG")),
        ])
    }

    @Test func pieceRoundsLogTheNotesLeftOut() throws {
        game.open(guitarTune([c2, e2, g3]), from: tuneURL)
        game.start()
        #expect(logged(RoundStarted.self).last?.piece?.guitarNotesOutOfReach == nil)
        #expect(logged(RoundStarted.self).last?.piece?.noteCount == 3)
        game.stop()
        game.dismissSummary()
        onGuitar()
        game.start()
        let piece = try #require(logged(RoundStarted.self).last?.piece)
        #expect(piece.guitarNotesOutOfReach == 1 && piece.noteCount == 2)
    }

    @Test func statsAreKeptInTheGuitarClef() async throws {
        onGuitar()
        game.open(guitarTune([e3, g3]), from: tuneURL)
        game.start()
        try playRight()
        game.answer(at: place(1, 0))
        let saved = try #require(defaults.data(forKey: Game.Keys.noteStats))
        let stats = try JSONDecoder().decode([String: NoteStat].self, from: saved)
        #expect(stats["treble8vb.E3"]?.attempts == 1 && stats["treble8vb.E3"]?.correct == 1)
        #expect(stats["treble8vb.G3"]?.attempts == 1 && stats["treble8vb.G3"]?.correct == 0)

        // The journal's fold and a crash's replay read the guitar clef back.
        let events = recorder.events
        #expect(JournalProjection.fold(openingBalances: [], runs: [events]).noteStats == stats)
        let shown = try #require(logged(QuestionShown.self).first)
        #expect(RoundReplay.staffNote(of: shown) == StaffNote(clef: .treble8vb, pitch: e3))
        #expect(RoundReplay(round: shown.round, events: events).misses == [StaffNote(clef: .treble8vb, pitch: g3): 1])
    }

    @Test func theExportHasTheGuitarColumns() async throws {
        let folder = UsageTestFolder()
        let log = UsageLog(folder: folder.url.appendingPathComponent("Usage", isDirectory: true))
        let defaults = InMemoryDefaults()
        let game = Game(defaults: defaults, recorder: log, library: library)
        game.settings.isMuted = true
        game.settings.answerInput = .guitar
        game.open(guitarTune([e3, e3, e3]), from: tuneURL)
        game.start()
        game.answer(at: place(4, 2))
        game.answer(at: place(1, 0))
        try await waitUntil { !game.isShowingMiss }
        game.stop()

        let archive = folder.url.appendingPathComponent("export.zip")
        try UsageExport.export(log, to: archive, defaults: defaults)
        let unzipped = folder.url.appendingPathComponent("unzipped", isDirectory: true)
        let ditto = try Process.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", archive.path, unzipped.path])
        ditto.waitUntilExit()
        let top = unzipped.appendingPathComponent(try #require(try FileManager.default.contentsOfDirectory(atPath: unzipped.path).first))

        let answers = try csv(top.appendingPathComponent("answers.csv"))
        // The real piano's column (2026-11-15) comes after the guitar's.
        #expect(answers.header.suffix(6) == ["pieceTitle", "guitarTuning", "guitarFrets", "answerString", "answerFret", "answerVelocity"])
        try #require(answers.rows.count == 2)
        #expect(answers.rows.map { $0["answerVelocity"] } == ["", ""])
        #expect(answers.rows.map { $0["guitarTuning"] } == ["standard", "standard"])
        #expect(answers.rows.map { $0["guitarFrets"] } == ["12", "12"])
        #expect(answers.rows.map { $0["answerString"] } == ["4", "1"])
        #expect(answers.rows.map { $0["answerFret"] } == ["2", "0"])
        #expect(answers.rows.map { $0["clef"] } == ["treble8vb", "treble8vb"])
        #expect(answers.rows.map { $0["source"] } == ["guitar", "guitar"])
        #expect(answers.rows.map { $0["answerPitch"] } == ["E3", "E4"])
        #expect(answers.rows.map { $0["wrongOctave"] } == ["false", "true"])

        let rounds = try csv(top.appendingPathComponent("rounds.csv"))
        #expect(rounds.header.suffix(3) == ["answers", "guitarTuning", "pieceGuitarNotesOutOfReach"])
        #expect(rounds.rows.first?["guitarTuning"] == "standard" && rounds.rows.first?["pieceGuitarNotesOutOfReach"] == "0")
        #expect(rounds.rows.first?["answerInput"] == "guitar")

        let schema = try String(contentsOf: top.appendingPathComponent("SCHEMA.md"), encoding: .utf8)
        for word in ["`treble8vb`", "`guitarString`", "`guitarFret`", "`guitarTuning`", "`guitarFrets`", "`dropD`",
                     "`guitar E3 string 4 fret 2`", "`piece.guitarNotesOutOfReach`", "`treble8vb.E3`"] {
            #expect(schema.contains(word), "\(word)")
        }
    }

    /// A CSV file without quoted fields: its header, and its rows by column name.
    private func csv(_ url: URL) throws -> (header: [String], rows: [[String: String]]) {
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\r\n").filter { !$0.isEmpty }
        let header = try #require(lines.first).components(separatedBy: ",")
        let rows = lines.dropFirst().map { line -> [String: String] in
            let fields = line.components(separatedBy: ",")
            #expect(fields.count == header.count, "\(line)")
            return Dictionary(uniqueKeysWithValues: zip(header, fields))
        }
        return (header, rows)
    }

    // MARK: - After a crash

    /// Stops `game` as a crash would and takes the run file it leaves: its events from the round's
    /// `roundStarted` on.
    private func crash(_ game: Game) throws -> PendingRun {
        let start = try #require(recorder.events.lastIndex { $0.event.type == "roundStarted" })
        let events = Array(recorder.events[start...])
        let round = try #require(logged(RoundStarted.self).last?.round)
        game.appWillTerminate()
        return PendingRun(round: round, file: URL(fileURLWithPath: "/tmp/unused-run.jsonl"), events: events)
    }

    @Test func aGuitarRoundComesBackOnTheGuitar() throws {
        onGuitar(.dropD)
        game.settings.range = NoteRange(below: true, above: true, ledgerLines: 4)
        game.start()
        for _ in 0..<3 { try playRight() }
        let question = try #require(game.question)
        let run = try crash(game)

        let later = MemoryUsageRecorder()
        let restored = relaunch(recorder: later)
        restored.restore(run)
        #expect(restored.phase == .playing && restored.isPausedAfterCrash && restored.score == 3)
        #expect(restored.question?.clef == .treble8vb && restored.question?.pitch == question.pitch)
        #expect(restored.guitarTuning == .dropD)
        restored.resume()
        let shown = try #require(logged(QuestionShown.self, in: later).last)
        #expect(shown.clef == "treble8vb" && shown.pitch == LoggedPitch(question.pitch))
        #expect(shown.guitarTuning == "dropD" && shown.guitarFrets == restored.fretboard.frets)
        try playRight(on: restored)
        #expect(restored.score == 4 && restored.attempts == 4)
        let answer = try #require(logged(AnswerGiven.self, in: later).last)
        #expect(answer.source == .guitar && answer.correct && answer.guitarString != nil)
    }

    @Test func aGuitarRoundIsNotBroughtBackForAnotherInputOrTuning() throws {
        for change in [{ (game: Game) in game.settings.answerInput = .buttons },
                       { (game: Game) in game.settings.guitarTuning = .standard }] {
            onGuitar(.dropD)
            game.start()
            try playRight()
            let run = try crash(game)
            change(game)

            let later = MemoryUsageRecorder()
            let restored = relaunch(recorder: later)
            restored.restore(run)
            #expect(restored.phase == .idle && restored.question == nil)
            #expect(logged(RoundEnded.self, in: later).last?.reason == .interrupted)
        }
    }

    @Test func aRoundOnAnotherInputStillComesBackWhenTheInputChanges() throws {
        game.settings.answerInput = .piano
        game.start()
        if let question = game.question { game.answer(question.pitch) }
        let run = try crash(game)
        game.settings.answerInput = .keyboard

        let restored = relaunch(recorder: MemoryUsageRecorder())
        restored.restore(run)
        #expect(restored.phase == .playing && restored.question?.clef == .treble)
    }

    /// "Lantern at Dusk"'s left hand goes down to B1, below any guitar's reach in these tunings.
    @Test func aGuitarPieceRoundComesBackWithoutTheNotesOutOfReach() throws {
        onGuitar()
        game.openPiece(at: try #require(Fixtures.url("bar-view.musicxml")))
        try #require(game.pieceError == nil)
        game.settings.piece.hand = .left
        let outOfReach = game.guitarNotesOutOfReach
        #expect(outOfReach >= 3)
        let noteCount = game.pieceRoundNoteCount
        game.start()
        #expect(logged(RoundStarted.self).last?.piece?.noteCount == noteCount)
        for _ in 0..<4 { try playRight() }
        let progress = game.pieceProgress
        let run = try crash(game)

        let later = MemoryUsageRecorder()
        let restored = relaunch(recorder: later)
        restored.restore(run)
        #expect(restored.phase == .playing && restored.isPausedAfterCrash)
        #expect(restored.pieceProgress == progress)
        #expect(restored.guitarNotesOutOfReach == outOfReach)
        restored.resume()
        var answered = 0
        while restored.phase == .playing, answered < 500 {
            try playRight(on: restored)
            answered += 1
        }
        let summary = try #require(restored.summary)
        #expect(summary.finishedPiece && summary.score == summary.attempts)
        // Every note of the round once, across the crash: only those in reach.
        let answers = (logged(AnswerGiven.self) + logged(AnswerGiven.self, in: later)).filter { $0.round == run.round }
        #expect(answers.count == noteCount)
        #expect(answers.allSatisfy { Fretboard.canPlay($0.pitch?.midi ?? 0, in: .standard) })
    }
}

private let otherTuneURL = URL(fileURLWithPath: "/tmp/clefwise-tests/other-guitar-tune.musicxml")
