import Foundation
import Testing
@testable import Clefwise

// Bars as the importer lays them out for the bar view. bar-view.musicxml is an original two-staff
// piece written the way a notation app exports one; bar-signs.musicxml has hardly any
// <accidental> elements, so its signs come from the rule; bar-values.musicxml covers note values,
// rests, voices and stems. The older fixtures are checked too.

private func load(_ name: String) throws -> Score {
    let url = try #require(Fixtures.url(name))
    return try MusicXMLImporter.load(from: url)
}

private func onlyPart(_ name: String) throws -> ScorePart {
    let parts = try load(name).parts
    try #require(parts.count == 1)
    return parts[0]
}

private extension BarSymbol {
    /// "F♯4", "rest", or "bar rest" for a whole-bar rest.
    var label: String { pitch?.name ?? (isWholeBarRest ? "bar rest" : "rest") }
    /// The label and the sign printed in the bar: "F4 ♮", "F♯4" (no sign), "rest".
    var signed: String { label + (accidental.map { " \($0.symbol)" } ?? "") }
}

private extension ScoreMeasure {
    func on(staff: Int) -> [BarSymbol] { symbols.filter { $0.staff == staff } }
}

private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

@Suite struct BarViewPieceTests {
    private let piano: ScorePart

    init() throws {
        piano = try onlyPart("bar-view.musicxml")
    }

    @Test func barsStartWithThePickup() {
        #expect(piano.name == "Piano" && piano.staffCount == 2)
        #expect(piano.measureCount == 10 && piano.measures.count == 10)
        #expect(piano.measures.map(\.number) == Array(1...10))
        #expect(piano.measures.map(\.start) == [0, 1, 5, 9, 13, 17, 21, 25, 29, 33])
        #expect(piano.measures.map(\.length) == [1, 4, 4, 4, 4, 4, 4, 4, 4, 4])
        #expect(piano.notes.count == 108 && piano.skippedNoteCount == 0)
    }

    @Test func pickupBar() throws {
        let bar = piano.measures[0]
        #expect(bar.symbols.map(\.label) == ["B4", "bar rest", "E5"])
        #expect(bar.symbols.map(\.offset) == [0, 0, 0.5])
        // The left hand waits: a bar rest as long as the pickup.
        let rest = bar.symbols[1]
        #expect(rest.staff == 2 && rest.voice == 5 && rest.duration == 1 && rest.accidental == nil)
        #expect(rest.clef == .bass && rest.restPosition == nil && !rest.tiedToNext)
    }

    @Test func stavesStartWithTheirClefAndKey() {
        #expect(piano.measures.allSatisfy { $0.staves.map(\.keySignature) == [KeySignature(fifths: 1), KeySignature(fifths: 1)] })
        #expect(piano.measures.map { $0.staves[0].clef } == Array(repeating: .treble, count: 10))
        // The left hand moves to the treble clef halfway through bar 7, so bar 8 starts in it.
        #expect(piano.measures.map { $0.staves[1].clef }
                == [.bass, .bass, .bass, .bass, .bass, .bass, .bass, .treble, .bass, .bass])
    }

    @Test func clefChangesPartwayThroughABar() {
        let bar7 = piano.measures[6].on(staff: 2), bar8 = piano.measures[7].on(staff: 2)
        #expect(bar7.map(\.label) == ["E2", "B2", "E3", "G3", "B3", "E4", "G4", "B4"])
        #expect(bar7.map(\.clef) == [.bass, .bass, .bass, .bass, .treble, .treble, .treble, .treble])
        // Positions follow the clef: B3 hangs below the treble staff, B4 is on its middle line.
        #expect(bar7.compactMap(\.position) == [-2, 2, 5, 7, -3, 0, 2, 4])
        #expect(bar8.map(\.label) == ["C4", "E4", "A4", "E4", "B2", "D♯3", "F♯3", "A3"])
        #expect(bar8.map(\.clef) == [.treble, .treble, .treble, .treble, .bass, .bass, .bass, .bass])
    }

    @Test func noteValuesAndDots() {
        let measures = piano.measures
        // Bar 2's dotted melody, bar 3's chord and dotted eighth, bar 5's sixteenth-note run.
        #expect(measures[1].on(staff: 1).map(\.value)
                == [NoteValue(.quarter, dots: 1), NoteValue(.eighth), NoteValue(.quarter), NoteValue(.quarter)])
        #expect(measures[1].on(staff: 1).map(\.duration) == [1.5, 0.5, 1, 1])
        #expect(measures[2].on(staff: 1).map(\.value) == [NoteValue(.half), NoteValue(.half), NoteValue(.half),
                                                         NoteValue(.eighth, dots: 1), NoteValue(.sixteenth),
                                                         NoteValue(.quarter)])
        #expect(measures[4].on(staff: 1).map(\.value.kind)
                == [.quarter, .sixteenth, .sixteenth, .sixteenth, .sixteenth, .quarter, .quarter])
        #expect(measures[4].on(staff: 1).map(\.offset) == [0, 1, 1.25, 1.5, 1.75, 2, 3])
        #expect(measures[1].on(staff: 2).allSatisfy { $0.value == NoteValue(.eighth) && $0.duration == 0.5 })
        #expect(measures[9].symbols.allSatisfy { $0.value == NoteValue(.whole) && $0.duration == 4 })
    }

    @Test func triplet() {
        let upper = piano.measures[6].on(staff: 1)
        let triplet = Array(upper.prefix(3))
        #expect(triplet.map(\.label) == ["E6", "F♯6", "G6"])
        // Written as eighths, each lasting a third of a beat.
        #expect(triplet.allSatisfy { $0.value == NoteValue(.eighth) && close($0.duration, 1.0 / 3) })
        #expect(zip(triplet.map(\.offset), [0, 1.0 / 3, 2.0 / 3]).allSatisfy(close))
        #expect(upper[3].offset == 1 && upper[3].value == NoteValue(.quarter, dots: 1))
    }

    @Test func eightVaInTheRightHand() {
        let bar7 = piano.measures[6].on(staff: 1), bar8 = piano.measures[7].on(staff: 1)
        #expect(bar7.allSatisfy { $0.octaveShift == 1 })
        #expect(bar7.compactMap(\.writtenPitch?.name) == ["E5", "F♯5", "G5", "B5", "A5", "G5"])
        // The line ends halfway through bar 8, before the chord.
        #expect(bar8.map(\.label) == ["A6", "G6", "F♯6", "D♯5", "F♯5", "B5"])
        #expect(bar8.map(\.octaveShift) == [1, 1, 1, 0, 0, 0])
        #expect(piano.measures[6].on(staff: 2).allSatisfy { $0.octaveShift == 0 })
    }

    @Test func twoVoicesAndRests() throws {
        let upper = piano.measures[5].on(staff: 1)
        #expect(upper.map(\.label) == ["G5", "rest", "C5", "B4", "E5", "rest"])
        #expect(upper.map(\.voice) == [1, 2, 2, 2, 1, 2])
        #expect(upper.map(\.offset) == [0, 0, 0.5, 1, 2, 2])
        #expect(upper.map(\.value.kind) == [.half, .eighth, .eighth, .quarter, .half, .half])
        // The second voice's rests are placed low, on F4 and G4.
        #expect(upper.map(\.restPosition) == [nil, 1, nil, nil, nil, 2])
        #expect(upper.map(\.stemUp) == [true, nil, false, false, true, nil])
        #expect(upper.allSatisfy { $0.accidental == nil && !$0.isWholeBarRest })
        #expect(piano.measures[5].on(staff: 2).allSatisfy { $0.voice == 5 })

        // A quarter rest in the left hand of bar 5 isn't a bar rest.
        let rest = try #require(piano.measures[4].symbols.first { $0.isRest })
        #expect(rest.staff == 2 && rest.offset == 2 && rest.value == NoteValue(.quarter))
        #expect(!rest.isWholeBarRest && rest.restPosition == nil)
    }

    @Test func chords() {
        let bar3 = piano.measures[2].on(staff: 1)
        #expect(bar3.prefix(3).map(\.label) == ["A4", "C5", "E5"])
        #expect(Set(bar3.prefix(3).map(\.chord)).count == 1 && bar3[2].chord != bar3[3].chord)
        let lower = piano.measures[8].on(staff: 2)
        #expect(lower.map(\.label) == ["F2", "A2", "C3", "B1", "F♯2", "A2"])
        #expect(lower.map(\.chord) == [lower[0].chord, lower[0].chord, lower[0].chord,
                                       lower[3].chord, lower[3].chord, lower[3].chord])
        #expect(lower[0].chord != lower[3].chord)
    }

    @Test func stemsAsTheScoreGivesThem() {
        #expect(piano.measures[1].on(staff: 2).map(\.stemUp) == [true, true, true, true, false, false, false, false])
        #expect(piano.measures[1].on(staff: 1).allSatisfy { $0.stemUp == false })
        // Whole notes have no stem, so the score gives no direction.
        #expect(piano.measures[9].symbols.allSatisfy { $0.stemUp == nil })
    }

    @Test func tieAcrossTheBarLine() throws {
        let start = try #require(piano.measures[3].on(staff: 1).last)
        let end = try #require(piano.measures[4].symbols.first)
        #expect(start.label == "B4" && start.tiedToNext && !start.tiedFromPrevious)
        #expect(end.label == "B4" && end.tiedFromPrevious && !end.tiedToNext && end.offset == 0 && end.accidental == nil)
        // The held-over B is drawn but not asked.
        #expect(!piano.notes.contains { $0.measure == 5 && $0.symbolIndex == 0 })
        #expect(!piano.notes.contains { $0.measure == 5 && $0.onset == 13 && $0.staff == 1 })
        #expect(piano.measures.flatMap(\.symbols).filter(\.tiedFromPrevious).count == 1)
        #expect(piano.measures.flatMap(\.symbols).filter(\.tiedToNext).count == 1)
    }

    @Test func signsAsTheScorePrintsThem() throws {
        let printed = piano.measures.flatMap { measure in
            measure.symbols.filter { $0.accidental != nil }.map { "bar \(measure.number): \($0.signed)" }
        }
        #expect(printed == [
            "bar 4: D♯5 ♯", "bar 4: D♯3 ♯",   // each hand's second D♯ keeps the first one's sharp
            "bar 5: D♯5 ♯",                   // and the next bar needs it again
            "bar 8: D♯5 ♯", "bar 8: D♯3 ♯",
            "bar 9: F5 ♮", "bar 9: F2 ♮", "bar 9: F♯5 ♯", "bar 9: F♯2 ♯", "bar 9: D♯5 ♯",
        ])
        // On its own, the second D♯ of bar 4 has to show its sharp; in the bar it doesn't.
        let carried = try #require(piano.notes.first { $0.measure == 4 && $0.staff == 1 && $0.onset == 10.5 })
        #expect(carried.pitch == Pitch(.d, 5, .sharp) && carried.printedAccidental == .sharp)
        let (measure, index) = try #require(piano.symbol(for: carried))
        #expect(measure.symbols[index].pitch == carried.pitch && measure.symbols[index].accidental == nil)
    }

    @Test func beamsAsTheScoreWritesThem() {
        let measures = piano.measures
        // The pickup's two eighths; the left hand's eighths in fours, as written.
        #expect(measures[0].beamMarks() == ["[", "]"])
        #expect(measures[1].beamMarks(staff: 2) == ["[", "=", "=", "]", "[", "=", "=", "]"])
        // An eighth after a dotted quarter has a flag of its own.
        #expect(measures[1].beamMarks() == ["-", "-", "-", "-"])
        // A dotted eighth and a sixteenth, with a backward hook; a run of sixteenths.
        #expect(measures[2].beamMarks() == ["-", "[", "]<", "-"])
        #expect(measures[4].beamMarks() == ["-", "[[", "==", "==", "]]", "-", "-"])
        // The triplet; the second voice's eighth after its rest isn't beamed.
        #expect(measures[6].beamMarks().prefix(3) == ["[", "=", "]"])
        #expect(measures[5].beamMarks(staff: 1, voice: 2) == ["r", "-", "-", "r"])
        // Bars of chords and whole notes have none.
        #expect(measures[8].symbols.allSatisfy { $0.beams.isEmpty } && measures[9].symbols.allSatisfy { $0.beams.isEmpty })
        #expect(measures.flatMap(\.symbols).filter { !$0.beams.isEmpty }.count == 63)
    }

    @Test func timeSignature() {
        #expect(piano.measures.allSatisfy { $0.time == TimeSignature(beats: 4, beatType: 4) })
        #expect(piano.measures.map(\.printsTime) == [true] + Array(repeating: false, count: 9))
    }

    @Test func notesStayInReadingOrder() {
        // The bar layout doesn't change the notes: lower staff first, then low to high.
        #expect(piano.notes.prefix(8).map(\.pitch.name) == ["B4", "E5", "E2", "G5", "B2", "E3", "G3", "F♯5"])
        #expect(piano.notes.map(\.onset) == piano.notes.map(\.onset).sorted())
    }
}

@Suite struct BarSignRuleTests {
    private let piano: ScorePart

    init() throws {
        piano = try onlyPart("bar-signs.musicxml")
    }

    @Test func aSignHoldsForItsOctaveAndStaffUntilTheBarLine() {
        let bar = piano.measures[0]
        // F♮4 holds for the next F4 but not for F5; F♯4 then needs its sharp back.
        #expect(bar.on(staff: 1).map(\.signed) == ["F4 ♮", "F4", "F5 ♮", "F♯4 ♯"])
        // The lower staff keeps its own signs.
        #expect(bar.on(staff: 2).map(\.signed) == ["rest", "F4 ♮", "F4"])
        // One note at a time, every F♮ shows its natural.
        #expect(piano.notes.filter { $0.measure == 1 }.map(\.printedAccidental) == [.natural, .natural, .natural, .natural, .natural, nil])
    }

    @Test func aNewBarStartsFromTheKeyAndCourtesySignsPrint() {
        // The C♮ and the bracketed F♯ are courtesy signs from the score.
        #expect(piano.measures[1].on(staff: 1).map(\.signed) == ["F4 ♮", "C5 ♮", "F♯5 ♯", "B♭4 ♭"])
        #expect(piano.measures[1].on(staff: 2).map(\.label) == ["bar rest"])
    }

    @Test func aTiedOverNotePrintsNothingAndHoldsNothing() throws {
        let bar3 = piano.measures[2].on(staff: 1)
        #expect(bar3.map(\.signed) == ["B♭4", "B♭4 ♭", "G4", "E♭5 ♭"])
        #expect(bar3[0].tiedFromPrevious && !bar3[0].tiedToNext && bar3[3].tiedToNext)
        // Unless the score prints the sign again; then the next E♭ needs it, and E♮ cancels it.
        let bar4 = piano.measures[3].on(staff: 1)
        #expect(bar4.map(\.signed) == ["E♭5 ♭", "G5", "E♭5 ♭", "E5 ♮"])
        #expect(bar4[0].tiedFromPrevious && !bar4[1].tiedFromPrevious)
        // One note at a time, E5 is plain from the key.
        let e5 = try #require(piano.notes.first { $0.measure == 4 && $0.pitch == Pitch(.e, 5) })
        #expect(e5.printedAccidental == nil)
    }

    @Test func aTiedOverNoteSharesItsChordsID() throws {
        let bar4 = piano.measures[3].on(staff: 1)
        #expect(bar4[0].chord == bar4[1].chord && bar4[1].chord != bar4[2].chord)
        let g5 = try #require(piano.notes.first { $0.measure == 4 && $0.pitch == Pitch(.g, 5) })
        #expect(g5.chord == bar4[0].chord)
        // The tied-over E♭ isn't asked, so G5 is the only note of its chord.
        #expect(piano.notes.filter { $0.chord == g5.chord }.count == 1)
    }

    @Test func signsGoByTheWrittenOctaveAndHoldAcrossVoices() {
        let bar = piano.measures[4]
        // Under the 8va line F6 is written as F5, whose natural is already in force.
        #expect(bar.on(staff: 1).map(\.signed) == ["F5 ♮", "F6", "F♯6 ♯", "F♯5"])
        #expect(bar.on(staff: 1).map(\.octaveShift) == [0, 1, 1, 0])
        // Voice 6's F4 keeps voice 5's natural; its F♯4 needs the sharp.
        #expect(bar.on(staff: 2).map(\.signed) == ["F4 ♮", "rest", "F4", "G4", "F♯4 ♯"])
        #expect(bar.on(staff: 2).map(\.voice) == [5, 6, 6, 5, 6])
    }

    @Test func restsPrintNoSign() {
        #expect(piano.measures.flatMap(\.symbols).filter(\.isRest).allSatisfy { $0.accidental == nil })
    }
}

@Suite struct BarValueTests {
    private let cello: ScorePart

    init() throws {
        cello = try onlyPart("bar-values.musicxml")
    }

    @Test func valuesWithoutATypeComeFromTheDuration() {
        let bar = cello.measures[0]
        #expect(bar.symbols.map(\.label) == ["C3", "E3", "F3", "G3", "rest"])
        // A dotted quarter without a type, and a triplet eighth without one: the triplet is undone.
        #expect(bar.symbols.map(\.value) == [NoteValue(.quarter, dots: 1), NoteValue(.eighth), NoteValue(.eighth),
                                             NoteValue(.eighth), NoteValue(.eighth)])
        #expect(zip(bar.symbols.map(\.duration), [1.5, 1.0 / 3, 1.0 / 3, 1.0 / 3, 0.5]).allSatisfy(close))
        #expect(zip(bar.symbols.map(\.offset), [0, 1.5, 1.5 + 1.0 / 3, 1.5 + 2.0 / 3, 2.5]).allSatisfy(close))
    }

    @Test func stems() {
        // Up, down, "none", and none given.
        #expect(cello.measures[0].symbols.map(\.stemUp) == [true, false, nil, nil, nil])
        #expect(cello.measures[2].symbols.map(\.stemUp) == [nil, false, false])
    }

    @Test func wholeBarRests() {
        // <rest measure="yes"/> in 3/4: drawn as a bar rest, lasting three beats.
        let barRest = cello.measures[1].symbols
        #expect(barRest.map(\.label) == ["bar rest"])
        #expect(barRest[0].duration == 3 && barRest[0].value == NoteValue(.half, dots: 1))
        // A rest without a type that lasts the whole bar is one too.
        #expect(cello.measures[2].symbols.map(\.label) == ["bar rest", "A2", "B2"])
        // A typed rest isn't.
        #expect(cello.measures[0].symbols[4].isRest && !cello.measures[0].symbols[4].isWholeBarRest)
    }

    @Test func namedVoicesGetNumbersOfTheirOwn() {
        #expect(cello.measures[2].symbols.map(\.voice) == [1, 2, 2])
        // No <voice> means voice 1.
        #expect(cello.measures[4].symbols.map(\.voice) == [1])
    }

    @Test func doubleDotsAndARestPlacedOnTheStaff() {
        let bar = cello.measures[3].symbols
        #expect(bar.map(\.value) == [NoteValue(.quarter, dots: 2), NoteValue(.sixteenth), NoteValue(.quarter)])
        #expect(bar.map(\.offset) == [0, 1.75, 2])
        // A2 is the bass staff's first space.
        #expect(bar.map(\.restPosition) == [nil, nil, 1])
    }

    @Test func graceNotesHiddenRestsAndDoubleSharpsAreNotDrawn() {
        #expect(cello.measures[4].symbols.map(\.label) == ["C3"])
        #expect(cello.skippedNoteCount == 1)
        #expect(cello.notes.count == 9)
    }
}

@Suite struct BarLayoutOfOlderFixturesTests {
    @Test func clefChangesAtABarStart() throws {
        // Bar 2 switches the lower staff to treble after a <backup>; the switch back is written
        // at the end of bar 2, so bar 3 starts in bass.
        let measures = try onlyPart("grand-staff.musicxml").measures
        #expect(measures.map { $0.staves.map(\.clef) } == [[.treble, .bass], [.treble, .treble], [.treble, .bass]])
        #expect(measures[1].on(staff: 2).map(\.clef) == [.treble, .treble])
        #expect(measures[2].on(staff: 2).map(\.clef) == [.bass])
        #expect(measures[0].symbols.map(\.label) == ["G4", "B4", "D5", "G2", "D3", "F♯5", "A4", "B2", "D3"])
        #expect(measures[0].symbols.map(\.voice) == [1, 1, 1, 5, 5, 1, 1, 5, 5])
    }

    @Test func tiesOverTwoBarLinesAndAPickup() throws {
        let flute = try onlyPart("ties-rests-grace.musicxml")
        #expect(flute.measures.map(\.start) == [0, 1, 4, 7])
        #expect(flute.measures.map(\.length) == [1, 3, 3, 3])
        // The grace note and the cue aren't drawn.
        #expect(flute.measures.map { $0.symbols.map(\.label) } == [["rest", "D4"], ["G4", "E4"], ["E4"], ["E4", "rest", "C5"]])
        let e4 = flute.measures.compactMap { $0.symbols.first { $0.pitch == Pitch(.e, 4) } }
        #expect(e4.map(\.tiedToNext) == [true, true, false])
        #expect(e4.map(\.tiedFromPrevious) == [false, true, true])
        #expect(e4.map(\.value) == [NoteValue(.half), NoteValue(.half, dots: 1), NoteValue(.quarter)])
        #expect(flute.measures[0].symbols[0].value == NoteValue(.eighth))
        #expect(!flute.measures[0].symbols[0].isWholeBarRest)
    }

    @Test func otherClefsLeaveTheStaffUndrawn() throws {
        let viola = try onlyPart("clefs.musicxml")
        #expect(viola.measures.map { $0.staves.map(\.clef) } == [[nil], [.treble], [nil], [.bass]])
        #expect(viola.measures.map(\.symbols.count) == [0, 1, 0, 1])
    }

    @Test func signsCarryInTheBarUnlikeOneNoteAtATime() throws {
        let violin = try onlyPart("accidentals.musicxml")
        #expect(violin.measures.map { $0.staves[0].keySignature.fifths } == [0, 1, 1, -1])
        #expect(violin.measures.map { $0.symbols.map(\.signed) } == [
            ["F♯4 ♯", "F♯4", "B♭4 ♭", "F4 ♮"],
            ["F4 ♮", "F4", "G4"],           // the double sharp isn't drawn
            ["F♯4 ♯", "F♯4", "rest"],       // a bracketed courtesy sharp; no quarter flat
            ["B♭4", "B4 ♮", "B4", "F4"],
        ])
        // On its own, bar 2's second F has to show its natural.
        #expect(violin.notes[5].measure == 2 && violin.notes[5].printedAccidental == .natural)
    }

    @Test func barRestsInEveryPart() throws {
        let parts = try load("voice-and-piano.musicxml").parts
        #expect(parts.map(\.measures.count) == [2, 2, 2])
        #expect(parts[0].measures[1].symbols.map(\.label) == ["bar rest"])
        #expect(parts[0].measures[1].symbols[0].value == NoteValue(.whole))
        #expect(parts[1].measures[0].on(staff: 1).map(\.octaveShift) == [1])
        #expect(parts[1].measures[0].staves.map(\.clef) == [.treble, .bass])
    }

    @Test func octaveLinesUpAndDown() throws {
        let symbols = try onlyPart("ottava.musicxml").measures.flatMap(\.symbols)
        #expect(symbols.map(\.octaveShift) == [0, 1, 1, 1, 1, 0, -1, 2, 0])
        #expect(symbols[6].writtenPitch == Pitch(.c, 5) && symbols[6].position == 5)
    }

    @Test func stemsFromANotationApp() throws {
        let clarinet = try onlyPart("clarinet-tune.mxl")
        #expect(clarinet.measures.flatMap(\.symbols).map(\.stemUp) == [true, true, false, false, false, false, false])
        #expect(clarinet.measures[1].symbols.map(\.signed) == ["D♯5 ♯", "E5", "C5"])
    }

    @Test func beamsAsWrittenOrByTheBeat() throws {
        // Written beams: the clarinet's pair of eighths and the cello's triplet.
        #expect(try onlyPart("clarinet-tune.mxl").measures.map { $0.beamMarks() } == [["-", "[", "]", "-"], ["-", "-", "-"]])
        let cello = try onlyPart("bar-values.musicxml")
        #expect(cello.measures[0].beamMarks() == ["-", "[", "=", "]", "r"])
        // A sixteenth after a double-dotted quarter has nothing to join.
        #expect(cello.measures[3].beamMarks() == ["-", "-", "r"])
        // The others write no beams and have no two eighths in a beat: the pickup's eighth stays
        // on its own after its rest.
        #expect(try onlyPart("ties-rests-grace.musicxml").measures[0].beamMarks() == ["r", "-"])
        for name in ["grand-staff.musicxml", "accidentals.musicxml", "bar-signs.musicxml", "ottava.musicxml",
                     "clefs.musicxml", "ties-rests-grace.musicxml", "voice-and-piano.musicxml"] {
            #expect(try load(name).parts.allSatisfy { $0.measures.allSatisfy { $0.symbols.allSatisfy { $0.beams.isEmpty } } }, "\(name)")
        }
    }

    @Test func timeSignatures() throws {
        let common = TimeSignature(beats: 4, beatType: 4), threeFour = TimeSignature(beats: 3, beatType: 4)
        #expect(try onlyPart("grand-staff.musicxml").measures.map(\.time) == [common, common, common])
        #expect(try onlyPart("bar-values.musicxml").measures.allSatisfy { $0.time == threeFour })
        let flute = try onlyPart("ties-rests-grace.musicxml")
        #expect(flute.measures.map(\.time) == Array(repeating: threeFour, count: 4))
        #expect(flute.measures.map(\.printsTime) == [true, false, false, false])
        // Every part reads its own.
        #expect(try load("voice-and-piano.musicxml").parts.allSatisfy { $0.measures.map(\.printsTime) == [true, false] })
    }
}

@Suite struct BarLayoutInvariantTests {
    static let fixtures = [
        "bar-view.musicxml", "bar-signs.musicxml", "bar-values.musicxml", "grand-staff.musicxml",
        "accidentals.musicxml", "ties-rests-grace.musicxml", "ottava.musicxml", "clefs.musicxml",
        "voice-and-piano.musicxml", "clarinet-tune.musicxml", "clarinet-tune.mxl",
        "beams.musicxml", "auto-beams.musicxml",
    ]

    @Test(arguments: fixtures) func everyNoteFindsItsSymbol(_ name: String) throws {
        for part in try load(name).parts {
            #expect(part.measures.count == part.measureCount)
            for note in part.notes {
                let (measure, index) = try #require(part.symbol(for: note), "\(note.pitch.name) in bar \(note.measure)")
                let symbol = measure.symbols[index]
                #expect(measure.number == note.measure)
                #expect(symbol.pitch == note.pitch && symbol.staff == note.staff && symbol.chord == note.chord)
                #expect(close(measure.start + symbol.offset, note.onset))
                #expect(symbol.clef == note.clef && symbol.octaveShift == note.octaveShift && !symbol.tiedFromPrevious)
            }
            let placed = part.notes.map { "\($0.measure).\($0.symbolIndex ?? -1)" }
            #expect(Set(placed).count == placed.count)
        }
    }

    @Test(arguments: fixtures) func symbolsAreInDrawingOrder(_ name: String) throws {
        for part in try load(name).parts {
            for measure in part.measures {
                #expect(measure.staves.count == part.staffCount)
                #expect(measure.symbols.allSatisfy { $0.offset >= 0 && $0.offset < measure.length })
                #expect(measure.symbols.allSatisfy { !$0.isRest || ($0.accidental == nil && !$0.tiedToNext) })
                for (a, b) in zip(measure.symbols, measure.symbols.dropFirst()) {
                    #expect(Self.drawnInOrder(a, b), "bar \(measure.number): \(a.label) before \(b.label)")
                }
            }
            // Bars follow on from each other.
            for (a, b) in zip(part.measures, part.measures.dropFirst()) {
                #expect(close(a.start + a.length, b.start))
            }
        }
    }

    /// By offset, then staff, then voice, rests first, then low to high.
    private static func drawnInOrder(_ a: BarSymbol, _ b: BarSymbol) -> Bool {
        if a.offset != b.offset { return a.offset < b.offset }
        if a.staff != b.staff { return a.staff < b.staff }
        if a.voice != b.voice { return a.voice < b.voice }
        if a.isRest != b.isRest { return a.isRest }
        guard let p = a.pitch, let q = b.pitch else { return true }
        return (p.midiNumber, p.diatonicIndex) <= (q.midiNumber, q.diatonicIndex)
    }

    @Test func aLargeScoreIsQuick() throws {
        // 1,000 bars of eighths in both hands, with an 8va line and two clef changes in every bar.
        let bars = 1000
        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
            <part id="P1">
            """
        for bar in 1...bars {
            xml += "<measure number=\"\(bar)\">"
            if bar == 1 {
                xml += "<attributes><divisions>2</divisions><key><fifths>1</fifths></key><staves>2</staves>"
                    + "<clef number=\"1\"><sign>G</sign><line>2</line></clef><clef number=\"2\"><sign>F</sign><line>4</line></clef></attributes>"
            }
            xml += "<direction><direction-type><octave-shift type=\"down\" size=\"8\"/></direction-type><staff>1</staff></direction>"
            for step in ["C", "D", "E", "F", "G", "A", "B", "C"] {
                xml += "<note><pitch><step>\(step)</step><octave>6</octave></pitch><duration>1</duration><voice>1</voice>"
                    + "<type>eighth</type><staff>1</staff></note>"
            }
            xml += "<direction><direction-type><octave-shift type=\"stop\" size=\"8\"/></direction-type><staff>1</staff></direction>"
            xml += "<backup><duration>8</duration></backup>"
            for (index, step) in ["C", "E", "G", "B", "C", "E", "G", "B"].enumerated() {
                if index == 4 { xml += "<attributes><clef number=\"2\"><sign>G</sign><line>2</line></clef></attributes>" }
                xml += "<note><pitch><step>\(step)</step><octave>\(index < 4 ? 3 : 4)</octave></pitch><duration>1</duration>"
                    + "<voice>5</voice><type>eighth</type><staff>2</staff></note>"
            }
            xml += "<attributes><clef number=\"2\"><sign>F</sign><line>4</line></clef></attributes></measure>"
        }
        xml += "</part></score-partwise>"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Clefwise-large-\(UUID().uuidString).musicxml")
        try Data(xml.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let clock = ContinuousClock()
        var score: Score?
        let elapsed = try clock.measure { score = try MusicXMLImporter.load(from: url) }
        let piano = try #require(score?.parts.first)
        #expect(piano.notes.count == bars * 16 && piano.measures.count == bars)
        #expect(piano.measures[999].on(staff: 2).map(\.clef) == Array(repeating: .bass, count: 4) + Array(repeating: .treble, count: 4))
        #expect(piano.measures.allSatisfy { $0.staves.map(\.clef) == [.treble, .bass] })
        #expect(piano.measures[500].on(staff: 1).allSatisfy { $0.octaveShift == 1 })
        #expect(elapsed < .seconds(10), "took \(elapsed)")
    }
}
