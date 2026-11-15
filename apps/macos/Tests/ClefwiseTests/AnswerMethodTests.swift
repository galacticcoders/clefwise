import Foundation
import Testing
@testable import Clefwise

/// The answer methods Progress tells apart (`AnswerMethod`), the filter by method, and the report's
/// fields for them: the contract the analyzer and the charts build on.
@Suite struct AnswerMethodTests {
    @Test func methodsComeNamingFirstThenPlaying() {
        #expect(AnswerMethod.allCases == [.keyboard, .buttons, .realPiano, .piano, .guitar])
        #expect(AnswerMethod.allCases.map(\.label) == ["Keyboard", "Note buttons", "Real piano", "Piano", "Guitar"])
        #expect(AnswerMethod.allCases.map(\.family) == [.naming, .naming, .playing, .playing, .playing])
        #expect(AnswerMethod.Family.allCases.map(\.label) == ["Naming", "Playing"])
        // Keys as the dashboard had them: the setting's raw value, `midi` for the real piano.
        #expect(AnswerMethod.allCases.map(\.rawValue) == ["keyboard", "buttons", "midi", "piano", "guitar"])
        #expect(BreakdownRow.realPianoKey == "midi" && BreakdownRow.inputLabel("midi") == "Real piano")
        #expect(BreakdownRow.inputLabel("keyboard") == "Keyboard" && BreakdownRow.inputLabel("harp") == "Harp")
    }

    @Test func anAnswerIsTheSettingsMethodButARealPiano() {
        #expect(AnswerMethod.of(source: .typing, input: "keyboard") == .keyboard)
        #expect(AnswerMethod.of(source: .click, input: "buttons") == .buttons)
        #expect(AnswerMethod.of(source: .shortcut, input: "buttons") == .buttons)
        #expect(AnswerMethod.of(source: .piano, input: "piano") == .piano)
        #expect(AnswerMethod.of(source: .midi, input: "piano") == .realPiano)
        #expect(AnswerMethod.of(source: .guitar, input: "guitar") == .guitar)
        // An input this version doesn't know; `midi` is never a setting.
        #expect(AnswerMethod.of(source: .click, input: "harp") == nil)
        #expect(AnswerMethod.of(source: .piano, input: "midi") == nil)
    }

    @Test func eachMethodKeepsItsSlotsColour() {
        #expect(AnswerMethod.allCases.map(\.color) == Array(DashboardTheme.series.prefix(5)))
        #expect(Set(AnswerMethod.allCases.map(\.color)).count == 5)
    }

    @Test func methodsGroupByFamily() {
        let groups = AnswerMethod.byFamily([.guitar, .keyboard, .realPiano])
        #expect(groups.map(\.family) == [.naming, .playing])
        #expect(groups.map(\.methods) == [[.keyboard], [.realPiano, .guitar]])
        #expect(AnswerMethod.byFamily([AnswerMethod.piano]).map(\.family) == [.playing])
        #expect(AnswerMethod.byFamily([AnswerMethod]()).isEmpty)
    }

    @Test func theFilterReadsOldAndNewSaves() throws {
        let decode = { (json: String) in try JSONDecoder().decode(ProgressFilter.self, from: Data(json.utf8)) }
        // Saved before the method filter: every method.
        #expect(try decode(#"{"range":"week","clef":"bass"}"#) == ProgressFilter(range: .week, clef: .bass))
        // A method a later version knows falls back to every method alone.
        #expect(try decode(#"{"range":"week","clef":"bass","method":"theremin"}"#) == ProgressFilter(range: .week, clef: .bass))
        var filter = ProgressFilter(range: .quarter, clef: .treble)
        filter.method = .realPiano
        #expect(try decode(String(decoding: JSONEncoder().encode(filter), as: UTF8.self)) == filter)
    }

    @Test func theFilterOffersMethodsPractised() {
        var report = ProgressReport.empty(ProgressFilter())
        #expect(ProgressFilter.methodChoices(for: report, selected: nil).isEmpty)
        report.methodsPractised = [.guitar, .keyboard]
        #expect(ProgressFilter.methodChoices(for: report, selected: nil) == [.keyboard, .guitar])
        // The one chosen stays offered, even with no answers left in it.
        #expect(ProgressFilter.methodChoices(for: report, selected: .buttons) == [.keyboard, .buttons, .guitar])
    }

    @Test func theSampleSplitsItsDaysByMethod() {
        let sample = ProgressReport.sample()
        for day in sample.days where day.answers > 0 {
            #expect(day.methods.map(\.answers).reduce(0, +) == day.answers)
            #expect(day.methods.map(\.correct).reduce(0, +) == day.correct)
            let order = day.methods.map { AnswerMethod.allCases.firstIndex(of: $0.method)! }
            #expect(order == order.sorted())
        }
        #expect(sample.methodsPractised.isSuperset(of: [.keyboard, .realPiano, .guitar]))
        #expect(Set(sample.byInput.map(\.key)).isSubset(of: Set(AnswerMethod.allCases.map(\.rawValue))))
        #expect(sample.previousByInput != nil)
        #expect(sample.recentRounds.contains { $0.realPianoAnswers > 0 })
    }
}
