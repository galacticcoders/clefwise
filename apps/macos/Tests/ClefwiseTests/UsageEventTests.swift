import Foundation
import Testing
@testable import Clefwise

@Suite struct UsageEventTests {
    private func line(_ event: UsageEvent) throws -> (text: String, json: [String: Any], logged: LoggedEvent) {
        let logged = LoggedEvent(event, session: UUID(), sequence: 7)
        let data = try LoggedEvent.encoder.encode(logged)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (String(decoding: data, as: UTF8.self), json, logged)
    }

    @Test func payloadSitsNextToTheEnvelope() throws {
        let answer = AnswerGiven(
            round: UUID(), question: UUID(), responseMs: 1820, source: .typing,
            letter: "F", accidental: 1, name: "Fa♯", pitch: nil, correct: true, wrongOctave: nil,
            keystrokes: [Keystroke(key: "f", ms: 900, result: .typed), Keystroke(key: "a", ms: 1300, result: .typed),
                         Keystroke(key: "#", ms: 1820, result: .submitted)],
            scoreAfter: 3, streakAfter: 3)
        let (text, json, _) = try line(.answerGiven(answer))
        #expect(json["type"] as? String == "answerGiven")
        #expect(json["schema"] as? Int == LoggedEvent.schemaVersion)
        #expect(json["sequence"] as? Int == 7)
        #expect(json["responseMs"] as? Int == 1820)
        #expect(json["source"] as? String == "typing")
        #expect(json["name"] as? String == "Fa♯")
        #expect((json["keystrokes"] as? [Any])?.count == 3)
        #expect(!text.contains("\n"), "one event per line")
    }

    @Test func aPieceReopenedBySwitchingJournalsSaysSo() throws {
        let parts = [PartInfo(name: "Clarinet", notes: 40, measures: 16, staves: 1, skipped: 0)]
        let opened = PieceOpened(path: "/Scores/clarinet-tune.musicxml", title: "Clarinet Tune", via: .journalSwitch,
                                 parts: parts, libraryID: UUID(), restoredSettings: true)
        let failed = PieceOpenFailed(path: "/Scores/gone.musicxml", via: .journalSwitch, error: "The file is gone.")
        for event in [UsageEvent.pieceOpened(opened), .pieceOpenFailed(failed)] {
            let (text, json, logged) = try line(event)
            #expect(json["via"] as? String == "journalSwitch")
            #expect(try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data(text.utf8)).event == logged.event)
        }
    }

    @Test func timesKeepMilliseconds() throws {
        let (_, json, _) = try line(.appActivity(AppActivity(active: true)))
        let time = try #require(json["time"] as? String)
        #expect(time.contains("."), "fractional seconds: \(time)")
        #expect(time.hasSuffix("Z"))
    }

    @Test func linesDecodeBackToTheSameEvent() throws {
        let events: [UsageEvent] = [
            .appLaunched(AppLaunched(appVersion: "0.1.0", build: "1", osVersion: "26.5", model: "Mac15,12",
                                     locale: "en_GB", timeZone: "Europe/Bucharest", screen: Size(width: 1728, height: 1117))),
            .settingChanged(SettingChanged(setting: "naming", from: .string("letters"), to: .string("solfege"))),
            .roundStarted(RoundStarted(round: UUID(), via: .key, settings: JSONValue(encoding: Game.Settings()),
                                       keyFifths: 1, piece: nil)),
            .questionShown(QuestionShown(round: UUID(), question: UUID(), index: 0, clef: "treble",
                                         pitch: LoggedPitch(Pitch(.f, 6, .sharp)), written: LoggedPitch(Pitch(.f, 5, .sharp)),
                                         position: 8, keyFifths: 1, printedAccidental: nil, octaveShift: 1,
                                         pieceNote: PieceNoteRef(measure: 9, staff: 1, onset: 24, chord: 46, symbolIndex: 3),
                                         pickChance: nil, naming: "letters", input: "piano",
                                         hintsVisible: false, keyNamesVisible: true, barView: true, barStaves: [1, 2])),
            .roundEnded(RoundEnded(round: UUID(), reason: .pieceComplete, durationMs: 61_000, score: 38, attempts: 38,
                                   bestStreak: 38, averageResponseMs: 950, bestScore: nil, isNewBest: false, notesToReview: [])),
            .statsSnapshot(StatsSnapshot(reason: "test", noteStats: ["treble.C4": NoteStat()], bestScores: ["treble.staff": 12])),
        ]
        for event in events {
            let (_, _, logged) = try line(event)
            let data = try LoggedEvent.encoder.encode(logged)
            let decoded = try LoggedEvent.decoder.decode(LoggedEvent.self, from: data)
            #expect(decoded.event == logged.event)
            #expect([decoded.id, decoded.session] == [logged.id, logged.session])
            #expect(decoded.sequence == logged.sequence && decoded.schema == logged.schema)
            // Times are written to the millisecond.
            #expect(abs(decoded.time.timeIntervalSince(logged.time)) < 0.001)
        }
    }

    @Test func barViewFieldsAreLeftOutWithoutAValue() throws {
        var shown = QuestionShown(round: UUID(), question: UUID(), index: 0, clef: "bass",
                                  pitch: LoggedPitch(Pitch(.c, 3)), written: LoggedPitch(Pitch(.c, 3)), position: 3,
                                  keyFifths: 0, printedAccidental: nil, octaveShift: 0, pieceNote: nil, pickChance: 0.5,
                                  naming: "letters", input: "buttons", hintsVisible: false, keyNamesVisible: false)
        var json = try line(.questionShown(shown)).json
        #expect(json["barView"] == nil && json["barStaves"] == nil)

        shown.pieceNote = PieceNoteRef(measure: 2, staff: 2, onset: 4, chord: 7, symbolIndex: 1)
        shown.barView = true
        shown.barStaves = [1, 2]
        json = try line(.questionShown(shown)).json
        #expect(json["barView"] as? Bool == true)
        #expect(json["barStaves"] as? [Int] == [1, 2])
        #expect((json["pieceNote"] as? [String: Any])?["symbolIndex"] as? Int == 1)

        // A piece without a bar layout: shown on its own, nowhere drawn.
        shown.pieceNote = PieceNoteRef(measure: 2, staff: 2, onset: 4, chord: 7)
        shown.barView = false
        shown.barStaves = nil
        json = try line(.questionShown(shown)).json
        #expect(json["barView"] as? Bool == false && json["barStaves"] == nil)
        #expect((json["pieceNote"] as? [String: Any])?["symbolIndex"] == nil)
    }

    @Test func settingsBecomePlainJSON() {
        guard case .object(let settings) = JSONValue(encoding: Game.Settings()) else {
            Issue.record("settings should encode to an object")
            return
        }
        #expect(settings["naming"] == .string("letters"))
        #expect(settings["isMuted"] == .bool(false))
    }

    // MARK: - The practice journal's additions

    @Test func roundRestoredRoundTripsAndLeavesOutAMissingQuestion() throws {
        var restored = RoundRestored(round: UUID(), activeMs: 42_500, unansweredQuestion: nil)
        var (text, json, logged) = try line(.roundRestored(restored))
        #expect(json["type"] as? String == "roundRestored")
        #expect(json["activeMs"] as? Int == 42_500)
        #expect(json["round"] as? String == restored.round.uuidString)
        #expect(json["unansweredQuestion"] == nil && !text.contains("unansweredQuestion"))
        #expect(try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data(text.utf8)).event == logged.event)

        restored.unansweredQuestion = UUID()
        (text, json, logged) = try line(.roundRestored(restored))
        #expect(json["unansweredQuestion"] as? String == restored.unansweredQuestion?.uuidString)
        #expect(try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data(text.utf8)).event == .roundRestored(restored))
    }

    @Test func interruptedEndSaysWhenItWasWritten() throws {
        var ended = RoundEnded(round: UUID(), reason: .interrupted, durationMs: 95_000, score: 30, attempts: 32,
                               bestStreak: 12, averageResponseMs: 1400, bestScore: nil, isNewBest: false,
                               notesToReview: ["F♯4"])
        var json = try line(.roundEnded(ended)).json
        #expect(json["reason"] as? String == "interrupted")
        #expect(json["recordedAt"] == nil, "left out without a value")

        ended.recordedAt = usageTestTime("2026-11-05T09:31:12.348Z")
        let (text, written, _) = try line(.roundEnded(ended))
        json = written
        // Written like every other time in the log.
        #expect(json["recordedAt"] as? String == "2026-11-05T09:31:12.348Z")
        let decoded = try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data(text.utf8))
        guard case .roundEnded(let back) = decoded.event else {
            Issue.record("should decode as roundEnded")
            return
        }
        #expect(back.reason == .interrupted)
        let recordedAt = try #require(back.recordedAt)
        #expect(abs(recordedAt.timeIntervalSince(usageTestTime("2026-11-05T09:31:12.348Z"))) < 0.001)
        var withoutTime = back
        withoutTime.recordedAt = ended.recordedAt
        #expect(withoutTime == ended)
    }

    @Test func pieceLinesFromBeforeTheJournalStillDecode() throws {
        // A round on a piece logged before `chords`, `libraryID` and the journal's fields existed.
        let text = #"{"id":"0E3A8E52-6B8B-4E59-9C51-0E7B3E2C6B11","keyFifths":1,"piece":{"hand":"right","measureCount":4,"noteCount":6,"oneNotePerChord":false,"order":"inOrder","part":"Piano","partIndex":0,"path":"/Users/me/Tune.musicxml","startBar":1,"title":"Tune"},"round":"5C1D2E3F-4A5B-4C6D-8E7F-9A0B1C2D3E4F","schema":1,"sequence":3,"session":"A1B2C3D4-E5F6-4711-8899-AABBCCDDEEFF","settings":{},"time":"2026-11-01T10:00:00.000Z","type":"roundStarted","via":"button"}"#
        let decoded = try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data(text.utf8))
        guard case .roundStarted(let started) = decoded.event, let piece = started.piece else {
            Issue.record("should decode as a piece round")
            return
        }
        #expect(piece.title == "Tune" && piece.noteCount == 6)
        #expect(piece.chords == nil && piece.libraryID == nil)
        #expect(piece.id == nil && piece.file == nil && piece.staves == nil)
        #expect(decoded.id.uuidString == "0E3A8E52-6B8B-4E59-9C51-0E7B3E2C6B11")
    }

    @Test func pieceJournalFieldsRoundTripAndAreLeftOutWithoutAValue() throws {
        var piece = PieceContext(title: "Tune", path: "/Users/me/Tune.musicxml", part: "Piano", partIndex: 0,
                                 hand: "both", order: "inOrder", startBar: 1, oneNotePerChord: false, noteCount: 40,
                                 measureCount: 16, chords: "eachNote", libraryID: UUID())
        var started = RoundStarted(round: UUID(), via: .button, settings: .object([:]), keyFifths: 1, piece: piece)
        var pieceJSON = try #require(try line(.roundStarted(started)).json["piece"] as? [String: Any])
        #expect(pieceJSON["id"] == nil && pieceJSON["file"] == nil && pieceJSON["staves"] == nil)

        piece.id = String(repeating: "ab", count: 32)
        piece.file = String(repeating: "cd", count: 32)
        piece.staves = 2
        started.piece = piece
        let (text, json, logged) = try line(.roundStarted(started))
        pieceJSON = try #require(json["piece"] as? [String: Any])
        #expect(pieceJSON["id"] as? String == piece.id)
        #expect(pieceJSON["file"] as? String == piece.file)
        #expect(pieceJSON["staves"] as? Int == 2)
        // The piece's id sits inside `piece`, apart from the event's own.
        #expect(json["id"] as? String == logged.id.uuidString)
        #expect(try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data(text.utf8)).event == .roundStarted(started))
    }

    @Test func libraryEventsRoundTripWithTheSpecsFieldNames() throws {
        let first = String(repeating: "ab", count: 32), second = String(repeating: "cd", count: 32)
        var added = PieceAdded(piece: first, title: "Tune", fileName: "Tune.mxl")
        let events: [(UsageEvent, String, [String: Any])] = [
            (.pieceAdded(added), "pieceAdded", ["piece": first, "title": "Tune", "fileName": "Tune.mxl"]),
            (.pieceRevised(PieceRevised(piece: first, file: second, title: "Tune, revised")), "pieceRevised",
             ["piece": first, "file": second, "title": "Tune, revised"]),
            (.pieceRemoved(PieceRemoved(piece: first)), "pieceRemoved", ["piece": first]),
        ]
        let envelope: Set<String> = ["schema", "type", "id", "time", "session", "sequence"]
        for (event, type, fields) in events {
            let (text, json, logged) = try line(event)
            #expect(json["type"] as? String == type)
            // Exactly the spec's fields next to the envelope: optional ones without a value are left out.
            #expect(Set(json.keys).subtracting(envelope) == Set(fields.keys), "\(type)")
            for (key, value) in fields { #expect(json[key] as? String == value as? String, "\(type).\(key)") }
            #expect(try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data(text.utf8)).event == logged.event)
        }

        added.libraryID = UUID()
        added.originalPath = "/Users/me/Scores/Tune.mxl"
        let (text, json, _) = try line(.pieceAdded(added))
        #expect(json["libraryID"] as? String == added.libraryID?.uuidString)
        #expect(json["originalPath"] as? String == "/Users/me/Scores/Tune.mxl")
        #expect(text.contains(#""originalPath":"/Users/me/Scores/Tune.mxl""#), "slashes not escaped")
        #expect(try LoggedEvent.decoder.decode(LoggedEvent.self, from: Data(text.utf8)).event == .pieceAdded(added))
    }

    @Test func memoryRecorderStampsTheTimeItIsGiven() {
        let recorder = MemoryUsageRecorder()
        let earlier = usageTestTime("2026-11-01T08:00:00.000Z")
        recorder.record(.uiAction(UIAction(name: "now", detail: nil)))
        recorder.record(.uiAction(UIAction(name: "earlier", detail: nil)), at: earlier)
        #expect(recorder.events.map(\.sequence) == [0, 1])
        #expect(recorder.events[1].time == earlier)
    }

    @Test func schemaDocumentsTheJournalAdditions() {
        let schema = UsageExport.schema
        for type in ["roundRestored", "pieceAdded", "pieceRevised", "pieceRemoved"] {
            #expect(schema.contains("### `\(type)`"), "\(type)")
        }
        #expect(schema.contains("only in the practice journal's event files"))
        for field in ["`interrupted`", "`recordedAt`", "`piece.id`", "`piece.file`", "`piece.staves`", "`unansweredQuestion`"] {
            #expect(schema.contains(field), "\(field)")
        }
    }

    @Test func memoryRecorderNumbersEvents() {
        let recorder = MemoryUsageRecorder()
        recorder.record(.uiAction(UIAction(name: "a", detail: nil)))
        recorder.record(.uiAction(UIAction(name: "b", detail: nil)))
        #expect(recorder.events.map(\.sequence) == [0, 1])
        #expect(Set(recorder.events.map(\.session)).count == 1)
    }
}
