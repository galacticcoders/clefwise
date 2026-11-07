import Foundation
import Testing
@testable import Clefwise

// Bringing a round back after a crash (`Game.restore`), or ending it as `interrupted` when it can't
// come back; see spec/practice-journal.md, "After a crash". Each test plays part of a round, takes
// its events as its run file holds them, and starts the app again on the same defaults and library.

/// What the first game had when it stopped, and the run file it left.
private struct Crash {
    let run: PendingRun
    /// Round time used, as the game measured it.
    let activeMs: Int
    let score: Int, attempts: Int, streak: Int
    let question: Question?
    let group: [Question]?
    let pieceProgress: Game.PieceProgress?
    let barDisplay: BarDisplay?
}

private func payloads<T>(_ type: T.Type, in events: [LoggedEvent]) -> [T] {
    events.compactMap { $0.event.payload as? T }
}

/// The same note, whatever the question's id.
private func sameNote(_ a: Question?, _ b: Question?) -> Bool {
    a?.clef == b?.clef && a?.pitch == b?.pitch && a?.keySignature == b?.keySignature
        && a?.printedAccidental == b?.printedAccidental && a?.octaveShift == b?.octaveShift
}

@MainActor
@Suite final class RoundRestoreTests: GameTestBench {
    /// Time between the crash and the next launch, which counts as neither round time nor paused time.
    private static let gap: Duration = .milliseconds(300)
    /// How far apart two clocks may be on one stretch of round time.
    private static let toleranceMs = 50

    // MARK: - Helpers

    /// Stops `game` as a crash would and takes the run file it leaves: its events from the round's
    /// `roundStarted` on, or after `earlier` events (a round that came back once already) every
    /// event of this session.
    private func stopLikeACrash(_ game: Game, logged recorder: MemoryUsageRecorder,
                                after earlier: [LoggedEvent] = []) throws -> Crash {
        let events: [LoggedEvent]
        if earlier.isEmpty {
            let start = try #require(recorder.events.lastIndex { $0.event.type == "roundStarted" })
            events = Array(recorder.events[start...])
        } else {
            events = earlier + recorder.events
        }
        let started = try #require(payloads(RoundStarted.self, in: events).first)
        let state = (score: game.score, attempts: game.attempts, streak: game.streak, question: game.question,
                     group: game.group?.questions, progress: game.pieceProgress, bar: game.barDisplay)
        // Nothing more from this game: quitting stops its clock and tasks, and what it logs now is
        // after the crash. Its end says the round time used.
        game.appWillTerminate()
        let end = try #require(payloads(RoundEnded.self, in: recorder.events).last)
        return Crash(run: PendingRun(round: started.round, file: URL(fileURLWithPath: "/tmp/unused-run.jsonl"), events: events),
                     activeMs: end.durationMs, score: state.score, attempts: state.attempts, streak: state.streak,
                     question: state.question, group: state.group, pieceProgress: state.progress, barDisplay: state.bar)
    }

    /// The app starting again after a while, in a new session that logs its `appLaunched` first.
    private func relaunchAfterCrash() async throws -> (game: Game, recorder: MemoryUsageRecorder) {
        try await Task.sleep(for: Self.gap)
        let later = MemoryUsageRecorder()
        later.record(.appLaunched(AppLaunched(appVersion: "test", build: "1", osVersion: "26.0", model: "Mac15,12",
                                              locale: "en_GB", timeZone: "Europe/Stockholm", screen: nil)))
        return (relaunch(recorder: later), later)
    }

    /// Answers what's asked right: the note, or every note asked together (a piano key each).
    @discardableResult
    private func answerRight(on game: Game) -> Bool {
        guard let question = game.question else { return false }
        if let group = game.group {
            var keys: Set<Int> = []
            for pitch in group.questions.map(\.pitch) where keys.insert(pitch.midiNumber).inserted { game.answer(pitch) }
        } else {
            game.answer(question.pitch)
        }
        return true
    }

    /// Answers the note asked with another letter, on the note buttons.
    private func answerWrong(on game: Game) throws {
        let question = try #require(game.question)
        game.answer(try #require(NoteLetter.allCases.first { $0 != question.pitch.letter }))
    }

    /// "Lantern at Dusk", kept in the library so the next launch reopens it, practised as told.
    private func openLantern(hand: Game.PieceSettings.Hand = .right, order: Game.PieceSettings.Order = .inOrder,
                             chords: Game.PieceSettings.Chords = .eachNote) throws {
        game.openPiece(at: try #require(Fixtures.url("bar-view.musicxml")))
        try #require(game.pieceError == nil)
        game.settings.piece.hand = hand
        game.settings.piece.order = order
        game.settings.piece.chords = chords
    }

    /// `restored` is the round as it was at the crash, paused, with `roundRestored` logged and
    /// nothing asked yet.
    private func expectRebuilt(_ restored: Game, from crash: Crash, logged later: MemoryUsageRecorder) throws {
        #expect(restored.phase == .playing && restored.isPaused && !restored.isTakingAnswers)
        #expect(restored.summary == nil && restored.pausedVia == nil)
        #expect(restored.score == crash.score && restored.attempts == crash.attempts && restored.streak == crash.streak)
        #expect(abs(Int((restored.elapsed * 1000).rounded()) - crash.activeMs) < Self.toleranceMs,
                "\(restored.elapsed) s against \(crash.activeMs) ms")
        #expect(restored.pieceProgress == crash.pieceProgress)
        #expect(restored.barDisplay == crash.barDisplay)
        let restoredEvent = try #require(payloads(RoundRestored.self, in: later.events).last)
        #expect(restoredEvent.round == crash.run.round)
        #expect(abs(restoredEvent.activeMs - crash.activeMs) < Self.toleranceMs)
        #expect(!later.events.contains { $0.event.type == "questionShown" })
        #expect(later.events.last?.event.type == "roundRestored")
    }

    /// Resumes `restored` and checks the note on screen at the crash is asked again, exactly as it
    /// was, as a new question.
    private func resumeAskingAgain(_ restored: Game, after crash: Crash, logged later: MemoryUsageRecorder) throws {
        let before = later.events.count
        restored.resume(via: .button)
        let new = Array(later.events.dropFirst(before))
        #expect(new.first?.event.type == "roundResumed")
        let shown = payloads(QuestionShown.self, in: new)
        let earlier = payloads(QuestionShown.self, in: crash.run.events)
        let unanswered = try crash.group ?? [#require(crash.question)]
        try #require(shown.count == unanswered.count)
        for (offset, (again, old)) in zip(shown, earlier.suffix(shown.count)).enumerated() {
            #expect(again.question != old.question)
            #expect(again.index == earlier.count + offset)
            #expect(again.clef == old.clef && again.pitch == old.pitch && again.written == old.written)
            #expect(again.keyFifths == old.keyFifths && again.printedAccidental == old.printedAccidental)
            #expect(again.pieceNote == old.pieceNote && again.barView == old.barView && again.barStaves == old.barStaves)
            #expect(again.pickChance == nil)
            #expect(again.groupSize == old.groupSize && (again.group == nil) == (old.group == nil))
            if let group = again.group { #expect(group != old.group) }
        }
        #expect(sameNote(restored.question, crash.question))
        #expect(restored.isTakingAnswers)
    }

    /// The round's end, logged after it came back, agrees with every answer logged for it before
    /// the crash and after; and so does the summary, if there's one.
    private func expectEndAgrees(_ crash: Crash, then later: MemoryUsageRecorder, summary: RoundSummary?) throws {
        let events = crash.run.events + later.events
        let answers = payloads(AnswerGiven.self, in: events).filter { $0.round == crash.run.round }
        let end = try #require(payloads(RoundEnded.self, in: later.events).last)
        #expect(end.round == crash.run.round)
        #expect(end.attempts == answers.count)
        #expect(end.score == answers.filter(\.correct).count && end.score == answers.last?.scoreAfter)
        #expect(end.bestStreak == answers.map(\.streakAfter).max())
        let replay = RoundReplay(round: crash.run.round, events: events)
        #expect(abs((end.averageResponseMs ?? 0) - (replay.averageResponseMs ?? 0)) <= 1)
        // The time between the crash and the round coming back is in neither.
        #expect(abs(end.durationMs - replay.activeMs) < Self.toleranceMs, "\(end.durationMs) against \(replay.activeMs)")
        #expect(abs((end.pausedMs ?? 0) - replay.pausedMs) < Self.toleranceMs)
        guard let summary else { return }
        #expect(summary.score == end.score && summary.attempts == end.attempts && summary.bestStreak == end.bestStreak)
        #expect(summary.notesToReview.map { "\($0.clef.rawValue).\($0.pitch.name)" } == end.notesToReview)
        #expect(summary.averageSeconds.map { Int(($0 * 1000).rounded()) } == end.averageResponseMs)
    }

    /// `game` ended the round as `interrupted` instead of bringing it back: at the run's last event,
    /// with what its events say.
    @discardableResult
    private func expectInterrupted(_ game: Game, _ crash: Crash, logged later: MemoryUsageRecorder) throws -> RoundEnded {
        #expect(game.phase == .idle && game.question == nil && !game.isPaused)
        #expect(!later.events.contains { $0.event.type == "roundRestored" })
        let logged = try #require(later.events.last)
        guard case .roundEnded(let end) = logged.event else {
            Issue.record("Last event: \(logged.event.type)")
            throw CancellationError()
        }
        #expect(end.round == crash.run.round && end.reason == .interrupted)
        #expect(logged.time == crash.run.events.last?.time)
        #expect(abs(try #require(end.recordedAt).timeIntervalSinceNow) < 5)
        let answers = payloads(AnswerGiven.self, in: crash.run.events)
        #expect(end.attempts == answers.count && end.score == answers.last?.scoreAfter)
        #expect(end.bestStreak == answers.map(\.streakAfter).max() && end.bestScore == nil && end.isNewBest == nil)
        #expect(defaults.object(forKey: "restoringRound") == nil)
        return end
    }

    // MARK: - Random notes

    @Test func anEndlessRoundComesBackAsItWas() async throws {
        game.start()
        for _ in 0..<3 { answerRight() }
        let missed = try #require(game.question)
        try answerWrong(on: game)
        try await waitUntil { !game.isShowingMiss }
        answerRight()
        // Round time up to the last event comes back; any after it is lost.
        try await Task.sleep(for: .milliseconds(100))
        answerRight()
        let crash = try stopLikeACrash(game, logged: recorder)
        #expect(crash.score == 5 && crash.attempts == 6 && crash.streak == 2)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        #expect(payloads(RoundRestored.self, in: later.events).last?.unansweredQuestion == crash.question?.id)
        #expect(sameNote(restored.question, crash.question))
        try resumeAskingAgain(restored, after: crash, logged: later)
        answerRight(on: restored)
        answerRight(on: restored)
        restored.stop()

        let summary = try #require(restored.summary)
        #expect(summary.score == 7 && summary.attempts == 8 && summary.bestStreak == 4)
        #expect(summary.notesToReview == [StaffNote(clef: missed.clef, pitch: missed.pitch)])
        #expect(payloads(RoundEnded.self, in: later.events).last?.reason == .stopped)
        try expectEndAgrees(crash, then: later, summary: summary)
    }

    @Test func aTimedRoundKeepsTheTimeItHadLeft() async throws {
        game.settings.practiceLimit = .time
        game.settings.practiceMinutes = 2
        game.start()
        for _ in 0..<3 { answerRight() }
        try await Task.sleep(for: .milliseconds(100))
        answerRight()
        let crash = try stopLikeACrash(game, logged: recorder)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        #expect(restored.roundTimeLimit == 120)
        #expect(abs(restored.timeRemaining - (120 - Double(crash.activeMs) / 1000)) < 0.05)
        try resumeAskingAgain(restored, after: crash, logged: later)
        answerRight(on: restored)
        restored.tick(at: .now + .seconds(121))

        let summary = try #require(restored.summary)
        #expect(summary.timeRanOut && summary.hadLimit && summary.score == 5)
        #expect(payloads(RoundEnded.self, in: later.events).last?.reason == .timeUp)
        try expectEndAgrees(crash, then: later, summary: summary)
    }

    @Test func aRoundOfSetNotesCountsOnFromWhereItWas() async throws {
        game.settings.practiceLimit = .notes
        game.settings.practiceNotes = 6
        game.start()
        for _ in 0..<4 { answerRight() }
        let crash = try stopLikeACrash(game, logged: recorder)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        #expect(restored.notesLeft == 2)
        try resumeAskingAgain(restored, after: crash, logged: later)
        answerRight(on: restored)
        #expect(restored.phase == .playing)
        answerRight(on: restored)

        let summary = try #require(restored.summary)
        #expect(summary.finishedNotes && summary.attempts == 6 && summary.score == 6)
        #expect(payloads(RoundEnded.self, in: later.events).last?.reason == .notesDone)
        try expectEndAgrees(crash, then: later, summary: summary)
    }

    @Test func aSprintFromBeforeItWentComesBackAsPractice() async throws {
        game.start()
        for _ in 0..<3 { answerRight() }
        try await Task.sleep(for: .milliseconds(100))
        answerRight()
        let crash = try stopLikeACrash(game, logged: recorder)
        // As a version until 2026-11-07 left it, set for a sprint: `mode` in the saved settings and
        // in the run's `roundStarted`.
        let saved = try #require(defaults.data(forKey: Game.Keys.settings))
        var settings = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        settings["mode"] = "sprint"
        defaults.set(try JSONSerialization.data(withJSONObject: settings), forKey: Game.Keys.settings)
        let events = crash.run.events.map { logged -> LoggedEvent in
            guard case .roundStarted(var started) = logged.event, case .object(var values) = started.settings else { return logged }
            values["mode"] = .string("sprint")
            started.settings = .object(values)
            return LoggedEvent(.roundStarted(started), session: logged.session, sequence: logged.sequence, time: logged.time)
        }

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(PendingRun(round: crash.run.round, file: crash.run.file, events: events))
        try expectRebuilt(restored, from: crash, logged: later)
        // A practice round with no limit: no minute's clock runs out.
        #expect(restored.roundTimeLimit == nil && restored.roundNoteLimit == nil)
        try resumeAskingAgain(restored, after: crash, logged: later)
        answerRight(on: restored)
        restored.tick(at: .now + .seconds(61))
        #expect(restored.phase == .playing)
        answerRight(on: restored)
        restored.stop()

        let summary = try #require(restored.summary)
        #expect(!summary.timeRanOut && !summary.hadLimit && summary.score == 6)
        let end = try #require(payloads(RoundEnded.self, in: later.events).last)
        #expect(end.reason == .stopped && end.bestScore == nil && end.isNewBest == nil)
        try expectEndAgrees(crash, then: later, summary: summary)
    }

    // MARK: - Pieces

    @Test func aPieceInOrderCarriesOnFromItsPlace() async throws {
        try openLantern()
        game.start()
        for _ in 0..<4 { answerRight() }
        try await Task.sleep(for: .milliseconds(50))
        answerRight()
        let crash = try stopLikeACrash(game, logged: recorder)
        #expect(crash.pieceProgress?.done == 5)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        try resumeAskingAgain(restored, after: crash, logged: later)
        var answered = 0
        while restored.phase == .playing, answered < 500, answerRight(on: restored) { answered += 1 }

        let summary = try #require(restored.summary)
        #expect(summary.finishedPiece)
        #expect(payloads(RoundEnded.self, in: later.events).last?.reason == .pieceComplete)
        // Every note of the round answered once, in order, across the crash.
        let events = crash.run.events + later.events
        let shown = Dictionary(payloads(QuestionShown.self, in: events).map { ($0.question, $0) }) { first, _ in first }
        let notes = payloads(AnswerGiven.self, in: events).compactMap { shown[$0.question]?.pieceNote }
        let noteCount = try #require(payloads(RoundStarted.self, in: events).first?.piece?.noteCount)
        let keys = Set(notes.map { "\($0.measure)/\($0.staff)/\($0.onset)/\($0.chord)/\($0.symbolIndex ?? -1)" })
        #expect(notes.count == noteCount && keys.count == noteCount && summary.attempts == noteCount)
        #expect(zip(notes, notes.dropFirst()).allSatisfy { $0.onset <= $1.onset })
        try expectEndAgrees(crash, then: later, summary: summary)
    }

    @Test func pieceSettingsChangedMidRoundWaitForTheNextRound() async throws {
        try openLantern()
        game.start()
        for _ in 0..<3 { answerRight() }
        // Changed for the next round: the round going on stays as it started.
        game.settings.piece.hand = .left
        game.settings.piece.order = .shuffled
        answerRight()
        let crash = try stopLikeACrash(game, logged: recorder)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        #expect(restored.barStrip?.showsDone == true)
        try resumeAskingAgain(restored, after: crash, logged: later)
        var answered = 0
        while restored.phase == .playing, answered < 500, answerRight(on: restored) { answered += 1 }

        let summary = try #require(restored.summary)
        #expect(summary.finishedPiece)
        // Its original notes: the right hand's, in order, each once.
        let events = crash.run.events + later.events
        let shown = Dictionary(payloads(QuestionShown.self, in: events).map { ($0.question, $0) }) { first, _ in first }
        let notes = payloads(AnswerGiven.self, in: events).compactMap { shown[$0.question]?.pieceNote }
        let started = try #require(payloads(RoundStarted.self, in: events).first?.piece)
        #expect(started.hand == "right" && started.order == "inOrder")
        #expect(notes.count == started.noteCount && notes.allSatisfy { $0.staff == 1 })
        #expect(zip(notes, notes.dropFirst()).allSatisfy { $0.onset <= $1.onset })
        // The changes stay, for the next round.
        #expect(restored.settings.piece.hand == .left && restored.settings.piece.order == .shuffled)
        let summaryAgain = try #require(restored.summary)
        try expectEndAgrees(crash, then: later, summary: summaryAgain)
    }

    @Test func aShuffledPieceComesBackOnTheSameNote() async throws {
        try openLantern(hand: .both, order: .shuffled)
        game.start()
        for _ in 0..<6 { answerRight() }
        let crash = try stopLikeACrash(game, logged: recorder)
        #expect(crash.pieceProgress?.done == 6)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        try resumeAskingAgain(restored, after: crash, logged: later)
        for _ in 0..<3 { answerRight(on: restored) }
        #expect(restored.pieceProgress?.done == 9)
        restored.stop()
        let summary = try #require(restored.summary)
        try expectEndAgrees(crash, then: later, summary: summary)
    }

    @Test func notesAskedTogetherComeBackTogether() async throws {
        try openLantern(hand: .both, chords: .together)
        game.settings.answerInput = .piano
        game.start()
        answerRight(on: game)
        var answered = 1
        while game.group == nil, answered < 100 {
            answerRight(on: game)
            answered += 1
        }
        let group = try #require(game.group?.questions)
        let crash = try stopLikeACrash(game, logged: recorder)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        #expect(restored.group?.questions.count == group.count)
        #expect(zip(restored.group?.questions ?? [], group).allSatisfy { sameNote($0, $1) })
        #expect(payloads(RoundRestored.self, in: later.events).last?.unansweredQuestion == group.first?.id)
        try resumeAskingAgain(restored, after: crash, logged: later)
        let again = payloads(QuestionShown.self, in: later.events)
        #expect(Set(again.map(\.group)).count == 1)
        for _ in 0..<3 { answerRight(on: restored) }
        restored.stop()
        let summary = try #require(restored.summary)
        try expectEndAgrees(crash, then: later, summary: summary)
    }

    @Test func inAPieceTheNoteAfterAMissComesNext() async throws {
        try openLantern()
        game.start()
        answerRight()
        answerRight()
        try answerWrong(on: game)
        let crash = try stopLikeACrash(game, logged: recorder)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        #expect(payloads(RoundRestored.self, in: later.events).last?.unansweredQuestion == nil)
        restored.resume(via: .key)
        #expect(restored.pieceProgress?.done == 3 && restored.isTakingAnswers)
        let missed = try #require(payloads(QuestionShown.self, in: crash.run.events).last)
        let next = try #require(payloads(QuestionShown.self, in: later.events).last)
        #expect(next.pieceNote != missed.pieceNote && next.index == missed.index + 1)
    }

    // MARK: - Paused, missed

    @Test func aRoundPausedAtTheCrashComesBackWithItsTime() async throws {
        game.start()
        answerRight()
        answerRight()
        try await Task.sleep(for: .milliseconds(100))
        game.pause(via: .button)
        try await Task.sleep(for: .milliseconds(50))
        let paused = try #require(payloads(RoundPaused.self, in: recorder.events).last)
        let crash = try stopLikeACrash(game, logged: recorder)
        #expect(crash.activeMs == paused.activeMs)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        // Exactly the round time the pause logged.
        #expect(payloads(RoundRestored.self, in: later.events).last?.activeMs == paused.activeMs)
        #expect(restored.elapsed == Double(paused.activeMs) / 1000)
        try await Task.sleep(for: .milliseconds(100))
        try resumeAskingAgain(restored, after: crash, logged: later)
        // The pause after coming back counts from `roundRestored`.
        let resumed = try #require(payloads(RoundResumed.self, in: later.events).last)
        #expect(resumed.pausedMs >= 100 && resumed.pausedMs < 300, "\(resumed.pausedMs) ms")
        answerRight(on: restored)
        restored.stop()
        let summary = try #require(restored.summary)
        try expectEndAgrees(crash, then: later, summary: summary)
    }

    @Test func aCrashRightAfterAMissGoesOnToTheNextNote() async throws {
        game.start()
        answerRight()
        answerRight()
        let missed = try #require(game.question)
        try answerWrong(on: game)
        #expect(game.isShowingMiss)
        let crash = try stopLikeACrash(game, logged: recorder)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        #expect(restored.streak == 0)
        #expect(payloads(RoundRestored.self, in: later.events).last?.unansweredQuestion == nil)
        restored.resume(via: .button)
        // Not the missed note again: the next one, as after any miss.
        let next = try #require(payloads(QuestionShown.self, in: later.events).last)
        #expect(next.index == 3 && next.pickChance != nil)
        #expect(!(next.clef == missed.clef.rawValue && next.pitch == LoggedPitch(missed.pitch)))
        answerRight(on: restored)
        restored.stop()
        let summary = try #require(restored.summary)
        #expect(summary.notesToReview == [StaffNote(clef: missed.clef, pitch: missed.pitch)])
        try expectEndAgrees(crash, then: later, summary: summary)
    }

    // MARK: - When it isn't brought back

    @Test func aRoundThatCrashesAgainBeforeAnAnswerIsEnded() async throws {
        game.start()
        for _ in 0..<3 { answerRight() }
        let first = try stopLikeACrash(game, logged: recorder)
        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(first.run)
        restored.resume(via: .button)
        let askedAgain = try #require(restored.question)
        try await Task.sleep(for: .milliseconds(100))
        let second = try stopLikeACrash(restored, logged: later, after: first.run.events)
        // Long after the restore settled, so only the run file tells.
        defaults.removeObject(forKey: "restoringRound")

        let (third, latest) = try await relaunchAfterCrash()
        third.restore(second.run)
        let end = try expectInterrupted(third, second, logged: latest)
        #expect(end.score == 3 && end.attempts == 3 && end.bestStreak == 3)
        // Up to the run's last event, the note asked again: the time after it is lost. The second
        // game ran on for 100 ms from the round time it was brought back with: the first run's up
        // to its last event, which can be a millisecond or so short of what the first game measured
        // when it stopped, so that's the time to count the 100 ms from.
        let broughtBack = try #require(payloads(RoundRestored.self, in: later.events).last).activeMs
        #expect(abs(broughtBack - first.activeMs) < Self.toleranceMs)
        #expect(second.activeMs >= broughtBack + 100)
        #expect(abs(end.durationMs - first.activeMs) < Self.toleranceMs)
        #expect(end.unansweredQuestion?.question == askedAgain.id)
        #expect(try #require(end.unansweredQuestion?.shownMs) < Self.toleranceMs)
    }

    @Test func aRoundThatCrashesAgainWhilePausedComesBackAgain() async throws {
        game.start()
        for _ in 0..<2 { answerRight() }
        let first = try stopLikeACrash(game, logged: recorder)
        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(first.run)
        let second = try stopLikeACrash(restored, logged: later, after: first.run.events)
        defaults.removeObject(forKey: "restoringRound")

        let (third, latest) = try await relaunchAfterCrash()
        third.restore(second.run)
        try expectRebuilt(third, from: second, logged: latest)
        #expect(payloads(RoundRestored.self, in: latest.events).last?.unansweredQuestion == first.question?.id)
        try resumeAskingAgain(third, after: second, logged: latest)
        answerRight(on: third)
        third.stop()
        let summary = try #require(third.summary)
        try expectEndAgrees(second, then: latest, summary: summary)
    }

    @Test func aRestoreThatNeverSettledIsNotTriedAgain() async throws {
        game.start()
        answerRight()
        try answerWrong(on: game)
        let crash = try stopLikeACrash(game, logged: recorder)
        // The last launch crashed while bringing this round back.
        defaults.set(crash.run.round.uuidString, forKey: "restoringRound")

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        let end = try expectInterrupted(restored, crash, logged: later)
        #expect(abs(end.durationMs - crash.activeMs) < Self.toleranceMs)
        #expect(end.score == 1 && end.attempts == 2 && end.notesToReview.count == 1)
        #expect(end.unansweredQuestion == nil)
    }

    @Test func theDevicesNoteLastsUntilTheRoundHasSettledBackIn() async throws {
        game.start()
        answerRight()
        let crash = try stopLikeACrash(game, logged: recorder)
        // A note about another round doesn't stop this one.
        defaults.set(UUID().uuidString, forKey: "restoringRound")

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
        #expect(defaults.object(forKey: "restoringRound") as? String == crash.run.round.uuidString)
        try await waitUntil { defaults.object(forKey: "restoringRound") == nil }
        #expect(defaults.object(forKey: "restoringRound") == nil)
    }

    @Test func aPieceNoLongerInTheLibraryEndsTheRound() async throws {
        try openLantern()
        game.start()
        for _ in 0..<3 { answerRight() }
        let crash = try stopLikeACrash(game, logged: recorder)
        library.remove(try #require(game.pieceEntryID))

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        #expect(restored.piece == nil)
        try expectInterrupted(restored, crash, logged: later)
    }

    @Test func aPieceThatChangedEndsTheRound() async throws {
        try openLantern()
        game.start()
        for _ in 0..<3 { answerRight() }
        let crash = try stopLikeACrash(game, logged: recorder)
        let started = try #require(payloads(RoundStarted.self, in: crash.run.events).first)
        let context = try #require(started.piece)

        /// The run as if its round had started on `piece`.
        func run(on piece: PieceContext) -> PendingRun {
            var changed = started
            changed.piece = piece
            var events = crash.run.events
            events[0] = LoggedEvent(.roundStarted(changed), session: events[0].session, sequence: 0, time: events[0].time)
            return PendingRun(round: crash.run.round, file: crash.run.file, events: events)
        }

        // A score with another note in it.
        var moreNotes = context
        moreNotes.noteCount += 1
        var (restored, later) = try await relaunchAfterCrash()
        restored.restore(run(on: moreNotes))
        try expectInterrupted(restored, crash, logged: later)

        // Another file than the one the round was on.
        var otherFile = context
        otherFile.id = String(repeating: "a", count: 64)
        otherFile.file = String(repeating: "b", count: 64)
        (restored, later) = try await relaunchAfterCrash()
        restored.restore(run(on: otherFile))
        try expectInterrupted(restored, crash, logged: later)

        // The library's copy replaced by another score.
        let entry = try #require(library.entries.first)
        try Data(contentsOf: try #require(Fixtures.url("grand-staff.musicxml"))).write(to: library.fileURL(for: entry))
        (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectInterrupted(restored, crash, logged: later)
    }

    @Test func changedSettingsEndTheRound() async throws {
        game.start()
        for _ in 0..<2 { answerRight() }
        let crash = try stopLikeACrash(game, logged: recorder)
        var settings = try JSONDecoder().decode(Game.Settings.self, from: try #require(defaults.data(forKey: "settings")))
        settings.clefChoice = .bass
        defaults.set(try JSONEncoder().encode(settings), forKey: "settings")

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectInterrupted(restored, crash, logged: later)
    }

    @Test func settingsThatDontShapeTheRoundCanChange() async throws {
        game.start()
        answerRight()
        let crash = try stopLikeACrash(game, logged: recorder)
        var settings = try JSONDecoder().decode(Game.Settings.self, from: try #require(defaults.data(forKey: "settings")))
        settings.naming = .solfege
        settings.showHints = true
        defaults.set(try JSONEncoder().encode(settings), forKey: "settings")

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(crash.run)
        try expectRebuilt(restored, from: crash, logged: later)
    }

    @Test func eventsThatDontMakeARoundEndIt() async throws {
        game.start()
        for _ in 0..<2 { answerRight() }
        let crash = try stopLikeACrash(game, logged: recorder)
        // Its first line lost.
        let headless = PendingRun(round: crash.run.round, file: crash.run.file, events: Array(crash.run.events.dropFirst()))

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(headless)
        #expect(restored.phase == .idle)
        let end = try #require(payloads(RoundEnded.self, in: later.events).last)
        #expect(end.reason == .interrupted && end.score == 2 && end.attempts == 2)
        #expect(later.events.last?.time == crash.run.events.last?.time)
    }

    @Test func aRunThatEndedIsLeftAlone() async throws {
        game.start()
        answerRight()
        game.stop()
        let start = try #require(recorder.events.lastIndex { $0.event.type == "roundStarted" })
        let events = Array(recorder.events[start...])
        let round = try #require(payloads(RoundStarted.self, in: events).first?.round)

        let (restored, later) = try await relaunchAfterCrash()
        restored.restore(PendingRun(round: round, file: URL(fileURLWithPath: "/tmp/unused-run.jsonl"), events: events))
        #expect(restored.phase == .idle)
        #expect(later.events.map(\.event.type) == ["appLaunched"])
    }
}

// MARK: - Replaying the events

/// Builds a run file's events by hand, across sessions.
private struct Run {
    let round = UUID()
    private(set) var events: [LoggedEvent] = []
    private var session = UUID()
    private var shownCount = 0
    let start = usageTestTime("2026-11-05T09:00:00.000Z")

    /// The app launched again after a crash.
    mutating func relaunch(after seconds: Double) {
        session = UUID()
        add(.appLaunched(AppLaunched(appVersion: "test", build: "1", osVersion: "26.0", model: "Mac15,12", locale: "en_GB",
                                     timeZone: "UTC", screen: nil)), at: seconds)
    }

    mutating func add(_ event: UsageEvent, at seconds: Double) {
        events.append(LoggedEvent(event, session: session, sequence: events.count, time: start.addingTimeInterval(seconds)))
    }

    mutating func started(at seconds: Double = 0) {
        add(.roundStarted(RoundStarted(round: round, via: .button, settings: JSONValue(encoding: Game.Settings()),
                                       keyFifths: 0, piece: nil)), at: seconds)
    }

    /// A question on `pitch` (or one of several asked together); returns its id.
    @discardableResult
    mutating func shown(_ pitch: Pitch, at seconds: Double, group: UUID? = nil, groupSize: Int? = nil) -> UUID {
        let id = UUID()
        add(.questionShown(QuestionShown(round: round, question: id, index: shownCount, clef: "treble",
                                         pitch: LoggedPitch(pitch), written: LoggedPitch(pitch),
                                         position: Clef.treble.position(of: pitch), keyFifths: 0, printedAccidental: nil,
                                         octaveShift: 0, pieceNote: nil, pickChance: nil, naming: "letters", input: "buttons",
                                         hintsVisible: false, keyNamesVisible: false, group: group, groupSize: groupSize)),
            at: seconds)
        shownCount += 1
        return id
    }

    /// A question on `pitch` shown at `shownAt` and answered at `answeredAt`.
    mutating func ask(_ pitch: Pitch, at shownAt: Double, answeredAt: Double, correct: Bool = true, score: Int, streak: Int) {
        let question = shown(pitch, at: shownAt)
        answered(question, at: answeredAt, ms: Int(((answeredAt - shownAt) * 1000).rounded()), correct: correct,
                 score: score, streak: streak)
    }

    mutating func answered(_ question: UUID, at seconds: Double, ms: Int, correct: Bool, score: Int, streak: Int,
                           group: UUID? = nil) {
        add(.answerGiven(AnswerGiven(round: round, question: question, responseMs: ms, source: .click, letter: "C",
                                     accidental: 0, name: "C", pitch: nil, correct: correct, wrongOctave: nil, keystrokes: [],
                                     scoreAfter: score, streakAfter: streak, group: group)), at: seconds)
    }
}

@Suite struct RoundReplayTests {
    private let c5 = Pitch(.c, 5), d5 = Pitch(.d, 5), e5 = Pitch(.e, 5), f5 = Pitch(.f, 5)

    @Test func scoreStreaksMissesAndTimesComeFromTheAnswers() {
        var run = Run()
        run.started()
        run.ask(c5, at: 0, answeredAt: 1, score: 1, streak: 1)
        run.ask(d5, at: 1, answeredAt: 3, score: 2, streak: 2)
        run.ask(e5, at: 3, answeredAt: 3.9, correct: false, score: 2, streak: 0)
        run.ask(e5, at: 5.2, answeredAt: 6, score: 3, streak: 1)
        let onScreen = run.shown(f5, at: 6)
        let replay = RoundReplay(round: run.round, events: run.events)
        #expect(replay.started?.round == run.round && !replay.hasEnded)
        #expect(replay.score == 3 && replay.streak == 1 && replay.attempts == 4 && replay.bestStreak == 2)
        #expect(replay.misses == [StaffNote(clef: .treble, pitch: e5): 1])
        #expect(replay.responseTimes == [1, 2, 0.8])
        #expect(replay.averageResponseMs == 1267)
        #expect(replay.questionsShown == 5)
        #expect(replay.unansweredQuestion.map(\.question) == [onScreen])
        #expect(replay.activeMs == 6000 && replay.pausedMs == 0)
        #expect(replay.lastQuestionShownMs == 0)
        #expect(replay.lastEventTime == run.start.addingTimeInterval(6))
    }

    @Test func notesAskedTogetherTimeAsOneAndOnlyWhenAllRight() {
        var run = Run()
        run.started()
        let chord = UUID(), missedChord = UUID()
        let first = [run.shown(c5, at: 0, group: chord, groupSize: 2), run.shown(e5, at: 0, group: chord, groupSize: 2)]
        for id in first { run.answered(id, at: 2, ms: 2000, correct: true, score: 2, streak: 2, group: chord) }
        let second = [run.shown(d5, at: 2, group: missedChord, groupSize: 2), run.shown(f5, at: 2, group: missedChord, groupSize: 2)]
        run.answered(second[0], at: 3, ms: 1000, correct: true, score: 3, streak: 0, group: missedChord)
        run.answered(second[1], at: 3, ms: 1000, correct: false, score: 3, streak: 0, group: missedChord)
        let third = [run.shown(c5, at: 4.2, group: UUID(), groupSize: 2), run.shown(d5, at: 4.2, group: nil, groupSize: nil)]
        let replay = RoundReplay(round: run.round, events: run.events)
        #expect(replay.attempts == 4 && replay.score == 3 && replay.bestStreak == 2)
        #expect(replay.responseTimes == [2])
        #expect(replay.misses == [StaffNote(clef: .treble, pitch: f5): 1])
        // The latest question is the last group logged, not answered.
        #expect(replay.lastQuestion.map(\.question) == [third[1]])
        #expect(replay.unansweredQuestion.count == 1)
    }

    @Test func roundTimeLeavesOutPausesAndTheTimeAfterACrash() {
        var run = Run()
        run.started()
        let first = run.shown(c5, at: 0)
        run.answered(first, at: 4, ms: 4000, correct: true, score: 1, streak: 1)
        let second = run.shown(d5, at: 4)
        run.add(.roundPaused(RoundPaused(round: run.round, question: second, via: .button, activeMs: 9_000)), at: 9)
        run.add(.roundResumed(RoundResumed(round: run.round, question: second, via: .button, pausedMs: 10_000)), at: 19)
        run.answered(second, at: 22, ms: 8000, correct: true, score: 2, streak: 2)
        run.shown(e5, at: 22)
        run.add(.appActivity(AppActivity(active: false)), at: 23)
        // Crashed; back an hour later.
        var replay = RoundReplay(round: run.round, events: run.events)
        #expect(replay.activeMs == 13_000 && replay.pausedMs == 10_000)
        #expect(replay.lastQuestionShownMs == 1000)

        run.relaunch(after: 3600)
        replay = RoundReplay(round: run.round, events: run.events)
        #expect(replay.activeMs == 13_000, "the time since the crash isn't round time")
        run.add(.roundRestored(RoundRestored(round: run.round, activeMs: 13_000, unansweredQuestion: nil)), at: 3600)
        run.add(.roundResumed(RoundResumed(round: run.round, question: nil, via: .key, pausedMs: 5000)), at: 3605)
        let again = run.shown(e5, at: 3605)
        run.answered(again, at: 3607, ms: 2000, correct: true, score: 3, streak: 3)
        run.add(.windowResized(WindowResized(size: Size(width: 900, height: 700))), at: 3610)
        replay = RoundReplay(round: run.round, events: run.events)
        #expect(replay.activeMs == 13_000 + 5_000 && replay.pausedMs == 15_000)
        #expect(!replay.resumedAfterRestoreWithoutAnswer)
        #expect(replay.lastEventTime == run.start.addingTimeInterval(3610))
    }

    @Test func aPauseGoingOnAtTheCrashCountsUpToTheLastEvent() {
        var run = Run()
        run.started()
        run.ask(c5, at: 0, answeredAt: 2, score: 1, streak: 1)
        let onScreen = run.shown(d5, at: 2)
        run.add(.roundPaused(RoundPaused(round: run.round, question: onScreen, via: .appSwitch, activeMs: 3_000)), at: 3)
        run.add(.appActivity(AppActivity(active: false)), at: 3)
        run.add(.appActivity(AppActivity(active: true)), at: 8)
        let replay = RoundReplay(round: run.round, events: run.events)
        #expect(replay.activeMs == 3_000 && replay.pausedMs == 5_000)
        #expect(replay.lastQuestionShownMs == 1_000 && replay.lastQuestionPausedMs == 5_000)
        #expect(replay.unansweredQuestion.map(\.question) == [onScreen])
    }

    @Test func aResumeAfterARestoreWithNoAnswerIsNoted() {
        var run = Run()
        run.started()
        run.ask(c5, at: 0, answeredAt: 1, score: 1, streak: 1)
        let onScreen = run.shown(d5, at: 1)
        run.relaunch(after: 600)
        run.add(.roundRestored(RoundRestored(round: run.round, activeMs: 1_000, unansweredQuestion: onScreen)), at: 600)
        #expect(!RoundReplay(round: run.round, events: run.events).resumedAfterRestoreWithoutAnswer)
        run.add(.roundResumed(RoundResumed(round: run.round, question: nil, via: .button, pausedMs: 2_000)), at: 602)
        run.shown(d5, at: 602)
        #expect(RoundReplay(round: run.round, events: run.events).resumedAfterRestoreWithoutAnswer)
        // Another crash, another restore: it's the latest that counts.
        run.relaunch(after: 900)
        run.add(.roundRestored(RoundRestored(round: run.round, activeMs: 1_500, unansweredQuestion: nil)), at: 900)
        #expect(!RoundReplay(round: run.round, events: run.events).resumedAfterRestoreWithoutAnswer)
    }

    @Test func otherRoundsAndAnEndAreNoticed() {
        var run = Run()
        run.started()
        run.ask(c5, at: 0, answeredAt: 1, score: 1, streak: 1)
        run.add(.answerGiven(AnswerGiven(round: UUID(), question: UUID(), responseMs: 1, source: .click, letter: "C",
                                         accidental: 0, name: "C", pitch: nil, correct: true, wrongOctave: nil,
                                         keystrokes: [], scoreAfter: 9, streakAfter: 9)), at: 2)
        var replay = RoundReplay(round: run.round, events: run.events)
        #expect(replay.attempts == 1 && replay.score == 1 && !replay.hasEnded)
        run.add(.roundEnded(RoundEnded(round: run.round, reason: .stopped, durationMs: 2000, score: 1, attempts: 1,
                                       bestStreak: 1, averageResponseMs: 1000, notesToReview: [])), at: 2)
        replay = RoundReplay(round: run.round, events: run.events)
        #expect(replay.hasEnded)
    }
}

// MARK: - The dashboard

@Suite struct RestoredRoundProgressTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    private let now = usageTestTime("2026-11-05T15:00:00.000Z")

    private func report(_ events: [LoggedEvent]) -> ProgressReport {
        // As the log reads them: in time order.
        let sorted = events.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
        return ProgressAnalyzer.report(from: sorted, filter: ProgressFilter(range: .week, clef: .all), now: now,
                                       calendar: calendar)
    }

    /// A round started at 09:00 that crashed after two answers, the second one's note still on
    /// screen, and came back at the next launch two hours later.
    private func restoredRun() -> Run {
        var run = Run()
        run.started()
        run.ask(Pitch(.c, 5), at: 0, answeredAt: 2, score: 1, streak: 1)
        run.ask(Pitch(.g, 4), at: 2, answeredAt: 5, correct: false, score: 1, streak: 0)
        let onScreen = run.shown(Pitch(.d, 5), at: 6.2)
        run.relaunch(after: 7200)
        run.add(.roundRestored(RoundRestored(round: run.round, activeMs: 6_000, unansweredQuestion: onScreen)), at: 7200)
        run.add(.roundResumed(RoundResumed(round: run.round, question: nil, via: .button, pausedMs: 4_000)), at: 7204)
        run.ask(Pitch(.d, 5), at: 7204, answeredAt: 7206, score: 2, streak: 1)
        return run
    }

    @Test func aRoundThatCameBackIsOneRoundWithoutTheGap() throws {
        var run = restoredRun()
        // Still going: the round time so far, not the hours since it started.
        var week = report(run.events)
        #expect(week.totals.rounds == 1 && week.totals.answers == 3 && week.totals.correct == 2)
        #expect(week.totals.practiceSeconds == 8)
        let going = try #require(week.recentRounds.first)
        #expect(going.started == run.start && going.durationMs == 8_000 && going.endReason == nil)
        // The note asked again doesn't follow on from itself.
        #expect(week.responseTimes.byPreviousNote.first { $0.distance == .samePlace }?.answers == 0)

        run.add(.roundEnded(RoundEnded(round: run.round, reason: .stopped, durationMs: 9_000, pausedMs: 4_000, score: 2,
                                       attempts: 3, bestStreak: 1, averageResponseMs: 2000,
                                       notesToReview: ["treble.G4"])), at: 7207)
        week = report(run.events)
        #expect(week.totals.rounds == 1 && week.totals.practiceSeconds == 9)
        let ended = try #require(week.recentRounds.first)
        #expect(ended.started == run.start && ended.durationMs == 9_000 && ended.endReason == .stopped)
        #expect(ended.score == 2 && ended.attempts == 3)
        // Its time goes on the day it started.
        #expect(week.days.first { calendar.isDate($0.day, inSameDayAs: run.start) }?.practiceSeconds == 9)
    }

    @Test func anInterruptedRoundEndsAtItsLastEvent() throws {
        var run = Run()
        run.started()
        run.ask(Pitch(.c, 5), at: 0, answeredAt: 2, score: 1, streak: 1)
        run.shown(Pitch(.e, 5), at: 2)
        run.relaunch(after: 3600)
        // Written at the later launch, timed at the round's last event.
        var end = RoundEnded(round: run.round, reason: .interrupted, durationMs: 2_000, score: 1, attempts: 1, bestStreak: 1,
                             averageResponseMs: 2000, notesToReview: [])
        end.recordedAt = run.start.addingTimeInterval(3600)
        run.add(.roundEnded(end), at: 2)
        let week = report(run.events)
        let round = try #require(week.recentRounds.first)
        #expect(week.totals.rounds == 1 && week.totals.practiceSeconds == 2)
        #expect(round.endReason == .interrupted && round.durationMs == 2_000 && round.score == 1 && round.attempts == 1)
    }
}
