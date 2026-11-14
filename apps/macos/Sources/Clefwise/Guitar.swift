import Foundation

// The guitar as an answer input: its tuning, the places on the neck, and what it can reach.
//
// Guitar music is written in the guitar clef (`Clef.treble8vb`: the treble clef with a small 8
// below), an octave above how it sounds. Everything here is in sounding pitches, as `Question.pitch`
// and `ScoreNote.pitch` are, so a fretboard position matches a question by MIDI number, like a
// piano key: the bottom line of the guitar clef (E3 sounding) is the D string's 2nd fret.

/// How the six strings are tuned: their open pitches, as they sound.
///
/// Saved and logged as one string: a preset's `key` ("standard", "dropD"…), or for any other
/// tuning its open strings' names from the 6th, "D2 A2 D3 G3 B3 E4".
struct GuitarTuning: Hashable, Identifiable {
    /// Open strings from the 6th (lowest, thickest) to the 1st (highest), as sounding pitches.
    /// Always six.
    let strings: [Pitch]

    init(strings: [Pitch]) {
        precondition(strings.count == 6, "A guitar tuning has six strings")
        self.strings = strings
    }

    static let standard = GuitarTuning(strings: [Pitch(.e, 2), Pitch(.a, 2), Pitch(.d, 3), Pitch(.g, 3), Pitch(.b, 3), Pitch(.e, 4)])
    /// The 6th string down a tone, as "6=D" on a score asks.
    static let dropD = GuitarTuning(strings: [Pitch(.d, 2), Pitch(.a, 2), Pitch(.d, 3), Pitch(.g, 3), Pitch(.b, 3), Pitch(.e, 4)])
    static let doubleDropD = GuitarTuning(strings: [Pitch(.d, 2), Pitch(.a, 2), Pitch(.d, 3), Pitch(.g, 3), Pitch(.b, 3), Pitch(.d, 4)])
    static let dadgad = GuitarTuning(strings: [Pitch(.d, 2), Pitch(.a, 2), Pitch(.d, 3), Pitch(.g, 3), Pitch(.a, 3), Pitch(.d, 4)])
    static let openD = GuitarTuning(strings: [Pitch(.d, 2), Pitch(.a, 2), Pitch(.d, 3), Pitch(.f, 3, .sharp), Pitch(.a, 3), Pitch(.d, 4)])
    static let openG = GuitarTuning(strings: [Pitch(.d, 2), Pitch(.g, 2), Pitch(.d, 3), Pitch(.g, 3), Pitch(.b, 3), Pitch(.d, 4)])
    static let halfStepDown = GuitarTuning(strings: [Pitch(.e, 2, .flat), Pitch(.a, 2, .flat), Pitch(.d, 3, .flat),
                                                     Pitch(.g, 3, .flat), Pitch(.b, 3, .flat), Pitch(.e, 4, .flat)])

    /// The tunings offered in the Tuning menu, Standard first.
    static let presets: [GuitarTuning] = [.standard, .dropD, .doubleDropD, .dadgad, .openD, .openG, .halfStepDown]

    private static let presetNames: [GuitarTuning: (key: String, name: String)] = [
        .standard: ("standard", "Standard"),
        .dropD: ("dropD", "Drop D"),
        .doubleDropD: ("doubleDropD", "Double drop D"),
        .dadgad: ("dadgad", "DADGAD"),
        .openD: ("openD", "Open D"),
        .openG: ("openG", "Open G"),
        .halfStepDown: ("halfStepDown", "Half step down"),
    ]

    var id: String { key }

    /// What it's saved and logged as: the preset's key, or the open strings' names from the 6th.
    var key: String { Self.presetNames[self]?.key ?? strings.map(\.name).joined(separator: " ") }

    /// "Standard", "Drop D"…; a tuning that isn't a preset is called by its open strings ("C G D G B D").
    var name: String { Self.presetNames[self]?.name ?? stringNames(in: .letters) }

    /// Whether it's one of the `presets`.
    var isPreset: Bool { Self.presetNames[self] != nil }

    /// The open strings from the 6th to the 1st, without octaves, in a naming system: "E A D G B E",
    /// "Mi La Re Sol Si Mi".
    func stringNames(in naming: NamingSystem) -> String {
        strings.map { naming.name(of: $0) }.joined(separator: " ")
    }

    /// From a saved or logged `key`; nil when it's neither a preset's key nor six pitch names.
    init?(key: String) {
        if let preset = Self.presets.first(where: { Self.presetNames[$0]?.key == key }) {
            self = preset
            return
        }
        let pitches = key.split(separator: " ").compactMap { Pitch(name: String($0)) }
        guard pitches.count == 6, key.split(separator: " ").count == 6 else { return nil }
        self.init(strings: pitches)
    }

    /// The open string's pitch; `string` counts as guitarists do, 1 = the highest … 6 = the lowest.
    func openPitch(of string: Int) -> Pitch {
        strings[6 - string]
    }
}

extension GuitarTuning: Codable {
    init(from decoder: Decoder) throws {
        let key = try decoder.singleValueContainer().decode(String.self)
        guard let tuning = GuitarTuning(key: key) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a guitar tuning: \(key)"))
        }
        self = tuning
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

/// A place on the neck: a string and a fret.
struct GuitarPosition: Hashable, Codable {
    /// As guitarists number them: 1 = the highest (thinnest) string … 6 = the lowest.
    let string: Int
    /// 0 = the open string.
    let fret: Int

    init(string: Int, fret: Int) {
        self.string = string
        self.fret = fret
    }

    /// "string 2, fret 3"; "string 6, open".
    var label: String { fret == 0 ? "string \(string), open" : "string \(string), fret \(fret)" }
}

/// The neck as the guitar answer shows it: a tuning, and frets 0 (open) to `frets`.
struct Fretboard: Equatable {
    let tuning: GuitarTuning
    /// The highest fret shown, `minFrets...maxFrets`.
    let frets: Int

    /// Always at least an octave on every string.
    static let minFrets = 12
    /// A full electric neck; also the furthest a note may be and still be asked.
    static let maxFrets = 24

    init(tuning: GuitarTuning = .standard, frets: Int = Fretboard.minFrets) {
        self.tuning = tuning
        self.frets = min(max(frets, Self.minFrets), Self.maxFrets)
    }

    /// Every place shown, string 1 to 6, each from the open string up.
    var positions: [GuitarPosition] {
        (1...6).flatMap { string in (0...frets).map { GuitarPosition(string: string, fret: $0) } }
    }

    func midiNumber(at position: GuitarPosition) -> Int {
        tuning.openPitch(of: position.string).midiNumber + position.fret
    }

    /// The sounding pitch at `position`. Like the piano's black keys, notes between the natural ones
    /// are spelled as sharps (C♯, never D♭); compare with questions by `midiNumber`.
    func pitch(at position: GuitarPosition) -> Pitch {
        Pitch(midiNumber: midiNumber(at: position))
    }

    /// Every place shown that sounds `midiNumber`, from the 1st string to the 6th.
    func positions(sounding midiNumber: Int) -> [GuitarPosition] {
        (1...6).compactMap { string in
            let fret = midiNumber - tuning.openPitch(of: string).midiNumber
            return (0...frets).contains(fret) ? GuitarPosition(string: string, fret: fret) : nil
        }
    }

    /// The notes `tuning` can play on a full neck (open 6th string to the 1st string's
    /// `maxFrets`), by MIDI number. Notes outside it aren't asked while answering on the guitar.
    static func reach(of tuning: GuitarTuning) -> ClosedRange<Int> {
        let opens = tuning.strings.map(\.midiNumber)
        return opens.min()!...(opens.max()! + maxFrets)
    }

    static func canPlay(_ midiNumber: Int, in tuning: GuitarTuning) -> Bool {
        reach(of: tuning).contains(midiNumber)
    }

    /// The frets to show so that every note in `midiNumbers` the tuning can play has a place on the
    /// board: the lowest fret each can be played at, the highest of those, but at least `minFrets`
    /// and at most `maxFrets`. Notes out of reach are left out of the count.
    static func fretsNeeded(for midiNumbers: some Sequence<Int>, in tuning: GuitarTuning) -> Int {
        let opens = tuning.strings.map(\.midiNumber)
        let lowestFrets = midiNumbers.compactMap { midi in
            opens.map { midi - $0 }.filter { (0...maxFrets).contains($0) }.min()
        }
        return min(max(lowestFrets.max() ?? minFrets, minFrets), maxFrets)
    }
}

extension Pitch {
    /// The note a MIDI number sounds, spelled as the piano's keys are: naturals, and sharps
    /// between them (C♯, never D♭).
    init(midiNumber: Int) {
        let pitchClass = ((midiNumber % 12) + 12) % 12
        let octave = Int((Double(midiNumber) / 12).rounded(.down)) - 1
        let spelling: [(NoteLetter, Accidental)] = [
            (.c, .natural), (.c, .sharp), (.d, .natural), (.d, .sharp), (.e, .natural), (.f, .natural),
            (.f, .sharp), (.g, .natural), (.g, .sharp), (.a, .natural), (.a, .sharp), (.b, .natural),
        ]
        let (letter, accidental) = spelling[pitchClass]
        self.init(letter, octave, accidental)
    }

    /// From a name as `name` writes it ("F♯4", "E♭2", "C4"; "#" and "b" also read as the signs);
    /// nil for anything else.
    init?(name: String) {
        var rest = Substring(name)
        guard let first = rest.first, let letter = NoteLetter(character: first), first.isUppercase else { return nil }
        rest = rest.dropFirst()
        var accidental = Accidental.natural
        if let sign = rest.first, "♯#♭b".contains(sign) {
            accidental = "♯#".contains(sign) ? .sharp : .flat
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty, let octave = Int(rest) else { return nil }
        self.init(letter, octave, accidental)
    }
}
