import Foundation
import Testing
@testable import Clefwise

// The whole-bar view's game side: which bar the staff card draws, which of its notes is asked and
// which are done, the staves and their range, the signs questions print, and what the log says.

// MARK: - Hand-built scores with bars

/// A note or rest as the importer would lay it out: treble on the upper staff, bass on the lower.
private func drawn(_ pitch: Pitch?, staff: Int = 1, at offset: Double, lasting duration: Double = 1,
                   sign: Accidental? = nil, chord: Int, shift: Int = 0, wholeBarRest: Bool = false) -> BarSymbol {
    let kind: NoteValue.Kind = switch duration {
    case 4: .whole
    case 2: .half
    default: .quarter
    }
    return BarSymbol(pitch: pitch, clef: staff == 1 ? .treble : .bass, staff: staff, voice: 1, offset: offset,
                     duration: duration, value: NoteValue(kind), octaveShift: shift, accidental: sign, stemUp: nil,
                     chord: chord, tiedToNext: false, tiedFromPrevious: false, restPosition: nil,
                     isWholeBarRest: wholeBarRest)
}

/// A one-part piece in C major and 4/4 from its bars' symbols, each listed in the bar's order. Its
/// notes point at their symbols and come in reading order (by onset, lower staff first, low to high).
/// Shown on its own a note prints its own sign or, failing that, the one an earlier sign in the bar
/// gave it, as the importer does. `clef` gives each staff's clef as a bar starts (nil: one the bar
/// view can't draw).
private func piece(title: String = "Bars", staves: Int = 2,
                   clef: (_ bar: Int, _ staff: Int) -> Clef? = { _, staff in staff == 1 ? .treble : .bass },
                   _ bars: [[BarSymbol]]) -> Score {
    var measures: [ScoreMeasure] = []
    var notes: [ScoreNote] = []
    for (offset, symbols) in bars.enumerated() {
        let number = offset + 1, start = Double(offset * 4)
        measures.append(ScoreMeasure(number: number, start: start, length: 4,
                                     staves: (1...staves).map { .init(clef: clef(number, $0), keySignature: .cMajor) },
                                     symbols: symbols))
        for (index, symbol) in symbols.enumerated() {
            guard let pitch = symbol.pitch else { continue }
            notes.append(ScoreNote(pitch: pitch, clef: symbol.clef, keySignature: .cMajor,
                                   printedAccidental: symbol.accidental ?? (pitch.accidental == .natural ? nil : pitch.accidental),
                                   octaveShift: symbol.octaveShift, staff: symbol.staff, measure: number,
                                   onset: start + symbol.offset, chord: symbol.chord, symbolIndex: index))
        }
    }
    notes.sort { ($0.onset, -$0.staff, $0.pitch.midiNumber) < ($1.onset, -$1.staff, $1.pitch.midiNumber) }
    return Score(title: title, parts: [ScorePart(name: "Piano", notes: notes, measures: measures, measureCount: bars.count,
                                                 staffCount: staves, skippedNoteCount: 0)])
}

private let fSharp4 = Pitch(.f, 4, .sharp)

private let bar1 = [drawn(fSharp4, at: 0, sign: .sharp, chord: 1),
                    drawn(Pitch(.c, 3), staff: 2, at: 0, lasting: 4, chord: 101),
                    drawn(fSharp4, at: 1, chord: 2),
                    drawn(Pitch(.g, 4), at: 2, lasting: 2, chord: 3)]
private let bar3 = [drawn(Pitch(.c, 6), at: 0, lasting: 4, chord: 6),
                    drawn(nil, staff: 2, at: 0, lasting: 4, chord: 104, wholeBarRest: true)]
private let bar4 = [drawn(Pitch(.c, 5), at: 0, lasting: 4, chord: 7),
                    drawn(nil, staff: 2, at: 0, lasting: 4, chord: 105, wholeBarRest: true)]

/// Four bars for two hands.
/// Bar 1: F♯4 (with its ♯), F♯4 (the ♯ holds), G4 over a whole-note C3; symbols F♯4, C3, F♯4, G4.
/// Bar 2: A5 and a rest over E2 and D3; symbols A5, E2, rest, D3.
/// Bar 3: C6 over a whole-bar rest. Bar 4: C5 over a whole-bar rest.
/// The right hand goes from F♯4 (staff position 1) to C6 (12); the left from E2 (−2) to D3 (4).
private let bars = piece([
    bar1,
    [drawn(Pitch(.a, 5), at: 0, lasting: 2, chord: 4),
     drawn(Pitch(.e, 2), staff: 2, at: 0, lasting: 2, chord: 102),
     drawn(nil, at: 2, lasting: 2, chord: 5),
     drawn(Pitch(.d, 3), staff: 2, at: 2, lasting: 2, chord: 103)],
    bar3,
    bar4,
])

private let barsURL = URL(fileURLWithPath: "/tmp/clefwise-tests/bars.musicxml")

/// What the staff card shows at one point: the bar, the note asked in it and those done.
private struct Step: Equatable, CustomStringConvertible {
    let bar: Int
    let current: Int?
    let answered: Set<Int>

    init(_ bar: Int, _ current: Int?, _ answered: Set<Int> = []) {
        self.bar = bar
        self.current = current
        self.answered = answered
    }

    init(_ display: BarDisplay) {
        self.init(display.measure.number, display.current, display.answered)
    }

    var description: String { "bar \(bar) at \(current.map(String.init) ?? "–") after \(answered.sorted())" }
}

private extension GameTestBench {
    var step: Step? { game.barDisplay.map(Step.init) }

    /// Starts a round and answers right until it ends or `limit` notes, noting what the card showed for each.
    func steps(limit: Int = 100) -> [Step?] {
        game.start()
        var steps: [Step?] = []
        while game.phase == .playing, steps.count < limit {
            steps.append(step)
            answerRight()
        }
        return steps
    }

    var shownQuestions: [QuestionShown] { recorder.events.compactMap { $0.event.payload as? QuestionShown } }
}

// MARK: - The bar on screen

@MainActor
@Suite final class BarDisplayTests: GameTestBench {
    @Test func anInOrderRoundGoesThroughEachBar() throws {
        game.settings.mode = .practice
        game.open(bars, from: barsURL)
        #expect(steps() == [Step(1, 0), Step(1, 2, [0]), Step(1, 3, [0, 2]), Step(2, 0), Step(3, 0), Step(4, 0)])
        #expect(game.summary?.finishedPiece == true)

        game.start()
        let display = try #require(game.barDisplay)
        #expect(display.staves.map(\.number) == [1])
        #expect(display.staves.map(\.clef) == [.treble])
        #expect(display.staves.map(\.keySignature) == [.cMajor])
        #expect(display.measure == bars.parts[0].measures[0])
        #expect(!display.isLastBar)
        // The note asked is the one drawn there.
        #expect(display.measure.symbols[0].pitch == game.question?.pitch)
        for _ in 0..<5 { answerRight() }
        #expect(game.barDisplay?.measure.number == 4)
        #expect(game.barDisplay?.isLastBar == true)
    }

    @Test func bothHandsDrawTheGrandStaff() throws {
        game.settings.mode = .practice
        game.settings.piece.hand = .both
        game.open(bars, from: barsURL)
        let display = try #require(game.barDisplay)
        #expect(display.staves.map(\.number) == [1, 2])
        #expect(display.staves.map(\.clef) == [.treble, .bass])
        // Lower staff first at each onset, as the notes are read: C3, then the F♯ above it.
        #expect(steps() == [Step(1, 1), Step(1, 0, [1]), Step(1, 2, [0, 1]), Step(1, 3, [0, 1, 2]),
                            Step(2, 1), Step(2, 0, [1]), Step(2, 3, [0, 1]), Step(3, 0), Step(4, 0)])
    }

    @Test func oneHandDrawsItsOwnStaff() {
        game.settings.mode = .practice
        game.open(bars, from: barsURL)
        game.settings.piece.hand = .left
        #expect(game.barDisplay?.staves.map(\.number) == [2])
        #expect(game.barDisplay?.staves.map(\.clef) == [.bass])
        #expect(steps() == [Step(1, 1), Step(2, 1), Step(2, 3, [1])])

        game.settings.piece.hand = .right
        #expect(game.barDisplay?.staves.map(\.number) == [1])
        // Both hands, but from bar 3 the left hand only rests: its staff isn't needed.
        game.settings.piece.hand = .both
        game.settings.piece.startBar = 3
        #expect(game.barDisplay?.staves.map(\.number) == [1])
    }

    @Test func aSprintThatWrapsStartsThePassAfresh() {
        game.settings.mode = .sprint
        game.open(bars, from: barsURL)
        let pass = [Step(1, 0), Step(1, 2, [0]), Step(1, 3, [0, 2]), Step(2, 0), Step(3, 0), Step(4, 0)]
        // Back in bar 1, the notes done are this pass's, not the last one's.
        #expect(steps(limit: 8) == pass + [Step(1, 0), Step(1, 2, [0])])
    }

    @Test func shuffledRoundsMarkOnlyTheNoteAsked() throws {
        game.settings.mode = .practice
        game.settings.piece.order = .shuffled
        game.settings.piece.hand = .both
        game.open(bars, from: barsURL)
        game.start()
        for _ in 0..<40 {
            let display = try #require(game.barDisplay)
            let question = try #require(game.question)
            #expect(display.answered.isEmpty)
            let current = try #require(display.current)
            #expect(display.measure.symbols[current].pitch == question.pitch)
            #expect(display.staves.map(\.number) == [1, 2])
            answerRight()
        }
    }

    @Test func betweenRoundsTheNextRoundsFirstBarShows() {
        game.settings.mode = .practice
        game.open(bars, from: barsURL)
        #expect(step == Step(1, nil))
        game.settings.piece.startBar = 2
        #expect(step == Step(2, nil))
        _ = steps()
        #expect(game.phase == .finished)
        #expect(step == Step(2, nil))
        game.dismissSummary()
        game.settings.piece.hand = .left
        game.settings.piece.startBar = 1
        #expect(step == Step(1, nil))
        #expect(game.barDisplay?.staves.map(\.number) == [2])
        // Nothing to ask from bar 3 in the left hand: no bar.
        game.settings.piece.startBar = 3
        #expect(game.barDisplay == nil)
    }

    @Test func stavesFitTheRoundsNotesInEveryBar() throws {
        game.settings.mode = .practice
        game.open(bars, from: barsURL)
        // Bar 1 only goes up to G4, but the round reaches C6 in bar 3.
        #expect(game.barDisplay?.staves.map(\.positions) == [0...12])
        // From bar 4 the C6 is behind; C5 is on the staff, which counts in full anyway.
        game.settings.piece.startBar = 4
        #expect(game.barDisplay?.staves.map(\.positions) == [0...8])
        game.settings.piece.startBar = 1
        game.settings.piece.hand = .left
        // E2, two steps under the bass staff, comes in bar 2.
        #expect(game.barDisplay?.staves.map(\.positions) == [-2...8])

        // Unchanged from bar to bar.
        game.settings.piece.hand = .both
        game.start()
        var seen: Set<[ClosedRange<Int>]> = []
        while game.phase == .playing {
            seen.insert(try #require(game.barDisplay).staves.map(\.positions))
            answerRight()
        }
        #expect(seen == [[0...12, -2...8]])
    }

    @Test func positionsGoByWhereNotesAreWritten() {
        // E6 under 8va is written E5, on the top space; C4 sits on the first ledger line below.
        let high = piece(staves: 1, [[drawn(Pitch(.e, 6), at: 0, chord: 1, shift: 1), drawn(Pitch(.c, 4), at: 1, chord: 2)]])
        game.open(high, from: barsURL)
        #expect(game.barDisplay?.staves.map(\.positions) == [-2...8])
    }

    // MARK: Signs and answers

    @Test func barViewQuestionsPrintTheBarsSigns() throws {
        game.settings.mode = .practice
        game.open(bars, from: barsURL)
        game.start()
        var question = try #require(game.question)
        #expect(question.pitch == fSharp4 && question.printedAccidental == .sharp)
        game.answer(.f, .sharp)
        question = try #require(game.question)
        // The ♯ earlier in the bar holds, so none is printed; the answer is still F♯.
        #expect(question.pitch == fSharp4)
        #expect(question.printedAccidental == nil)
        #expect(question.keySignature == .cMajor && question.clef == .treble && question.octaveShift == 0)
        game.answer(.f, .sharp)
        #expect(game.score == 2)
        #expect(game.question?.pitch == Pitch(.g, 4))

        // F with no sign of its own is still F♯ in that bar.
        game.start()
        game.answer(.f, .sharp)
        game.answer(.f, .natural)
        #expect(game.isShowingMiss)
        #expect(game.score == 1 && game.attempts == 2)
    }

    @Test func withTheWholeBarOffNotesComeOnTheirOwnAsBefore() throws {
        game.settings.mode = .practice
        game.settings.piece.showsWholeBar = false
        game.open(bars, from: barsURL)
        #expect(game.barDisplay == nil)
        game.start()
        #expect(game.barDisplay == nil)
        #expect(game.barStrip == nil)
        #expect(game.question?.printedAccidental == .sharp)
        game.answer(.f, .sharp)
        // On its own the second F♯ needs its sign printed.
        #expect(game.question?.pitch == fSharp4)
        #expect(game.question?.printedAccidental == .sharp)
        #expect(steps().allSatisfy { $0 == nil })
    }

    @Test func theSettingIsFixedForARound() {
        game.settings.mode = .practice
        game.open(bars, from: barsURL)
        game.start()
        game.settings.piece.showsWholeBar = false
        #expect(game.barDisplay != nil)
        answerRight()
        #expect(step == Step(1, 2, [0]))
        #expect(game.question?.printedAccidental == nil)
        game.stop()
        #expect(game.barDisplay == nil)
        game.start()
        #expect(game.barDisplay == nil)
        game.settings.piece.showsWholeBar = true
        answerRight()
        #expect(game.barDisplay == nil)
        #expect(game.question?.printedAccidental == .sharp)
    }

    @Test func aPartWithoutBarsShowsOneNoteAtATime() throws {
        let part = bars.parts[0]
        let plain = Score(title: "No bars", parts: [ScorePart(name: "Piano", notes: part.notes, measureCount: 4,
                                                             staffCount: 2, skippedNoteCount: 0)])
        game.settings.mode = .practice
        game.open(plain, from: barsURL)
        #expect(game.barDisplay == nil)
        game.start()
        answerRight()
        #expect(game.barDisplay == nil)
        #expect(game.barStrip == nil)
        #expect(game.question?.printedAccidental == .sharp)
    }

    @Test func aClefTheBarViewCannotDrawShowsThatBarsNotesOnTheirOwn() throws {
        // Bar 2's lower staff is in a clef the bar view can't draw, so its notes there are left out.
        let alto = piece(clef: { bar, staff in bar == 2 && staff == 2 ? nil : staff == 1 ? .treble : .bass }, [
            bar1,
            [drawn(Pitch(.a, 5), at: 0, lasting: 2, chord: 4), drawn(nil, at: 2, lasting: 2, chord: 5)],
            bar3,
            bar4,
        ])
        game.settings.mode = .practice
        game.settings.piece.hand = .both
        game.open(alto, from: barsURL)
        #expect(steps() == [Step(1, 1), Step(1, 0, [1]), Step(1, 2, [0, 1]), Step(1, 3, [0, 1, 2]),
                            nil, Step(3, 0), Step(4, 0)])
        #expect(shownQuestions.map(\.barView) == [true, true, true, true, false, true, true])

        // The right hand only needs the upper staff, which bar 2 can draw.
        game.settings.piece.hand = .right
        #expect(steps() == [Step(1, 0), Step(1, 2, [0]), Step(1, 3, [0, 2]), Step(2, 0), Step(3, 0), Step(4, 0)])
    }

    // MARK: The bar strip

    @Test func theStripFollowsTheRound() {
        game.settings.mode = .practice
        game.open(bars, from: barsURL)
        #expect(game.barStrip == nil)
        game.start()
        #expect(game.barStrip == Game.BarStrip(bars: 1...4, current: 1, pieceBars: 4, showsDone: true))
        for _ in 0..<3 { answerRight() }
        #expect(game.barStrip?.current == 2)
        game.stop()
        #expect(game.barStrip == nil)

        game.settings.piece.hand = .left
        game.start()
        #expect(game.barStrip?.bars == 1...2)
        game.stop()

        game.settings.piece.hand = .right
        game.settings.piece.startBar = 2
        game.settings.piece.order = .shuffled
        game.start()
        #expect(game.barStrip?.bars == 2...4)
        #expect(game.barStrip?.pieceBars == 4)
        #expect(game.barStrip?.showsDone == false)
    }

    // MARK: Settings and the log

    @Test func settingsSavedBeforeTheBarViewTurnItOn() throws {
        let saved = #"{"part":1,"hand":"left","order":"shuffled","startBar":3,"oneNotePerChord":true}"#
        let old = try JSONDecoder().decode(Game.PieceSettings.self, from: Data(saved.utf8))
        #expect(old.showsWholeBar)
        #expect(old.part == 1 && old.hand == .left && old.order == .shuffled && old.startBar == 3 && old.oneNotePerChord)

        var off = Game.PieceSettings()
        off.showsWholeBar = false
        #expect(try !JSONDecoder().decode(Game.PieceSettings.self, from: JSONEncoder().encode(off)).showsWholeBar)

        // Through a launch, from settings saved before the bar view existed.
        let defaults = InMemoryDefaults()
        defaults.set(Data(#"{"naming":"solfege","piece":{"hand":"both","startBar":2}}"#.utf8), forKey: "settings")
        let launched = Game(defaults: defaults, recorder: MemoryUsageRecorder(), library: .temporary())
        #expect(launched.settings.piece.showsWholeBar)
        #expect(launched.settings.piece.hand == .both && launched.settings.naming == .solfege)
    }

    @Test func questionsSayHowTheyWereShown() throws {
        game.settings.mode = .practice
        game.open(bars, from: barsURL)
        game.start()
        answerRight()
        var shown = shownQuestions
        try #require(shown.count == 2)
        #expect(shown.map(\.barView) == [true, true])
        #expect(shown.map(\.barStaves) == [[1], [1]])
        #expect(shown.map(\.pieceNote?.symbolIndex) == [0, 2])
        // What's printed: the bar's ♯, then none.
        #expect(shown.map(\.printedAccidental) == [1, nil])
        #expect(shown.map(\.pitch.name) == ["F♯4", "F♯4"])

        game.stop()
        game.settings.piece.hand = .both
        game.start()
        let grand = try #require(shownQuestions.last)
        #expect(grand.barView == true && grand.barStaves == [1, 2])
        #expect(grand.pieceNote == PieceNoteRef(measure: 1, staff: 2, onset: 0, chord: 101, symbolIndex: 1))

        game.stop()
        game.settings.piece.hand = .right
        game.settings.piece.showsWholeBar = false
        #expect(recorder.events.contains {
            $0.event == .settingChanged(SettingChanged(setting: "piece.showsWholeBar", from: .bool(true), to: .bool(false)))
        })
        game.start()
        answerRight()
        shown = Array(shownQuestions.suffix(2))
        #expect(shown.map(\.barView) == [false, false])
        #expect(shown.map(\.barStaves) == [nil, nil])
        #expect(shown.map(\.pieceNote?.symbolIndex) == [0, 2])
        #expect(shown.map(\.printedAccidental) == [1, 1])

        game.stop()
        game.closePiece()
        game.start()
        let random = try #require(shownQuestions.last)
        #expect(random.barView == nil && random.barStaves == nil && random.pieceNote == nil)
    }
}
