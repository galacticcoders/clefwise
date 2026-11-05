import Foundation
import Testing
@testable import Clefwise

/// Practice rounds with a limit: a set time or a set number of notes.
@MainActor
@Suite final class PracticeLimitTests: GameTestBench {
    private func ended() -> RoundEnded? {
        recorder.events.reversed().lazy.compactMap { if case .roundEnded(let end) = $0.event { end } else { nil } }.first
    }

    private func practice(_ limit: Game.PracticeLimit, minutes: Int = 5, notes: Int = 100) {
        game.settings.mode = .practice
        game.settings.practiceLimit = limit
        game.settings.practiceMinutes = minutes
        game.settings.practiceNotes = notes
    }

    /// Answers `count` notes right, or wrong with the wrong piano key (and sits out the miss).
    private func answer(_ count: Int) {
        for _ in 0..<count { answerRight() }
    }

    @Test func practiceHasNoLimitUnlessOneIsChosen() {
        game.settings.mode = .practice
        #expect(game.settings.practiceLimit == .endless)
        #expect(game.roundTimeLimit == nil && game.roundNoteLimit == nil)
        game.start()
        answer(3)
        game.tick(at: .now + .seconds(100_000))
        #expect(game.phase == .playing)
        #expect(game.notesLeft == nil)
        game.stop()
        #expect(game.summary?.hadLimit == false && game.summary?.finishedNotes == false)
        #expect(ended()?.reason == .stopped)
    }

    @Test func settingsFromBeforeTheLimitLoad() throws {
        let saved = Data(#"{"mode":"practice"}"#.utf8)
        let settings = try JSONDecoder().decode(Game.Settings.self, from: saved)
        #expect(settings.mode == .practice && settings.practiceLimit == .endless)
        #expect(settings.practiceMinutes == 5 && settings.practiceNotes == 100)
    }

    @Test func theChosenLimitIsKept() throws {
        practice(.notes, minutes: 15, notes: 500)
        let data = try JSONEncoder().encode(game.settings)
        let settings = try JSONDecoder().decode(Game.Settings.self, from: data)
        #expect(settings.practiceLimit == .notes && settings.practiceMinutes == 15 && settings.practiceNotes == 500)
    }

    @Test func aTimedRoundEndsWhenItsTimeIsUp() {
        practice(.time, minutes: 2)
        #expect(game.roundTimeLimit == 120)
        game.start()
        answer(4)
        game.tick(at: .now + .seconds(119))
        #expect(game.phase == .playing)
        #expect(game.timeRemaining > 0)
        game.tick(at: .now + .seconds(121))
        #expect(game.phase == .finished)
        #expect(game.summary?.timeRanOut == true && game.summary?.score == 4)
        #expect(game.summary?.hadLimit == true && game.summary?.noteRoundSeconds == nil)
        #expect(ended()?.reason == .timeUp)
    }

    @Test func aTimedRoundWithNoAnswersStillHasAResult() {
        practice(.time, minutes: 2)
        game.start()
        game.tick(at: .now + .seconds(121))
        #expect(game.phase == .finished)
        #expect(game.summary?.attempts == 0)
    }

    @Test func aPausedTimedRoundKeepsItsTime() {
        practice(.time, minutes: 2)
        let start = ContinuousClock.now
        game.start()
        game.pause(via: .button, at: start + .seconds(60))
        game.tick(at: start + .seconds(500))
        #expect(game.phase == .playing)
        game.resume(via: .button, at: start + .seconds(500))
        game.tick(at: start + .seconds(550))
        #expect(game.phase == .playing)
        game.tick(at: start + .seconds(565))
        #expect(game.phase == .finished)
    }

    @Test func aRoundOfNotesEndsOnItsLastNote() throws {
        practice(.notes, notes: 50)
        #expect(game.roundNoteLimit == 50)
        game.start()
        #expect(game.notesLeft == 50)
        answer(49)
        #expect(game.notesLeft == 1 && game.phase == .playing)
        answer(1)
        #expect(game.phase == .finished && game.notesLeft == nil)
        let summary = try #require(game.summary)
        #expect(summary.finishedNotes && summary.hadLimit && !summary.timeRanOut)
        #expect(summary.attempts == 50 && summary.score == 50)
        #expect(summary.noteRoundSeconds != nil)
        #expect(ended()?.reason == .notesDone)
    }

    @Test func aWrongAnswerCountsTowardsTheNotes() async throws {
        practice(.notes, notes: 50)
        game.start()
        answer(49)
        // A key that can't be right: the note on screen is never this low.
        game.answer(Pitch(.c, 1))
        #expect(game.isShowingMiss && game.notesLeft == 0)
        try await waitUntil { game.phase == .finished }
        #expect(game.summary?.finishedNotes == true)
        #expect(game.summary?.attempts == 50 && game.summary?.score == 49)
    }

    @Test func stoppingEarlyIsNotFinishing() {
        practice(.notes, notes: 50)
        game.start()
        answer(10)
        game.stop()
        #expect(game.summary?.finishedNotes == false && game.summary?.hadLimit == true)
        #expect(game.summary?.noteRoundSeconds != nil)
        #expect(ended()?.reason == .stopped)
    }

    @Test func sprintsIgnoreThePracticeLimit() {
        practice(.notes, notes: 50)
        game.settings.mode = .sprint
        #expect(game.roundTimeLimit == 60 && game.roundNoteLimit == nil)
        game.settings.practiceLimit = .time
        #expect(game.roundTimeLimit == 60)
    }

    @Test func piecesIgnoreThePracticeLimit() throws {
        practice(.time, minutes: 2)
        game.open(try MusicXMLImporter.load(from: try #require(Fixtures.url("bar-view.musicxml"))),
                  from: URL(fileURLWithPath: "/tmp/clefwise-tests/bar-view.musicxml"))
        #expect(game.roundTimeLimit == nil && game.roundNoteLimit == nil)
        game.settings.practiceLimit = .notes
        #expect(game.roundNoteLimit == nil)
        game.start()
        game.tick(at: .now + .seconds(10_000))
        #expect(game.phase == .playing)
    }

    @Test func recentRoundsSayTheirLength() {
        practice(.notes, notes: 50)
        game.start()
        answer(50)
        practice(.time, minutes: 15)
        game.start()
        answer(1)
        game.stop()
        practice(.endless)
        game.start()
        answer(1)
        game.stop()
        game.settings.mode = .sprint
        game.settings.practiceLimit = .notes
        game.start()
        answer(1)
        game.stop()
        let rounds = ProgressAnalyzer.report(from: recorder.events, filter: ProgressFilter(range: .all)).recentRounds
        #expect(rounds.reversed().map(\.practiceLength) == ["50 notes", "15 min", nil, nil])
        #expect(rounds.last?.endReason == .notesDone)
    }

    @Test func theLogKeepsTheLimitForLaterComparisons() throws {
        practice(.time, minutes: 15)
        game.start()
        let started = try #require(recorder.events.lazy.compactMap { if case .roundStarted(let start) = $0.event { start } else { nil } }.first)
        guard case .object(let settings) = started.settings else {
            Issue.record("settings aren't an object")
            return
        }
        #expect(settings["practiceLimit"] == .string("time") && settings["practiceMinutes"] == .number(15))
    }
}
