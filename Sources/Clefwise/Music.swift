import Foundation

enum NoteLetter: Int, CaseIterable, Identifiable, Codable {
    case c, d, e, f, g, a, b

    var id: Self { self }
    var name: String { ["C", "D", "E", "F", "G", "A", "B"][rawValue] }
    /// Semitones above C within the same octave.
    var semitone: Int { [0, 2, 4, 5, 7, 9, 11][rawValue] }

    init?(character: Character) {
        guard let index = "cdefgab".firstIndex(of: Character(character.lowercased())) else { return nil }
        self.init(rawValue: "cdefgab".distance(from: "cdefgab".startIndex, to: index))
    }
}

enum Accidental: Int, CaseIterable, Codable {
    case flat = -1, natural = 0, sharp = 1

    var symbol: String {
        switch self {
        case .flat: "♭"
        case .natural: "♮"
        case .sharp: "♯"
        }
    }
}

/// A pitch in scientific pitch notation (C4 is middle C), spelled with a letter and accidental.
/// F♯4 and G♭4 sound the same but sit on different staff positions, so they're different pitches here.
struct Pitch: Hashable, Codable {
    let letter: NoteLetter
    let accidental: Accidental
    let octave: Int

    init(_ letter: NoteLetter, _ octave: Int, _ accidental: Accidental = .natural) {
        self.letter = letter
        self.accidental = accidental
        self.octave = octave
    }

    /// Counts white keys from C0, so one step is one line-or-space on the staff.
    init(diatonicIndex: Int, accidental: Accidental = .natural) {
        let octave = diatonicIndex >= 0 ? diatonicIndex / 7 : (diatonicIndex - 6) / 7
        self.init(NoteLetter(rawValue: diatonicIndex - octave * 7)!, octave, accidental)
    }

    /// Staff steps from C0; the accidental doesn't move the note on the staff.
    var diatonicIndex: Int { octave * 7 + letter.rawValue }
    /// Letter, accidental and octave, e.g. "F♯4"; naturals have no sign ("C4").
    var name: String { "\(letter.name)\(accidental == .natural ? "" : accidental.symbol)\(octave)" }
    var midiNumber: Int { (octave + 1) * 12 + letter.semitone + accidental.rawValue }
    /// 0–11 counting semitones from C; F♯ and G♭ share one.
    var pitchClass: Int { ((midiNumber % 12) + 12) % 12 }
    var frequency: Double { 440 * pow(2, Double(midiNumber - 69) / 12) }

    func with(_ accidental: Accidental) -> Pitch {
        Pitch(letter, octave, accidental)
    }
}

/// How many sharps (positive) or flats (negative) a key signature has. Kept within ±5 so no
/// note is ever spelled E♯, B♯, C♭ or F♭.
struct KeySignature: Hashable, Codable {
    let fifths: Int

    static let cMajor = KeySignature(fifths: 0)
    /// C first, then the sharp keys, then the flat keys.
    static let all = [0, 1, 2, 3, 4, 5, -1, -2, -3, -4, -5].map(KeySignature.init(fifths:))

    private static let sharpOrder: [NoteLetter] = [.f, .c, .g, .d, .a, .e, .b]
    private static let flatOrder: [NoteLetter] = [.b, .e, .a, .d, .g, .c, .f]

    /// Letters the signature alters, in the order they're written.
    var alteredLetters: [NoteLetter] {
        fifths >= 0 ? Array(Self.sharpOrder.prefix(fifths)) : Array(Self.flatOrder.prefix(-fifths))
    }

    /// The accidental a note on `letter` gets from the signature when none is printed.
    func accidental(for letter: NoteLetter) -> Accidental {
        guard alteredLetters.contains(letter) else { return .natural }
        return fifths > 0 ? .sharp : .flat
    }

    /// Staff positions (0 = bottom line) of the signature's sharps or flats, in writing order.
    func staffPositions(for clef: Clef) -> [Int] {
        let treble = fifths >= 0 ? [8, 5, 9, 6, 3, 7, 4] : [4, 7, 3, 6, 2, 5, 1]
        let shift = clef == .treble ? 0 : -2
        return treble.prefix(abs(fifths)).map { $0 + shift }
    }

    var majorKey: String { ["D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B"][fifths + 5] }
    var minorKey: String { ["B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯", "G♯"][fifths + 5] }
    /// "no ♯/♭", "1♯", "3♭"…
    var countLabel: String {
        fifths == 0 ? "no ♯/♭" : "\(abs(fifths))\(fifths > 0 ? Accidental.sharp.symbol : Accidental.flat.symbol)"
    }
}

enum KeyChoice: Hashable, Codable, Identifiable {
    case fixed(KeySignature)
    /// A new random key signature each round.
    case random

    static var allCases: [KeyChoice] { KeySignature.all.map(KeyChoice.fixed) + [.random] }

    var id: Self { self }
    var label: String {
        switch self {
        case .fixed(let key): "\(key.majorKey) major · \(key.countLabel)"
        case .random: "Random key"
        }
    }
}

enum Clef: String, CaseIterable, Codable {
    case treble, bass

    var name: String { self == .treble ? "Treble" : "Bass" }

    /// The pitch that sits on the bottom staff line.
    var bottomLine: Pitch { self == .treble ? Pitch(.e, 4) : Pitch(.g, 2) }

    /// Staff position 0 is the bottom line; each +1 moves up one line-or-space.
    func pitch(atPosition position: Int) -> Pitch {
        Pitch(diatonicIndex: bottomLine.diatonicIndex + position)
    }

    func position(of pitch: Pitch) -> Int {
        pitch.diatonicIndex - bottomLine.diatonicIndex
    }

    /// Letters of the five lines and four spaces, bottom to top.
    var lineLetters: [NoteLetter] { stride(from: 0, through: 8, by: 2).map { pitch(atPosition: $0).letter } }
    var spaceLetters: [NoteLetter] { stride(from: 1, through: 7, by: 2).map { pitch(atPosition: $0).letter } }

    /// Memory aids; these only work with letter names.
    var lineMnemonic: String { self == .treble ? "Every Good Boy Does Fine" : "Good Boys Do Fine Always" }
    var spaceMnemonic: String { self == .treble ? "spells FACE" : "All Cows Eat Grass" }
}

/// How notes are called. Solfège and sargam are used as fixed names here: Do = Sa = C.
enum NamingSystem: String, CaseIterable, Identifiable, Codable {
    case letters, solfege, sargam

    var id: Self { self }
    var label: String {
        switch self {
        case .letters: "C D E"
        case .solfege: "Do Re Mi"
        case .sargam: "Sa Re Ga"
        }
    }

    func name(of letter: NoteLetter) -> String {
        switch self {
        case .letters: letter.name
        case .solfege: ["Do", "Re", "Mi", "Fa", "Sol", "La", "Si"][letter.rawValue]
        case .sargam: ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"][letter.rawValue]
        }
    }

    func names(of letters: [NoteLetter]) -> String {
        letters.map(name(of:)).joined(separator: " ")
    }

    /// Name of a spelled pitch, without octave: "F♯", "Fa♯". Sargam has one name per semitone
    /// (Sa = C), so F♯ and G♭ are both "tivra Ma".
    func name(of pitch: Pitch) -> String {
        switch self {
        case .letters, .solfege:
            return name(of: pitch.letter) + (pitch.accidental == .natural ? "" : pitch.accidental.symbol)
        case .sargam:
            return ["Sa", "komal Re", "Re", "komal Ga", "Ga", "Ma", "tivra Ma", "Pa", "komal Dha", "Dha", "komal Ni", "Ni"][pitch.pitchClass]
        }
    }

    /// Whether `letter` with `accidental` is a name of its own. Sargam only has komal Re, Ga, Dha,
    /// Ni and tivra Ma (komal Sa would just be Ni); letters and solfège can sharpen or flatten anything.
    func hasName(_ letter: NoteLetter, _ accidental: Accidental) -> Bool {
        guard self == .sargam else { return true }
        switch accidental {
        case .natural: return true
        case .flat: return [.d, .e, .a, .b].contains(letter)
        case .sharp: return letter == .f
        }
    }

    /// What a letter plus sign is called: "F♯", "Sol♭", "komal Re"; nil when it has no name of its own.
    func answerName(of letter: NoteLetter, _ accidental: Accidental) -> String? {
        hasName(letter, accidental) ? name(of: Pitch(letter, 4, accidental)) : nil
    }

    /// Whether answering `letter` + `accidental` names `pitch` (any octave). Letters and solfège
    /// go by spelling: G♭ isn't F♯, because the note sits on the F line. Sargam goes by swara,
    /// so either spelling of tivra Ma counts.
    func accepts(_ letter: NoteLetter, _ accidental: Accidental, for pitch: Pitch) -> Bool {
        switch self {
        case .letters, .solfege:
            return letter == pitch.letter && accidental == pitch.accidental
        case .sargam:
            return Pitch(letter, pitch.octave, accidental).pitchClass == pitch.pitchClass
        }
    }

    /// Name of the black key just above `letter`, as lines: its sharp and flat spellings,
    /// or in sargam the komal (flat) / tivra (sharp, only Ma) swara.
    func blackKeyName(above letter: NoteLetter) -> [String] {
        guard letter != .e, let next = NoteLetter(rawValue: letter.rawValue + 1) else { return [] }
        switch self {
        case .letters, .solfege: return ["\(name(of: letter))♯", "\(name(of: next))♭"]
        case .sargam: return letter == .f ? ["tivra", name(of: letter)] : ["komal", name(of: next)]
        }
    }
}

enum ClefChoice: String, CaseIterable, Identifiable, Codable {
    case treble, bass, both

    var id: Self { self }
    var label: String { rawValue.capitalized }
    var summary: String {
        switch self {
        case .treble: "Treble clef"
        case .bass: "Bass clef"
        case .both: "Treble & bass clefs"
        }
    }
    var clefs: [Clef] {
        switch self {
        case .treble: [.treble]
        case .bass: [.bass]
        case .both: [.treble, .bass]
        }
    }
}

enum NoteRange: String, CaseIterable, Identifiable, Codable {
    case staff, oneLedgerLine, threeLedgerLines

    var id: Self { self }
    var label: String {
        switch self {
        case .staff: "On the staff"
        case .oneLedgerLine: "+1 ledger line"
        case .threeLedgerLines: "+3 ledger lines"
        }
    }
    /// Staff positions (0 = bottom line, 8 = top line) that questions are drawn from.
    var positions: ClosedRange<Int> {
        switch self {
        case .staff: 0...8
        case .oneLedgerLine: -2...10
        case .threeLedgerLines: -6...14
        }
    }
}

struct Question: Equatable {
    let id = UUID()
    let clef: Clef
    /// The note as played, accidental included (F♯ in G major even though no sign is printed).
    let pitch: Pitch
    let keySignature: KeySignature
    /// Sign printed right before the note; nil when the key signature already gives its accidental.
    let printedAccidental: Accidental?

    init(clef: Clef, pitch: Pitch, keySignature: KeySignature = .cMajor, printedAccidental: Accidental? = nil) {
        self.clef = clef
        self.pitch = pitch
        self.keySignature = keySignature
        self.printedAccidental = printedAccidental
    }

    var position: Int { clef.position(of: pitch) }
}
