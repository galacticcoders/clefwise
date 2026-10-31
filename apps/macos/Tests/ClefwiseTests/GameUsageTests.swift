import Foundation
import Testing
@testable import Clefwise

// What `Game` records in the usage log. Every game here logs to a `MemoryUsageRecorder` and keeps
// its settings in memory (see `GameTestBench`), so nothing reaches the real log or preferences.

private func fixture(_ name: String) throws -> URL {
    try #require(Fixtures.url(name))
}

/// G major, one part on one staff: G4 and F♯4 in bar 1, then E6 under an 8va line (written E5) in bar 2.
private let tune = Score(title: "Usage tune", parts: [ScorePart(name: "Flute", notes: [
    ScoreNote(pitch: Pitch(.g, 4), clef: .treble, keySignature: KeySignature(fifths: 1), printedAccidental: nil,
              octaveShift: 0, staff: 1, measure: 1, onset: 0, chord: 1),
    ScoreNote(pitch: Pitch(.f, 4, .sharp), clef: .treble, keySignature: KeySignature(fifths: 1), printedAccidental: nil,
              octaveShift: 0, staff: 1, measure: 1, onset: 1, chord: 2),
    ScoreNote(pitch: Pitch(.e, 6), clef: .treble, keySignature: KeySignature(fifths: 1), printedAccidental: nil,
              octaveShift: 1, staff: 1, measure: 2, onset: 4, chord: 3),
], measureCount: 4, staffCount: 1, skippedNoteCount: 0)])

private let tuneURL = URL(fileURLWithPath: "/tmp/clefwise-usage-tests/tune.musicxml")

private extension GameTestBench {
    /// The payloads of type `T` logged so far, in order.
    func logged<T>(_ type: T.Type) -> [T] {
        recorder.events.compactMap { $0.event.payload as? T }
    }

    var types: [String] { recorder.events.map(\.event.type) }

    @discardableResult
    func press(_ characters: String, keyCode: UInt16 = 0) -> Bool {
        game.handleKey(characters: characters, keyCode: keyCode)
    }

    /// Long enough for times measured from a question to pass a millisecond.
    func pause() async throws {
        try await Task.sleep(for: .milliseconds(5))
    }

    /// A note-button answer that isn't the question's letter.
    func wrongLetter() throws -> NoteLetter {
        let question = try #require(game.question)
        return try #require(NoteLetter.allCases.first { $0 != question.pitch.letter })
    }
}

@MainActor
@Suite final class GameUsageTests: GameTestBench {
    // MARK: Stats snapshot

    @Test func statsAreSnapshottedOncePerStore() {
        #expect(types.first == "statsSnapshot")
        #expect(logged(StatsSnapshot.self) == [StatsSnapshot(reason: "beforeUsageLog", noteStats: [:], bestScores: [:])])

        game.start()
        answerRight()
        game.stop()
        let later = MemoryUsageRecorder()
        _ = relaunch(recorder: later)
        #expect(!later.events.contains { $0.event.type == "statsSnapshot" })
    }

    @Test func theSnapshotHoldsWhatTheAppKnewBefore() throws {
        let older = InMemoryDefaults()
        let stats = ["treble.C4": NoteStat(attempts: 3, correct: 2, recent: [true, false, true])]
        older.set(try JSONEncoder().encode(stats), forKey: "noteStats")
        older.set(try JSONEncoder().encode(["treble.staff": 12]), forKey: "bestScores")
        let recorder = MemoryUsageRecorder()
        _ = Game(defaults: older, recorder: recorder)
        #expect(recorder.events.map(\.event) == [
            .statsSnapshot(StatsSnapshot(reason: "beforeUsageLog", noteStats: stats, bestScores: ["treble.staff": 12])),
        ])
        #expect(older.object(forKey: "usageLogStarted") != nil)
    }

    // MARK: Questions and answers

    @Test func randomRoundsLogQuestionsAndClickedAnswers() async throws {
        game.settings.mode = .practice
        game.start()
        let started = try #require(logged(RoundStarted.self).last)
        #expect(started.via == .button)
        #expect(started.keyFifths == 0)
        #expect(started.piece == nil)
        #expect(started.settings == JSONValue(encoding: game.settings))

        for index in 0..<3 {
            let question = try #require(game.question)
            let shown = try #require(logged(QuestionShown.self).last)
            #expect(shown.round == started.round)
            #expect(shown.question == question.id)
            #expect(shown.index == index)
            #expect(shown.clef == "treble")
            #expect(shown.pitch == LoggedPitch(question.pitch))
            #expect(shown.written == shown.pitch)
            #expect(shown.position == question.position)
            #expect(shown.keyFifths == 0 && shown.printedAccidental == nil && shown.octaveShift == 0)
            #expect(shown.pieceNote == nil)
            #expect(shown.barView == nil && shown.barStaves == nil)
            let chance = try #require(shown.pickChance)
            #expect(chance > 0 && chance <= 1)
            #expect(shown.naming == "letters" && shown.input == "buttons")
            #expect(!shown.hintsVisible && !shown.keyNamesVisible)

            try await pause()
            game.answer(question.pitch.letter)
            let answer = try #require(logged(AnswerGiven.self).last)
            #expect(answer.round == started.round && answer.question == question.id)
            #expect(answer.source == .click)
            #expect(answer.responseMs > 0)
            #expect(answer.letter == question.pitch.letter.name && answer.accidental == 0)
            #expect(answer.name == question.pitch.letter.name)
            #expect(answer.pitch == nil && answer.wrongOctave == nil)
            #expect(answer.correct)
            #expect(answer.keystrokes.isEmpty)
            #expect(answer.scoreAfter == index + 1 && answer.streakAfter == index + 1)
        }
    }

    @Test func shortcutsKeepTheirKeys() async throws {
        game.settings.mode = .practice
        game.start()
        var question = try #require(game.question)
        let letter = question.pitch.letter.name.lowercased()
        try await pause()
        #expect(press(letter))
        var answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.source == .shortcut && answer.correct)
        #expect(answer.keystrokes.map(\.key) == [letter])
        #expect(answer.keystrokes.map(\.result) == [.submitted])
        #expect(answer.keystrokes[0].ms > 0 && answer.keystrokes[0].ms <= answer.responseMs)

        // 1–7 by button position, after "h" shows the hints.
        question = try #require(game.question)
        let digit = String(question.pitch.letter.rawValue + 1)
        press("h")
        press(digit)
        answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.source == .shortcut && answer.correct)
        #expect(answer.keystrokes.map(\.key) == ["h", digit])
        #expect(answer.keystrokes.map(\.result) == [.other, .submitted])
        #expect(logged(SettingChanged.self).last == SettingChanged(setting: "showHints", from: .bool(false), to: .bool(true)))
        #expect(logged(QuestionShown.self).last?.hintsVisible == true)
    }

    @Test func typingLogsEveryKeystroke() async throws {
        game.settings.mode = .practice
        game.settings.answerInput = .keyboard
        // With sharps about, a whole name waits for Return in case a ♯ or ♭ follows.
        game.settings.key = .fixed(KeySignature(fifths: 1))
        game.start()
        let question = try #require(game.question)
        let letter = question.pitch.letter.name.lowercased()
        try await pause()
        press("x") // no name starts with x
        press(letter)
        press("\u{7f}", keyCode: 51)
        press(letter)
        if question.pitch.accidental == .sharp { press("#") } else { press("\r", keyCode: 36) }

        let answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.source == .typing && answer.correct)
        #expect(answer.question == question.id)
        let keystrokes = answer.keystrokes
        #expect(keystrokes.map(\.key) == ["x", letter, "Delete", letter, question.pitch.accidental == .sharp ? "#" : "Return"])
        #expect(keystrokes.map(\.result) == [.rejected, .typed, .deleted, .typed, .submitted])
        #expect(keystrokes[0].ms > 0)
        #expect(zip(keystrokes, keystrokes.dropFirst()).allSatisfy { $0.ms <= $1.ms })
        #expect(answer.responseMs >= keystrokes[4].ms)
        #expect(logged(QuestionShown.self).first?.input == "keyboard")
    }

    @Test func armingASignOnTheNoteButtonsIsLogged() async throws {
        game.settings.mode = .practice
        game.settings.key = .fixed(KeySignature(fifths: 1))
        game.start()
        let question = try #require(game.question)
        let letter = question.pitch.letter
        try await pause()
        press("#")
        press("#") // disarms
        press("=")
        press(letter.name.lowercased())

        let answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.keystrokes.map(\.key) == ["#", "#", "=", letter.name.lowercased()])
        #expect(answer.keystrokes.map(\.result) == [.armed, .armed, .armed, .submitted])
        #expect(answer.accidental == 1)
        #expect(answer.name == "\(letter.name)♯")
        #expect(answer.correct == (question.pitch.accidental == .sharp))
    }

    @Test func pianoAnswersKeepTheKeyAndTellAWrongOctave() async throws {
        game.settings.mode = .practice
        game.settings.answerInput = .piano
        game.settings.showKeyNames = true
        game.start()
        #expect(logged(QuestionShown.self).last?.keyNamesVisible == true)
        var question = try #require(game.question)
        let octaveUp = Pitch(question.pitch.letter, question.pitch.octave + 1, question.pitch.accidental)
        try await pause()
        press("k") // hides the key names
        game.answer(octaveUp)

        var answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.source == .piano)
        #expect(answer.pitch == LoggedPitch(octaveUp))
        #expect(!answer.correct && answer.wrongOctave == true)
        #expect(answer.scoreAfter == 0 && answer.streakAfter == 0)
        #expect(answer.keystrokes.map(\.key) == ["k"])
        #expect(answer.keystrokes.map(\.result) == [.other])

        try await waitUntil { !game.isShowingMiss }
        question = try #require(game.question)
        #expect(logged(QuestionShown.self).last?.keyNamesVisible == false)
        game.answer(question.pitch)
        answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.correct && answer.wrongOctave == false)
        #expect(answer.name == question.pitch.letter.name)
        #expect(answer.scoreAfter == 1 && answer.streakAfter == 1)
        // A different note altogether isn't a wrong octave.
        question = try #require(game.question)
        game.answer(Pitch(question.pitch.letter == .c ? .d : .c, question.pitch.octave))
        #expect(logged(AnswerGiven.self).last?.wrongOctave == false)
    }

    @Test func aSargamAnswerIsNamedAsASwara() throws {
        game.settings.mode = .practice
        game.settings.naming = .sargam
        game.settings.answerInput = .piano
        game.start()
        let question = try #require(game.question)
        game.answer(question.pitch)
        #expect(logged(AnswerGiven.self).last?.name == NamingSystem.sargam.name(of: question.pitch))
        #expect(logged(QuestionShown.self).first?.naming == "sargam")
    }

    // MARK: Ignored input

    @Test func inputWithNoRoundIsIgnored() {
        press("c")
        game.answer(Pitch(.c, 4))
        game.settings.answerInput = .keyboard
        #expect(!press("f"))
        game.settings.answerInput = .buttons
        game.settings.key = .fixed(KeySignature(fifths: 1))
        #expect(press("#"))
        #expect(logged(InputIgnored.self) == [
            InputIgnored(round: nil, reason: "noRound", source: .shortcut, detail: "C"),
            InputIgnored(round: nil, reason: "noRound", source: .piano, detail: "C4"),
            InputIgnored(round: nil, reason: "noRound", source: .typing, detail: "f"),
            InputIgnored(round: nil, reason: "noRound", source: .shortcut, detail: "#"),
        ])
    }

    @Test func answersDuringTheMissPauseAreIgnored() throws {
        game.settings.mode = .practice
        game.start()
        let round = try #require(logged(RoundStarted.self).last).round
        let question = try #require(game.question)
        let name = question.pitch.letter.name
        game.answer(try wrongLetter())
        game.answer(question.pitch.letter)
        press(name.lowercased())
        game.answer(question.pitch)
        #expect(logged(InputIgnored.self) == [
            InputIgnored(round: round, reason: "missPause", source: .click, detail: name),
            InputIgnored(round: round, reason: "missPause", source: .shortcut, detail: name),
            InputIgnored(round: round, reason: "missPause", source: .piano, detail: question.pitch.name),
        ])
        #expect(logged(AnswerGiven.self).count == 1)
        #expect(game.attempts == 1)
    }

    @Test func typingDuringTheMissPauseIsIgnored() throws {
        game.settings.mode = .practice
        game.settings.answerInput = .keyboard
        game.start()
        let round = try #require(logged(RoundStarted.self).last).round
        press(try wrongLetter().name.lowercased())
        press("d")
        #expect(logged(InputIgnored.self) == [InputIgnored(round: round, reason: "missPause", source: .typing, detail: "d")])
    }

    @Test func komalSaIsIgnored() async throws {
        game.settings.mode = .practice
        game.settings.naming = .sargam
        game.settings.key = .fixed(KeySignature(fifths: -1)) // F major, so ♭ is on offer
        game.start()
        let round = try #require(logged(RoundStarted.self).last).round
        let question = try #require(game.question)
        try await pause()
        game.toggleArmedAccidental(.flat)
        game.answer(.c)
        press("1")
        #expect(logged(InputIgnored.self) == [
            InputIgnored(round: round, reason: "noName", source: .click, detail: "Sa♭"),
            InputIgnored(round: round, reason: "noName", source: .shortcut, detail: "Sa♭"),
        ])
        #expect(logged(AnswerGiven.self).isEmpty)
        #expect(game.armedAccidental == .flat)

        // Then the right swara by keys: disarm, re-arm ♭ for B♭ (komal Ni), and the button's number.
        press("-")
        let flat = question.pitch.accidental == .flat
        if flat { press("-") }
        press(String(question.pitch.letter.rawValue + 1))
        let answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.correct)
        #expect(answer.name == NamingSystem.sargam.name(of: question.pitch))
        // The ♭ button click comes first, as "click ♭".
        #expect(answer.keystrokes.map(\.result) == [.armed, .rejected, .armed] + (flat ? [.armed] : []) + [.submitted])
        #expect(answer.keystrokes.first?.key == "click ♭")
    }

    @Test func unansweredQuestionKeepsItsKeystrokes() throws {
        game.settings.answerInput = .keyboard
        game.settings.naming = .solfege
        game.start()
        let question = try #require(game.question)
        press("s") // a start: "sol" or "si", so it waits
        game.stop()
        let ended = try #require(logged(RoundEnded.self).last)
        let unanswered = try #require(ended.unansweredQuestion)
        #expect(unanswered.question == question.id)
        #expect(unanswered.keystrokes.map(\.key) == ["s"])
        #expect(unanswered.keystrokes.map(\.result) == [.typed])
    }

    // MARK: Settings

    @Test func eachChangedSettingIsLoggedOnce() {
        // The bench mutes the game.
        #expect(logged(SettingChanged.self) == [SettingChanged(setting: "isMuted", from: .bool(false), to: .bool(true))])
        game.settings.naming = .solfege
        game.settings.naming = .solfege // unchanged: nothing to log
        game.settings.key = .fixed(KeySignature(fifths: 2))
        var settings = game.settings
        settings.showHints = true
        settings.mode = .practice
        game.settings = settings
        game.settings.key = .random
        #expect(Array(logged(SettingChanged.self).dropFirst()) == [
            SettingChanged(setting: "naming", from: .string("letters"), to: .string("solfege")),
            SettingChanged(setting: "key.fixed._0.fifths", from: .number(0), to: .number(2)),
            SettingChanged(setting: "mode", from: .string("sprint"), to: .string("practice")),
            SettingChanged(setting: "showHints", from: .bool(false), to: .bool(true)),
            SettingChanged(setting: "key.fixed._0.fifths", from: .number(2), to: .null),
            SettingChanged(setting: "key.random", from: .null, to: .object([:])),
        ])
    }

    @Test func pieceSettingsAreLoggedByTheirNestedKeys() {
        game.open(tune, from: tuneURL)
        game.settings.piece.hand = .left
        game.settings.piece.startBar = 99 // fitted to the piece's four bars: logged once, as fitted
        game.settings.piece.startBar = 4
        game.closePiece()
        #expect(Array(logged(SettingChanged.self).dropFirst()) == [
            SettingChanged(setting: "piecePath", from: .null, to: .string(tuneURL.path)),
            SettingChanged(setting: "piece.hand", from: .string("right"), to: .string("left")),
            SettingChanged(setting: "piece.startBar", from: .number(1), to: .number(4)),
            SettingChanged(setting: "piecePath", from: .string(tuneURL.path), to: .null),
        ])
    }

    // MARK: Round ends

    @Test func roundsEndForTheirReasons() {
        game.settings.mode = .practice
        game.start()
        answerRight()
        game.stop()
        game.start()
        press("\u{1b}", keyCode: 53) // Esc
        game.start()
        answerRight()
        game.start() // starting over mid-round
        game.appWillTerminate()
        game.appWillTerminate() // nothing left to end
        #expect(game.phase == .idle)

        let ended = logged(RoundEnded.self)
        #expect(ended.map(\.reason) == [.stopped, .stopped, .abandoned, .appQuit])
        #expect(ended.map(\.round) == logged(RoundStarted.self).map(\.round))
        #expect(ended.map(\.score) == [1, 0, 1, 0])
        #expect(ended.allSatisfy { $0.durationMs >= 0 && $0.bestScore == nil && !$0.isNewBest })
    }

    @Test func aSprintEndsWhenTimeIsUp() throws {
        game.settings.mode = .sprint
        game.start()
        for _ in 0..<3 { answerRight() }
        game.tick(at: .now + .seconds(61))
        #expect(game.summary?.timeRanOut == true)

        let ended = try #require(logged(RoundEnded.self).last)
        #expect(ended.reason == .timeUp)
        #expect(ended.score == 3 && ended.attempts == 3 && ended.bestStreak == 3)
        #expect(ended.bestScore == 3 && ended.isNewBest)
        #expect(ended.averageResponseMs != nil)
        #expect(ended.notesToReview.isEmpty)
    }

    @Test func aStoppedSprintKeepsTheBestScoreItDidNotBeat() throws {
        game.settings.mode = .sprint
        game.start()
        answerRight()
        game.stop()
        game.start()
        game.appWillTerminate()
        let ended = logged(RoundEnded.self)
        #expect(ended.map(\.isNewBest) == [true, false])
        #expect(ended.map(\.bestScore) == [1, 1])
        #expect(ended.last?.averageResponseMs == nil)
    }

    @Test func pieceRoundsLogTheirPieceAndEndWithIt() async throws {
        game.settings.mode = .practice
        game.open(tune, from: tuneURL)
        game.start()
        let started = try #require(logged(RoundStarted.self).last)
        #expect(started.keyFifths == 1)
        #expect(started.piece == PieceContext(title: "Usage tune", path: tuneURL.path, part: "Flute", partIndex: 0,
                                              hand: "right", order: "inOrder", startBar: 1, oneNotePerChord: false,
                                              noteCount: 3, measureCount: 4, chords: "eachNote"))
        game.answer(Pitch(.c, 1)) // misses G4
        try await waitUntil { !game.isShowingMiss }
        answerRight()
        answerRight()

        let shown = logged(QuestionShown.self)
        #expect(shown.map(\.pieceNote) == [PieceNoteRef(measure: 1, staff: 1, onset: 0, chord: 1),
                                           PieceNoteRef(measure: 1, staff: 1, onset: 1, chord: 2),
                                           PieceNoteRef(measure: 2, staff: 1, onset: 4, chord: 3)])
        #expect(shown.allSatisfy { $0.pickChance == nil && $0.keyFifths == 1 })
        // The tune has no bar layout, so its notes are shown on their own.
        #expect(shown.allSatisfy { $0.barView == false && $0.barStaves == nil })
        #expect(shown[1].pitch.accidental == 1 && shown[1].printedAccidental == nil)
        #expect(shown[2].pitch.name == "E6" && shown[2].written.name == "E5")
        #expect(shown[2].octaveShift == 1 && shown[2].position == 7)

        let ended = try #require(logged(RoundEnded.self).last)
        #expect(ended.reason == .pieceComplete)
        #expect(ended.score == 2 && ended.attempts == 3 && ended.bestStreak == 2)
        #expect(ended.bestScore == nil && !ended.isNewBest)
        #expect(ended.notesToReview == ["treble.G4"])
    }

    @Test func shuffledPieceRoundsLogPickChances() {
        game.settings.piece.order = .shuffled
        game.open(tune, from: tuneURL)
        _ = playRound(limit: 6)
        let chances = logged(QuestionShown.self).map(\.pickChance)
        #expect(chances.count == 7) // the six answered and the one after
        #expect(chances.allSatisfy { ($0 ?? 0) > 0 && ($0 ?? 2) <= 1 })
    }

    @Test func openingOrClosingAPieceAbandonsTheRound() {
        game.start()
        answerRight()
        game.open(tune, from: tuneURL)
        game.start()
        game.closePiece()
        #expect(Array(types.dropFirst(2)) == [
            "roundStarted", "questionShown", "answerGiven", "questionShown",
            "roundEnded", "pieceOpened", "settingChanged",
            "roundStarted", "questionShown",
            "roundEnded", "pieceClosed", "settingChanged",
        ])
        #expect(logged(RoundEnded.self).map(\.reason) == [.abandoned, .abandoned])
        #expect(logged(PieceClosed.self) == [PieceClosed(path: tuneURL.path)])
    }

    // MARK: Pieces

    @Test func openingFilesIsLogged() throws {
        let url = try fixture("voice-and-piano.musicxml")
        game.openPiece(at: url, via: .button)
        let score = try MusicXMLImporter.load(from: url)
        let opened = try #require(logged(PieceOpened.self).last)
        #expect(opened.path == url.path && opened.via == .button)
        #expect(opened.title == "Evening Song")
        #expect(opened.parts.map(\.name) == ["Voice", "Piano", "Part 4"])
        #expect(opened.parts.map(\.staves) == [1, 2, 1])
        #expect(opened.parts.map(\.measures) == [2, 2, 2])
        #expect(opened.parts.map(\.notes) == score.parts.map(\.notes.count))
        #expect(opened.parts.map(\.skipped) == score.parts.map(\.skippedNoteCount))

        let broken = try fixture("broken.mxl")
        game.openPiece(at: broken, via: .drop)
        let error = try #require(game.pieceError)
        game.open(Score(title: "Nothing", parts: []), from: tuneURL, via: .openAnother)
        #expect(logged(PieceOpenFailed.self) == [
            PieceOpenFailed(path: broken.path, via: .drop, error: error),
            PieceOpenFailed(path: tuneURL.path, via: .openAnother, error: "There are no notes to practise in this file."),
        ])
        #expect(game.piece?.title == "Evening Song") // still open
    }

    @Test func theLastPieceIsReopenedAtLaunch() throws {
        let url = try fixture("clarinet-tune.musicxml")
        game.openPiece(at: url)
        let launch = MemoryUsageRecorder()
        let relaunched = relaunch(recorder: launch)
        #expect(relaunched.piece != nil)
        #expect(launch.events.map(\.event.type) == ["pieceOpened"])
        let opened = try #require(launch.events.first?.event.payload as? PieceOpened)
        #expect(opened.via == .launch && opened.path == url.path)
    }

    @Test func aPieceGoneAtLaunchIsLoggedAsFailing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("clefwise-\(UUID()).musicxml")
        game.open(tune, from: missing)
        let launch = MemoryUsageRecorder()
        _ = relaunch(recorder: launch)
        #expect(launch.events.map(\.event) == [
            .pieceOpenFailed(PieceOpenFailed(path: missing.path, via: .launch, error: "The file is gone or can't be read.")),
            .settingChanged(SettingChanged(setting: "piecePath", from: .string(missing.path), to: .null)),
        ])
    }

    // MARK: Order

    @Test func roundEventsComeInOrder() async throws {
        game.settings.mode = .practice
        press(" ", keyCode: 49) // Space starts a round
        answerRight()
        game.answer(Pitch(.c, 1))
        try await waitUntil { !game.isShowingMiss }
        answerRight()
        press("\u{1b}", keyCode: 53)

        let roundTypes = Array(types.drop { $0 != "roundStarted" })
        #expect(roundTypes == ["roundStarted", "questionShown", "answerGiven", "questionShown", "answerGiven",
                               "questionShown", "answerGiven", "questionShown", "roundEnded"])
        let started = try #require(logged(RoundStarted.self).first)
        #expect(started.via == .key)
        let shown = logged(QuestionShown.self), answers = logged(AnswerGiven.self)
        #expect(shown.map(\.index) == [0, 1, 2, 3])
        #expect(answers.map(\.question) == shown.prefix(3).map(\.question))
        #expect(Set(shown.map(\.round) + answers.map(\.round)) == [started.round])
        #expect(answers.map(\.correct) == [true, false, true])
        #expect(answers.map(\.streakAfter) == [1, 0, 1])

        let ended = try #require(logged(RoundEnded.self).last)
        #expect(ended.round == started.round && ended.reason == .stopped)
        #expect(ended.score == 2 && ended.attempts == 3 && ended.bestStreak == 1)
        #expect(ended.notesToReview == ["treble.\(shown[1].pitch.name)"])
        #expect(recorder.events.map(\.sequence) == Array(recorder.events.indices))
    }
}
