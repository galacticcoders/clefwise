import Foundation
import Testing
@testable import Clefwise

// Naming the notes struck together as one answer ("All together"): the setting, which notes make
// a question, the three answer inputs, judging each note on its own, the result shown after a
// mistake, pausing, and what the log and its export say.

// MARK: - A hand-built piece with chords

/// A note or rest laid out as the importer would: treble on the upper staff, bass on the lower.
private func drawn(_ pitch: Pitch?, staff: Int = 1, voice: Int = 1, at offset: Double, lasting duration: Double = 1,
                   sign: Accidental? = nil, chord: Int, tiedToNext: Bool = false, tiedOver: Bool = false,
                   wholeBarRest: Bool = false) -> BarSymbol {
    let kind: NoteValue.Kind = switch duration {
    case 4: .whole
    case 2: .half
    default: .quarter
    }
    return BarSymbol(pitch: pitch, clef: staff == 1 ? .treble : .bass, staff: staff, voice: voice, offset: offset,
                     duration: duration, value: NoteValue(kind), octaveShift: 0, accidental: sign, stemUp: nil,
                     chord: chord, tiedToNext: tiedToNext, tiedFromPrevious: tiedOver, restPosition: nil,
                     isWholeBarRest: wholeBarRest)
}

/// A two-staff piece in C major from its bars' symbols, each listed in the bar's order. Like the
/// importer, tied-over notes are drawn but not asked, and the notes come in reading order.
private func piece(title: String = "Chord piece", _ bars: [[BarSymbol]]) -> Score {
    var measures: [ScoreMeasure] = []
    var notes: [ScoreNote] = []
    for (offset, symbols) in bars.enumerated() {
        let number = offset + 1, start = Double(offset * 4)
        measures.append(ScoreMeasure(number: number, start: start, length: 4,
                                     staves: [.init(clef: .treble, keySignature: .cMajor), .init(clef: .bass, keySignature: .cMajor)],
                                     symbols: symbols))
        for (index, symbol) in symbols.enumerated() {
            guard let pitch = symbol.pitch, !symbol.tiedFromPrevious else { continue }
            notes.append(ScoreNote(pitch: pitch, clef: symbol.clef, keySignature: .cMajor,
                                   printedAccidental: symbol.accidental, octaveShift: 0, staff: symbol.staff,
                                   measure: number, onset: start + symbol.offset, chord: symbol.chord, symbolIndex: index))
        }
    }
    notes.sort { ($0.onset, -$0.staff, $0.pitch.midiNumber) < ($1.onset, -$1.staff, $1.pitch.midiNumber) }
    return Score(title: title, parts: [ScorePart(name: "Piano", notes: notes, measures: measures, measureCount: bars.count,
                                                 staffCount: 2, skippedNoteCount: 0)])
}

private let b4 = Pitch(.b, 4), g5 = Pitch(.g, 5), c3 = Pitch(.c, 3), c5 = Pitch(.c, 5), c4 = Pitch(.c, 4)
private let g2 = Pitch(.g, 2), a4 = Pitch(.a, 4), e5 = Pitch(.e, 5), e4 = Pitch(.e, 4), eFlat4 = Pitch(.e, 4, .flat)

/// Bar 1: B4 and G5 over C3; C5 alone; C4 and C5 (an octave apart) over G2; then E4 (or with
/// `flat` E♭4, its sign printed) and B4.
/// Bar 2: two voices on the upper staff, E5 (tied over to beat 3) over C5, then A4 under the tied
/// E5, which isn't asked again; the lower staff rests.
///
/// Symbols: bar 1 is B4 G5 C3 · C5 · C4 C5 G2 · E4 B4 (indices 0–9); bar 2 is E5 C5 rest · E5~ A4.
private func chordPiece(flat: Bool = false) -> Score {
    piece([
        [drawn(b4, at: 0, chord: 1), drawn(g5, at: 0, chord: 1), drawn(c3, staff: 2, at: 0, lasting: 2, chord: 101),
         drawn(c5, at: 1, chord: 2),
         drawn(c4, at: 2, chord: 3), drawn(c5, at: 2, chord: 3), drawn(g2, staff: 2, at: 2, lasting: 2, chord: 102),
         drawn(flat ? eFlat4 : e4, at: 3, sign: flat ? .flat : nil, chord: 4), drawn(b4, at: 3, chord: 4)],
        [drawn(e5, voice: 1, at: 0, lasting: 2, chord: 5, tiedToNext: true), drawn(c5, voice: 2, at: 0, lasting: 2, chord: 6),
         drawn(nil, staff: 2, at: 0, lasting: 4, chord: 103, wholeBarRest: true),
         drawn(e5, voice: 1, at: 2, lasting: 2, chord: 5, tiedOver: true), drawn(a4, voice: 2, at: 2, lasting: 2, chord: 7)],
    ])
}

private let pieceURL = URL(fileURLWithPath: "/tmp/clefwise-tests/chords.musicxml")

/// Letters with ♯ and ♭, as `Game.typeableAnswers` has them when notes can be sharp or flat.
private let letterAnswers: [(text: String, letter: NoteLetter, accidental: Accidental)] = NoteLetter.allCases.flatMap { letter in
    [Accidental.natural, .sharp, .flat].map { (letter.name.lowercased() + ($0 == .natural ? "" : $0.symbol), letter, $0) }
}

private func names(_ text: String) -> [Game.NoteName] {
    var result: [Game.NoteName] = []
    for character in text {
        switch character {
        case "♯": result[result.count - 1] = Game.NoteName(letter: result.last!.letter, accidental: .sharp)
        case "♭": result[result.count - 1] = Game.NoteName(letter: result.last!.letter, accidental: .flat)
        default: result.append(Game.NoteName(letter: NoteLetter(character: character)!, accidental: .natural))
        }
    }
    return result
}

private extension GameTestBench {
    /// Opens the piece to name its chords together, in practice mode.
    func together(_ hand: Game.PieceSettings.Hand = .both, input: Game.AnswerInput = .buttons, flat: Bool = false,
                  naming: NamingSystem = .letters) {
        game.settings.mode = .practice
        game.settings.answerInput = input
        game.settings.naming = naming
        game.settings.piece.hand = hand
        game.settings.piece.chords = .together
        game.open(chordPiece(flat: flat), from: pieceURL)
    }

    /// The notes asked now: the group's, or the one note's.
    var asked: [Pitch] { game.group?.questions.map(\.pitch) ?? game.question.map { [$0.pitch] } ?? [] }

    /// Names every note asked now, right, top to bottom (any order counts); one note on its own on the piano.
    func nameAllRight() {
        guard let group = game.group else {
            if let question = game.question { game.answer(question.pitch) }
            return
        }
        for question in group.questions.reversed() { game.answer(question.pitch.letter, question.pitch.accidental) }
    }

    /// Starts a round and names everything right until it ends, noting what was asked each time.
    func askedThrough(limit: Int = 50) -> [[Pitch]] {
        game.start()
        var asked: [[Pitch]] = []
        while game.phase == .playing, asked.count < limit {
            asked.append(self.asked)
            nameAllRight()
        }
        return asked
    }

    func type(_ text: String) {
        for character in text { _ = game.handleKey(characters: String(character), keyCode: 0) }
    }

    func press(_ characters: String, keyCode: UInt16 = 0) {
        _ = game.handleKey(characters: characters, keyCode: keyCode)
    }

    func logged<T>(_ type: T.Type) -> [T] {
        recorder.events.compactMap { $0.event.payload as? T }
    }

    var stats: [String: NoteStat] {
        defaults.data(forKey: "noteStats").flatMap { try? JSONDecoder().decode([String: NoteStat].self, from: $0) } ?? [:]
    }
}

// MARK: - The setting

@Suite struct ChordSettingTests {
    private func decoded(_ json: String) throws -> Game.PieceSettings {
        try JSONDecoder().decode(Game.PieceSettings.self, from: Data(json.utf8))
    }

    @Test func noteByNoteIsTheDefault() throws {
        #expect(Game.PieceSettings().chords == .eachNote)
        #expect(try decoded("{}").chords == .eachNote)
        #expect(Game.PieceSettings.Chords.allCases.map(\.label) == ["Note by note", "Top / bottom note", "All together"])
    }

    @Test func oldSettingsKeepTheirCheckbox() throws {
        #expect(try decoded(#"{"oneNotePerChord":true}"#).chords == .topOrBottom)
        #expect(try decoded(#"{"oneNotePerChord":false}"#).chords == .eachNote)
        // A saved choice wins over the old checkbox.
        #expect(try decoded(#"{"oneNotePerChord":true,"chords":"together"}"#).chords == .together)
        #expect(try decoded(#"{"oneNotePerChord":true,"chords":"eachNote"}"#).chords == .eachNote)
        // A choice from a later version falls back rather than losing every setting.
        let later = try decoded(#"{"oneNotePerChord":true,"chords":"arpeggiated","startBar":3}"#)
        #expect(later.chords == .topOrBottom && later.startBar == 3)
    }

    @Test func theChoiceIsSavedAndTheCheckboxIsNot() throws {
        var settings = Game.PieceSettings()
        settings.chords = .together
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        #expect(json["chords"] as? String == "together")
        #expect(json["oneNotePerChord"] == nil)
        #expect(try JSONDecoder().decode(Game.PieceSettings.self, from: JSONEncoder().encode(settings)).chords == .together)
    }

    @Test func theCheckboxIsAnAliasForTopOrBottom() {
        var settings = Game.PieceSettings()
        settings.oneNotePerChord = true
        #expect(settings.chords == .topOrBottom && settings.oneNotePerChord)
        settings.oneNotePerChord = false
        #expect(settings.chords == .eachNote)
        settings.chords = .together
        #expect(!settings.oneNotePerChord)
        settings.oneNotePerChord = false // leaves "All together" alone
        #expect(settings.chords == .together)
    }

    @Test func allTogetherAlwaysUsesTheWholeBar() {
        var settings = Game.PieceSettings()
        settings.showsWholeBar = false
        #expect(!settings.usesWholeBar)
        settings.chords = .together
        #expect(settings.usesWholeBar)
        #expect(!settings.showsWholeBar) // kept for when another choice comes back
    }
}

@MainActor
@Suite final class ChordSettingGameTests: GameTestBench {
    @Test func settingsSavedBeforeTheChoiceStillLoad() throws {
        let defaults = InMemoryDefaults()
        defaults.set(Data(#"{"piece":{"hand":"both","oneNotePerChord":true}}"#.utf8), forKey: "settings")
        let recorder = MemoryUsageRecorder()
        let launched = Game(defaults: defaults, recorder: recorder, library: .temporary())
        #expect(launched.settings.piece.chords == .topOrBottom && launched.settings.piece.hand == .both)
        #expect(!recorder.events.contains { $0.event.type == "settingChanged" })
    }

    @Test func changesAreLoggedAsPieceChords() {
        game.settings.piece.chords = .together
        game.settings.piece.oneNotePerChord = true
        #expect(logged(SettingChanged.self).suffix(2) == [
            SettingChanged(setting: "piece.chords", from: .string("eachNote"), to: .string("together")),
            SettingChanged(setting: "piece.chords", from: .string("together"), to: .string("topOrBottom")),
        ])
    }

    @Test func allTogetherShowsTheWholeBarWhateverTheCheckboxSays() {
        game.settings.piece.showsWholeBar = false
        together(.right)
        #expect(game.barDisplay != nil)
        game.start()
        #expect(game.barDisplay?.current == 0)
        #expect(game.barStrip != nil)
        game.stop()
        game.settings.piece.chords = .eachNote
        #expect(game.barDisplay == nil)
    }
}

// MARK: - What's asked together

@MainActor
@Suite final class ChordGroupingTests: GameTestBench {
    @Test func oneHandAsksItsChordsAndVoicesTogether() {
        together(.right)
        // Bar 2's E5 and C5 are in two voices; its A4 sounds under the tied-over E5, which isn't asked again.
        #expect(askedThrough() == [[b4, g5], [c5], [c4, c5], [e4, b4], [c5, e5], [a4]])
        #expect(game.summary?.finishedPiece == true)
        #expect(game.summary?.attempts == 10 && game.summary?.score == 10)
    }

    @Test func bothHandsAskBothStavesTogether() {
        together(.both)
        #expect(askedThrough() == [[c3, b4, g5], [c5], [g2, c4, c5], [e4, b4], [c5, e5], [a4]])
        together(.left)
        #expect(askedThrough() == [[c3], [g2]])
    }

    @Test func theOtherChoicesAskAsBefore() {
        game.settings.mode = .practice
        game.settings.piece.hand = .both
        game.open(chordPiece(), from: pieceURL)
        #expect(askedThrough() == [[c3], [b4], [g5], [c5], [g2], [c4], [c5], [e4], [b4], [c5], [e5], [a4]])
        #expect(game.group == nil)
        game.settings.piece.chords = .topOrBottom
        // Bar 2's C5 and E5 are in two voices, so two chords of one note each.
        #expect(askedThrough() == [[c3], [g5], [c5], [g2], [c5], [b4], [c5], [e5], [a4]])
    }

    @Test func theFixtureAsksBothHandsTogether() throws {
        game.settings.mode = .practice
        game.settings.piece.chords = .together
        game.settings.piece.hand = .both
        game.openPiece(at: try #require(Fixtures.url("bar-view.musicxml")))
        game.settings.piece.startBar = 3
        game.start()
        #expect(asked == [Pitch(.a, 2), Pitch(.a, 4), Pitch(.c, 5), Pitch(.e, 5)])
        game.stop()
        game.settings.piece.startBar = 10
        game.start()
        #expect(asked == [Pitch(.e, 2), Pitch(.b, 2), Pitch(.e, 3), Pitch(.g, 4), Pitch(.b, 4), Pitch(.e, 5)])
        game.stop()
        // Bar 5 starts with a B4 tied over from bar 4: the right hand's first note is the D♯5 after it.
        game.settings.piece.startBar = 5
        game.settings.piece.hand = .right
        game.start()
        #expect(asked == [Pitch(.d, 5, .sharp)] && game.group == nil)
        game.stop()
        game.settings.piece.hand = .left
        game.start()
        #expect(asked == [Pitch(.e, 2), Pitch(.b, 2)])
    }

    @Test func theBarHighlightsTheGroup() throws {
        together(.both)
        game.start()
        // C3 (symbol 2) is asked first, B4 and G5 (0 and 1) with it.
        var display = try #require(game.barDisplay)
        #expect(display.current == 2 && display.together == [0, 1] && display.answered.isEmpty && display.marks.isEmpty)
        #expect(game.question?.pitch == c3)
        nameAllRight()
        display = try #require(game.barDisplay)
        #expect(display.current == 3 && display.together.isEmpty && display.answered == [0, 1, 2])
        nameAllRight()
        display = try #require(game.barDisplay)
        // G2 is lowest; the Cs come with it.
        #expect(display.current == 6 && display.together == [4, 5] && display.answered == [0, 1, 2, 3])
        nameAllRight()
        nameAllRight()
        display = try #require(game.barDisplay)
        #expect(display.measure.number == 2 && display.current == 1 && display.together == [0] && display.answered.isEmpty)
    }

    @Test func theProgressCountsNotes() {
        together(.both)
        game.start()
        #expect(game.pieceProgress == Game.PieceProgress(bar: 1, bars: 2, done: 0, total: 12))
        nameAllRight()
        #expect(game.pieceProgress == Game.PieceProgress(bar: 1, bars: 2, done: 3, total: 12))
        #expect(game.barStrip == Game.BarStrip(bars: 1...2, current: 1, pieceBars: 2, showsDone: true))
    }

    @Test func aSprintWrapsByGroups() {
        together(.right)
        game.settings.mode = .sprint
        #expect(askedThrough(limit: 8) == [[b4, g5], [c5], [c4, c5], [e4, b4], [c5, e5], [a4], [b4, g5], [c5]])
    }

    @Test func shuffledRoundsDrawGroups() {
        together(.both)
        game.settings.piece.order = .shuffled
        let asked = askedThrough(limit: 60)
        #expect(asked.count == 60)
        #expect(Set(asked) == [[c3, b4, g5], [c5], [g2, c4, c5], [e4, b4], [c5, e5], [a4]])
        #expect(zip(asked, asked.dropFirst()).allSatisfy { $0 != $1 })
        #expect(game.barDisplay?.answered.isEmpty == true)
        let chances = logged(QuestionShown.self).map(\.pickChance)
        #expect(chances.allSatisfy { ($0 ?? 0) > 0 && ($0 ?? 2) <= 1 })
    }

    @Test func barViewQuestionsPrintTheBarsSigns() throws {
        together(.right, flat: true)
        game.start()
        nameAllRight()
        nameAllRight()
        nameAllRight()
        let group = try #require(game.group)
        #expect(group.questions.map(\.pitch) == [eFlat4, b4])
        #expect(group.questions.map(\.printedAccidental) == [.flat, nil])
    }
}

// MARK: - Answering

@MainActor
@Suite final class ChordAnswerTests: GameTestBench {
    @Test func buttonsAddChipsAndTheLastOneSubmits() throws {
        together(.right)
        game.start()
        game.answer(.g)
        let group = try #require(game.group)
        #expect(group.entries.map(\.letter) == [.g] && group.result == nil)
        #expect(game.groupEntriesNeeded == 2)
        #expect(game.attempts == 0)
        game.answer(.b)
        #expect(game.score == 2 && game.attempts == 2 && game.streak == 2)
        #expect(asked == [c5])
        // The group just named is flashed, all right.
        #expect(game.groupFlash?.result?.isAllRight == true)
        #expect(game.groupFlash?.entries.map(\.letter) == [.g, .b])
    }

    @Test func chipsCanBeTakenBack() throws {
        together(.both)
        game.start()
        game.answer(.c)
        game.answer(.a)
        game.removeGroupEntry(at: 1)
        #expect(game.group?.entries.map(\.letter) == [.c])
        game.answer(.d)
        press("\u{7f}", keyCode: 51) // Delete takes back the last one
        #expect(game.group?.entries.map(\.letter) == [.c])
        game.answer(.g)
        game.answer(.b)
        #expect(game.score == 3 && game.attempts == 3)
        // With no group, Delete is left to the system as before.
        #expect(!game.handleKey(characters: "\u{7f}", keyCode: 51))
    }

    @Test func aRepeatedNameIsGivenOncePerNote() {
        together(.right)
        game.start()
        nameAllRight()
        nameAllRight()
        #expect(asked == [c4, c5])
        press("c")
        #expect(game.group?.entries.count == 1)
        press("c")
        #expect(game.score == 5 && game.attempts == 5)
    }

    @Test func theArmedSignGoesWithOneEntry() throws {
        together(.right, flat: true)
        game.start()
        for _ in 0..<3 { nameAllRight() }
        press("-")
        #expect(game.armedAccidental == .flat)
        press("e")
        #expect(game.armedAccidental == .natural)
        #expect(game.group?.entries.map(\.accidental) == [.flat])
        press("b")
        #expect(game.score == 7 && game.attempts == 7)
    }

    @Test func pianoKeysToggle() throws {
        together(.right, input: .piano)
        game.start()
        game.answer(b4)
        #expect(game.group?.entries.map(\.pitch) == [b4])
        game.answer(b4) // clicked again: taken back
        #expect(game.group?.entries.isEmpty == true)
        game.answer(g5)
        game.answer(b4)
        #expect(game.score == 2 && game.attempts == 2)
        // Keys must be exact: G4 isn't G5.
        nameAllRight()
        game.answer(c4)
        game.answer(Pitch(.c, 6))
        #expect(game.score == 4 && game.attempts == 5)
        let result = try #require(game.group?.result)
        #expect(result.isRight == [true, false] && result.entryIsRight == [true, false])
        // The mark says so, as the label of a single note does.
        #expect(game.barDisplay?.marks == [4: .right, 5: .wrong(name: "C · wrong octave")])
    }

    @Test func middleCIsMarkedAsSuch() throws {
        together(.right, input: .piano)
        game.start()
        nameAllRight()
        nameAllRight()
        game.answer(Pitch(.d, 4))
        game.answer(c5) // C4 is wrong
        #expect(game.barDisplay?.marks == [4: .wrong(name: "Middle C"), 5: .right])
    }

    @Test func notesSoundingOneKeyShareIt() {
        let unison = [Question(clef: .treble, pitch: c5), Question(clef: .treble, pitch: c5), Question(clef: .treble, pitch: e5)]
        let group = Game.NoteGroup(questions: unison)
        #expect(group.entriesNeeded(on: .piano) == 2 && group.entriesNeeded(on: .buttons) == 3)
        let keys = [Game.GroupEntry(letter: .c, accidental: .natural, pitch: c5), Game.GroupEntry(letter: .f, accidental: .natural, pitch: Pitch(.f, 5))]
        let result = Game.judge(keys, against: unison, naming: .letters)
        #expect(result.isRight == [true, true, false])
        #expect(result.entryIndices == [0, 0, 1])
        #expect(result.entryIsRight == [true, false])
        // Two wrong keys for the two Cs: they share the first one left over.
        let wrong = Game.judge([Game.GroupEntry(letter: .d, accidental: .natural, pitch: Pitch(.d, 5)), keys[1]],
                               against: unison, naming: .letters)
        #expect(wrong.isRight == [false, false, false] && wrong.entryIndices == [0, 0, 1])
    }

    @Test func judgingMatchesForTheMostRight() {
        let chord = [Question(clef: .bass, pitch: c3), Question(clef: .treble, pitch: c5), Question(clef: .treble, pitch: e5)]
        func entry(_ letter: NoteLetter, _ accidental: Accidental = .natural) -> Game.GroupEntry {
            Game.GroupEntry(letter: letter, accidental: accidental, pitch: nil)
        }
        // Any order; two Cs name both C notes.
        var result = Game.judge([entry(.e), entry(.c), entry(.c)], against: chord, naming: .letters)
        #expect(result.isRight == [true, true, true] && result.entryIndices == [1, 2, 0])
        // One C for two: the second C note is wrong and gets the entry left over.
        result = Game.judge([entry(.c), entry(.g), entry(.e)], against: chord, naming: .letters)
        #expect(result.isRight == [true, false, true] && result.entryIndices == [0, 1, 2])
        #expect(result.entryIsRight == [true, false, true] && result.rightCount == 2 && !result.isAllRight)
        // Leftovers pair with the notes named wrong in order.
        result = Game.judge([entry(.a), entry(.b), entry(.e)], against: chord, naming: .letters)
        #expect(result.isRight == [false, false, true] && result.entryIndices == [0, 1, 2])
        // Sargam goes by swara: D♭ and C♯ are both komal Re.
        result = Game.judge([entry(.d, .flat)], against: [Question(clef: .treble, pitch: Pitch(.c, 4, .sharp))], naming: .sargam)
        #expect(result.isAllRight)
        // Letters go by spelling.
        result = Game.judge([entry(.d, .flat)], against: [Question(clef: .treble, pitch: Pitch(.c, 4, .sharp))], naming: .letters)
        #expect(!result.isAllRight)
    }

    @Test func eachNoteIsScoredOnItsOwn() async throws {
        together(.both)
        game.start()
        game.answer(.c)
        game.answer(.b)
        game.answer(.a) // G5 is wrong
        #expect(game.score == 2 && game.attempts == 3 && game.streak == 0)
        #expect(stats["bass.C3"]?.correct == 1 && stats["treble.B4"]?.correct == 1)
        #expect(stats["treble.G5"]?.attempts == 1 && stats["treble.G5"]?.correct == 0)
        try await waitUntil { !game.isShowingMiss }
        nameAllRight() // C5
        nameAllRight() // G2 C4 C5
        #expect(game.streak == 4)
        game.stop()
        #expect(game.summary?.notesToReview == [StaffNote(clef: .treble, pitch: g5)])
        #expect(game.summary?.bestStreak == 4)
    }

    @Test func aMistakeShowsEachNotesMark() async throws {
        together(.both, naming: .solfege)
        game.start()
        game.answer(.c)
        game.answer(.a)
        game.answer(.b)
        #expect(game.isShowingMiss && game.score == 2 && game.attempts == 3)
        let group = try #require(game.group)
        let result = try #require(group.result)
        #expect(result.isRight == [true, true, false])
        #expect(group.entries.map(\.letter) == [.c, .a, .b])
        #expect(result.entryIsRight == [true, false, true])
        let display = try #require(game.barDisplay)
        #expect(display.marks == [2: .right, 0: .right, 1: .wrong(name: "Sol")])
        #expect(display.current == 2 && display.together == [0, 1])
        // More entries don't count during the pause.
        game.answer(.g)
        #expect(game.attempts == 3)
        #expect(logged(InputIgnored.self).last?.reason == "missPause")

        try await waitUntil { !game.isShowingMiss }
        #expect(asked == [c5] && game.group == nil)
        #expect(game.barDisplay?.marks.isEmpty == true)
    }

    @Test func aLoneNoteIsAskedAsBefore() async throws {
        together(.right)
        game.start()
        nameAllRight()
        #expect(asked == [c5] && game.group == nil)
        game.answer(.d)
        #expect(game.isShowingMiss && game.flash?.isCorrect == false)
        #expect(game.score == 2 && game.attempts == 3 && game.streak == 0)
        #expect(game.barDisplay?.marks.isEmpty == true && game.barDisplay?.together.isEmpty == true)
        let answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.group == nil && answer.groupSize == nil && !answer.correct)
        let shown = try #require(logged(QuestionShown.self).last)
        #expect(shown.group == nil && shown.groupSize == nil)
    }
}

// MARK: - Typing

@Suite struct TypedNamesTests {
    private let solfege: [(text: String, letter: NoteLetter, accidental: Accidental)] = NoteLetter.allCases.map {
        (NamingSystem.solfege.name(of: $0).lowercased(), $0, .natural)
    }

    @Test func namesComeBackToBack() {
        var typed = Game.TypedNames("sisol", count: 2, answers: solfege)
        #expect(typed.readings == [[.init(letter: .b, accidental: .natural), .init(letter: .g, accidental: .natural)]])
        #expect(typed.submitsAtOnce && !typed.needsReturn)
        typed = Game.TypedNames("dodo", count: 2, answers: solfege)
        #expect(typed.readings.count == 1 && typed.submitsAtOnce)
        // On the way: whole names and the start of one more.
        typed = Game.TypedNames("sis", count: 2, answers: solfege)
        #expect(typed.isViable && typed.readings.isEmpty && typed.canGrow)
        #expect(typed.shown == [.init(letter: .b, accidental: .natural)] && typed.rest == "s")
        // No more names than notes.
        #expect(!Game.TypedNames("sisols", count: 2, answers: solfege).isViable)
        #expect(!Game.TypedNames("x", count: 2, answers: solfege).isViable)
    }

    @Test func aBIsReadWithTheCountInMind() {
        // For three notes "ebg" is E B G; for two, E♭ G.
        let three = Game.TypedNames("ebg", count: 3, answers: letterAnswers)
        #expect(three.readings == [names("ebg")])
        // It could still grow (E♭ G and one more), so it waits for Return.
        #expect(three.needsReturn)
        #expect(three.shown == names("ebg"))
        let two = Game.TypedNames("ebg", count: 2, answers: letterAnswers)
        #expect(two.readings == [names("e♭g")])
        #expect(two.needsReturn) // G could still take a sign
        // Short of all the names, "eb" shows as E♭, as for one note.
        let start = Game.TypedNames("eb", count: 3, answers: letterAnswers)
        #expect(start.readings.isEmpty && start.shown == names("e♭"))
        // Read two ways: both are kept for judging.
        #expect(Game.TypedNames("ebb", count: 2, answers: letterAnswers).readings == [names("eb♭"), names("e♭b")])
        // ♯ after a name; a sign alone leads nowhere.
        #expect(Game.TypedNames("f♯c", count: 2, answers: letterAnswers).readings == [names("f♯c")])
        #expect(!Game.TypedNames("♯", count: 2, answers: letterAnswers).isViable)
    }
}

@MainActor
@Suite final class ChordTypingTests: GameTestBench {
    @Test func namesInAnyOrderSubmitByThemselves() throws {
        together(.right, input: .keyboard, naming: .solfege)
        game.start()
        type("sol")
        #expect(game.typedText == "sol" && game.attempts == 0)
        #expect(game.typedNames?.shown == names("g") && !game.typingNeedsReturn)
        type("si")
        #expect(game.score == 2 && game.attempts == 2 && game.typedText.isEmpty)
        #expect(asked == [c5])
        type("do") // one note: as before
        #expect(game.score == 3)
        type("dodo")
        #expect(game.score == 5 && game.attempts == 5)
        let answers = logged(AnswerGiven.self).suffix(2)
        #expect(answers.allSatisfy { $0.source == .typing && $0.correct && $0.name == "Do" })
    }

    @Test func withSignsAboutReturnSubmits() throws {
        together(.right, input: .keyboard, flat: true, naming: .solfege)
        game.start()
        type("sisol")
        #expect(game.typingNeedsReturn && game.attempts == 0)
        press("\r", keyCode: 36)
        #expect(game.score == 2)
        nameAllRight()
        nameAllRight()
        // E♭4 and B4: "mibsi" reads as Mi♭ Si.
        type("mibsi")
        #expect(game.typedNames?.shown == names("e♭b"))
        press("\r", keyCode: 36)
        #expect(game.score == 7 && game.attempts == 7)
    }

    @Test func aBIsJudgedWithTheReadingThatNamesTheMost() throws {
        together(.right, input: .keyboard, flat: true)
        game.start()
        for _ in 0..<3 { nameAllRight() }
        #expect(asked == [eFlat4, b4])
        // "ebb" is E B♭ or E♭ B: the second names both.
        type("ebb")
        press("\r", keyCode: 36)
        #expect(game.score == 7 && game.attempts == 7)
        let answers = logged(AnswerGiven.self).suffix(2)
        #expect(answers.map(\.name) == ["E♭", "B"])
    }

    @Test func keysThatLeadNowhereShake() throws {
        together(.right, input: .keyboard, naming: .solfege)
        game.start()
        type("x")
        #expect(game.rejectedKeystrokes == 1 && game.typedText.isEmpty)
        type("sis")
        press("\r", keyCode: 36) // not all the names yet
        #expect(game.rejectedKeystrokes == 2 && game.attempts == 0)
        press("\u{7f}", keyCode: 51)
        #expect(game.typedText == "si")
        type("la") // Si La: G5 is wrong
        #expect(game.attempts == 2 && game.score == 1 && game.isShowingMiss)
        type("do") // during the result: ignored
        #expect(game.typedText.isEmpty)
        let keys = try #require(logged(AnswerGiven.self).first).keystrokes
        #expect(keys.map(\.key) == ["x", "s", "i", "s", "Return", "Delete", "l", "a"])
        #expect(keys.map(\.result) == [.rejected, .typed, .typed, .typed, .rejected, .deleted, .typed, .submitted])
    }
}

// MARK: - Pausing

@MainActor
@Suite final class ChordPauseTests: GameTestBench {
    @Test func entriesWaitThroughAPause() {
        together(.both)
        game.start()
        game.answer(.c)
        game.pause()
        game.answer(.b)
        press("\u{7f}", keyCode: 51)
        game.removeGroupEntry(at: 0)
        #expect(game.group?.entries.map(\.letter) == [.c])
        #expect(logged(InputIgnored.self).map(\.reason) == ["paused", "paused"])
        game.resume()
        game.answer(.b)
        game.answer(.g)
        #expect(game.score == 3)
    }

    @Test func typingWaitsThroughAPause() {
        together(.right, input: .keyboard, flat: true, naming: .solfege)
        game.start()
        type("sisol")
        game.pause()
        press("\r", keyCode: 36)
        #expect(game.attempts == 0 && game.typedText == "sisol")
        game.resume()
        press("\r", keyCode: 36)
        #expect(game.score == 2)
    }

    @Test func aResultPausedOnWaitsForTheResume() async throws {
        together(.both)
        game.start()
        game.answer(.c)
        game.answer(.b)
        game.answer(.a)
        #expect(game.isShowingMiss)
        game.pause()
        #expect(game.barDisplay?.marks.count == 3)
        try await waitUntil { game.advancesOnResume }
        #expect(game.isShowingMiss && game.group?.result != nil)
        game.resume()
        #expect(!game.isShowingMiss && asked == [c5])
    }
}

// MARK: - The log

@MainActor
@Suite final class ChordLogTests: GameTestBench {
    @Test func eachNoteIsShownAndAnsweredOnItsOwn() async throws {
        together(.both)
        game.start()
        let started = try #require(logged(RoundStarted.self).last)
        #expect(started.piece?.chords == "together" && started.piece?.oneNotePerChord == false)
        #expect(started.piece?.noteCount == 12)

        var shown = logged(QuestionShown.self)
        try #require(shown.count == 3)
        let group = try #require(game.group)
        #expect(shown.map(\.question) == group.questions.map(\.id))
        #expect(shown.map(\.index) == [0, 1, 2])
        #expect(shown.allSatisfy { $0.group == group.id && $0.groupSize == 3 && $0.barView == true && $0.barStaves == [1, 2] })
        #expect(shown.map(\.pitch.name) == ["C3", "B4", "G5"])
        #expect(shown.map(\.pieceNote?.symbolIndex) == [2, 0, 1])

        try await Task.sleep(for: .milliseconds(5))
        press("b")
        game.answer(.a) // a click
        game.answer(.d) // C3 and G5 are wrong
        var answers = logged(AnswerGiven.self)
        try #require(answers.count == 3)
        #expect(answers.map(\.question) == group.questions.map(\.id))
        #expect(answers.map(\.correct) == [false, true, false])
        // B4 got the B; C3 and G5 the A and D left over, in order.
        #expect(answers.map(\.letter) == ["A", "B", "D"])
        #expect(answers.allSatisfy { $0.group == group.id && $0.groupSize == 3 && $0.source == .click })
        #expect(Set(answers.map(\.responseMs)).count == 1 && answers[0].responseMs > 0)
        #expect(answers.allSatisfy { $0.scoreAfter == 1 && $0.streakAfter == 0 })
        #expect(answers[0].keystrokes.map(\.key) == ["b", "click A", "click D"])
        #expect(answers[0].keystrokes.map(\.result) == [.typed, .typed, .submitted])
        #expect(answers[1].keystrokes.isEmpty && answers[2].keystrokes.isEmpty)

        try await waitUntil { !game.isShowingMiss }
        shown = logged(QuestionShown.self)
        #expect(shown.last?.index == 3 && shown.last?.group == nil)
        nameAllRight()
        answers = logged(AnswerGiven.self)
        #expect(answers.last?.group == nil && answers.last?.streakAfter == 1)
    }

    @Test func pianoEntriesAreLoggedAsKeys() throws {
        together(.right, input: .piano)
        game.start()
        game.answer(b4)
        game.answer(b4)
        game.answer(Pitch(.g, 4))
        game.answer(b4)
        let answers = logged(AnswerGiven.self)
        try #require(answers.count == 2)
        #expect(answers.map(\.pitch?.name) == ["B4", "G4"])
        #expect(answers.map(\.wrongOctave) == [false, true])
        #expect(answers.map(\.correct) == [true, false])
        #expect(answers[0].keystrokes.map(\.key) == ["piano B4", "piano B4", "piano G4", "piano B4"])
        #expect(answers[0].keystrokes.map(\.result) == [.typed, .deleted, .typed, .submitted])
    }

    @Test func aRoundEndingMidGroupKeepsItsGroup() throws {
        together(.right)
        game.start()
        let group = try #require(game.group)
        press("g")
        game.stop()
        let unanswered = try #require(logged(RoundEnded.self).last?.unansweredQuestion)
        #expect(unanswered.question == group.questions[0].id && unanswered.group == group.id)
        #expect(unanswered.keystrokes.map(\.key) == ["g"])
    }

    @Test func theEventsRoundTrip() throws {
        let group = UUID()
        let answer = AnswerGiven(round: UUID(), question: UUID(), responseMs: 900, source: .typing, letter: "G", accidental: 0,
                                 name: "Sol", pitch: nil, correct: true, wrongOctave: nil, keystrokes: [], scoreAfter: 2,
                                 streakAfter: 2, group: group, groupSize: 2)
        let data = try LoggedEvent.encoder.encode(LoggedEvent(.answerGiven(answer), session: UUID(), sequence: 1))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["group"] as? String == group.uuidString && json["groupSize"] as? Int == 2)
        #expect(try LoggedEvent.decoder.decode(LoggedEvent.self, from: data).event == .answerGiven(answer))

        // Old lines without them still read.
        var single = answer
        single.group = nil
        single.groupSize = nil
        let line = try LoggedEvent.encoder.encode(LoggedEvent(.answerGiven(single), session: UUID(), sequence: 2))
        #expect(!String(decoding: line, as: UTF8.self).contains("group"))
    }

    @Test func theExportHasTheGroupColumns() throws {
        together(.both)
        game.start()
        nameAllRight()
        game.answer(.d) // C5 alone, wrong
        game.stop()

        let folder = UsageTestFolder()
        let log = UsageLog(folder: folder.url.appendingPathComponent("Usage", isDirectory: true))
        for event in recorder.events { log.record(event.event) }
        let archive = folder.url.appendingPathComponent("export.zip")
        try UsageExport.export(log, to: archive, defaults: InMemoryDefaults())
        let unzipped = folder.url.appendingPathComponent("unzipped", isDirectory: true)
        let ditto = try Process.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", archive.path, unzipped.path])
        ditto.waitUntilExit()
        let top = try #require(try FileManager.default.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil).first)

        func rows(_ file: String) throws -> [[String: String]] {
            let lines = try String(contentsOf: top.appendingPathComponent(file), encoding: .utf8)
                .components(separatedBy: "\r\n").filter { !$0.isEmpty }
            let header = lines[0].components(separatedBy: ",")
            return lines.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(header, $0.components(separatedBy: ","))) }
        }
        let answers = try rows("answers.csv")
        try #require(answers.count == 4)
        let group = try #require(answers[0]["group"])
        #expect(!group.isEmpty && answers.prefix(3).allSatisfy { $0["group"] == group && $0["groupSize"] == "3" })
        #expect(answers[3]["group"] == "" && answers[3]["groupSize"] == "")
        #expect(answers.map { $0["pitch"] } == ["C3", "B4", "G5", "C5"])
        let rounds = try rows("rounds.csv")
        #expect(rounds.first?["pieceChords"] == "together" && rounds.first?["pieceOneNotePerChord"] == "false")
        let schema = try String(contentsOf: top.appendingPathComponent("SCHEMA.md"), encoding: .utf8)
        for column in ["group", "groupSize", "pieceChords", "piece.chords"] { #expect(schema.contains("`\(column)`")) }
    }

    @Test func theDashboardCountsEachNote() throws {
        together(.both)
        game.start()
        nameAllRight()
        game.answer(.d)
        game.stop()
        let report = ProgressAnalyzer.report(from: recorder.events, filter: ProgressFilter(range: .all, clef: .all))
        #expect(report.totals.answers == 4 && report.totals.correct == 3 && report.totals.rounds == 1)
    }
}
