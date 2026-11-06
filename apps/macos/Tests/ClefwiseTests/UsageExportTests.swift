import Foundation
import Testing
@testable import Clefwise

@Suite struct UsageExportTests {
    private let temporary = UsageTestFolder()
    private var logFolder: URL { temporary.url.appendingPathComponent("Usage", isDirectory: true) }
    private var destination: URL { temporary.url.appendingPathComponent("export.zip") }
    private let bucharest = TimeZone(identifier: "Europe/Bucharest")!
    private let start = usageTestTime("2026-10-30T16:00:00.000Z")
    private let pieceTitle = #"Für Elise, "WoO 59""#

    // MARK: - A scripted session

    private struct Script {
        let round1 = UUID(), round2 = UUID()
        let questions = (0..<4).map { _ in UUID() }
    }

    private func settings(_ change: (inout Game.Settings) -> Void) -> JSONValue {
        var settings = Game.Settings()
        change(&settings)
        return JSONValue(encoding: settings)
    }

    private func question(_ script: Script, _ number: Int, round: UUID, index: Int, _ pitch: Pitch, position: Int,
                          key: Int = 0, printed: Int? = nil, piece: PieceNoteRef? = nil, pickChance: Double? = nil,
                          naming: String = "letters", input: String, barStaves: [Int]? = nil) -> UsageEvent {
        .questionShown(QuestionShown(round: round, question: script.questions[number], index: index, clef: "treble",
                                     pitch: LoggedPitch(pitch), written: LoggedPitch(pitch), position: position,
                                     keyFifths: key, printedAccidental: printed, octaveShift: 0, pieceNote: piece,
                                     pickChance: pickChance, naming: naming, input: input,
                                     hintsVisible: false, keyNamesVisible: input == "piano",
                                     barView: piece.map { _ in barStaves != nil }, barStaves: barStaves))
    }

    private func answer(_ script: Script, _ number: Int, round: UUID, ms: Int, source: AnswerSource,
                        _ letter: String, _ accidental: Int, name: String, piano: Pitch? = nil, correct: Bool,
                        wrongOctave: Bool? = nil, keys: [Keystroke] = [], score: Int, streak: Int) -> UsageEvent {
        .answerGiven(AnswerGiven(round: round, question: script.questions[number], responseMs: ms, source: source,
                                 letter: letter, accidental: accidental, name: name, pitch: piano.map(LoggedPitch.init),
                                 correct: correct, wrongOctave: wrongOctave, keystrokes: keys,
                                 scoreAfter: score, streakAfter: streak))
    }

    /// A sprint typed in G major, a stretch in another app, then a piece answered on the piano.
    private func recordSession(into log: UsageLog, clock: UsageTestClock) -> Script {
        let script = Script()
        let piece = PieceContext(title: pieceTitle, path: "/Users/me/Für Elise.musicxml", part: "Piano", partIndex: 0,
                                 hand: "right", order: "inOrder", startBar: 9, oneNotePerChord: false,
                                 noteCount: 20, measureCount: 103)
        let events: [(Double, UsageEvent)] = [
            (0, .appLaunched(AppLaunched(appVersion: "0.1.0", build: "7", osVersion: "26.5", model: "Mac15,12",
                                         locale: "en_GB", timeZone: "Europe/Bucharest", screen: nil))),
            (0, .appActivity(AppActivity(active: true))),
            (1, .settingChanged(SettingChanged(setting: "answerInput", from: .string("buttons"), to: .string("keyboard")))),
            (2, .roundStarted(RoundStarted(round: script.round1, via: .button, settings: settings {
                $0.answerInput = .keyboard
                $0.key = .fixed(KeySignature(fifths: 1))
                $0.addsAccidentals = true
            }, keyFifths: 1, piece: nil))),
            (2, question(script, 0, round: script.round1, index: 0, Pitch(.f, 5, .sharp), position: 8, key: 1,
                         pickChance: 0.125, input: "keyboard")),
            (3.5, answer(script, 0, round: script.round1, ms: 1500, source: .typing, "F", 1, name: "F♯", correct: true,
                         keys: [Keystroke(key: "f", ms: 900, result: .typed), Keystroke(key: "x", ms: 1100, result: .rejected),
                                Keystroke(key: "#", ms: 1500, result: .submitted)],
                         score: 1, streak: 1)),
            (3.5, question(script, 1, round: script.round1, index: 1, Pitch(.b, 4, .flat), position: 4, key: 1,
                           printed: -1, pickChance: 0.25, input: "keyboard")),
            (5, answer(script, 1, round: script.round1, ms: 1500, source: .typing, "B", 0, name: "B", correct: false,
                       keys: [Keystroke(key: "b", ms: 1200, result: .typed), Keystroke(key: "Return", ms: 1500, result: .submitted)],
                       score: 1, streak: 0)),
            (6, .appActivity(AppActivity(active: false))),
            (10, .appActivity(AppActivity(active: true))),
            (62, .roundEnded(RoundEnded(round: script.round1, reason: .timeUp, durationMs: 60_000, score: 1, attempts: 2,
                                        bestStreak: 1, averageResponseMs: 1500, bestScore: 12, isNewBest: false,
                                        notesToReview: ["B♭4"]))),
            (70, .roundStarted(RoundStarted(round: script.round2, via: .key, settings: settings {
                $0.mode = .practice
                $0.naming = .solfege
                $0.answerInput = .piano
            }, keyFifths: 0, piece: piece))),
            (70, question(script, 2, round: script.round2, index: 0, Pitch(.e, 5), position: 7,
                          piece: PieceNoteRef(measure: 9, staff: 1, onset: 24, chord: 46, symbolIndex: 0), naming: "solfege",
                          input: "piano", barStaves: [1, 2])),
            (71.2, answer(script, 2, round: script.round2, ms: 1200, source: .piano, "E", 0, name: "Mi", piano: Pitch(.e, 4),
                          correct: false, wrongOctave: true, score: 0, streak: 0)),
            (71.2, question(script, 3, round: script.round2, index: 1, Pitch(.d, 5, .sharp), position: 6, printed: 1,
                            piece: PieceNoteRef(measure: 9, staff: 1, onset: 24.5, chord: 47), naming: "solfege", input: "piano")),
            (72, answer(script, 3, round: script.round2, ms: 800, source: .piano, "D", 1, name: "Re♯", piano: Pitch(.d, 5, .sharp),
                        correct: true, wrongOctave: false, score: 1, streak: 1)),
            (80, .roundEnded(RoundEnded(round: script.round2, reason: .pieceComplete, durationMs: 10_000, score: 1, attempts: 2,
                                        bestStreak: 1, averageResponseMs: 800, bestScore: nil, isNewBest: false,
                                        notesToReview: ["E5"]))),
            (85, .uiAction(UIAction(name: "exportUsage", detail: nil))),
            (90, .appTerminated(AppTerminated(sessionSeconds: 90))),
        ]
        for (seconds, event) in events {
            clock.now = start.addingTimeInterval(seconds)
            log.record(event)
        }
        return script
    }

    private func defaultsWithStats() throws -> UserDefaults {
        let defaults = InMemoryDefaults()
        var settings = Game.Settings()
        settings.naming = .solfege
        defaults.set(try JSONEncoder().encode(settings), forKey: "settings")
        var stat = NoteStat()
        stat.record(true)
        stat.record(false)
        defaults.set(try JSONEncoder().encode(["treble.F♯4": stat]), forKey: "noteStats")
        return defaults
    }

    // MARK: - Helpers

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(tool) \(arguments)")
        return String(decoding: data, as: UTF8.self)
    }

    /// Unzips `zip` and returns its top folder.
    private func unzip(_ zip: URL) throws -> URL {
        let target = temporary.url.appendingPathComponent("unzipped-\(UUID().uuidString)", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, target.path])
        let top = try FileManager.default.contentsOfDirectory(atPath: target.path)
        try #require(top.count == 1, "one top folder: \(top)")
        return target.appendingPathComponent(top[0], isDirectory: true)
    }

    /// RFC 4180 text as rows of fields.
    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if quoted {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.unicodeScalars.append(scalar)
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
            } else {
                switch scalar {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\r": break
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.unicodeScalars.append(scalar)
                }
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// A CSV file's header, and its rows by column name.
    private func table(_ url: URL) throws -> (header: [String], rows: [[String: String]]) {
        let rows = parseCSV(try String(contentsOf: url, encoding: .utf8))
        let header = try #require(rows.first)
        for row in rows.dropFirst() { #expect(row.count == header.count, "\(url.lastPathComponent): \(row)") }
        return (header, rows.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(header, $0)) })
    }

    private func exportScriptedSession() throws -> (script: Script, log: UsageLog, top: URL) {
        let clock = UsageTestClock(start)
        let log = UsageLog(folder: logFolder, clock: { clock.now }, timeZone: bucharest)
        let script = recordSession(into: log, clock: clock)
        try UsageExport.export(log, to: destination, defaults: try defaultsWithStats(), timeZone: bucharest)
        return (script, log, try unzip(destination))
    }

    // MARK: - Tests

    @Test func zipHoldsTheRawEventsTablesAndSavedValues() throws {
        let (_, log, top) = try exportScriptedSession()
        #expect(top.lastPathComponent.hasPrefix("Clefwise usage 20"))
        let files = try FileManager.default.subpathsOfDirectory(atPath: top.path).sorted()
        #expect(files == ["SCHEMA.md", "answers.csv", "best-scores.json", "events", "events/usage-2026-10-30.jsonl",
                          "note-stats.json", "piece-library.json", "rounds.csv", "sessions.csv", "settings.json"])
        // No library folder given: an empty list.
        #expect(try String(contentsOf: top.appendingPathComponent("piece-library.json"), encoding: .utf8) == "[]\n")
        // Nothing Mac-only (resource forks, ._ files) in the archive itself.
        let entries = try run("/usr/bin/zipinfo", ["-1", destination.path])
        #expect(!entries.contains("__MACOSX") && !entries.contains("/._"))

        let raw = try Data(contentsOf: log.folder.appendingPathComponent("usage-2026-10-30.jsonl"))
        #expect(try Data(contentsOf: top.appendingPathComponent("events/usage-2026-10-30.jsonl")) == raw)

        let settings = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: top.appendingPathComponent("settings.json"))) as? [String: Any])
        #expect(settings["naming"] as? String == "solfege")
        let stats = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: top.appendingPathComponent("note-stats.json"))) as? [String: Any])
        #expect((stats["treble.F♯4"] as? [String: Any])?["attempts"] as? Int == 2)
        #expect(try String(contentsOf: top.appendingPathComponent("best-scores.json"), encoding: .utf8) == "{}\n")
        #expect(try String(contentsOf: top.appendingPathComponent("settings.json"), encoding: .utf8).contains("\n  \""),
                "pretty-printed")

        let schema = try String(contentsOf: top.appendingPathComponent("SCHEMA.md"), encoding: .utf8)
        #expect(schema.hasPrefix("# Clefwise usage data\n\nExported "))
        #expect(schema.contains("(Europe/Bucharest): 19 events from 1 day files."))
    }

    @Test func answersJoinTheirQuestionAndRound() throws {
        let (script, log, top) = try exportScriptedSession()
        let (header, answers) = try table(top.appendingPathComponent("answers.csv"))
        #expect(header.prefix(4) == ["localTime", "time", "session", "round"])
        try #require(answers.count == 4)

        let typed = answers[0]
        #expect(typed["localTime"] == "2026-10-30 18:00:03.500")
        #expect(typed["time"] == "2026-10-30T16:00:03.500Z")
        #expect(typed["session"] == log.session.uuidString)
        #expect(typed["round"] == script.round1.uuidString)
        #expect(typed["question"] == script.questions[0].uuidString)
        let expected: [String: String] = [
            "questionIndex": "0", "clef": "treble", "pitch": "F♯5", "pitchMidi": "78", "written": "F♯5", "position": "8",
            "keyFifths": "1", "printedAccidental": "", "octaveShift": "0", "pieceBar": "", "pieceStaff": "",
            "barView": "", "barStaves": "",
            "naming": "letters", "input": "keyboard", "source": "typing", "answerLetter": "F", "answerAccidental": "1",
            "answerName": "F♯", "answerPitch": "", "answerMidi": "", "correct": "true", "wrongOctave": "",
            "responseMs": "1500", "keystrokes": "3", "rejectedKeystrokes": "1", "scoreAfter": "1", "streakAfter": "1",
            "hintsVisible": "false", "keyNamesVisible": "false", "pickChance": "0.125", "mode": "sprint",
            "clefChoice": "treble", "range": "staff", "keySetting": "1", "addsAccidentals": "true", "pieceTitle": "",
        ]
        for (column, value) in expected { #expect(typed[column] == value, "\(column)") }

        #expect(answers[1]["printedAccidental"] == "-1")
        #expect(answers[1]["correct"] == "false")
        #expect(answers[1]["rejectedKeystrokes"] == "0")

        let piano = answers[2]
        #expect(piano["pieceBar"] == "9" && piano["pieceStaff"] == "1")
        #expect(piano["answerPitch"] == "E4" && piano["answerMidi"] == "64" && piano["pitchMidi"] == "76")
        #expect(piano["wrongOctave"] == "true" && piano["correct"] == "false")
        #expect(piano["naming"] == "solfege" && piano["input"] == "piano" && piano["mode"] == "practice")
        #expect(piano["keySetting"] == "0" && piano["keystrokes"] == "0")
        #expect(piano["pieceTitle"] == pieceTitle)
        #expect(piano["barView"] == "true" && piano["barStaves"] == "1 2")
        #expect(answers[3]["answerName"] == "Re♯" && answers[3]["printedAccidental"] == "1")
        #expect(answers[3]["barView"] == "false" && answers[3]["barStaves"] == "")
    }

    @Test func roundsAndSessionsAreSummed() throws {
        let (script, log, top) = try exportScriptedSession()
        let rounds = try table(top.appendingPathComponent("rounds.csv")).rows
        try #require(rounds.count == 2)
        let sprint = rounds[0]
        #expect(sprint["round"] == script.round1.uuidString)
        #expect(sprint["startLocalTime"] == "2026-10-30 18:00:02.000" && sprint["startTime"] == "2026-10-30T16:00:02.000Z")
        #expect(sprint["endLocalTime"] == "2026-10-30 18:01:02.000" && sprint["endTime"] == "2026-10-30T16:01:02.000Z")
        let sprintExpected: [String: String] = [
            "via": "button", "mode": "sprint", "clefChoice": "treble", "range": "staff", "keySetting": "1", "keyFifths": "1",
            "addsAccidentals": "true", "naming": "letters", "answerInput": "keyboard", "pieceTitle": "", "endReason": "timeUp",
            "durationMs": "60000", "score": "1", "attempts": "2", "accuracy": "0.5", "bestStreak": "1",
            "averageResponseMs": "1500", "bestScore": "12", "isNewBest": "false", "notesToReview": "B♭4", "answers": "2",
        ]
        for (column, value) in sprintExpected { #expect(sprint[column] == value, "\(column)") }

        let piece = rounds[1]
        let pieceExpected: [String: String] = [
            "via": "key", "mode": "practice", "pieceTitle": pieceTitle, "piecePart": "Piano", "pieceHand": "right",
            "pieceOrder": "inOrder", "pieceStartBar": "9", "pieceOneNotePerChord": "false", "pieceNotes": "20",
            "endReason": "pieceComplete", "bestScore": "", "answers": "2",
        ]
        for (column, value) in pieceExpected { #expect(piece[column] == value, "\(column)") }

        let sessions = try table(top.appendingPathComponent("sessions.csv")).rows
        try #require(sessions.count == 1)
        let session = sessions[0]
        let sessionExpected: [String: String] = [
            "session": log.session.uuidString, "launchLocalTime": "2026-10-30 18:00:00.000",
            "launchTime": "2026-10-30T16:00:00.000Z", "quitTime": "2026-10-30T16:01:30.000Z",
            "durationSeconds": "90.0", "appVersion": "0.1.0", "build": "7", "osVersion": "26.5", "model": "Mac15,12",
            // Active 0–6 s, then 10–90 s.
            "foregroundSeconds": "86.0",
            "events": "19", "rounds": "2", "answers": "4", "correct": "2", "accuracy": "0.5",
        ]
        for (column, value) in sessionExpected { #expect(session[column] == value, "\(column)") }
    }

    @Test func csvQuotesWhatNeedsIt() throws {
        #expect(UsageExport.csvField("plain") == "plain")
        #expect(UsageExport.csvField("F♯4") == "F♯4")
        #expect(UsageExport.csvField("a,b") == #""a,b""#)
        #expect(UsageExport.csvField(#"say "hi""#) == #""say ""hi""""#)
        #expect(UsageExport.csvField("two\nlines") == "\"two\nlines\"")
        #expect(UsageExport.csvField("cr\r\nlf") == "\"cr\r\nlf\"")

        let (_, _, top) = try exportScriptedSession()
        let rounds = try Data(contentsOf: top.appendingPathComponent("rounds.csv"))
        #expect(!rounds.starts(with: [0xEF, 0xBB, 0xBF]), "no byte-order mark")
        let text = String(decoding: rounds, as: UTF8.self)
        #expect(text.contains(#","Für Elise, ""WoO 59""","#))
        #expect(text.contains("\r\n") && text.hasSuffix("\r\n"))
        #expect(text.utf8.count == rounds.count, "valid UTF-8")
    }

    @Test func schemaDescribesEveryColumnAndEvent() throws {
        let (_, _, top) = try exportScriptedSession()
        let schema = try String(contentsOf: top.appendingPathComponent("SCHEMA.md"), encoding: .utf8)
        for file in ["answers.csv", "rounds.csv", "sessions.csv"] {
            for column in try table(top.appendingPathComponent(file)).header {
                #expect(schema.contains("`\(column)`"), "\(file): \(column)")
            }
        }
        let types = ["appLaunched", "appTerminated", "appActivity", "windowResized", "settingChanged", "roundStarted",
                     "questionShown", "answerGiven", "inputIgnored", "roundEnded", "pieceOpened", "pieceOpenFailed",
                     "pieceClosed", "uiAction", "statsSnapshot"]
        for type in types { #expect(schema.contains("### `\(type)`"), "\(type)") }
    }

    @Test func toleratesACutOffLine() throws {
        let clock = UsageTestClock(start)
        let log = UsageLog(folder: logFolder, clock: { clock.now }, timeZone: bucharest)
        _ = recordSession(into: log, clock: clock)
        log.flush()
        let file = logFolder.appendingPathComponent("usage-2026-10-30.jsonl")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"schema":1,"type":"answerGi"#.utf8))
        try handle.close()

        try UsageExport.export(log, to: destination, defaults: InMemoryDefaults(), timeZone: bucharest)
        let top = try unzip(destination)
        #expect(try table(top.appendingPathComponent("answers.csv")).rows.count == 4)
        #expect(try Data(contentsOf: top.appendingPathComponent("events/usage-2026-10-30.jsonl")) == Data(contentsOf: file))
        let schema = try String(contentsOf: top.appendingPathComponent("SCHEMA.md"), encoding: .utf8)
        #expect(schema.contains("19 events from 1 day files, skipping 1 unreadable line."))
        #expect(try String(contentsOf: top.appendingPathComponent("settings.json"), encoding: .utf8) == "{}\n")
    }

    @Test func aJournalsSavedValuesComeFromItsNamespace() throws {
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        let defaults = try defaultsWithStats()
        let namespace = "journal.6f9619ff-8b86-4011-b42d-00c04fc964ff."
        defaults.set(try JSONEncoder().encode(["bass.staff": 7]), forKey: namespace + "bestScores")
        try UsageExport.export(UsageLog(folder: logFolder), to: destination, defaults: defaults, namespace: namespace)
        let top = try unzip(destination)
        #expect(try String(contentsOf: top.appendingPathComponent("best-scores.json"), encoding: .utf8)
                == "{\n  \"bass.staff\" : 7\n}\n")
        // Nothing saved in the journal's namespace yet: not the values under the plain keys.
        #expect(try String(contentsOf: top.appendingPathComponent("settings.json"), encoding: .utf8) == "{}\n")
        #expect(try String(contentsOf: top.appendingPathComponent("note-stats.json"), encoding: .utf8) == "{}\n")
    }

    @Test func replacesAnExistingFile() throws {
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        try Data("an older export".utf8).write(to: destination)
        let log = UsageLog(folder: logFolder)
        log.record(.uiAction(UIAction(name: "exportUsage", detail: nil)))
        try UsageExport.export(log, to: destination, defaults: InMemoryDefaults())
        let top = try unzip(destination)
        #expect(try table(top.appendingPathComponent("answers.csv")).rows.isEmpty)
        #expect(try table(top.appendingPathComponent("sessions.csv")).rows.count == 1)
    }

    @Test @MainActor func holdsThePieceLibrarysIndex() throws {
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        let library = PieceLibrary(folder: temporary.url.appendingPathComponent("Pieces", isDirectory: true))
        let score = temporary.url.appendingPathComponent("tune.musicxml")
        try Data("<score-partwise/>".utf8).write(to: score)
        let entry = try library.add(score, title: "Tune")
        try UsageExport.export(UsageLog(folder: logFolder), to: destination, defaults: InMemoryDefaults(),
                               libraryFolder: library.folder)
        let top = try unzip(destination)
        let exported = try Data(contentsOf: top.appendingPathComponent("piece-library.json"))
        #expect(exported == (try Data(contentsOf: PieceLibrary.indexURL(in: library.folder))))
        let pieces = try #require(try JSONSerialization.jsonObject(with: exported) as? [[String: Any]])
        #expect(pieces.count == 1 && pieces[0]["id"] as? String == entry.id.uuidString)
        #expect(pieces[0]["originalPath"] as? String == score.path)
    }

    @Test func roundsSayTheirPracticeLimit() throws {
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        let log = UsageLog(folder: logFolder)
        func round(_ change: (inout Game.Settings) -> Void) {
            var settings = Game.Settings()
            change(&settings)
            log.record(.roundStarted(RoundStarted(round: UUID(), via: .button, settings: JSONValue(encoding: settings),
                                                  keyFifths: 0, piece: nil)))
        }
        round { $0.mode = .practice; $0.practiceLimit = .notes; $0.practiceNotes = 250 }
        round { $0.mode = .practice; $0.practiceLimit = .time; $0.practiceMinutes = 15 }
        round { $0.mode = .practice }
        // A limit left in the settings means nothing to a sprint.
        round { $0.mode = .sprint; $0.practiceLimit = .time }
        try UsageExport.export(log, to: destination, defaults: InMemoryDefaults())
        let rows = try table(try unzip(destination).appendingPathComponent("rounds.csv")).rows
        #expect(rows.map { $0["practiceLimit"] } == ["notes", "time", "", ""])
        #expect(rows.map { $0["practiceTarget"] } == ["250", "15", "", ""])
    }

    @Test func emptyLogStillExports() throws {
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        try UsageExport.export(UsageLog(folder: logFolder), to: destination, defaults: InMemoryDefaults())
        let top = try unzip(destination)
        #expect(try FileManager.default.contentsOfDirectory(atPath: top.appendingPathComponent("events").path).isEmpty)
        #expect(try table(top.appendingPathComponent("rounds.csv")).header.first == "startLocalTime")
    }

    @Test func failureSaysWhatWentWrong() throws {
        let log = UsageLog(folder: logFolder)
        let nowhere = temporary.url.appendingPathComponent("missing folder/export.zip")
        let error = try #require(throws: UsageExportError.self) {
            try UsageExport.export(log, to: nowhere, defaults: InMemoryDefaults())
        }
        #expect(error.localizedDescription.hasPrefix("Couldn't export the usage data: couldn't save “export.zip”."))
        #expect(!FileManager.default.fileExists(atPath: nowhere.path))
    }
}

// MARK: - Rounds that came back after a crash

extension UsageExportTests {
    /// One round crashes and comes back at the next launch, so it spans two sessions; it belongs to
    /// the one it started in. Another crashes and can't come back: a third launch ends it as
    /// `interrupted`, timed at its last event.
    @Test func aRoundThatCameBackBelongsToTheSessionItStartedIn() throws {
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        let clock = UsageTestClock(start)
        let restored = UUID(), interrupted = UUID()
        let questions = (0..<5).map { _ in UUID() }
        func launch() -> UsageLog {
            let log = UsageLog(folder: logFolder, clock: { clock.now }, timeZone: bucharest)
            log.record(.appLaunched(AppLaunched(appVersion: "0.2.0", build: "8", osVersion: "26.5", model: "Mac15,12",
                                                locale: "en_GB", timeZone: "Europe/Bucharest", screen: nil)))
            return log
        }
        func shown(_ round: UUID, _ number: Int, index: Int) -> UsageEvent {
            .questionShown(QuestionShown(round: round, question: questions[number], index: index, clef: "treble",
                                         pitch: LoggedPitch(Pitch(.c, 5)), written: LoggedPitch(Pitch(.c, 5)), position: 5,
                                         keyFifths: 0, printedAccidental: nil, octaveShift: 0, pieceNote: nil, pickChance: 0.1,
                                         naming: "letters", input: "buttons", hintsVisible: false, keyNamesVisible: false))
        }
        func answer(_ round: UUID, _ number: Int, score: Int) -> UsageEvent {
            .answerGiven(AnswerGiven(round: round, question: questions[number], responseMs: 1000, source: .click, letter: "C",
                                     accidental: 0, name: "C", pitch: nil, correct: true, wrongOctave: nil, keystrokes: [],
                                     scoreAfter: score, streakAfter: score))
        }
        let practice = settings { $0.mode = .practice }

        let first = launch()
        first.record(.roundStarted(RoundStarted(round: restored, via: .button, settings: practice, keyFifths: 0, piece: nil)))
        first.record(shown(restored, 0, index: 0))
        clock.advance(2)
        first.record(answer(restored, 0, score: 1))
        first.record(shown(restored, 1, index: 1))
        first.flush()

        clock.advance(3600)
        let second = launch()
        second.record(.roundRestored(RoundRestored(round: restored, activeMs: 2_000, unansweredQuestion: questions[1])))
        clock.advance(5)
        second.record(.roundResumed(RoundResumed(round: restored, question: nil, via: .button, pausedMs: 5_000)))
        second.record(shown(restored, 2, index: 2))
        clock.advance(1)
        second.record(answer(restored, 2, score: 2))
        second.record(.roundEnded(RoundEnded(round: restored, reason: .stopped, durationMs: 3_000, pausedMs: 5_000, score: 2,
                                             attempts: 2, bestStreak: 2, averageResponseMs: 1000, bestScore: nil,
                                             isNewBest: false, notesToReview: [])))
        clock.advance(10)
        second.record(.roundStarted(RoundStarted(round: interrupted, via: .key, settings: practice, keyFifths: 0, piece: nil)))
        second.record(shown(interrupted, 3, index: 0))
        clock.advance(1)
        second.record(answer(interrupted, 3, score: 1))
        second.record(shown(interrupted, 4, index: 1))
        let lastEvent = clock.now
        second.flush()

        clock.advance(7200)
        let third = launch()
        var end = RoundEnded(round: interrupted, reason: .interrupted, durationMs: 1_000, score: 1, attempts: 1, bestStreak: 1,
                             averageResponseMs: 1000, bestScore: nil, isNewBest: false, notesToReview: [])
        end.recordedAt = clock.now
        third.record(.roundEnded(end), at: lastEvent)
        try UsageExport.export(third, to: destination, defaults: InMemoryDefaults(), timeZone: bucharest)
        let top = try unzip(destination)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rounds = try table(top.appendingPathComponent("rounds.csv")).rows
        #expect(rounds.count == 2)
        let back = try #require(rounds.first { $0["round"] == restored.uuidString })
        #expect(back["session"] == first.session.uuidString && back["startTime"] == iso.string(from: start))
        #expect(back["restores"] == "1" && back["answers"] == "2" && back["endReason"] == "stopped")
        #expect(back["durationMs"] == "3000" && back["pausedMs"] == "5000" && back["endRecordedTime"] == "")
        let lost = try #require(rounds.first { $0["round"] == interrupted.uuidString })
        #expect(lost["session"] == second.session.uuidString && lost["restores"] == "0")
        #expect(lost["endReason"] == "interrupted" && lost["endTime"] == iso.string(from: lastEvent))
        #expect(lost["endRecordedTime"] == iso.string(from: clock.now) && lost["answers"] == "1")

        let sessions = try table(top.appendingPathComponent("sessions.csv")).rows
        let bySession = Dictionary(uniqueKeysWithValues: sessions.compactMap { row in row["session"].map { ($0, row) } })
        let launches = [first, second, third].map { bySession[$0.session.uuidString] }
        #expect(launches.map { $0?["rounds"] } == ["1", "1", "0"])
        #expect(launches.map { $0?["restoredRounds"] } == ["0", "1", "0"])
        #expect(launches.map { $0?["answers"] } == ["1", "2", "0"])
        // The third launch starts at its launch, not at the earlier time its round end is timed at.
        #expect(launches[2]?["launchTime"] == iso.string(from: clock.now))
    }
}
