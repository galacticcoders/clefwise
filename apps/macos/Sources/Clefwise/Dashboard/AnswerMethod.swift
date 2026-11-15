import SwiftUI

/// How answers were given, as Progress tells them apart: the "Answer with" setting, with a real
/// piano's keys (source `midi`) apart from the piano on screen.
///
/// The order is fixed, and the same everywhere: legends, stacked columns bottom to top, the filter
/// menu, and each method's colour (`color`, the categorical slot of its position). Naming methods
/// come first, then playing ones. Raw values are the dashboard's keys (`BreakdownRow.key`): the
/// setting's raw value, or `midi` for the real piano.
enum AnswerMethod: String, CaseIterable, Identifiable, Codable {
    case keyboard, buttons
    case realPiano = "midi"
    case piano, guitar

    /// Both read the note. Naming says its name (typing it, or a note button); playing finds it on
    /// an instrument (a piano on screen or a real one, a guitar's neck).
    enum Family: String, CaseIterable, Identifiable {
        case naming, playing

        var id: Self { self }
        var label: String {
            switch self {
            case .naming: "Naming"
            case .playing: "Playing"
            }
        }
    }

    var id: Self { self }

    /// As the "Answer with" switch says it ("Keyboard", "Note buttons", "Piano", "Guitar"), and
    /// "Real piano" for keys on a piano plugged in.
    var label: String {
        switch self {
        case .realPiano: "Real piano"
        case .keyboard: Game.AnswerInput.keyboard.label
        case .buttons: Game.AnswerInput.buttons.label
        case .piano: Game.AnswerInput.piano.label
        case .guitar: Game.AnswerInput.guitar.label
        }
    }

    var family: Family {
        switch self {
        case .keyboard, .buttons: .naming
        case .realPiano, .piano, .guitar: .playing
        }
    }

    /// Its series colour: the categorical slot of its place in `allCases` (blue, orange, aqua,
    /// yellow, magenta). Never by rank: a filter that leaves fewer methods keeps every colour.
    var color: Color {
        DashboardTheme.series[Self.allCases.firstIndex(of: self)!]
    }

    /// How an answer was given: source `midi` is the real piano; otherwise the question's `input`
    /// (`QuestionShown.input`, the setting's raw value). Nil for an input this version doesn't know.
    static func of(source: AnswerSource, input: String) -> AnswerMethod? {
        source == .midi ? .realPiano : AnswerMethod(rawValue: input).flatMap { $0 == .realPiano ? nil : $0 }
    }

    /// `methods` in this order, under their families: [(Naming, [Keyboard]), (Playing, [Real piano, Guitar])],
    /// leaving out a family with none.
    static func byFamily(_ methods: some Collection<AnswerMethod>) -> [(family: Family, methods: [AnswerMethod])] {
        Family.allCases.compactMap { family in
            let members = allCases.filter { $0.family == family && methods.contains($0) }
            return members.isEmpty ? nil : (family, members)
        }
    }
}
