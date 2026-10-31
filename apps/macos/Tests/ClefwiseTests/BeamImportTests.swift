import Foundation
import Testing
@testable import Clefwise

// Beams and time signatures as the importer reads them. beams.musicxml writes <beam> the way
// MuseScore exports it, broken groups included; auto-beams.musicxml has none, so its notes are
// beamed by the beat. Smaller cases are written out below with `part(_:)`.
//
// Beams are spelt one character per level: "[" begin, "=" continue, "]" end, ">" forward hook,
// "<" backward hook. "[[" is a note that begins both the eighth and the sixteenth beam; "-" is a
// note drawn with flags (or none) and "r" a rest.

private func load(_ name: String) throws -> Score {
    let url = try #require(Fixtures.url(name))
    return try MusicXMLImporter.load(from: url)
}

private func onlyPart(_ name: String) throws -> ScorePart {
    let parts = try load(name).parts
    try #require(parts.count == 1)
    return parts[0]
}

extension BarSymbol {
    /// The beams spelt as above: "[[", "]<", "-" for none, "r" for a rest.
    var beamMarks: String {
        if isRest { return beams.isEmpty ? "r" : "r?" }
        if beams.isEmpty { return "-" }
        return beams.map { part in
            switch part {
            case .begin: "["
            case .continue: "="
            case .end: "]"
            case .forwardHook: ">"
            case .backwardHook: "<"
            }
        }.joined()
    }
}

private extension BarSymbol {
    /// "F♯4", or "rest".
    var label: String { pitch?.name ?? "rest" }
}

private extension ScoreMeasure {
    func on(staff: Int) -> [BarSymbol] { symbols.filter { $0.staff == staff } }
}

extension ScoreMeasure {
    /// The beams of each chord (once) and rest on a staff, in order; every voice, or just one.
    func beamMarks(staff: Int = 1, voice: Int? = nil) -> [String] {
        var seen = Set<Int>()
        return symbols
            .filter { $0.staff == staff && (voice == nil || $0.voice == voice) && seen.insert($0.chord).inserted }
            .map(\.beamMarks)
    }
}

/// `<time>` for `part(_:)`: "6/8", "3+2/8"; `attributes` such as ` symbol="common"`.
private func timeElement(_ fraction: String, _ attributes: String = "") -> String {
    let parts = fraction.split(separator: "/")
    return "<time\(attributes)><beats>\(parts[0])</beats><beat-type>\(parts[1])</beat-type></time>"
}

/// A small score with one bar per string, each a list of notes such as "r8 16[[ 16=] 8]":
/// - `r` a rest, `h` a hidden rest, `g` a grace note (before the value);
/// - the value: 4 a quarter, 8 an eighth, 16. a dotted sixteenth; then `t` for a triplet note;
/// - `+` adds a chord note a third above, without beams of its own;
/// - `[ = ] > <` the `<beam>` levels written, from level 1 (written without `number`);
/// - `~` ties the note to the next one;
/// - `@2` puts it on staff 2 (bass clef), `v5` in voice 5 (voice 1 by default, on either staff);
/// - `back` backs up to the start of the bar.
/// `times` gives each bar's `<attributes>` contents besides the first bar's divisions and clefs.
private func part(times: [Int: String] = [1: timeElement("4/4")], staves: Int = 1, _ bars: String...) throws -> ScorePart {
    let divisions = 48.0
    var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Test</part-name></score-part></part-list>
        <part id="P1">
        """
    var tied = false
    for (index, bar) in bars.enumerated() {
        xml += "<measure number=\"\(index + 1)\">"
        var attributes = times[index + 1] ?? ""
        if index == 0 {
            attributes = "<divisions>48</divisions>" + attributes + "<staves>\(staves)</staves>"
                + "<clef number=\"1\"><sign>G</sign><line>2</line></clef>"
                + (staves > 1 ? "<clef number=\"2\"><sign>F</sign><line>4</line></clef>" : "")
        }
        if !attributes.isEmpty { xml += "<attributes>\(attributes)</attributes>" }
        var position = 0.0
        for token in bar.split(separator: " ") {
            if token == "back" {
                xml += "<backup><duration>\(Int(position))</duration></backup>"
                position = 0
                continue
            }
            var rest = Substring(token)
            let kind = rest.first.flatMap { "rhg".contains($0) ? $0 : nil }
            if kind != nil { rest = rest.dropFirst() }
            let digits = rest.prefix { $0.isNumber }
            rest = rest.dropFirst(digits.count)
            let dots = rest.prefix { $0 == "." }.count
            rest = rest.dropFirst(dots)
            let triplet = rest.first == "t"
            if triplet { rest = rest.dropFirst() }
            let chord = rest.first == "+"
            if chord { rest = rest.dropFirst() }
            let marks = rest.prefix { "[=]<>".contains($0) }
            rest = rest.dropFirst(marks.count)
            let tiesOn = rest.first == "~"
            if tiesOn { rest = rest.dropFirst() }
            var staff = 1, voice = 1
            while let first = rest.first {
                let number = rest.dropFirst().prefix { $0.isNumber }
                guard ["@", "v"].contains(first), let value = Int(number) else { throw ScoreImportError(message: "bad token \(token)") }
                if first == "@" { staff = value } else { voice = value }
                rest = rest.dropFirst(1 + number.count)
            }
            let value = try #require(Int(digits), "bad token \(token)")
            let type = [1: "whole", 2: "half", 4: "quarter", 8: "eighth", 16: "16th", 32: "32nd", 64: "64th"][value]!
            let duration = Int(divisions * 4 / Double(value) * (2 - pow(0.5, Double(dots))) * (triplet ? 2.0 / 3 : 1))

            func note(_ pitch: String, chord isChord: Bool, beams: Substring) -> String {
                var note = kind == "h" ? "<note print-object=\"no\">" : "<note>"
                if kind == "g" { note += "<grace/>" }
                if isChord { note += "<chord/>" }
                if kind == "r" || kind == "h" {
                    note += "<rest/>"
                } else {
                    note += "<pitch><step>\(pitch.prefix(1))</step><octave>\(pitch.dropFirst())</octave></pitch>"
                }
                if kind != "g" { note += "<duration>\(duration)</duration>" }
                if tied && !isChord { note += "<tie type=\"stop\"/>" }
                if tiesOn && !isChord { note += "<tie type=\"start\"/>" }
                note += "<voice>\(voice)</voice><type>\(type)</type>" + String(repeating: "<dot/>", count: dots)
                if triplet { note += "<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>" }
                note += "<staff>\(staff)</staff>"
                for (level, mark) in beams.enumerated() {
                    let text = ["[": "begin", "=": "continue", "]": "end", ">": "forward hook", "<": "backward hook"][String(mark)]!
                    note += level == 0 ? "<beam>\(text)</beam>" : "<beam number=\"\(level + 1)\">\(text)</beam>"
                }
                return note + "</note>"
            }
            xml += note(staff == 1 ? "B4" : "D3", chord: false, beams: marks)
            if chord { xml += note(staff == 1 ? "D5" : "F3", chord: true, beams: "") }
            if kind != "g" {
                tied = tiesOn
                position += Double(duration)
            }
        }
        xml += "</measure>"
    }
    xml += "</part></score-partwise>"
    return try onlyPart(xml: xml)
}

/// Reads a score written out in full.
private func onlyPart(xml: String) throws -> ScorePart {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Clefwise-beams-\(UUID().uuidString).musicxml")
    try Data(xml.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let parts = try MusicXMLImporter.load(from: url).parts
    try #require(parts.count == 1)
    return parts[0]
}

// MARK: - Beams written in the score

@Suite struct WrittenBeamTests {
    private let piano: ScorePart

    init() throws {
        piano = try onlyPart("beams.musicxml")
    }

    @Test func theReferenceBar() {
        let bar = piano.measures[0]
        // An eighth rest; G4 F4 G4 B4 C5 (16 16 8 16 16) under one beam, with a second beam over
        // each pair of sixteenths, as the user's score prints it; then a B4 half note.
        #expect(bar.on(staff: 1).map(\.label) == ["rest", "G4", "F4", "G4", "B4", "C5", "B4"])
        #expect(bar.beamMarks() == ["r", "[[", "=]", "=", "=[", "]]", "-"])
        #expect(bar.on(staff: 1).last?.stemUp == false)
        // The left hand's eighths are beamed in fours, as written, not by the beat.
        #expect(bar.beamMarks(staff: 2) == ["[", "=", "=", "]", "[", "=", "=", "]"])
    }

    @Test func hooksAndThirtySeconds() {
        let bar = piano.measures[1]
        let thirtySeconds: [String] = ["[[["] + Array(repeating: "===", count: 6) + ["]]]"]
        #expect(bar.beamMarks() == ["[", "]<", "[>", "]"] + thirtySeconds + ["-"])
        #expect(bar.on(staff: 1).filter { $0.value.kind == .thirtySecond }.count == 8)
        #expect(bar.beamMarks(staff: 2) == ["-"])
    }

    @Test func everyNoteOfAChordCarriesItsBeams() {
        // The score writes each chord's <beam> on its first note only.
        let chords = piano.measures[2].symbols.filter { $0.staff == 1 && $0.voice == 1 }
        #expect(chords.map(\.label) == ["C5", "E5", "D5", "F5", "E5", "G5", "D5", "F5", "C5", "E5"])
        #expect(chords.map(\.beamMarks) == ["[", "[", "]", "]", "[", "[", "]", "]", "-", "-"])
    }

    @Test func aSecondVoiceHasItsOwnBeams() {
        let bar = piano.measures[2]
        #expect(bar.beamMarks(staff: 1, voice: 2) == ["[", "]", "[", "]", "[", "]", "[", "]"])
        #expect(bar.on(staff: 1).filter { $0.voice == 2 }.allSatisfy { $0.stemUp == false })
        #expect(bar.beamMarks(staff: 2) == ["-", "-"])
    }

    @Test func brokenGroupsGetFlags() {
        let bar = piano.measures[3]
        // A4 B4 begin a group that never ends; D5 C5 is a group of its own.
        #expect(bar.on(staff: 1).map(\.label) == ["A4", "B4", "C5", "D5", "C5", "B4"])
        #expect(bar.beamMarks() == ["-", "-", "-", "[", "]", "-"])
        // C3 E3 end a group that never began.
        #expect(bar.beamMarks(staff: 2) == ["-", "-", "-", "-"])
    }

    @Test func aTiedOverNoteKeepsItsBeams() throws {
        let bar = piano.measures[4]
        let first = try #require(bar.on(staff: 1).first)
        #expect(first.tiedFromPrevious && first.label == "B4")
        #expect(bar.beamMarks() == ["[", "=", "=", "=", "=", "]"])
    }

    @Test func timeSignatures() {
        #expect(piano.measures.map(\.time) == Array(repeating: TimeSignature(beats: 4, beatType: 4, symbol: .common), count: 4)
                + [TimeSignature(beats: 3, beatType: 4)])
        #expect(piano.measures.map(\.printsTime) == [true, false, false, false, true])
        #expect(piano.measures.map(\.length) == [4, 4, 4, 4, 3])
    }

    @Test func readingIsUnchanged() {
        // Beams change nothing about the questions: the tied-over B4 isn't asked.
        #expect(piano.skippedNoteCount == 0)
        #expect(piano.notes.count == piano.measures.flatMap(\.symbols).filter { !$0.isRest && !$0.tiedFromPrevious }.count)
        #expect(piano.notes.prefix(4).map(\.pitch.name) == ["C3", "G3", "G4", "F4"])
    }
}

// MARK: - Beams by the beat

@Suite struct BeatBeamTests {
    private let flute: ScorePart

    init() throws {
        flute = try onlyPart("auto-beams.musicxml")
    }

    @Test func theScoreHasNoBeamsOfItsOwn() throws {
        let url = try #require(Fixtures.url("auto-beams.musicxml"))
        #expect(try !String(contentsOf: url, encoding: .utf8).contains("<beam"))
        #expect(flute.measures.flatMap(\.symbols).allSatisfy { $0.stemUp == nil && $0.voice == 1 })
    }

    @Test func aPickupCountsItsBeatsFromTheEnd() {
        // Four eighths in 6/8: the last eighth of beat one, then all of beat two.
        #expect(flute.measures[0].length == 2)
        #expect(flute.measures[0].beamMarks() == ["-", "[", "=", "]"])
    }

    @Test func compoundTimeBeamsEighthsInThrees() {
        // Then a quarter and a lone eighth on the second beat.
        #expect(flute.measures[1].beamMarks() == ["[", "=", "]", "-", "-"])
        // A dotted eighth, a sixteenth and an eighth: the sixteenth's hook points back.
        #expect(flute.measures[2].beamMarks().prefix(3) == ["[", "=<", "]"])
    }

    @Test func restsBreakGroups() {
        // An eighth, a rest, an eighth: nothing to beam.
        #expect(flute.measures[2].beamMarks().suffix(3) == ["-", "r", "-"])
        // Sixteenths either side of a rest make two groups.
        #expect(flute.measures[3].beamMarks() == ["[[", "]]", "r", "[[", "]]", "-"])
    }

    @Test func simpleTimeBeamsSixteenthsInFours() {
        #expect(flute.measures[4].beamMarks() == ["[[", "==", "==", "]]", "[", "=[", "]]"])
    }

    @Test func chordsAndTriplets() {
        let bar = flute.measures[5]
        #expect(bar.beamMarks() == ["[[", "=]", "]", "[", "=", "]"])
        // Both notes of each chord.
        #expect(bar.symbols.prefix(6).map(\.beamMarks) == ["[[", "[[", "=]", "=]", "]", "]"])
        #expect(bar.symbols.suffix(3).allSatisfy { abs($0.duration - 1.0 / 3) < 1e-9 })
    }

    @Test func hooksPointToTheirBeat() {
        #expect(flute.measures[6].beamMarks() == ["[>", "]", "[", "]<"])
    }

    @Test func aNoteAcrossTheBeatIsNotBeamed() {
        #expect(flute.measures[7].beamMarks() == ["-", "-", "-"])
    }

    @Test func cutTimeBeamsEighthsInFours() {
        #expect(flute.measures[8].beamMarks() == ["[", "=", "=", "]", "[", "=", "=", "]"])
    }

    @Test func timeSignatures() {
        let sixEight = TimeSignature(beats: 6, beatType: 8), twoFour = TimeSignature(beats: 2, beatType: 4)
        let cut = TimeSignature(beats: 2, beatType: 2, symbol: .cut)
        #expect(flute.measures.map(\.time) == [sixEight, sixEight, sixEight, sixEight, twoFour, twoFour, twoFour, twoFour, cut, cut])
        #expect(flute.measures.map(\.printsTime) == [true, false, false, false, true, false, false, false, true, false])
    }
}

// MARK: - The rules, case by case

@Suite struct WrittenBeamRuleTests {
    @Test func levelsAsWritten() throws {
        let bar = try part("r8 16[[ 16=] 8] 16[[ 16]] 2").measures[0]
        #expect(bar.beamMarks() == ["r", "[[", "=]", "]", "[[", "]]", "-"])
        #expect(bar.symbols.allSatisfy { $0.beams.count == ($0.isRest ? 0 : $0.value.flags) })
    }

    @Test func groupsThatNeverEndOrNeverBeginAreDropped() throws {
        let bars = try part("8[ 8[ 8] 8 2", "8= 8] 8] 8 2", "8[ 8 8] 8 2", "2 4 8[ 8=", "8] 8 2.").measures
        // A begin with no end; the next group is kept.
        #expect(bars[0].beamMarks() == ["-", "[", "]", "-", "-"])
        // A group with no begin, and an end with no group.
        #expect(bars[1].beamMarks() == ["-", "-", "-", "-", "-"])
        // A note without a beam in the middle.
        #expect(bars[2].beamMarks() == ["-", "-", "-", "-", "-"])
        // Beams stop at the bar line.
        #expect(bars[3].beamMarks() == ["-", "-", "-", "-"])
        #expect(bars[4].beamMarks() == ["-", "-", "-"])
    }

    @Test func higherLevelsMustRunAlongTheEighthBeam() throws {
        let bars = try part("16[[ 16] 2.", "16[[ 16=] 16=[ 4", "32[[ 32=][ 32=[] 32]] 2.", "8[ 4] 2.", "8[ 8> 8] 8 2").measures
        // The sixteenth beam never ends.
        #expect(bars[0].beamMarks() == ["-", "-", "-"])
        #expect(bars[1].beamMarks() == ["-", "-", "-", "-"])
        // A third beam over a gap in the second.
        #expect(bars[2].beamMarks() == ["-", "-", "-", "-", "-"])
        // A quarter note can't be beamed.
        #expect(bars[3].beamMarks() == ["-", "-", "-"])
        // A hook on the eighth beam isn't a group, and it breaks the one it's in.
        #expect(bars[4].beamMarks() == ["-", "-", "-", "-", "-"])
    }

    @Test func missingOrExtraLevelsComeFromTheValues() throws {
        // Sixteenths written with one beam get their second; eighths written with two lose it.
        let bar = try part("16[ 16= 8] 8[[ 8]] 8.[ 16] 4").measures[0]
        #expect(bar.beamMarks() == ["[[", "=]", "]", "[", "]", "[", "]<", "-"])
    }

    @Test func aChordSharesTheBeamsOfWhicheverNoteHasThem() throws {
        let note = { (step: String, chord: Bool, beam: String?) in
            "<note>\(chord ? "<chord/>" : "")<pitch><step>\(step)</step><octave>4</octave></pitch><duration>1</duration>"
                + "<type>eighth</type>\(beam.map { "<beam number=\"1\">\($0)</beam>" } ?? "")</note>"
        }
        let xml = """
            <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Test</part-name></score-part></part-list>
            <part id="P1"><measure number="1"><attributes><divisions>2</divisions></attributes>
            \(note("C", false, nil))\(note("E", true, "begin"))\(note("G", true, nil))
            \(note("D", false, nil))\(note("F", true, nil))\(note("A", true, "end"))
            <note><pitch><step>B</step><octave>4</octave></pitch><duration>6</duration><type>half</type><dot/></note>
            </measure></part></score-partwise>
            """
        let bar = try onlyPart(xml: xml).measures[0]
        #expect(bar.symbols.map(\.beamMarks) == ["[", "[", "[", "]", "]", "]", "-"])
        // The score gives no <time>.
        #expect(bar.time == nil && !bar.printsTime)
    }

    @Test func aLevelMissingUnderAWrittenOneDropsTheGroup() throws {
        let note = { (beams: String) in
            "<note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>32nd</type>\(beams)</note>"
        }
        let xml = """
            <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Test</part-name></score-part></part-list>
            <part id="P1"><measure number="1"><attributes><divisions>8</divisions></attributes>
            \(note("<beam number=\"1\">begin</beam><beam number=\"3\">begin</beam>"))
            \(note("<beam number=\"1\">end</beam><beam number=\"3\">end</beam>"))
            \(note("<beam number=\"1\">begin</beam><beam number=\"2\">begin</beam><beam number=\"3\">begin</beam>"))
            \(note("<beam number=\"1\">end</beam><beam number=\"2\">end</beam><beam number=\"3\">end</beam>"))
            <note><rest/><duration>28</duration><type>half</type><dot/><dot/></note>
            </measure></part></score-partwise>
            """
        #expect(try onlyPart(xml: xml).measures[0].beamMarks() == ["-", "-", "[[[", "]]]", "r"])
    }

    @Test func crossStaffGroupsAreDropped() throws {
        // Voice 5 climbs from the lower staff into the upper one in one group; then a group that
        // stays on the lower staff.
        let bar = try part(staves: 2, "2v1 2v1 back 8[@2v5 8=@2v5 8=@1v5 8]@1v5 8[@2v5 8]@2v5 4@2v5").measures[0]
        #expect(bar.beamMarks(staff: 2) == ["-", "-", "[", "]", "-"])
        #expect(bar.beamMarks(staff: 1, voice: 5) == ["-", "-"])
        #expect(bar.beamMarks(staff: 1, voice: 1) == ["-", "-"])
    }

    @Test func eachStaffBeamsOnItsOwnEvenInTheSameVoice() throws {
        let bar = try part(staves: 2, "8[ 8] 2. back 8[@2 8]@2 2.@2").measures[0]
        #expect(bar.beamMarks(staff: 1) == ["[", "]", "-"])
        #expect(bar.beamMarks(staff: 2) == ["[", "]", "-"])
    }

    @Test func aBeamOverARestIsKept() throws {
        let bar = try part("8[ r8 8] 8 2").measures[0]
        #expect(bar.beamMarks() == ["[", "r", "]", "-", "-"])
    }

    @Test func tiedNotesKeepTheirBeams() throws {
        let bars = try part("2. 8[ 8]~", "8[~ 8] 2.").measures
        #expect(bars[0].beamMarks() == ["-", "[", "]"])
        #expect(bars[1].beamMarks() == ["[", "]", "-"])
        #expect(bars[1].symbols[0].tiedFromPrevious && bars[1].symbols[0].tiedToNext && bars[1].symbols[1].tiedFromPrevious)
    }

    @Test func graceNotesAndHiddenNotesAreLeftOut() throws {
        let bar = try part("8[ g8[ g8] 8] h8 8 2").measures[0]
        #expect(bar.beamMarks() == ["[", "]", "-", "-"])
    }

    @Test func onePartsBeamsDontStopAnotherBeingBeamedByTheBeat() throws {
        let xml = """
            <score-partwise version="4.0"><part-list>
            <score-part id="P1"><part-name>Written</part-name></score-part><score-part id="P2"><part-name>Plain</part-name></score-part>
            </part-list>
            <part id="P1"><measure number="1"><attributes><divisions>2</divisions></attributes>
            <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type></note>
            <note><pitch><step>D</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type></note>
            <note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type><beam>begin</beam></note>
            <note><pitch><step>F</step><octave>5</octave></pitch><duration>1</duration><type>eighth</type><beam>end</beam></note>
            <note><pitch><step>G</step><octave>5</octave></pitch><duration>4</duration><type>half</type></note>
            </measure></part>
            <part id="P2"><measure number="1"><attributes><divisions>2</divisions></attributes>
            <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>eighth</type></note>
            <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><type>eighth</type></note>
            <note><pitch><step>E</step><octave>4</octave></pitch><duration>6</duration><type>half</type><dot/></note>
            </measure></part></score-partwise>
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Clefwise-beams-\(UUID().uuidString).musicxml")
        try Data(xml.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let parts = try MusicXMLImporter.load(from: url).parts
        // A part that writes beams anywhere is taken at its word: its first two eighths keep their flags.
        #expect(parts.map { $0.measures[0].beamMarks() } == [["-", "-", "[", "]", "-"], ["[", "]", "-"]])
    }
}

@Suite struct BeatBeamRuleTests {
    @Test func withoutATimeSignatureBeatsAreQuarters() throws {
        let bar = try part(times: [:], "8 8 8 8 16 16 16 16 4").measures[0]
        #expect(bar.time == nil && !bar.printsTime)
        #expect(bar.beamMarks() == ["[", "]", "[", "]", "[[", "==", "==", "]]", "-"])
    }

    @Test func simpleTime() throws {
        let bars = try part(times: [1: timeElement("3/4"), 2: timeElement("2/2"), 3: timeElement("3/8")],
                            "8 8 8 8 8 8", "8 8 8 8 4 4", "8 8 16 16").measures
        #expect(bars[0].beamMarks() == ["[", "]", "[", "]", "[", "]"])
        #expect(bars[1].beamMarks() == ["[", "=", "=", "]", "-", "-"])
        // In 3/8 a beat is an eighth, so only the sixteenths share one.
        #expect(bars[2].beamMarks() == ["-", "-", "[[", "]]"])
    }

    @Test func compoundTime() throws {
        let bars = try part(times: [1: timeElement("12/8"), 2: timeElement("9/8"), 3: timeElement("6/16")],
                            "8 8 8 8 8 8 8 8 8 4.", "8 8 8 16 16 16 16 16 16 4.", "16 16 16 16 16 16").measures
        #expect(bars[0].beamMarks() == ["[", "=", "]", "[", "=", "]", "[", "=", "]", "-"])
        #expect(bars[1].beamMarks() == ["[", "=", "]", "[[", "==", "==", "==", "==", "]]", "-"])
        #expect(bars[2].beamMarks() == ["[[", "==", "]]", "[[", "==", "]]"])
    }

    @Test func onlyAFirstBarIsAPickup() throws {
        // Three eighths before the first full bar end on the beat; three in a short last bar begin on it.
        let bars = try part("8 8 8", "8 8 8 8 2", "8 8 8").measures
        #expect(bars.map(\.length) == [1.5, 4, 1.5])
        #expect(bars[0].beamMarks() == ["-", "[", "]"])
        #expect(bars[2].beamMarks() == ["[", "]", "-"])
    }

    @Test func aPickupInCompoundTime() throws {
        let bar = try part(times: [1: timeElement("6/8")], "16 16 8").measures[0]
        #expect(bar.beamMarks() == ["[[", "=]", "]"])
    }

    @Test func restsGapsAndLongerNotesBreakGroups() throws {
        let bars = try part(times: [1: timeElement("2/2")], "8 r8 8 8 2", "8 h8 8 8 2", "8 4 8 2").measures
        #expect(bars[0].beamMarks() == ["-", "r", "[", "]", "-"])
        // A hidden rest leaves a gap, which breaks the group too.
        #expect(bars[1].beamMarks() == ["-", "[", "]", "-"])
        #expect(bars[2].beamMarks() == ["-", "-", "-", "-"])
    }

    @Test func aRestAtTheStartOfABeat() throws {
        // The reference rhythm, without its beams: grouped by the beat rather than as printed.
        let bar = try part("r8 16 16 8 16 16 2").measures[0]
        #expect(bar.beamMarks() == ["r", "[[", "]]", "[", "=[", "]]", "-"])
    }

    @Test func hooks() throws {
        let bars = try part(times: [1: timeElement("2/4"), 3: timeElement("4/4"), 4: timeElement("6/8")],
                            "8. 16 16 8.", "16 8 16 16 16 8", "16. 32 8 8 32 16. 8.. 32 16. 32 16 16",
                            "8. 16 8 8 16 8.").measures
        #expect(bars[0].beamMarks() == ["[", "]<", "[>", "]"])
        // The first sixteenth of a beat points forward, the last back.
        #expect(bars[1].beamMarks() == ["[>", "=", "]<", "[[", "=]", "]"])
        // A thirty-second's hook follows the sixteenth beam: back where it ends, forward where it
        // begins, and back to a dotted sixteenth where it runs both ways.
        #expect(bars[2].beamMarks() == ["[[", "=]<", "]", "[", "=[>", "]]", "[", "]<<", "[[", "==<", "==", "]]"])
        // In 6/8, back to a dotted eighth, forward after a plain one.
        #expect(bars[3].beamMarks() == ["[", "=<", "]", "[", "=>", "]"])
    }

    @Test func triplets() throws {
        let bar = try part(times: [1: timeElement("2/4")], "8t 8t 8t 16t 16t 16t 16t 16t 16t").measures[0]
        #expect(bar.beamMarks() == ["[", "=", "]", "[[", "==", "==", "==", "==", "]]"])
    }

    @Test func voicesAndStavesAreBeamedApart() throws {
        let bar = try part(staves: 2, "8 8 8 8 2 back 8v2 8v2 4v2 2v2 back 8@2v5 8@2v5 2.@2v5").measures[0]
        #expect(bar.beamMarks(staff: 1, voice: 1) == ["[", "]", "[", "]", "-"])
        #expect(bar.beamMarks(staff: 1, voice: 2) == ["[", "]", "-", "-"])
        #expect(bar.beamMarks(staff: 2) == ["[", "]", "-"])
    }

    @Test func chordsTiesAndGraceNotes() throws {
        let bars = try part("8+ 8+ g16 8 8 2~", "8 8 2.").measures
        #expect(bars[0].symbols.map(\.beamMarks) == ["[", "[", "]", "]", "[", "]", "-"])
        #expect(bars[1].beamMarks() == ["[", "]", "-"])
        #expect(bars[1].symbols[0].tiedFromPrevious)
    }
}

// MARK: - Time signatures

@Suite struct TimeSignatureTests {
    @Test func commonAndCutTime() throws {
        let bars = try part(times: [1: timeElement("4/4", " symbol=\"common\""), 2: timeElement("2/2", " symbol=\"cut\""),
                                    3: timeElement("3/4", " symbol=\"common\""), 4: timeElement("4/4", " symbol=\"normal\"")],
                            "1", "1", "2.", "1").measures
        #expect(bars.map(\.time?.symbol) == [.common, .cut, .numbers, .numbers])
        #expect(bars.map(\.time?.beats) == [4, 2, 3, 4])
    }

    @Test func changesCarryForward() throws {
        let bars = try part(times: [1: timeElement("3/4"), 3: timeElement("6/8"), 5: timeElement("6/8")], "2.", "2.", "4. 4.", "4. 4.", "4. 4.")
            .measures
        #expect(bars.map(\.time) == [TimeSignature(beats: 3, beatType: 4), TimeSignature(beats: 3, beatType: 4)]
                + Array(repeating: TimeSignature(beats: 6, beatType: 8), count: 3))
        // A repeated signature is printed again, as the score writes it.
        #expect(bars.map(\.printsTime) == [true, false, true, false, true])
    }

    @Test func aHiddenTimeSignatureStillCounts() throws {
        let bars = try part(times: [1: timeElement("2/4", " print-object=\"no\""), 2: timeElement("3/4")], "8 8 8 8", "2.").measures
        #expect(bars.map(\.time) == [TimeSignature(beats: 2, beatType: 4), TimeSignature(beats: 3, beatType: 4)])
        #expect(bars.map(\.printsTime) == [false, true])
    }

    @Test func noTimeSignatureAtAll() throws {
        let bars = try part(times: [:], "1", "1").measures
        #expect(bars.allSatisfy { $0.time == nil && !$0.printsTime })
    }

    @Test func aTimeSignatureFromALaterBar() throws {
        let bars = try part(times: [2: timeElement("3/4")], "1", "2.").measures
        #expect(bars.map(\.time) == [nil, TimeSignature(beats: 3, beatType: 4)])
        #expect(bars.map(\.printsTime) == [false, true])
    }

    @Test func compositeAndUnmeasuredTime() throws {
        let composite = "<time><beats>3+2</beats><beat-type>8</beat-type></time>"
        let fractions = "<time><beats>3</beats><beat-type>8</beat-type><beats>2</beats><beat-type>4</beat-type></time>"
        let free = "<time><senza-misura/></time>"
        let bars = try part(times: [1: composite, 2: fractions, 3: free], "4. 4", "4. 4 4", "2").measures
        #expect(bars.map(\.time) == [TimeSignature(beats: 5, beatType: 8), TimeSignature(beats: 7, beatType: 8),
                                     TimeSignature(beats: 7, beatType: 8)])
        #expect(bars.map(\.printsTime) == [true, true, false])
    }

    @Test func aTimeSignatureForOneStaffOnly() throws {
        let times = "<time number=\"2\"><beats>2</beats><beat-type>4</beat-type></time>"
            + "<time number=\"1\"><beats>3</beats><beat-type>4</beat-type></time>"
        let bar = try part(times: [1: times], staves: 2, "2. back 2.@2").measures[0]
        #expect(bar.time == TimeSignature(beats: 3, beatType: 4))
    }
}

// MARK: - Every fixture

@Suite struct BeamInvariantTests {
    /// On each staff and voice, by offset: level 1 groups run begin, continue…, end; higher levels
    /// run inside them; beamed notes have a beam per flag; rests have none; a chord's notes agree.
    @Test(arguments: BarLayoutInvariantTests.fixtures) func beamsAreWellFormed(_ name: String) throws {
        for part in try load(name).parts {
            for measure in part.measures {
                let place = "\(name) bar \(measure.number)"
                #expect(measure.symbols.filter(\.isRest).allSatisfy { $0.beams.isEmpty }, "\(place): a rest has beams")
                // A chord's notes share their beams.
                for chord in Dictionary(grouping: measure.symbols, by: \.chord).values {
                    #expect(Set(chord.map(\.beams)).count == 1, "\(place): a chord's notes disagree")
                }
                let lines = Dictionary(grouping: measure.symbols.filter { !$0.isRest }) { [$0.staff, $0.voice] }
                for line in lines.values {
                    var seen = Set<Int>()
                    let chords = line.filter { seen.insert($0.chord).inserted }
                    Self.checkGroups(chords, at: place)
                }
            }
        }
    }

    private static func checkGroups(_ chords: [BarSymbol], at place: String) {
        var group: [BarSymbol] = []
        for chord in chords {
            guard let first = chord.beams.first else {
                #expect(group.isEmpty, "\(place): a group is broken by a note without beams")
                group = []
                continue
            }
            // Beamed notes have flags, and a beam for each.
            #expect(chord.beams.count == chord.value.flags, "\(place): \(chord.beamMarks) on a \(chord.value)")
            switch first {
            case .begin:
                #expect(group.isEmpty, "\(place): a group begins inside another")
                group = [chord]
            case .continue:
                #expect(!group.isEmpty, "\(place): a continue outside a group")
                group.append(chord)
            case .end:
                #expect(!group.isEmpty, "\(place): an end outside a group")
                group.append(chord)
                checkLevels(group, at: place)
                group = []
            case .forwardHook, .backwardHook:
                Issue.record("\(place): a hook on the eighth beam")
            }
        }
        #expect(group.isEmpty, "\(place): a group never ends")
    }

    /// Levels 2 and up run begin…end, or hook, within the group, along a beam on the level under them.
    private static func checkLevels(_ group: [BarSymbol], at place: String) {
        #expect(Set(group.map(\.staff)).count == 1)
        #expect(zip(group, group.dropFirst()).allSatisfy { $0.offset < $1.offset })
        let deepest = group.map(\.beams.count).max() ?? 1
        for level in stride(from: 1, to: deepest, by: 1) {
            var open = false
            for chord in group {
                guard chord.beams.count > level else {
                    #expect(!open, "\(place): level \(level + 1) broken off")
                    continue
                }
                let part = chord.beams[level], under = chord.beams[level - 1]
                switch part {
                case .begin, .continue:
                    #expect(open == (part == .continue), "\(place): level \(level + 1) out of order")
                    #expect(under == .begin || under == .continue, "\(place): level \(level + 1) beyond the beam under it")
                    open = true
                case .end:
                    #expect(open, "\(place): level \(level + 1) ends without beginning")
                    open = false
                case .forwardHook, .backwardHook:
                    #expect(!open, "\(place): a hook inside a level \(level + 1) beam")
                }
            }
            #expect(!open, "\(place): level \(level + 1) never ends")
        }
    }
}
