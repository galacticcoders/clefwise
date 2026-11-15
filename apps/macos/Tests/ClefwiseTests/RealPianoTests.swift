import Foundation
import Testing
@testable import Clefwise

// A real piano or keyboard plugged in over USB (MIDI): reading what it sends, answering with its
// keys, and how those answers are logged and counted. `PianoConnection` itself isn't made here,
// so the tests never hear a real piano; chords on it are in `ChordTests`.

@Suite struct MIDIMessageTests {
    @Test func aNoteOnIsAKeyPress() {
        // Message type 2 (MIDI 1.0), group 0, a note-on on channel 1: Do(C4) = 60, velocity 100.
        #expect(MIDIMessages.keyPresses(in: [0x2090_3C64]) == [MIDIKeyPress(note: 60, velocity: 100)])
        // Any group and channel.
        #expect(MIDIMessages.keyPresses(in: [0x239F_4801]) == [MIDIKeyPress(note: 72, velocity: 1)])
    }

    @Test func keysGoingUpAreNotPresses() {
        #expect(MIDIMessages.keyPresses(in: [0x2090_3C00]).isEmpty) // a note-on at velocity 0
        #expect(MIDIMessages.keyPresses(in: [0x2080_3C40]).isEmpty) // a note-off
    }

    @Test func everythingElseIsPassedOver() {
        // Active sensing (a Yamaha digital piano sends it five times a second), the sustain pedal, then two keys.
        let words: [UInt32] = [0x10FE_0000, 0x20B0_407F, 0x2090_3C64, 0x10FE_0000, 0x2090_4050]
        #expect(MIDIMessages.keyPresses(in: words) == [MIDIKeyPress(note: 60, velocity: 100), MIDIKeyPress(note: 64, velocity: 80)])
    }

    @Test func longerMessagesAreSkippedWhole() {
        // A 7-bit SysEx message takes two words: its second isn't a note-on, though it looks like one.
        #expect(MIDIMessages.keyPresses(in: [0x3016_0000, 0x2090_3C64]).isEmpty)
        // A MIDI 2.0 note-on (two words) isn't read: the port asks for MIDI 1.0. One after it is.
        #expect(MIDIMessages.keyPresses(in: [0x4090_3C00, 0xFFFF_0000, 0x2090_4050]) == [MIDIKeyPress(note: 64, velocity: 80)])
    }

    @Test func keysAreNamedAsOnThePianoOnScreen() {
        #expect(MIDIKeyPress(note: 60, velocity: 1).pitch == Pitch(.c, 4))
        #expect(MIDIKeyPress(note: 61, velocity: 1).pitch == Pitch(.c, 4, .sharp))
        #expect(MIDIKeyPress(note: 21, velocity: 1).pitch == Pitch(.a, 0)) // a piano's lowest key
        #expect(MIDIKeyPress(note: 108, velocity: 1).pitch == Pitch(.c, 8)) // and its highest
    }
}

@MainActor
@Suite final class RealPianoGameTests: GameTestBench {
    private func logged<T>(_ type: T.Type) -> [T] {
        recorder.events.compactMap { $0.event.payload as? T }
    }

    override init() {
        super.init()
        // These play at once; `aKeyStruckWithTheAnswerIsIgnored` puts the grace back.
        game.realKeyGraceMs = 0
    }

    private func play(_ pitch: Pitch, velocity: Int = 64) {
        game.playedOnPiano(MIDIKeyPress(note: pitch.midiNumber, velocity: velocity))
    }

    @Test func aKeyStruckWithTheAnswerIsIgnored() async throws {
        game.realKeyGraceMs = 150
        game.settings.answerInput = .piano
        game.start()
        // Read for longer than the grace, then answered with a neighbour brushed at the same time.
        try await Task.sleep(for: .milliseconds(200))
        let first = try #require(game.question)
        play(first.pitch)
        play(Pitch(midiNumber: first.pitch.midiNumber + 2))
        #expect(game.score == 1 && game.attempts == 1)
        let ignored = try #require(logged(InputIgnored.self).last)
        #expect(ignored.reason == "tooSoon" && ignored.source == .midi)
        // Read for long enough, the next key counts.
        try await Task.sleep(for: .milliseconds(200))
        let second = try #require(game.question)
        play(second.pitch)
        #expect(game.score == 2 && game.attempts == 2)
    }

    @Test func aRealKeyAnswersLikeTheOneOnScreen() throws {
        game.settings.answerInput = .piano
        game.start()
        let first = try #require(game.question)
        play(first.pitch, velocity: 90)
        #expect(game.score == 1 && game.attempts == 1)
        let right = try #require(logged(AnswerGiven.self).last)
        #expect(right.source == .midi && right.correct && right.midiVelocity == 90)
        #expect(right.pitch == LoggedPitch(Pitch(midiNumber: first.pitch.midiNumber)))

        // The exact key: the right note an octave up is a miss.
        let second = try #require(game.question)
        play(Pitch(second.pitch.letter, second.pitch.octave + 1, second.pitch.accidental), velocity: 30)
        let wrong = try #require(logged(AnswerGiven.self).last)
        #expect(wrong.source == .midi && !wrong.correct && wrong.wrongOctave == true && wrong.midiVelocity == 30)
        #expect(game.score == 1 && game.attempts == 2 && game.isShowingMiss)

        // During the pause after a miss, as for any input.
        play(second.pitch)
        let ignored = try #require(logged(InputIgnored.self).last)
        #expect(ignored.reason == "missPause" && ignored.source == .midi)
        #expect(game.attempts == 2)
    }

    @Test func theScreensPianoIsStillThePiano() throws {
        game.settings.answerInput = .piano
        game.start()
        answerRight()
        let answer = try #require(logged(AnswerGiven.self).last)
        #expect(answer.source == .piano && answer.midiVelocity == nil)
    }

    @Test func playingBetweenRoundsIsNotLogged() {
        game.settings.answerInput = .piano
        let before = recorder.events.count
        play(Pitch(.c, 4))
        #expect(recorder.events.count == before)
        game.start()
        game.stop()
        let after = recorder.events.count
        play(Pitch(.c, 4))
        #expect(recorder.events.count == after && game.attempts == 0)
    }

    @Test func withAnotherInputChosenARealKeyIsIgnored() throws {
        game.settings.answerInput = .keyboard
        game.start()
        let question = try #require(game.question)
        play(question.pitch)
        #expect(game.attempts == 0 && game.question?.id == question.id)
        let ignored = try #require(logged(InputIgnored.self).last)
        #expect(ignored.reason == "notPiano" && ignored.source == .midi)
        #expect(ignored.detail == Pitch(midiNumber: question.pitch.midiNumber).name)
    }

    @Test func whilePausedARealKeyIsIgnored() throws {
        game.settings.answerInput = .piano
        game.start()
        let question = try #require(game.question)
        game.pause()
        play(question.pitch)
        #expect(game.attempts == 0)
        let ignored = try #require(logged(InputIgnored.self).last)
        #expect(ignored.reason == "paused" && ignored.source == .midi)
    }

    @Test func aRealPianoSoundsItself() {
        #expect(Game.playsRightAnswer(via: .piano, muted: false))
        #expect(!Game.playsRightAnswer(via: .midi, muted: false))
        #expect(!Game.playsRightAnswer(via: .piano, muted: true))
    }
}

/// Progress counts answers on a real piano as an answer method of their own, "Real piano".
@Suite struct RealPianoDashboardTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    private let now = usageTestTime("2026-11-15T15:00:00.000Z")

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: calendar.startOfDay(for: now))!
    }

    @Test func realPianoAnswersCountApart() {
        var log = Log()
        let round = log.round(at: at(10, 0)) { $0.answerInput = .piano }
        log.answer(round, at: at(10, 0, 1), Pitch(.e, 4), ms: 900, input: "piano")
        log.answer(round, at: at(10, 0, 2), Pitch(.g, 4), ms: 700, input: "piano", source: .midi)
        log.answer(round, at: at(10, 0, 3), Pitch(.b, 4), correct: false, ms: 1500, input: "piano", source: .midi)
        log.end(round, at: at(10, 0, 4), durationMs: 4000, score: 2, attempts: 3)
        let week = ProgressAnalyzer.report(from: log.events, filter: ProgressFilter(range: .week, clef: .all), now: now,
                                           calendar: calendar)
        #expect(week.totals.answers == 3 && week.totals.correct == 2)
        let byKey = Dictionary(uniqueKeysWithValues: week.byInput.map { ($0.key, $0) })
        #expect(Set(byKey.keys) == ["piano", BreakdownRow.realPianoKey])
        #expect(byKey["piano"]?.answers == 1 && byKey["piano"]?.correct == 1)
        #expect(byKey[BreakdownRow.realPianoKey]?.answers == 2 && byKey[BreakdownRow.realPianoKey]?.correct == 1)
        #expect(BreakdownRow.inputLabel(BreakdownRow.realPianoKey) == "Real piano")
        #expect(BreakdownRow.inputLabel("piano") == "Piano" && BreakdownRow.inputLabel("buttons") == "Note buttons")
    }
}
