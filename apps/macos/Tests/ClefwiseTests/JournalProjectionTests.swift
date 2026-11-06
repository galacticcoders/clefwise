import Foundation
import Testing
@testable import Clefwise

// Folding a journal's runs into note stats and best scores (spec/practice-journal.md, "Reading"):
// rounds played on a real `Game`, then folded from its events, or from the journal its log is
// brought into, must give exactly what `Game` saved as it went.

@MainActor
@Suite final class JournalProjectionTests: GameTestBench {
    /// Note stats and best scores as `game` saved them in the defaults.
    private var saved: (noteStats: [String: NoteStat], bestScores: [String: Int]) {
        let noteStats = defaults.data(forKey: "noteStats")
            .flatMap { try? JSONDecoder().decode([String: NoteStat].self, from: $0) } ?? [:]
        return (noteStats, storedBestScores() ?? [:])
    }

    /// Names whatever's asked right: each note asked together by its name, a note on its own on the
    /// piano.
    private func nameRight(on game: Game) {
        if let group = game.group {
            for question in group.questions { game.answer(question.pitch.letter, question.pitch.accidental) }
        } else if let question = game.question {
            game.answer(question.pitch)
        }
    }

    private func right(_ count: Int, on game: Game) {
        for _ in 0..<count where game.phase == .playing && !game.isShowingMiss {
            nameRight(on: game)
        }
    }

    /// Names the note asked wrong, or of notes asked together the first.
    private func wrong(on game: Game) {
        if let group = game.group {
            for (offset, question) in group.questions.enumerated() {
                let letter = offset == 0 ? NoteLetter(rawValue: (question.pitch.letter.rawValue + 1) % 7)! : question.pitch.letter
                game.answer(letter, question.pitch.accidental)
            }
        } else {
            game.answer(Pitch(.c, 1))
        }
    }

    private func runOutOfTime(_ game: Game) {
        game.tick(at: .now + .seconds(61))
    }

    private func openingBalances(in events: [LoggedEvent]) -> [StatsSnapshot] {
        events.compactMap { if case .statsSnapshot(let snapshot) = $0.event { snapshot } else { nil } }
    }

    @Test func roundsOfEveryKindFoldToWhatGameSaved() async throws {
        let firstSetup = Game.bestScoreKey(for: game.settings)

        // Sprints on random notes: run out of time, stopped below the best, a tie, abandoned by
        // starting over, quit.
        game.start()
        right(5, on: game)
        wrong(on: game)
        runOutOfTime(game)
        game.start()
        right(3, on: game)
        game.stop()
        game.start()
        right(5, on: game)
        game.stop()
        game.start()
        right(7, on: game)
        game.start()
        right(6, on: game)
        runOutOfTime(game)
        game.start()
        right(9, on: game)
        game.appWillTerminate()

        // Another setup: the bass clef on the piano.
        game.settings.clefChoice = .bass
        game.settings.answerInput = .piano
        let secondSetup = Game.bestScoreKey(for: game.settings)
        game.start()
        right(4, on: game)
        game.stop()

        // A sprint naming nothing right sets no best score for its setup.
        game.settings.key = .fixed(KeySignature(fifths: 1))
        let thirdSetup = Game.bestScoreKey(for: game.settings)
        game.start()
        wrong(on: game)
        runOutOfTime(game)

        // A long practice round, so recent results overflow, with a miss in the middle.
        game.settings.clefChoice = .treble
        game.settings.answerInput = .buttons
        game.settings.key = .fixed(.cMajor)
        game.settings.mode = .practice
        game.start()
        right(40, on: game)
        wrong(on: game)
        try await waitUntil { !game.isShowingMiss }
        right(60, on: game)
        game.stop()

        // A sprint on a piece: its notes count, its score doesn't.
        game.settings.mode = .sprint
        game.settings.piece.hand = .both
        game.openPiece(at: try #require(Fixtures.url("bar-view.musicxml")))
        game.start()
        right(8, on: game)
        runOutOfTime(game)

        // Chords named together, one note of the first named wrong.
        game.settings.mode = .practice
        game.settings.piece.chords = .together
        game.settings.piece.startBar = 3
        game.start()
        #expect(game.group?.questions.count == 4)
        wrong(on: game)
        try await waitUntil { !game.isShowingMiss }
        right(4, on: game)
        game.stop()

        let stored = saved
        // The rounds did what they're here for.
        #expect(stored.bestScores == [firstSetup: 6, secondSetup: 4])
        #expect(stored.bestScores[thirdSetup] == nil)
        #expect(stored.noteStats.values.contains { $0.attempts > 8 && $0.recent.count == 8 })
        let answers = recorder.events.compactMap { if case .answerGiven(let answer) = $0.event { answer } else { nil } }
        #expect(answers.contains { $0.group != nil && !$0.correct } && answers.contains { $0.group != nil && $0.correct })

        let runs = LogImport.runs(in: recorder.events)
        #expect(runs.count == 11)
        let projection = JournalProjection.fold(openingBalances: openingBalances(in: recorder.events), runs: runs)
        #expect(projection.noteStats == stored.noteStats)
        #expect(projection.bestScores == stored.bestScores)
        #expect(projection.runsRead == 11)
    }

    @Test func theOpeningBalanceCarriesOnThroughTheJournalsFiles() async throws {
        // Stats from before the usage log: the next launch records them as its opening balance.
        let setup = Game.bestScoreKey(for: game.settings)
        let before: [String: NoteStat] = [
            "treble.E4": NoteStat(attempts: 20, correct: 15, recent: [true, false, true, true, false, true, true, true]),
            "treble.G4": NoteStat(attempts: 9, correct: 9, recent: [true, true, true, true, true, true, true, true]),
            "bass.C2": NoteStat(attempts: 4, correct: 1, recent: [false, false, true, false]),
        ]
        defaults.removeObject(forKey: "usageLogStarted")
        defaults.set(try JSONEncoder().encode(before), forKey: "noteStats")
        defaults.set(try JSONEncoder().encode([setup: 3, "bass.staff.piano": 50]), forKey: "bestScores")
        let log = MemoryUsageRecorder()
        let game = relaunch(recorder: log)
        game.settings.isMuted = true
        #expect(openingBalances(in: log.events).first?.noteStats == before)

        // Rounds start a few milliseconds apart, as the journal orders runs by their start.
        func play(_ round: () async throws -> Void) async throws {
            try await Task.sleep(for: .milliseconds(3))
            try await round()
        }
        try await play { // a tie with the best from before
            game.start()
            right(3, on: game)
            game.stop()
        }
        try await play { // beats it
            game.start()
            right(4, on: game)
            wrong(on: game)
            runOutOfTime(game)
        }
        try await play { // practice, a miss among many right
            game.settings.mode = .practice
            game.start()
            right(30, on: game)
            wrong(on: game)
            try await waitUntil { !game.isShowingMiss }
            right(40, on: game)
            game.stop()
        }
        let stored = saved
        #expect(stored.bestScores == [setup: 4, "bass.staff.piano": 50])
        #expect(stored.noteStats["bass.C2"] == before["bass.C2"])

        // Straight from the events…
        let fromEvents = JournalProjection.fold(openingBalances: openingBalances(in: log.events),
                                                runs: LogImport.runs(in: log.events))
        #expect(fromEvents.noteStats == stored.noteStats && fromEvents.bestScores == stored.bestScores)

        // …and from the journal the log is brought into, with files a reader must leave out.
        let temporary = UsageTestFolder()
        let usage = temporary.url.appendingPathComponent("Usage", isDirectory: true)
        try FileManager.default.createDirectory(at: usage, withIntermediateDirectories: true)
        try log.events.reduce(into: Data()) { $0 += try $1.encodedLine() }
            .write(to: usage.appendingPathComponent("usage-2026-11-06.jsonl"))
        let journal = FolderJournal(folder: temporary.url.appendingPathComponent("Journal", isDirectory: true))
        let summary = try LogImport.bringInNow(
            usageLog: usage, pieceLibrary: temporary.url.appendingPathComponent("Pieces", isDirectory: true),
            device: UUID(), launch: AppLaunched(appVersion: "1", build: "1", osVersion: "26", model: "Mac", locale: "en_GB",
                                                timeZone: "UTC", screen: nil),
            into: journal)
        #expect(summary.runsWritten == 3 && summary.eventsWritten == 1)

        let folder = try #require(journal.folder)
        let first = try #require(journal.contents().first { $0.key.hasPrefix("runs/") })
        // A sync service's conflicted copy of a run: its name doesn't fit.
        try first.value.write(to: folder.appendingPathComponent(first.key.replacingOccurrences(of: ".jsonl", with: " (conflicted copy).jsonl")))
        // A run still arriving: no `roundEnded` yet.
        let arriving = log.events.first { if case .roundStarted = $0.event { true } else { false } }!
        let cutShort = try #require(String(data: first.value, encoding: .utf8)?.split(separator: "\n").prefix(5)
            .joined(separator: "\n"))
        let arrivingID = UUID()
        try Data((cutShort + "\n").utf8).write(to: folder.appendingPathComponent(
            JournalLayout.runPath(startedAt: arriving.time.addingTimeInterval(3600), run: arrivingID)))

        let fromFiles = JournalProjection.read(journal: folder)
        #expect(fromFiles.noteStats == stored.noteStats)
        #expect(fromFiles.bestScores == stored.bestScores)
        #expect(fromFiles.runsRead == 3 && fromFiles.runsSkipped == 1 && fromFiles.unreadableLines == 0)
    }

    @Test func secondDevicesOpeningBalanceAddsToTheFirst() {
        var projection = JournalProjection()
        projection.apply(StatsSnapshot(reason: "beforeUsageLog",
                                       noteStats: ["treble.E4": NoteStat(attempts: 6, correct: 5, recent: [true, true, false, true, true, true])],
                                       bestScores: ["treble.staff": 10, "bass.staff": 4]))
        projection.apply(StatsSnapshot(reason: "beforeUsageLog",
                                       noteStats: ["treble.E4": NoteStat(attempts: 3, correct: 1, recent: [false, true, false]),
                                                   "treble.F4": NoteStat(attempts: 1, correct: 1, recent: [true])],
                                       bestScores: ["treble.staff": 8, "bass.staff": 7]))
        #expect(projection.noteStats == [
            "treble.E4": NoteStat(attempts: 9, correct: 6, recent: [true, false, true, true, true, false, true, false]),
            "treble.F4": NoteStat(attempts: 1, correct: 1, recent: [true]),
        ])
        #expect(projection.bestScores == ["treble.staff": 10, "bass.staff": 7])
    }
}
