import Foundation
import Testing
@testable import Clefwise

// MARK: - Hand-built scores

/// A note for a hand-built score: treble on the upper staff, bass on the lower, unless told otherwise.
private func note(_ pitch: Pitch, staff: Int = 1, bar: Int = 1, onset: Double = 0, chord: Int,
                  clef: Clef? = nil, key: KeySignature = .cMajor, printed: Accidental? = nil,
                  shift: Int = 0) -> ScoreNote {
    ScoreNote(pitch: pitch, clef: clef ?? (staff == 1 ? .treble : .bass), keySignature: key,
              printedAccidental: printed, octaveShift: shift, staff: staff, measure: bar, onset: onset,
              chord: chord)
}

/// A one-part score; the notes must already be in reading order.
private func score(title: String = "Test piece", staves: Int = 1, bars: Int? = nil,
                   _ notes: [ScoreNote]) -> Score {
    Score(title: title, parts: [ScorePart(name: "Piano", notes: notes,
                                          measureCount: bars ?? notes.map(\.measure).max() ?? 1,
                                          staffCount: staves, skippedNoteCount: 0)])
}

/// Bar 1: a C3–G3 chord in the left hand under an E4–G4–C5 chord in the right, then D5.
/// Bar 2: F2 under A4. Bar 3: B4, then G2. Bar 4 is a rest.
private let twoHands = score(title: "Two hands", staves: 2, bars: 4, [
    note(Pitch(.c, 3), staff: 2, onset: 0, chord: 10),
    note(Pitch(.g, 3), staff: 2, onset: 0, chord: 10),
    note(Pitch(.e, 4), onset: 0, chord: 1),
    note(Pitch(.g, 4), onset: 0, chord: 1),
    note(Pitch(.c, 5), onset: 0, chord: 1),
    note(Pitch(.d, 5), onset: 1, chord: 2),
    note(Pitch(.f, 2), staff: 2, bar: 2, onset: 4, chord: 11),
    note(Pitch(.a, 4), bar: 2, onset: 4, chord: 3),
    note(Pitch(.b, 4), bar: 3, onset: 8, chord: 4),
    note(Pitch(.g, 2), staff: 2, bar: 3, onset: 9, chord: 12),
])

private let rightHand = [Pitch(.e, 4), Pitch(.g, 4), Pitch(.c, 5), Pitch(.d, 5), Pitch(.a, 4), Pitch(.b, 4)]
private let leftHand = [Pitch(.c, 3), Pitch(.g, 3), Pitch(.f, 2), Pitch(.g, 2)]
private let bothHands = [Pitch(.c, 3), Pitch(.g, 3), Pitch(.e, 4), Pitch(.g, 4), Pitch(.c, 5), Pitch(.d, 5),
                         Pitch(.f, 2), Pitch(.a, 4), Pitch(.b, 4), Pitch(.g, 2)]

private let gMajor = KeySignature(fifths: 1)

/// G4, F♯4 from the key, F♯4 again, then F4 with a printed natural.
private let gMajorTune = score(title: "In G", [
    note(Pitch(.g, 4), onset: 0, chord: 1, key: gMajor),
    note(Pitch(.f, 4, .sharp), onset: 1, chord: 2, key: gMajor),
    note(Pitch(.f, 4, .sharp), onset: 2, chord: 3, key: gMajor),
    note(Pitch(.f, 4), onset: 3, chord: 4, key: gMajor, printed: .natural),
])

private let fileURL = URL(fileURLWithPath: "/tmp/clefwise-tests/two-hands.musicxml")
private let otherFileURL = URL(fileURLWithPath: "/tmp/clefwise-tests/other.musicxml")

// MARK: - Test bench

/// Defaults kept in memory only. A throwaway suite would leave an empty plist in
/// ~/Library/Preferences for every test, even after `removePersistentDomain(forName:)`.
final class InMemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    override func object(forKey key: String) -> Any? { values[key] }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
}

/// A game with its own throwaway defaults, its usage events kept in memory, and no sound.
@MainActor
class GameTestBench {
    let defaults: UserDefaults = InMemoryDefaults()
    /// Never the real usage log: every `Game` in the tests gets one of these.
    let recorder = MemoryUsageRecorder()
    /// Never the real piece library either: a folder of its own in the temporary directory.
    let library = PieceLibrary.temporary()
    let game: Game

    init() {
        game = Game(defaults: defaults, recorder: recorder, library: library)
        game.settings.isMuted = true
    }

    /// The app starting again on the same defaults and library, with its own log.
    func relaunch(recorder: MemoryUsageRecorder = MemoryUsageRecorder()) -> Game {
        Game(defaults: defaults, recorder: recorder, library: library)
    }

    /// Answers the current question right, on the piano; returns what was asked.
    @discardableResult
    func answerRight() -> Pitch? {
        guard let question = game.question else { return nil }
        game.answer(question.pitch)
        return question.pitch
    }

    /// Starts a round and answers every note right until it ends (or `limit` notes); returns the notes asked.
    func playRound(limit: Int = 100) -> [Pitch] {
        game.start()
        var asked: [Pitch] = []
        while game.phase == .playing, asked.count < limit, let pitch = answerRight() {
            asked.append(pitch)
        }
        return asked
    }

    /// Waits for the miss pause and other short delays.
    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

// MARK: - Piece rounds

@MainActor
@Suite final class PieceRoundTests: GameTestBench {
    @Test func inOrderWalksEachHand() {
        game.open(twoHands, from: fileURL)

        game.settings.piece.hand = .right
        #expect(playRound() == rightHand)
        #expect(game.summary?.finishedPiece == true)

        game.settings.piece.hand = .left
        #expect(playRound() == leftHand)
        #expect(game.summary?.finishedPiece == true)

        game.settings.piece.hand = .both
        #expect(playRound() == bothHands)
        #expect(game.summary?.finishedPiece == true)
    }

    @Test func questionsComeFromTheScore() {
        game.settings.piece.hand = .both
        game.open(twoHands, from: fileURL)
        game.start()
        #expect(game.question?.clef == .bass)
        #expect(game.displayedClef == .bass)
        answerRight()
        answerRight()
        #expect(game.question?.clef == .treble)
        #expect(game.question?.pitch == Pitch(.e, 4))
        #expect(game.displayedClef == .treble)
    }

    @Test func singleStaffPartsIgnoreTheHand() {
        game.settings.piece.hand = .left
        game.open(gMajorTune, from: fileURL)
        #expect(playRound().count == 4)
    }

    @Test func startsFromTheStartBar() {
        game.settings.piece.hand = .both
        game.open(twoHands, from: fileURL)
        game.settings.piece.startBar = 2
        game.start()
        #expect(game.pieceProgress == Game.PieceProgress(bar: 2, bars: 4, done: 0, total: 4))
        game.stop()
        #expect(playRound() == [Pitch(.f, 2), Pitch(.a, 4), Pitch(.b, 4), Pitch(.g, 2)])
    }

    @Test func oneNotePerChordKeepsTheTopInTheRightHandAndTheBottomInTheLeft() {
        game.settings.piece.oneNotePerChord = true
        game.open(twoHands, from: fileURL)

        game.settings.piece.hand = .both
        #expect(playRound() == [Pitch(.c, 3), Pitch(.c, 5), Pitch(.d, 5), Pitch(.f, 2), Pitch(.a, 4),
                                Pitch(.b, 4), Pitch(.g, 2)])
        game.settings.piece.hand = .right
        #expect(playRound() == [Pitch(.c, 5), Pitch(.d, 5), Pitch(.a, 4), Pitch(.b, 4)])
        game.settings.piece.hand = .left
        #expect(playRound() == [Pitch(.c, 3), Pitch(.f, 2), Pitch(.g, 2)])
    }

    @Test func aRoundFinishesAfterTheLastNote() throws {
        game.open(twoHands, from: fileURL)
        _ = playRound()
        #expect(game.phase == .finished)
        #expect(game.question == nil)
        #expect(game.pieceProgress == nil)
        let summary = try #require(game.summary)
        #expect(summary.finishedPiece)
        #expect(summary.pieceTitle == "Two hands")
        #expect(summary.score == 6)
        #expect(summary.attempts == 6)
        #expect(!summary.timeRanOut)
        #expect(!summary.mixedClefs)

        game.settings.piece.hand = .both
        _ = playRound()
        #expect(game.summary?.mixedClefs == true)
    }

    @Test func stoppingEarlyDoesNotFinishThePiece() {
        game.open(twoHands, from: fileURL)
        game.start()
        answerRight()
        game.stop()
        #expect(game.summary?.finishedPiece == false)
        #expect(game.summary?.pieceTitle == "Two hands")
    }

    @Test func theLastNoteEndsTheRoundRatherThanGoingRoundAgain() {
        game.open(twoHands, from: fileURL)
        // Asked for more notes than the piece has: it doesn't start again from the start bar.
        #expect(playRound(limit: 8) == rightHand)
        #expect(game.phase == .finished && game.summary?.finishedPiece == true)
        #expect(game.pieceProgress == nil)

        // Nor does a time limit keep it going: pieces ignore it.
        game.settings.practiceLimit = .time
        #expect(playRound(limit: 8) == rightHand)
        #expect(game.summary?.finishedPiece == true && game.summary?.timeRanOut == false)
    }

    @Test func shuffledDrawsOnlyFromTheSelectionAndNeverRepeatsAtOnce() {
        game.settings.piece.order = .shuffled
        game.open(twoHands, from: fileURL)
        let asked = playRound(limit: 200)
        #expect(asked.count == 200)
        #expect(game.phase == .playing) // shuffled rounds don't end with the piece
        #expect(Set(asked) == Set(rightHand))
        #expect(zip(asked, asked.dropFirst()).allSatisfy { $0 != $1 })
        #expect(game.pieceProgress?.done == 200)
        #expect(game.pieceProgress?.total == 6)
        game.stop()
        #expect(game.summary?.finishedPiece == false)
    }

    @Test func shuffledRepeatsWhenThereIsNothingElse() {
        game.settings.piece.order = .shuffled
        game.open(score([note(Pitch(.c, 4), onset: 0, chord: 1), note(Pitch(.c, 4), onset: 1, chord: 2)]),
                  from: fileURL)
        #expect(playRound(limit: 5) == Array(repeating: Pitch(.c, 4), count: 5))
    }

    @Test func gMajorPieceTakesSharpAnswers() throws {
        game.open(gMajorTune, from: fileURL)
        #expect(game.currentKeySignature == gMajor)
        #expect(game.accidentalsPossible)
        game.start()

        #expect(game.question?.keySignature == gMajor)
        game.answer(.g, .natural)
        let fSharp = try #require(game.question)
        #expect(fSharp.pitch == Pitch(.f, 4, .sharp))
        #expect(fSharp.printedAccidental == nil)
        game.answer(.f, .sharp)
        #expect(game.score == 2)
        // The piano goes by sound, so the black key counts whichever way it's spelled.
        game.answer(Pitch(.g, 4, .flat))
        #expect(game.score == 3)
        #expect(game.question?.printedAccidental == .natural)
        game.answer(.f, .natural)
        #expect(game.score == 4)
        #expect(game.summary?.finishedPiece == true)

        let stats = try #require(defaults.data(forKey: "noteStats")
            .flatMap { try? JSONDecoder().decode([String: NoteStat].self, from: $0) })
        #expect(stats["treble.F♯4"]?.correct == 2)
    }

    @Test func eightVaNoteIsWrittenLowAndAnsweredAsItSounds() throws {
        game.open(score([note(Pitch(.e, 6), onset: 0, chord: 1, shift: 1),
                         note(Pitch(.e, 6), onset: 1, chord: 2, shift: 1)]), from: fileURL)
        #expect(game.pianoKeys.contains(Pitch(.e, 6).diatonicIndex))
        #expect(game.staffPositionsToFit == nil)
        game.start()

        let question = try #require(game.question)
        #expect(question.octaveShift == 1)
        #expect(question.writtenPitch == Pitch(.e, 5))
        #expect(question.position == 7)
        game.answer(Pitch(.e, 6))
        #expect(game.score == 1)
        // The key where it's written is an octave too low.
        game.answer(Pitch(.e, 5))
        #expect(game.score == 1)
        #expect(game.flash?.isCorrect == false)
    }

    @Test func accidentalsPossibleGoesByTheSelectedNotes() {
        // The toolbar's key and accidentals don't apply to a piece.
        game.settings.key = .fixed(KeySignature(fifths: 2))
        game.settings.addsAccidentals = true
        game.open(twoHands, from: fileURL)
        #expect(!game.accidentalsPossible)

        game.open(score(staves: 2, [note(Pitch(.f, 3, .sharp), staff: 2, chord: 1, printed: .sharp),
                                    note(Pitch(.c, 5), chord: 2)]), from: otherFileURL)
        game.settings.piece.hand = .right
        #expect(!game.accidentalsPossible)
        game.settings.piece.hand = .left
        #expect(game.accidentalsPossible)
        game.settings.piece.hand = .both
        #expect(game.accidentalsPossible)
    }

    @Test func pianoCoversTheSelectedNotesInWholeOctaves() {
        game.open(twoHands, from: fileURL)
        game.settings.piece.hand = .both
        #expect(game.pianoKeys == Pitch(.c, 2).diatonicIndex...Pitch(.b, 5).diatonicIndex)
        game.settings.piece.hand = .right
        #expect(game.pianoKeys == Pitch(.c, 4).diatonicIndex...Pitch(.b, 5).diatonicIndex)
        game.settings.piece.hand = .left
        #expect(game.pianoKeys == Pitch(.c, 2).diatonicIndex...Pitch(.b, 3).diatonicIndex)

        // C♭4 is played on B3.
        game.open(score([note(Pitch(.c, 4, .flat), chord: 1, printed: .flat)]), from: otherFileURL)
        #expect(game.pianoKeys == Pitch(.c, 3).diatonicIndex...Pitch(.b, 3).diatonicIndex)
    }

    @Test func staffFitsNotesBeyondThreeLedgerLines() {
        game.open(twoHands, from: fileURL)
        #expect(game.staffPositionsToFit == nil)

        // C1 is eleven steps under the bass staff, C7 nineteen over the bottom treble line.
        game.open(score(staves: 2, [note(Pitch(.c, 1), staff: 2, chord: 1), note(Pitch(.c, 7), chord: 2)]),
                  from: otherFileURL)
        game.settings.piece.hand = .both
        #expect(game.staffPositionsToFit == -11...19)
        game.settings.piece.hand = .right
        #expect(game.staffPositionsToFit == 19...19)

        // Under 8va the same C7 is written as C6, within three ledger lines.
        game.open(score([note(Pitch(.e, 4), chord: 1), note(Pitch(.c, 7), onset: 1, chord: 2, shift: 1)]),
                  from: otherFileURL)
        #expect(game.staffPositionsToFit == nil)
    }

    @Test func progressFollowsTheRound() {
        game.settings.piece.hand = .both
        game.open(twoHands, from: fileURL)
        #expect(game.pieceProgress == nil)
        game.start()
        #expect(game.pieceProgress == Game.PieceProgress(bar: 1, bars: 4, done: 0, total: 10))
        for _ in 0..<6 { answerRight() }
        #expect(game.pieceProgress == Game.PieceProgress(bar: 2, bars: 4, done: 6, total: 10))
        game.stop()
        #expect(game.pieceProgress == nil)
    }

    @Test func nothingToAskSetsAnErrorInsteadOfStarting() {
        game.settings.piece.hand = .both
        game.open(twoHands, from: fileURL)
        game.settings.piece.startBar = 4 // only a rest
        game.start()
        #expect(game.phase == .idle)
        #expect(game.question == nil)
        #expect(game.pieceError?.contains("bar 4") == true)

        // A grand staff with nothing in the left hand.
        game.open(score(staves: 2, [note(Pitch(.c, 5), chord: 1)]), from: otherFileURL)
        game.settings.piece.hand = .left
        game.start()
        #expect(game.phase == .idle)
        #expect(game.pieceError?.contains("left-hand") == true)

        game.settings.piece.hand = .right
        game.start()
        #expect(game.phase == .playing)
        #expect(game.pieceError == nil)
    }

    @Test func openAndCloseEndARoundQuietly() {
        game.open(twoHands, from: fileURL)
        game.start()
        answerRight()
        answerRight()
        game.open(gMajorTune, from: otherFileURL)
        #expect(game.phase == .idle)
        #expect(game.summary == nil)
        #expect(game.question == nil)
        #expect(game.score == 0)
        #expect(game.piece?.title == "In G")

        game.start()
        answerRight()
        game.closePiece()
        #expect(game.phase == .idle)
        #expect(game.summary == nil)
        #expect(!game.isPractisingPiece)
        #expect(game.settings.piecePath == nil)

        // A summary on screen goes too.
        game.open(gMajorTune, from: otherFileURL)
        _ = playRound()
        #expect(game.phase == .finished)
        game.closePiece()
        #expect(game.phase == .idle)
        #expect(game.summary == nil)
    }

    @Test func reopeningKeepsPieceSettingsAndAnotherFileStartsAtBarOne() {
        game.open(twoHands, from: fileURL)
        game.settings.piece.startBar = 3
        game.open(twoHands, from: fileURL)
        #expect(game.settings.piece.startBar == 3)
        #expect(game.settings.piecePath == fileURL.path)

        game.open(twoHands, from: otherFileURL)
        #expect(game.settings.piece.startBar == 1)
        #expect(game.pieceURL == otherFileURL)
    }

    @Test func partAndStartBarStayWithinThePiece() {
        let twoParts = Score(title: "Duet", parts: twoHands.parts + gMajorTune.parts)
        game.open(twoParts, from: fileURL)
        game.settings.piece.startBar = 3
        // The second part has one bar.
        game.settings.piece.part = 1
        #expect(game.settings.piece.startBar == 1)
        #expect(game.piecePart?.notes.count == 4)
        game.open(gMajorTune, from: otherFileURL)
        #expect(game.settings.piece.part == 0)

        game.open(twoHands, from: fileURL)
        game.settings.piece.startBar = 99
        #expect(game.settings.piece.startBar == 4)
        game.settings.piece.startBar = 0
        #expect(game.settings.piece.startBar == 1)

        // The same file again, now two bars long.
        game.settings.piece.startBar = 4
        game.open(score(staves: 2, bars: 2, Array(twoHands.parts[0].notes.prefix(8))), from: fileURL)
        #expect(game.settings.piece.startBar == 2)
    }

    @Test func pieceSettingsWaitForTheNextRound() {
        game.open(twoHands, from: fileURL)
        game.start()
        answerRight()
        game.settings.piece.hand = .left
        #expect(game.question?.pitch == Pitch(.g, 4))
        #expect(game.pieceProgress?.total == 6)
        game.stop()
        #expect(playRound() == leftHand)
    }

    @Test func aMissStillMovesOn() async throws {
        game.open(twoHands, from: fileURL)
        game.start()
        game.answer(Pitch(.c, 1))
        #expect(game.isShowingMiss)
        game.answer(Pitch(.e, 4)) // too late: ignored during the pause
        #expect(game.attempts == 1)
        try await waitUntil { !game.isShowingMiss }
        #expect(game.question?.pitch == Pitch(.g, 4))
        #expect(game.pieceProgress?.done == 1)
    }

    @Test func missingTheLastNoteStillFinishesThePiece() async throws {
        game.open(twoHands, from: fileURL)
        game.settings.piece.startBar = 3
        game.start()
        #expect(game.question?.pitch == Pitch(.b, 4))
        game.answer(Pitch(.c, 1))
        try await waitUntil { game.phase == .finished }
        #expect(game.summary?.finishedPiece == true)
        #expect(game.summary?.score == 0)
        #expect(game.summary?.notesToReview == [StaffNote(clef: .treble, pitch: Pitch(.b, 4))])
    }

    @Test func aPieceThatIsGoneIsForgottenAtLaunch() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("clefwise-\(UUID()).musicxml")
        game.open(twoHands, from: missing)
        game.settings.piece.startBar = 3
        #expect(game.settings.piecePath == missing.path)

        let relaunched = relaunch()
        #expect(relaunched.settings.piece.startBar == 3) // it did read the saved settings
        #expect(relaunched.piece == nil)
        #expect(relaunched.settings.piecePath == nil)
        #expect(relaunched.pieceError == nil)
        #expect(relaunch().settings.piecePath == nil)
    }

    @Test func aPieceThatNoLongerReadsIsForgottenAtLaunch() throws {
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("clefwise-\(UUID()).musicxml")
        try Data("not a score".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        game.open(twoHands, from: junk)

        let relaunched = relaunch()
        #expect(relaunched.piece == nil)
        #expect(relaunched.settings.piecePath == nil)
        #expect(relaunched.pieceError == nil)
    }
}

// MARK: - Random rounds

@MainActor
@Suite final class RandomRoundTests: GameTestBench {
    @Test func questionsFollowTheToolbarSettings() throws {
        #expect(game.pieceProgress == nil)
        #expect(game.staffPositionsToFit == nil)
        #expect(!game.accidentalsPossible)
        #expect(game.pianoKeys == Pitch(.c, 4).diatonicIndex...Pitch(.b, 5).diatonicIndex)
        #expect(game.displayedClef == .treble)

        game.start()
        var asked: [Question] = []
        for _ in 0..<60 {
            let question = try #require(game.question)
            asked.append(question)
            answerRight()
        }
        #expect(asked.allSatisfy { $0.clef == .treble && (0...8).contains($0.position) })
        #expect(asked.allSatisfy { $0.keySignature == .cMajor && $0.printedAccidental == nil && $0.octaveShift == 0 })
        #expect(zip(asked, asked.dropFirst()).allSatisfy { $0.pitch != $1.pitch })
        #expect(game.pieceProgress == nil)
        game.stop()
        #expect(game.summary?.pieceTitle == nil)
        #expect(game.summary?.finishedPiece == false)
    }

    @Test func keySettingStillApplies() {
        game.settings.key = .fixed(gMajor)
        #expect(game.accidentalsPossible)
        #expect(game.currentKeySignature == gMajor)
        game.start()
        #expect(game.question?.keySignature == gMajor)
    }

    @Test func closingAPieceGoesBackToRandomNotes() {
        game.settings.clefChoice = .bass
        game.open(twoHands, from: fileURL)
        game.closePiece()
        game.start()
        #expect(game.question?.clef == .bass)
        #expect(game.pieceProgress == nil)
        #expect(game.pianoKeys == Pitch(.c, 2).diatonicIndex...Pitch(.b, 3).diatonicIndex)
    }
}
