import Foundation
import Testing
@testable import Clefwise

// The practice journal's names, fixed bytes, header and reader (spec/practice-journal.md).

private let runID = UUID(uuidString: "5C1D2E3F-4A5B-4C6D-8E7F-9A0B1C2D3E4F")!
private let deviceID = UUID(uuidString: "A1B2C3D4-E5F6-4711-8899-AABBCCDDEEFF")!
private let launch = AppLaunched(appVersion: "0.1.0", build: "7", osVersion: "26.5.2", model: "MacBookPro18,2",
                                 locale: "sv_SE", timeZone: "Europe/Stockholm",
                                 screen: Size(width: 1728, height: 1117), systemAppearance: "dark")

@Suite struct RunFileHeaderTests {
    @Test func aRunHeaderIsOneSortedLine() throws {
        let header = RunFileHeader(run: runID, device: deviceID, launch: launch)
        let line = try header.encodedLine()
        let text = String(decoding: line, as: UTF8.self)
        // Keys sorted, the time zone's slash not escaped, one line feed at the end.
        #expect(text == #"{"appVersion":"0.1.0","build":"7","device":"A1B2C3D4-E5F6-4711-8899-AABBCCDDEEFF","format":1,"locale":"sv_SE","model":"MacBookPro18,2","osVersion":"26.5.2","platform":"macOS","run":"5C1D2E3F-4A5B-4C6D-8E7F-9A0B1C2D3E4F","timeZone":"Europe/Stockholm"}"# + "\n")
        #expect(RunFileHeader(line: line) == header)
        #expect(RunFileHeader(line: line.dropLast()) == header)
    }

    @Test func anEventHeaderNamesTheEventInstead() throws {
        let event = UUID()
        let header = RunFileHeader(event: event, device: deviceID, launch: launch)
        #expect(header.event == event && header.run == nil)
        #expect(header.format == RunFileHeader.currentFormat && header.platform == "macOS")
        #expect([header.osVersion, header.model, header.appVersion, header.build, header.locale, header.timeZone]
                == ["26.5.2", "MacBookPro18,2", "0.1.0", "7", "sv_SE", "Europe/Stockholm"])
        let line = try header.encodedLine()
        let json = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(json["event"] as? String == event.uuidString && json["run"] == nil)
        #expect(RunFileHeader(line: line) == header)
    }

    @Test func otherLinesAreNotHeaders() {
        #expect(RunFileHeader(line: Data(#"{"format":1,"run":"#.utf8)) == nil)
        #expect(RunFileHeader(line: Data(#"{"schema":1,"type":"uiAction"}"#.utf8)) == nil)
    }
}

@Suite struct JournalLayoutTests {
    private let hash = String(repeating: "0123456789abcdef", count: 4)

    @Test func rootFilesHaveTheirExactBytes() {
        #expect(JournalLayout.markerName == "clefwise.json")
        #expect(JournalLayout.markerContents == Data([UInt8](#"{"format":"clefwise-journal"}"#.utf8) + [0x0A]))
        #expect(JournalLayout.gitAttributesName == ".gitattributes")
        #expect(JournalLayout.gitAttributesContents == Data([0x2A, 0x20, 0x2D, 0x74, 0x65, 0x78, 0x74, 0x0A]))
        #expect(JournalLayout.rootFiles == ["clefwise.json": JournalLayout.markerContents,
                                            ".gitattributes": JournalLayout.gitAttributesContents])
    }

    @Test func recordsAreNamedByTheirUTCTimeAndLowercaseId() {
        let time = usageTestTime("2026-11-05T09:31:12.948Z")
        #expect(JournalLayout.runPath(startedAt: time, run: runID)
                == "runs/2026/11/20261105T093112Z-5c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f.jsonl")
        #expect(JournalLayout.eventPath(at: time, event: deviceID)
                == "events/2026/11/20261105T093112Z-a1b2c3d4-e5f6-4711-8899-aabbccddeeff.jsonl")
        #expect(JournalLayout.piecePath(hash: hash.uppercased(), fileExtension: "MXL") == "pieces/\(hash).mxl")
    }

    @Test func foldersFollowTheUTCDateAcrossMonthsAndYears() {
        let id = runID.uuidString.lowercased()
        let cases = [
            ("2026-11-30T23:59:59.999Z", "runs/2026/11/20261130T235959Z"),
            ("2026-12-01T00:00:00.000Z", "runs/2026/12/20261201T000000Z"),
            // Already 1 November in Bucharest and Stockholm, still October in UTC.
            ("2026-10-31T22:30:00.000Z", "runs/2026/10/20261031T223000Z"),
            ("2026-12-31T23:59:59.000Z", "runs/2026/12/20261231T235959Z"),
            ("2027-01-01T00:00:00.000Z", "runs/2027/01/20270101T000000Z"),
        ]
        for (time, path) in cases {
            #expect(JournalLayout.runPath(startedAt: usageTestTime(time), run: runID) == "\(path)-\(id).jsonl")
        }
    }

    @Test func itsOwnNamesFitAndSayWhatTheyAre() {
        let time = usageTestTime("2026-11-05T09:31:12.948Z")
        let toTheSecond = usageTestTime("2026-11-05T09:31:12.000Z")
        let run = JournalLayout.runPath(startedAt: time, run: runID)
        let event = JournalLayout.eventPath(at: time, event: deviceID)
        #expect(JournalLayout.file(at: run) == .run(startedAt: toTheSecond, id: runID))
        #expect(JournalLayout.file(at: event) == .event(at: toTheSecond, id: deviceID))
        #expect(JournalLayout.file(at: "pieces/\(hash).musicxml") == .piece(hash: hash, fileExtension: "musicxml"))
        #expect(JournalLayout.file(at: "clefwise.json") == .marker)
        #expect(JournalLayout.file(at: ".gitattributes") == .gitAttributes)
        for path in [run, event, "pieces/\(hash).xml", "pieces/\(hash).mxl"] {
            #expect(JournalLayout.fits(path), "\(path)")
        }
    }

    @Test func junkDoesNotFit() {
        let run = JournalLayout.runPath(startedAt: usageTestTime("2026-11-05T09:31:12.000Z"), run: runID)
        let name = (run as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let junk = [
            "runs/2026/11/x 2.jsonl",
            "runs/2026/11/\(stem) 2.jsonl",
            "runs/2026/11/\(stem) (conflicted copy 2026-11-05).jsonl",
            "runs/2026/11/\(stem.uppercased()).jsonl",
            "runs/2026/11/\(stem.replacingOccurrences(of: "5c1d2e3f", with: "5C1D2E3F")).jsonl",
            "runs/2026/10/\(name)",
            "runs/2025/11/\(name)",
            "runs/2026/11/.\(name).icloud",
            "runs/2026/11/\(name).icloud",
            "runs/2026/11/\(name).tmp",
            "runs/2026/11/\(stem).json",
            "runs/2026/11/.DS_Store",
            "runs/2026/\(name)",
            "events/2026/11/x/\(name)",
            "notes/2026/11/\(name)",
            "/runs/2026/11/\(name)",
            "runs/2026/13/20261305T093112Z-\(runID.uuidString.lowercased()).jsonl",
            "runs/2026/11/20261105T253112Z-\(runID.uuidString.lowercased()).jsonl",
            "runs/2026/11/20261105 093112Z-\(runID.uuidString.lowercased()).jsonl",
            "pieces/\(hash).MXL",
            "pieces/\(hash.uppercased()).mxl",
            "pieces/\(hash.dropLast(2)).mxl",
            "pieces/\(hash) 2.mxl",
            "pieces/\(hash).pdf",
            "pieces/\(hash).mxl.icloud",
            "pieces/x/\(hash).mxl",
            "clefwise 2.json",
            "Clefwise.json",
            ".DS_Store",
            "",
        ]
        for path in junk {
            #expect(!JournalLayout.fits(path), "\(path)")
        }
    }
}

@Suite struct RunFileReadingTests {
    private let temporary = UsageTestFolder()

    private func write(_ data: Data, as name: String = "run.jsonl") throws -> URL {
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        let url = temporary.url.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func events() -> [LoggedEvent] {
        let session = UUID()
        return [
            LoggedEvent(.roundStarted(RoundStarted(round: runID, via: .button, settings: .object([:]), keyFifths: 0, piece: nil)),
                        session: session, sequence: 4),
            LoggedEvent(.appActivity(AppActivity(active: false)), session: session, sequence: 5),
            LoggedEvent(.roundEnded(RoundEnded(round: runID, reason: .stopped, durationMs: 1000, score: 1, attempts: 1,
                                               bestStreak: 1, averageResponseMs: 800, bestScore: nil, isNewBest: false,
                                               notesToReview: [])),
                        session: session, sequence: 6),
        ]
    }

    @Test func readsTheHeaderThenTheEventsAndCountsACutOffLine() throws {
        let header = RunFileHeader(run: runID, device: deviceID, launch: launch)
        let logged = events()
        var data = try header.encodedLine()
        for event in logged { data += try event.encodedLine() }
        data += Data(#"{"schema":1,"type":"answerGiven","id":"5C1"#.utf8)
        let read = RunFile.read(try write(data))
        #expect(read.header == header)
        #expect(read.events.map(\.event) == logged.map(\.event))
        #expect(read.events.map(\.id) == logged.map(\.id))
        #expect(read.unreadableLines == 1)
    }

    @Test func aFirstLineThatIsNoHeaderIsCountedNotReadAsAnEvent() throws {
        let logged = events()
        var data = Data()
        for event in logged { data += try event.encodedLine() }
        let read = RunFile.read(try write(data))
        #expect(read.header == nil)
        #expect(read.events.map(\.event) == logged.dropFirst().map(\.event))
        #expect(read.unreadableLines == 1)
    }

    @Test func aFileThatCannotBeReadGivesNothing() {
        let read = RunFile.read(temporary.url.appendingPathComponent("not downloaded yet.jsonl"))
        #expect(read.header == nil && read.events.isEmpty && read.unreadableLines == 0)
    }
}

@Suite struct JournalContractTests {
    @Test func theDeviceIDIsMadeOnceAndKept() {
        let defaults = InMemoryDefaults()
        let first = DeviceID.current(in: defaults)
        #expect(DeviceID.current(in: defaults) == first)
        #expect(defaults.object(forKey: "deviceID") as? String == first.uuidString)
        #expect(DeviceID.current(in: InMemoryDefaults()) != first, "another installation, another id")
    }

    @Test func aPieceFileIsNamedByItsSHA256() {
        let piece = JournalPieceFile(data: Data("abc".utf8), fileExtension: "mxl")
        #expect(piece.hash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(JournalLayout.piecePath(hash: piece.hash, fileExtension: piece.fileExtension)
                == "pieces/ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad.mxl")
        #expect(JournalLayout.fits(JournalLayout.piecePath(hash: piece.hash, fileExtension: piece.fileExtension)))
    }
}
