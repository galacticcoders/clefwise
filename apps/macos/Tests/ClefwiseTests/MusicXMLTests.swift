import Foundation
import Testing
@testable import Clefwise

// The fixtures are small hand-written pieces. clarinet-tune.mxl holds clarinet-tune.musicxml (as
// Scores/Clarinet Tune.musicxml, plus a decoy XML file) with a container.xml; no-container.mxl and
// zipped-score.xml hold accidentals.musicxml without one. All three were made with `zip`.

private func fixture(_ name: String) throws -> URL {
    try #require(Fixtures.url(name))
}

private func load(_ name: String) throws -> Score {
    try MusicXMLImporter.load(from: fixture(name))
}

private func onlyPart(_ name: String) throws -> ScorePart {
    let parts = try load(name).parts
    try #require(parts.count == 1)
    return parts[0]
}

private func importError(_ name: String) throws -> String {
    try #require(throws: ScoreImportError.self) { try load(name) }.message
}

@Suite struct MusicXMLGrandStaffTests {
    @Test func readsLowerStaffFirstThenLowToHigh() throws {
        let score = try load("grand-staff.musicxml")
        #expect(score.title == "Grand Staff Study")
        let piano = try #require(score.parts.first)
        #expect(score.parts.count == 1)
        #expect(piano.name == "Piano")
        #expect(piano.staffCount == 2)
        #expect(piano.measureCount == 3)
        #expect(piano.skippedNoteCount == 0)
        #expect(piano.notes.map(\.pitch.name)
                == ["G2", "D3", "G4", "B4", "D5", "F♯5", "B2", "D3", "A4", "C4", "B4", "E4", "G2", "G4"])
        #expect(piano.notes.map(\.staff) == [2, 2, 1, 1, 1, 1, 2, 2, 1, 2, 1, 2, 2, 1])
        #expect(piano.notes.map(\.onset) == [0, 0, 0, 0, 0, 1, 2, 2, 2, 4, 4, 6, 8, 8])
        #expect(piano.notes.map(\.measure) == [1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3])
        #expect(piano.notes.allSatisfy { $0.keySignature == KeySignature(fifths: 1) && $0.octaveShift == 0 })
    }

    @Test func chordsShareAnIDOnTheirOwnStaff() throws {
        let notes = try onlyPart("grand-staff.musicxml").notes
        let chords = notes.map(\.chord)
        #expect(chords[0] == chords[1])
        #expect(chords[2] == chords[3] && chords[3] == chords[4])
        #expect(chords[0] != chords[2])
        #expect(chords[6] == chords[7])
        // Both hands' first chords, F♯5, the second left-hand chord, then seven single notes.
        #expect(Set(chords).count == 10)
    }

    @Test func keySignatureSharpIsPlayedButNotPrinted() throws {
        let notes = try onlyPart("grand-staff.musicxml").notes
        #expect(notes[5].pitch == Pitch(.f, 5, .sharp))
        #expect(notes.allSatisfy { $0.printedAccidental == nil })
    }

    @Test func clefChangesOnTheLowerStaff() throws {
        let notes = try onlyPart("grand-staff.musicxml").notes
        // Bar 2 switches staff 2 to treble after a <backup>; the switch back to bass is written
        // at the end of bar 2 and only applies from bar 3.
        #expect(notes.map(\.clef) == [.bass, .bass, .treble, .treble, .treble, .treble, .bass, .bass,
                                      .treble, .treble, .treble, .treble, .bass, .treble])
    }
}

@Suite struct MusicXMLAccidentalTests {
    @Test func printedCarriedAndCancelledSigns() throws {
        let score = try load("accidentals.musicxml")
        #expect(score.title == "Accidental Study")
        let violin = try #require(score.parts.first)
        #expect(violin.notes.map(\.pitch.name)
                == ["F♯4", "F♯4", "B♭4", "F4", "F4", "F4", "G4", "F♯4", "F♯4", "B♭4", "B4", "B4", "F4"])
        #expect(violin.notes.map(\.printedAccidental) == [
            .sharp, .sharp, .flat, .natural,  // the second F♯ carries the first one's sharp
            .natural, .natural, nil,          // in G major: a natural, then an F still natural from it
            .sharp, nil,                      // a courtesy sharp, then F♯ from the key
            nil, .natural, .natural, nil,     // in F major
        ])
    }

    @Test func keyChangesMidPiece() throws {
        let notes = try onlyPart("accidentals.musicxml").notes
        #expect(notes.map(\.keySignature.fifths) == [0, 0, 0, 0, 1, 1, 1, 1, 1, -1, -1, -1, -1])
    }

    @Test func doubleSharpsAndMicrotonesAreCounted() throws {
        let violin = try onlyPart("accidentals.musicxml")
        #expect(violin.skippedNoteCount == 2)
        #expect(!violin.notes.contains { $0.pitch.letter == .c || $0.pitch.letter == .e })
    }
}

@Suite struct MusicXMLTimingTests {
    @Test func pickupTiesRestsGraceAndCueNotes() throws {
        let score = try load("ties-rests-grace.musicxml")
        #expect(score.title == "ties-rests-grace")
        let flute = try #require(score.parts.first)
        // The grace B4, the cue A5 and the tied-over E4s aren't notes to read, nor counted as skipped.
        #expect(flute.notes.map(\.pitch.name) == ["D4", "G4", "E4", "C5"])
        #expect(flute.skippedNoteCount == 0)
        // The pickup bar is an eighth rest and an eighth: half a beat, so bar 2 starts at 1.
        #expect(flute.notes.map(\.onset) == [0.5, 1, 2, 9])
        #expect(flute.notes.map(\.measure) == [1, 2, 2, 4])
        #expect(flute.measureCount == 4)
        #expect(Set(flute.notes.map(\.chord)).count == 4)
    }

    @Test func eightVaKeepsSoundingPitch() throws {
        let notes = try onlyPart("ottava.musicxml").notes
        #expect(notes.map(\.pitch.name) == ["C5", "E6", "G6", "C7", "E7", "A5", "C4", "C8", "C6"])
        #expect(notes.map(\.octaveShift) == [0, 1, 1, 1, 1, 0, -1, 2, 0])
        #expect(notes[1].question.writtenPitch == Pitch(.e, 5))
        #expect(notes[6].question.writtenPitch == Pitch(.c, 5))
    }
}

@Suite struct MusicXMLClefTests {
    @Test func otherClefsAreSkippedAndCounted() throws {
        let viola = try onlyPart("clefs.musicxml")
        // Two notes in alto clef and one under a treble clef with an 8 below.
        #expect(viola.skippedNoteCount == 3)
        #expect(viola.notes.map(\.pitch.name) == ["A4", "A2"])
        #expect(viola.notes.map(\.clef) == [.treble, .bass])
        #expect(viola.notes.map(\.measure) == [2, 4])
    }
}

@Suite struct MusicXMLPartTests {
    @Test func partsWithoutNotesToReadAreDropped() throws {
        let score = try load("voice-and-piano.musicxml")
        #expect(score.title == "Evening Song")
        // Drums only have unpitched notes and Strings only rests; the fourth part has no name.
        #expect(score.parts.map(\.name) == ["Voice", "Piano", "Part 4"])
        #expect(score.parts.map(\.staffCount) == [1, 2, 1])
        #expect(score.parts.map(\.measureCount) == [2, 2, 2])
    }

    @Test func eachPartKeepsItsOwnState() throws {
        let parts = try load("voice-and-piano.musicxml").parts
        let voice = parts[0], piano = parts[1]
        #expect(voice.notes.map(\.pitch.name) == ["D5", "E5", "F♯5", "G5"])
        #expect(voice.notes.allSatisfy { $0.keySignature == KeySignature(fifths: 2) && $0.printedAccidental == nil })
        // The 8va line is on the right hand only.
        #expect(piano.notes.map(\.pitch.name) == ["D3", "D6", "A2", "D3", "D5"])
        #expect(piano.notes.map(\.staff) == [2, 1, 2, 2, 1])
        #expect(piano.notes.map(\.octaveShift) == [0, 1, 0, 0, 0])
        #expect(parts[2].notes.map(\.pitch.name) == ["A4"])
    }
}

@Suite struct MusicXMLFileTests {
    private func expectClarinetTune(_ score: Score) throws {
        #expect(score.title == "Clarinet Tune")
        let clarinet = try #require(score.parts.first)
        #expect(clarinet.name == "Clarinet in B♭")
        // A transposing instrument: the pitches stay as written on the page.
        #expect(clarinet.notes.map(\.pitch.name) == ["G4", "A4", "B4", "C5", "D♯5", "E5", "C5"])
        #expect(clarinet.notes.map(\.onset) == [0, 1, 1.5, 2, 4, 5, 6])
        #expect(clarinet.notes.map(\.printedAccidental) == [nil, nil, nil, nil, .sharp, nil, nil])
        #expect(clarinet.measureCount == 2)
    }

    @Test func museScoreExportWithDoctypeAndCredits() throws {
        try expectClarinetTune(load("clarinet-tune.musicxml"))
    }

    @Test func compressedFileFollowsContainer() throws {
        try expectClarinetTune(load("clarinet-tune.mxl"))
    }

    @Test func compressedFileWithoutContainer() throws {
        let score = try load("no-container.mxl")
        #expect(score.title == "Accidental Study")
        #expect(score.parts.first?.notes.count == 13)
    }

    @Test func compressedFileIsRecognisedByContent() throws {
        #expect(try load("zipped-score.xml").title == "Accidental Study")
    }

    @Test func timewiseIsRefused() throws {
        #expect(try importError("timewise.musicxml").contains("timewise"))
    }

    @Test func otherFilesAreRefused() throws {
        #expect(try importError("shopping-list.xml") == "“shopping-list.xml” isn't a MusicXML file.")
        #expect(try importError("plain-text.musicxml") == "“plain-text.musicxml” isn't a MusicXML file.")
    }

    @Test func scoreWithNothingToReadIsRefused() throws {
        #expect(try importError("drums-only.musicxml").contains("no notes"))
    }

    @Test func damagedFilesAreRefused() throws {
        #expect(try importError("truncated.musicxml").contains("damaged"))
        #expect(try importError("broken.mxl").contains("damaged"))
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("no-such-score.musicxml")
        #expect(throws: ScoreImportError.self) { try MusicXMLImporter.load(from: missing) }
    }
}
