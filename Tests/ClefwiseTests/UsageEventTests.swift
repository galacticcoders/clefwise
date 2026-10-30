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
                                         pieceNote: PieceNoteRef(measure: 9, staff: 1, onset: 24, chord: 46),
                                         pickChance: nil, naming: "letters", input: "piano",
                                         hintsVisible: false, keyNamesVisible: true)),
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

    @Test func settingsBecomePlainJSON() {
        guard case .object(let settings) = JSONValue(encoding: Game.Settings()) else {
            Issue.record("settings should encode to an object")
            return
        }
        #expect(settings["naming"] == .string("letters"))
        #expect(settings["isMuted"] == .bool(false))
    }

    @Test func memoryRecorderNumbersEvents() {
        let recorder = MemoryUsageRecorder()
        recorder.record(.uiAction(UIAction(name: "a", detail: nil)))
        recorder.record(.uiAction(UIAction(name: "b", detail: nil)))
        #expect(recorder.events.map(\.sequence) == [0, 1])
        #expect(Set(recorder.events.map(\.session)).count == 1)
    }
}
