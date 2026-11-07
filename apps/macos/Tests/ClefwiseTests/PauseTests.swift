import Foundation
import Testing
@testable import Clefwise

// Pausing a round: the clock stops, answers don't count, and every time the log keeps leaves the
// pause out. Times the tests choose are passed as `at:`, as with `tick(at:)`; the few tests that
// check logged durations pause for real, briefly.

private extension GameTestBench {
    var paused: [RoundPaused] { recorder.events.compactMap { if case .roundPaused(let e) = $0.event { e } else { nil } } }
    var resumed: [RoundResumed] { recorder.events.compactMap { if case .roundResumed(let e) = $0.event { e } else { nil } } }
    var ended: [RoundEnded] { recorder.events.compactMap { if case .roundEnded(let e) = $0.event { e } else { nil } } }
    var answers: [AnswerGiven] { recorder.events.compactMap { if case .answerGiven(let e) = $0.event { e } else { nil } } }
    var ignored: [InputIgnored] { recorder.events.compactMap { if case .inputIgnored(let e) = $0.event { e } else { nil } } }

    /// A wrong answer on the piano: the white key above the note.
    func answerWrong() {
        guard let pitch = game.question?.pitch else { return }
        game.answer(Pitch(diatonicIndex: pitch.diatonicIndex + 1))
    }
}

@MainActor
@Suite final class PauseTests: GameTestBench {
    @Test func aPausedTimedRoundKeepsItsTime() {
        game.settings.practiceLimit = .time
        game.settings.practiceMinutes = 2
        let start = ContinuousClock.now
        game.start()
        game.pause(at: start + .seconds(10))
        #expect(game.isPaused && !game.isTakingAnswers)

        // Paused, the clock doesn't move, however long it lasts.
        game.tick(at: start + .seconds(200))
        #expect(game.phase == .playing)
        #expect(game.elapsed < 11)

        // Resumed after 90 seconds paused: 110 of the round's 120 seconds are left.
        game.resume(at: start + .seconds(100))
        #expect(!game.isPaused && game.isTakingAnswers)
        game.tick(at: start + .seconds(205))
        #expect(game.phase == .playing)
        #expect(game.elapsed >= 114 && game.elapsed < 116)
        game.tick(at: start + .seconds(211))
        #expect(game.phase == .finished)
        #expect(game.summary?.timeRanOut == true)
    }

    @Test func answersDontCountWhilePaused() {
        game.start()
        let question = game.question
        game.pause()
        answerRight()
        answerWrong()
        #expect(game.attempts == 0 && game.score == 0)
        #expect(game.question == question)
        #expect(ignored.map(\.reason) == ["paused", "paused"])

        game.resume()
        answerRight()
        #expect(game.attempts == 1 && game.score == 1)
    }

    @Test func spaceStartsPausesAndResumes() {
        #expect(game.handleKey(characters: " ", keyCode: 49))
        #expect(game.phase == .playing && !game.isPaused)
        _ = game.handleKey(characters: " ", keyCode: 49)
        #expect(game.isPaused)
        _ = game.handleKey(characters: " ", keyCode: 49)
        #expect(!game.isPaused)
        #expect(paused.map(\.via) == [.key])
        #expect(resumed.map(\.via) == [.key])

        // Esc stops a paused round like any other.
        _ = game.handleKey(characters: " ", keyCode: 49)
        _ = game.handleKey(characters: "\u{1b}", keyCode: 53)
        #expect(game.phase != .playing)
        #expect(!game.isPaused)
    }

    @Test func typingWaitsWhilePaused() {
        game.settings.answerInput = .keyboard
        game.start()
        _ = game.handleKey(characters: " ", keyCode: 49)
        _ = game.handleKey(characters: "c", keyCode: 8)
        #expect(game.typedText.isEmpty)
        #expect(ignored.last?.reason == "paused")
    }

    @Test func pausingTwiceOrResumingUnpausedChangesNothing() {
        let start = ContinuousClock.now
        game.resume(at: start)
        game.start()
        game.pause(at: start + .seconds(1))
        game.pause(at: start + .seconds(5))
        game.resume(at: start + .seconds(8))
        game.resume(at: start + .seconds(9))
        #expect(paused.count == 1 && resumed.count == 1)
        #expect(resumed.first?.pausedMs == 7000)
    }

    @Test func theLogLeavesPausesOut() async throws {
        game.start()
        let question = try #require(recorder.events.compactMap { if case .questionShown(let e) = $0.event { e } else { nil } }.last)
        game.pause(via: .button)
        try await Task.sleep(for: .milliseconds(300))
        game.resume(via: .button)
        answerRight()
        game.stop()

        let pause = try #require(paused.first)
        #expect(pause.round == question.round && pause.question == question.question)
        let resume = try #require(resumed.first)
        #expect(resume.pausedMs >= 300)

        // The answer came right after the resume: its response time is the time before the pause.
        let answer = try #require(answers.first)
        #expect(answer.pausedMs == resume.pausedMs)
        #expect(answer.responseMs < 300)

        let end = try #require(ended.first)
        #expect(end.pausedMs == resume.pausedMs)
        #expect(end.durationMs < 300)
    }

    @Test func endingWhilePausedCountsThePauseInProgress() async throws {
        game.start()
        game.pause()
        try await Task.sleep(for: .milliseconds(250))
        game.stop()
        #expect(!game.isPaused)
        #expect(resumed.isEmpty)
        let end = try #require(ended.first)
        #expect(end.durationMs < 250)
        #expect((end.pausedMs ?? 0) >= 250)
        #expect((end.unansweredQuestion?.pausedMs ?? 0) >= 250)
        #expect((end.unansweredQuestion?.shownMs ?? .max) < 250)
    }

    @Test func aMissPausedOnWaitsForTheResume() async throws {
        game.start()
        answerWrong()
        #expect(game.isShowingMiss)
        let missed = game.question
        game.pause()
        // Until the pause after a miss has run out, however busy the test run is.
        try await waitUntil { game.advancesOnResume }
        #expect(game.isShowingMiss)
        #expect(game.question == missed)

        game.resume()
        #expect(!game.isShowingMiss)
        #expect(game.question != missed)
        #expect(game.isTakingAnswers)
    }

    @Test func switchingAppsPausesARoundGoing() {
        game.appDidResignActive()
        #expect(!game.isPaused && paused.isEmpty) // no round, nothing to pause

        game.start()
        game.appDidResignActive()
        #expect(game.isPaused && game.pausedVia == .appSwitch)
        #expect(paused.map(\.via) == [.appSwitch])
        // Coming back doesn't carry on by itself; Space does.
        game.appDidResignActive()
        #expect(paused.count == 1)
        _ = game.handleKey(characters: " ", keyCode: 49)
        #expect(!game.isPaused && game.pausedVia == nil)
        #expect(resumed.map(\.via) == [.key])

        // A round already paused by hand stays paused by hand.
        game.pause(via: .button)
        game.appDidResignActive()
        #expect(game.pausedVia == .button && paused.count == 2)
    }

    @Test func aNewRoundStartsUnpaused() {
        game.start()
        game.pause()
        game.start()
        #expect(!game.isPaused && game.isTakingAnswers)
        #expect(ended.first?.reason == .abandoned)
        #expect(ended.first?.pausedMs != nil)
    }
}

@Suite struct PauseEventTests {
    @Test func pauseEventsRoundTrip() throws {
        let round = UUID(), question = UUID()
        for event in [UsageEvent.roundPaused(RoundPaused(round: round, question: question, via: .button, activeMs: 4200)),
                      .roundResumed(RoundResumed(round: round, question: nil, via: .key, pausedMs: 31000))] {
            let data = try LoggedEvent.encoder.encode(LoggedEvent(event, session: UUID(), sequence: 3))
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["type"] as? String == event.type)
            #expect(try LoggedEvent.decoder.decode(LoggedEvent.self, from: data).event == event)
        }
    }

    @Test func oldLinesWithoutPausesStillRead() throws {
        let line = #"{"schema":1,"type":"roundEnded","id":"6A1F2C33-0D3E-4E7B-9C45-0B7E5D1A2F10","time":"2026-10-30T17:02:11.348Z","session":"8D7C1B22-5E4F-4A3B-8C2D-1E0F9A8B7C6D","sequence":9,"round":"1C2B3A49-5D6E-4F70-8A9B-0C1D2E3F4A5B","reason":"stopped","durationMs":61000,"score":3,"attempts":4,"bestStreak":2,"isNewBest":false,"notesToReview":[]}"#
        let decoded = try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data(line.utf8))
        guard case .roundEnded(let end) = decoded.event else {
            Issue.record("not a roundEnded")
            return
        }
        #expect(end.durationMs == 61000 && end.pausedMs == nil)
    }
}
