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

/// A natural (white-key) pitch in scientific pitch notation: C4 is middle C.
struct Pitch: Hashable, Codable {
    let letter: NoteLetter
    let octave: Int

    init(_ letter: NoteLetter, _ octave: Int) {
        self.letter = letter
        self.octave = octave
    }

    /// Counts white keys from C0, so one step is one line-or-space on the staff.
    init(diatonicIndex: Int) {
        let octave = diatonicIndex >= 0 ? diatonicIndex / 7 : (diatonicIndex - 6) / 7
        self.init(NoteLetter(rawValue: diatonicIndex - octave * 7)!, octave)
    }

    var diatonicIndex: Int { octave * 7 + letter.rawValue }
    var name: String { "\(letter.name)\(octave)" }
    var midiNumber: Int { (octave + 1) * 12 + letter.semitone }
    var frequency: Double { 440 * pow(2, Double(midiNumber - 69) / 12) }
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
    let pitch: Pitch

    var position: Int { clef.position(of: pitch) }
}
