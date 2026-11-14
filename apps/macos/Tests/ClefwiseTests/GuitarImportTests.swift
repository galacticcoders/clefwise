import Foundation
import Testing
@testable import Clefwise

// Guitar scores: the guitar clef (a treble clef with an 8 below, or a plain treble clef with an
// octave-down <transpose>), pitches as they sound, the tuning a score asks for, and tablature.
// guitar-drop-d.musicxml is written as MuseScore 4 exports its classical guitar,
// guitar-transpose.musicxml as its "treble clef" guitar does, guitar-tab.musicxml as a guitar with
// a linked tablature staff. Smaller cases are written out here.

private func load(_ name: String) throws -> Score {
    try MusicXMLImporter.load(from: #require(Fixtures.url(name)))
}

private func onlyPart(_ name: String) throws -> ScorePart {
    let parts = try load(name).parts
    try #require(parts.count == 1)
    return parts[0]
}

/// Reads a score written out in full.
private func score(xml: String) throws -> Score {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Clefwise-guitar-\(UUID().uuidString).musicxml")
    try Data(xml.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    return try MusicXMLImporter.load(from: url)
}

/// One part, "Guitar", with `measures` as its contents; `credits` go before the part list.
private func part(_ measures: String, credits: String = "") throws -> ScorePart {
    let parts = try score(xml: """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">\(credits)
        <part-list><score-part id="P1"><part-name>Guitar</part-name></score-part></part-list>
        <part id="P1">\(measures)</part>
        </score-partwise>
        """).parts
    try #require(parts.count == 1)
    return parts[0]
}

/// A whole note: `pitch` like "E3" or "F#3", on `staff`.
private func note(_ pitch: String, staff: Int? = nil, voice: Int = 1, extra: String = "") -> String {
    let parsed = Pitch(name: pitch)!
    let alter = parsed.accidental == .natural ? "" : "<alter>\(parsed.accidental.rawValue)</alter>"
    return """
        <note><pitch><step>\(parsed.letter.name)</step>\(alter)<octave>\(parsed.octave)</octave></pitch>
        <duration>4</duration><voice>\(voice)</voice><type>whole</type>\(staff.map { "<staff>\($0)</staff>" } ?? "")\(extra)</note>
        """
}

private func measure(_ number: Int, attributes: String = "", _ contents: String) -> String {
    "<measure number=\"\(number)\">\(attributes.isEmpty ? "" : "<attributes>\(attributes)</attributes>")\(contents)</measure>"
}

private let guitarClef = "<clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef>"
private let octaveDown = "<transpose><diatonic>0</diatonic><chromatic>0</chromatic><octave-change>-1</octave-change></transpose>"

/// `<staff-details>` with six strings, from the lowest: "D2 A2 D3 G3 B3 E4".
private func staffTuning(_ strings: String, staff: Int? = nil, lines: Int = 6) -> String {
    let tunings = strings.split(separator: " ").enumerated().map { line, name in
        let pitch = Pitch(name: String(name))!
        let alter = pitch.accidental == .natural ? "" : "<tuning-alter>\(pitch.accidental.rawValue)</tuning-alter>"
        return "<staff-tuning line=\"\(line + 1)\"><tuning-step>\(pitch.letter.name)</tuning-step>\(alter)<tuning-octave>\(pitch.octave)</tuning-octave></staff-tuning>"
    }.joined()
    return "<staff-details\(staff.map { " number=\"\($0)\"" } ?? "")><staff-lines>\(lines)</staff-lines>\(tunings)</staff-details>"
}

private func words(_ text: String) -> String {
    "<direction><direction-type><words>\(text)</words></direction-type></direction>"
}

// MARK: - The guitar clef

@Suite struct GuitarClefImportTests {
    /// MuseScore 4's classical guitar: the treble clef with an 8 below, pitches as they sound.
    @Test func theOctaveTrebleClefIsTheGuitarClefWithPitchesAsTheySound() throws {
        let guitar = try onlyPart("guitar-drop-d.musicxml")
        #expect(guitar.name == "Guitar")
        #expect(guitar.staffCount == 1 && guitar.measureCount == 5 && guitar.skippedNoteCount == 0)
        #expect(guitar.notes.allSatisfy { $0.clef == .treble8vb && $0.octaveShift == 0 && $0.keySignature.fifths == 2 })
        #expect(guitar.notes.prefix(7).map(\.pitch.name) == ["D2", "F♯4", "A3", "D4", "A2", "F♯4", "E4"])
        // The open 6th string in drop D, on the fourth ledger line below.
        let lowD = guitar.notes[0]
        #expect(lowD.pitch.midiNumber == 38)
        #expect(lowD.question.position == -8 && lowD.question.writtenPitch == Pitch(.d, 2))
        // The key's sharps aren't printed again.
        #expect(guitar.notes.allSatisfy { $0.printedAccidental == nil })
    }

    @Test func theGuitarClefsBarsKeepTheirVoicesAndBeams() throws {
        let guitar = try onlyPart("guitar-drop-d.musicxml")
        #expect(guitar.measures.count == 5)
        #expect(guitar.measures.allSatisfy { $0.staves == [.init(clef: .treble8vb, keySignature: KeySignature(fifths: 2))] })
        let bar = guitar.measures[0]
        #expect(bar.symbols.allSatisfy { $0.clef == .treble8vb && $0.staff == 1 })
        #expect(Set(bar.symbols.map(\.voice)) == [1, 2])
        #expect(bar.symbols.filter { $0.voice == 2 }.allSatisfy { $0.stemUp == false })
        let eighths = bar.symbols.filter { $0.value == NoteValue(.eighth) }
        #expect(eighths.map { $0.pitch?.name } == ["A3", "D4"])
        #expect(eighths.map(\.beams) == [[.begin], [.end]])
        #expect(bar.symbols.first { $0.pitch == Pitch(.d, 2) }?.position == -8)
    }

    /// A plain treble clef under an octave-down `<transpose>`: written an octave above how it sounds.
    @Test func anOctaveDownTranspositionIsTheGuitarClefAnOctaveLower() throws {
        let guitar = try onlyPart("guitar-transpose.musicxml")
        #expect(guitar.notes.map(\.pitch.name) == ["E2", "F♯2", "G2", "A2", "B2", "C3", "D3", "E3", "E3", "B2"])
        #expect(guitar.notes.allSatisfy { $0.clef == .treble8vb && $0.octaveShift == 0 })
        // The open low E is E2 as it sounds, written below the third ledger line as before.
        let lowE = guitar.notes[0]
        #expect(lowE.pitch.midiNumber == 40)
        #expect(lowE.question.position == -7 && Clef.treble8vb.position(of: Pitch(.e, 2)) == -7)
        #expect(lowE.question.position == Clef.treble.position(of: Pitch(.e, 3)))
        #expect(guitar.measures.allSatisfy { $0.staves.map(\.clef) == [.treble8vb] })
        // Its notes keep their places, and the placed rest stays on the middle line.
        let bar = guitar.measures[1]
        #expect(bar.symbols.map(\.position) == [0, nil, -3])
        #expect(bar.symbols[1].restPosition == 4)
        #expect(guitar.measures[0].symbols.map(\.beams) == [[.begin], [.continue], [.continue], [.end],
                                                           [.begin], [.continue], [.continue], [.end]])
        // It says nothing about its tuning.
        #expect(guitar.guitarTuning == nil)
    }

    /// Sibelius writes both: the clef's 8 is only drawn, the transposition gives the sound.
    @Test func bothTheOctaveClefAndTheTranspositionReadAsWrittenAnOctaveUp() throws {
        let guitar = try part(measure(1, attributes: "<divisions>1</divisions>\(guitarClef)\(octaveDown)", note("E3")))
        #expect(guitar.notes.map(\.pitch) == [Pitch(.e, 2)])
        #expect(guitar.notes[0].clef == .treble8vb && guitar.notes[0].question.position == -7)
    }

    @Test func clefChangesToAndFromTheGuitarClefWorkLikeOthers() throws {
        let viola = try onlyPart("clefs.musicxml")
        // Bar 1 in alto clef is skipped; bar 3's treble with an 8 below is the guitar clef.
        #expect(viola.skippedNoteCount == 2)
        #expect(viola.notes.map(\.pitch.name) == ["A4", "G3", "A2"])
        #expect(viola.notes.map(\.clef) == [.treble, .treble8vb, .bass])
        #expect(viola.measures.map { $0.staves.first?.clef } == [nil, .treble, .treble8vb, .bass])
        #expect(viola.measures[2].symbols.map(\.position) == [2])
    }

    @Test func otherOctaveClefsAreStillSkipped() throws {
        let attributes = "<divisions>1</divisions>"
        let viola = try part(
            measure(1, attributes: attributes + "<clef><sign>G</sign><line>2</line><clef-octave-change>1</clef-octave-change></clef>", note("C6"))
            + measure(2, attributes: "<clef><sign>F</sign><line>4</line><clef-octave-change>-1</clef-octave-change></clef>", note("C2"))
            + measure(3, attributes: "<clef><sign>G</sign><line>2</line><clef-octave-change>-2</clef-octave-change></clef>", note("C3"))
            + measure(4, attributes: "<clef><sign>G</sign><line>2</line></clef>", note("C5")))
        #expect(viola.skippedNoteCount == 3)
        #expect(viola.notes.map(\.pitch.name) == ["C5"])
        #expect(viola.notes.map(\.clef) == [.treble])
        #expect(viola.guitarTuning == nil)
    }

    /// Only an octave down and nothing else is a guitar's: a B♭ clarinet's notes stay as written, in
    /// the treble clef, as before; a bass clef an octave down (a bass guitar) stays in the bass clef.
    @Test func otherTranspositionsAreStillIgnored() throws {
        let clarinet = try onlyPart("clarinet-tune.musicxml")
        #expect(clarinet.notes.map(\.pitch.name) == ["G4", "A4", "B4", "C5", "D♯5", "E5", "C5"])
        #expect(clarinet.notes.allSatisfy { $0.clef == .treble } && clarinet.guitarTuning == nil)
        let bass = try part(measure(1, attributes: "<divisions>1</divisions><clef><sign>F</sign><line>4</line></clef>\(octaveDown)",
                                    note("E2")))
        #expect(bass.notes.map(\.pitch) == [Pitch(.e, 2)] && bass.notes[0].clef == .bass)
        let saxophone = try part(measure(1, attributes: """
            <divisions>1</divisions><clef><sign>G</sign><line>2</line></clef>
            <transpose><diatonic>-1</diatonic><chromatic>-2</chromatic><octave-change>-1</octave-change></transpose>
            """, note("D5")))
        #expect(saxophone.notes.map(\.pitch) == [Pitch(.d, 5)] && saxophone.notes[0].clef == .treble)
    }

    @Test func aTranspositionForOneStaffMovesOnlyThatStaff() throws {
        let piano = try part(measure(1, attributes: """
            <divisions>1</divisions><staves>2</staves>
            <clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>G</sign><line>2</line></clef>
            <transpose number="2"><diatonic>0</diatonic><chromatic>0</chromatic><octave-change>-1</octave-change></transpose>
            """, note("E4", staff: 1) + "<backup><duration>4</duration></backup>" + note("E3", staff: 2)))
        #expect(piano.notes.map(\.pitch.name) == ["E2", "E4"])
        #expect(piano.notes.map(\.clef) == [.treble8vb, .treble])
        #expect(piano.measures[0].staves.map(\.clef) == [.treble, .treble8vb])
    }
}

// MARK: - Tablature

@Suite struct GuitarTablatureImportTests {
    /// MuseScore's guitar with a linked tablature staff: the tablature repeats the notes, so it goes.
    @Test func aTablatureStaffBesideNotesIsLeftOut() throws {
        let guitar = try onlyPart("guitar-tab.musicxml")
        #expect(guitar.staffCount == 1)
        #expect(guitar.skippedNoteCount == 0)
        #expect(guitar.notes.map(\.pitch.name) == ["D2", "A2", "D3", "F♯3", "G3", "B3", "D2", "A2"])
        #expect(guitar.notes.allSatisfy { $0.staff == 1 && $0.clef == .treble8vb })
        #expect(guitar.measures.allSatisfy { $0.staves.map(\.clef) == [.treble8vb] })
        #expect(guitar.measures.allSatisfy { $0.symbols.allSatisfy { $0.staff == 1 && $0.voice == 1 } })
        #expect(guitar.measures.map(\.symbols.count) == [4, 4])
        // Its staff tuning is the part's.
        #expect(guitar.guitarTuning == .dropD)
    }

    /// MuseScore can put the tablature above the notes: the staff in notes becomes staff 1.
    @Test func theStaffLeftIsNumberedOne() throws {
        let guitar = try part(measure(1, attributes: """
            <divisions>1</divisions><staves>2</staves>
            <clef number="1"><sign>TAB</sign></clef>\(staffTuning("E2 A2 D3 G3 B3 E4", staff: 1))
            <clef number="2"><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef>
            """, note("G3", staff: 1, voice: 5) + "<backup><duration>4</duration></backup>" + note("G3", staff: 2)))
        #expect(guitar.staffCount == 1 && guitar.skippedNoteCount == 0)
        #expect(guitar.notes.map(\.staff) == [1] && guitar.notes.map(\.pitch) == [Pitch(.g, 3)])
        #expect(guitar.measures[0].staves.map(\.clef) == [.treble8vb])
        #expect(guitar.measures[0].symbols.map(\.staff) == [1])
        #expect(guitar.guitarTuning == .standard)
    }

    /// The MusicXML tutorial's tablature part: a part of its own, its pitches as they sound.
    @Test func aGuitarTablaturePartIsReadInTheGuitarClef() throws {
        let tab = try part(measure(1, attributes: "<divisions>1</divisions><clef><sign>TAB</sign><line>5</line></clef>"
                                       + staffTuning("E2 A2 D3 G3 B3 E4"),
                                   note("C4", extra: "<notations><technical><string>3</string><fret>5</fret></technical></notations>")))
        #expect(tab.staffCount == 1 && tab.skippedNoteCount == 0)
        #expect(tab.notes.map(\.pitch) == [Pitch(.c, 4)] && tab.notes[0].clef == .treble8vb)
        #expect(tab.measures[0].staves.map(\.clef) == [.treble8vb])
        #expect(tab.guitarTuning == .standard)
    }

    @Test func otherTablatureIsSkipped() throws {
        // A bass guitar's four strings aren't read in the guitar clef.
        let bass = try score(xml: """
            <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Bass</part-name></score-part>
            <score-part id="P2"><part-name>Flute</part-name></score-part></part-list>
            <part id="P1">\(measure(1, attributes: """
                <divisions>1</divisions><clef><sign>TAB</sign></clef>
                <staff-details><staff-lines>4</staff-lines>
                <staff-tuning line="1"><tuning-step>E</tuning-step><tuning-octave>1</tuning-octave></staff-tuning>
                <staff-tuning line="2"><tuning-step>A</tuning-step><tuning-octave>1</tuning-octave></staff-tuning>
                <staff-tuning line="3"><tuning-step>D</tuning-step><tuning-octave>2</tuning-octave></staff-tuning>
                <staff-tuning line="4"><tuning-step>G</tuning-step><tuning-octave>2</tuning-octave></staff-tuning>
                </staff-details>
                """, note("E1")))</part>
            <part id="P2">\(measure(1, attributes: "<divisions>1</divisions>", note("C5")))</part>
            </score-partwise>
            """)
        #expect(bass.parts.map(\.name) == ["Flute"])
    }

    @Test func aStaffTuningWinsOverATextTuning() throws {
        let guitar = try part(measure(1, attributes: "<divisions>1</divisions>\(guitarClef)" + staffTuning("D2 A2 D3 G3 B3 D4"),
                                      words("6=C") + note("D2")))
        #expect(guitar.guitarTuning == .doubleDropD)
    }

    /// A tablature staff written an octave up, as notes under `<transpose>` are, sounds an octave lower.
    @Test func aTransposedStaffTuningSoundsAnOctaveLower() throws {
        let guitar = try part(measure(1, attributes: """
            <divisions>1</divisions><staves>2</staves>
            <clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>TAB</sign></clef>
            \(staffTuning("E3 A3 D4 G4 B4 E5", staff: 2))\(octaveDown)
            """, note("E3", staff: 1) + "<backup><duration>4</duration></backup>" + note("E3", staff: 2, voice: 5)))
        #expect(guitar.notes.map(\.pitch) == [Pitch(.e, 2)])
        #expect(guitar.guitarTuning == .standard)
    }
}

// MARK: - Tunings written on the score

@Suite struct GuitarTuningTextTests {
    @Test func aRetunedStringInTheFirstBarsIsThePartsTuning() throws {
        #expect(try onlyPart("guitar-drop-d.musicxml").guitarTuning == .dropD)
        let guitar = try part(measure(1, attributes: "<divisions>1</divisions>\(guitarClef)", note("D2"))
                              + measure(2, words("5=G") + note("G2")))
        #expect(guitar.guitarTuning?.key == "E2 G2 D3 G3 B3 E4")
    }

    @Test func aRetunedStringInTheCreditsCounts() throws {
        let credits = """
            <credit page="1"><credit-words>Canon</credit-words></credit>
            <credit page="1"><credit-words enclosure="circle">6</credit-words><credit-words>=D</credit-words>
            <credit-words>⑤=G</credit-words></credit>
            """
        let guitar = try part(measure(1, attributes: "<divisions>1</divisions>\(guitarClef)", note("D2")), credits: credits)
        #expect(guitar.guitarTuning?.strings.map(\.name) == ["D2", "G2", "D3", "G3", "B3", "E4"])
    }

    @Test func textLaterInThePieceIsNotTheTuning() throws {
        let guitar = try part(measure(1, attributes: "<divisions>1</divisions>\(guitarClef)", note("E2"))
                              + measure(2, note("E2")) + measure(3, note("E2")) + measure(4, words("6=D") + note("D2")))
        #expect(guitar.guitarTuning == nil)
    }

    @Test func onlyGuitarPartsHaveATuning() throws {
        let violin = try part(measure(1, attributes: "<divisions>1</divisions><clef><sign>G</sign><line>2</line></clef>",
                                      words("6=D") + note("D4")))
        #expect(violin.guitarTuning == nil)
        let credits = "<credit page=\"1\"><credit-words>6=D</credit-words></credit>"
        let flute = try part(measure(1, attributes: "<divisions>1</divisions>", note("D5")), credits: credits)
        #expect(flute.guitarTuning == nil)
    }

    @Test func retunedStringsAreFoundInText() {
        func found(_ text: String) -> [String] {
            WrittenRetuning.retunings(in: text).map { "\($0.string)=\($0.letter.name)\($0.accidental == .natural ? "" : $0.accidental.symbol)" }
        }
        #expect(found("6=D") == ["6=D"])
        #expect(found("6 = D") == ["6=D"])
        #expect(found("⑥=D") == ["6=D"])
        #expect(found("⑥ = D") == ["6=D"])
        #expect(found("(6)=D") == ["6=D"])
        #expect(found("6＝D") == ["6=D"])
        #expect(found("6=D 5=G") == ["6=D", "5=G"])
        #expect(found("6=D, 5=G") == ["6=D", "5=G"])
        #expect(found("⑥=D ⑤=G ④=D") == ["6=D", "5=G", "4=D"])
        #expect(found("Tuning: 6=D") == ["6=D"])
        #expect(found("6 =D\n5= A") == ["6=D", "5=A"])
        #expect(found("3=F#") == ["3=F♯"])
        #expect(found("3=F♯") == ["3=F♯"])
        #expect(found("2=Bb") == ["2=B♭"])
        #expect(found("2=B♭") == ["2=B♭"])
        #expect(found("1=D") == ["1=D"])
        #expect(found("①=E♭") == ["1=E♭"])
        for unrelated in ["", "Allegro", "♩=60", "q = 120", "Capo 2", "7=D", "0=D", "16=D", "6=Dance", "6=H", "6=d", "Op. 6",
                          "6-D", "D=6", "6=", "=D", "6 D", "⑦=D", "6=Do", "(7)=D"] {
            #expect(found(unrelated).isEmpty, "\(unrelated)")
        }
    }

    @Test func eachRetunedStringTakesTheNearestPitchOfItsName() {
        func strings(_ texts: String...) -> [String]? { WrittenRetuning.tuning(in: texts)?.strings.map(\.name) }
        #expect(strings("6=D") == ["D2", "A2", "D3", "G3", "B3", "E4"])
        #expect(strings("5=G") == ["E2", "G2", "D3", "G3", "B3", "E4"])
        #expect(strings("3=F♯") == ["E2", "A2", "D3", "F♯3", "B3", "E4"])
        #expect(strings("1=D") == ["E2", "A2", "D3", "G3", "B3", "D4"])
        #expect(strings("2=C") == ["E2", "A2", "D3", "G3", "C4", "E4"])
        #expect(strings("6=C") == ["C2", "A2", "D3", "G3", "B3", "E4"])
        #expect(strings("6=Eb") == ["E♭2", "A2", "D3", "G3", "B3", "E4"])
        // A tritone either way: the lower.
        #expect(strings("6=A#") == ["A♯1", "A2", "D3", "G3", "B3", "E4"])
        // The first one written counts.
        #expect(strings("6=D", "6=C") == ["D2", "A2", "D3", "G3", "B3", "E4"])
        #expect(strings("Allegro") == nil)
        #expect(WrittenRetuning.tuning(in: []) == nil)
    }

    @Test func retuningsThatMakeAPresetAreThatPreset() {
        #expect(WrittenRetuning.tuning(in: ["6=D"]) == .dropD)
        #expect(WrittenRetuning.tuning(in: ["6=D 1=D"]) == .doubleDropD)
        #expect(WrittenRetuning.tuning(in: ["6=D", "①=D"]) == .doubleDropD)
        #expect(WrittenRetuning.tuning(in: ["6=D 5=A 4=D 3=G 2=A 1=D"]) == .dadgad)
        #expect(WrittenRetuning.tuning(in: ["⑥=D ⑤=G ①=D"]) == .openG)
        #expect(WrittenRetuning.tuning(in: ["6=E"]) == .standard)
        #expect(WrittenRetuning.tuning(in: ["6=D"])?.isPreset == true)
    }
}

// MARK: - Other scores

@Suite struct GuitarImportLeavesOtherScoresAloneTests {
    /// Every other fixture is read as before: no guitar clef, no tuning (`clefs.musicxml` has the
    /// one octave clef among them, checked above).
    @Test func scoresWithoutAGuitarAreReadAsBefore() throws {
        let folder = try #require(Fixtures.folder)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { !$0.hasPrefix("guitar-") && $0 != "clefs.musicxml" && $0 != "README.md" }
        #expect(names.count >= 20)
        for name in names {
            guard let score = try? MusicXMLImporter.load(from: folder.appendingPathComponent(name)) else { continue }
            for part in score.parts {
                #expect(part.guitarTuning == nil, "\(name)")
                #expect(!part.notes.contains { $0.clef == .treble8vb }, "\(name)")
                #expect(!part.measures.contains { $0.staves.contains { $0.clef == .treble8vb } || $0.symbols.contains { $0.clef == .treble8vb } },
                        "\(name)")
            }
        }
    }
}
