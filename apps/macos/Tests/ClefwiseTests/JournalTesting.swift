import Foundation
@testable import Clefwise

// What the practice journal's tests share: a launch, this device, the events of a run, and a
// folder of their own for the usage log, the device's working files and the journal.

enum JournalFixture {
    static let device = UUID(uuidString: "A1B2C3D4-E5F6-4711-8899-AABBCCDDEEFF")!
    static let launch = AppLaunched(appVersion: "0.1.0", build: "7", osVersion: "26.5.2", model: "MacBookPro18,2",
                                    locale: "sv_SE", timeZone: "Europe/Stockholm",
                                    screen: Size(width: 1728, height: 1117), systemAppearance: "dark")

    static func started(_ round: UUID) -> UsageEvent {
        .roundStarted(RoundStarted(round: round, via: .button, settings: .object(["mode": .string("practice")]),
                                   keyFifths: 0, piece: nil))
    }

    static func answer(_ round: UUID, correct: Bool = true) -> UsageEvent {
        .answerGiven(AnswerGiven(round: round, question: UUID(), responseMs: 900, source: .click, letter: "C",
                                 accidental: 0, name: "C", pitch: nil, correct: correct, wrongOctave: nil,
                                 keystrokes: [Keystroke(key: "c", ms: 850, result: .submitted)],
                                 scoreAfter: 1, streakAfter: 1))
    }

    static func paused(_ round: UUID) -> UsageEvent {
        .roundPaused(RoundPaused(round: round, question: nil, via: .appSwitch, activeMs: 4_000))
    }

    static func ended(_ round: UUID, reason: RoundEndReason = .stopped) -> UsageEvent {
        .roundEnded(RoundEnded(round: round, reason: reason, durationMs: 5_000, score: 1, attempts: 1, bestStreak: 1,
                               averageResponseMs: 900, notesToReview: []))
    }

    static func action(_ name: String) -> UsageEvent {
        .uiAction(UIAction(name: name, detail: nil))
    }

    /// A run file's bytes: its header, then `events` stamped one second apart from `start`.
    static func runFile(_ round: UUID, _ events: [UsageEvent], start: Date) throws -> (data: Data, logged: [LoggedEvent]) {
        let session = UUID()
        let logged = events.enumerated().map {
            LoggedEvent($0.element, session: session, sequence: $0.offset, time: start.addingTimeInterval(Double($0.offset)))
        }
        var data = try RunFileHeader(run: round, device: device, launch: launch).encodedLine()
        for event in logged { data += try event.encodedLine() }
        return (data, logged)
    }
}

/// A test's own folder, with the usage log, the device's state (`Current`, `Pending`) and the
/// journal's parent folder in it, and its own defaults. Never the real ones.
final class JournalTestBench {
    let temporary = UsageTestFolder()
    let defaults = InMemoryDefaults()
    let journal: PracticeJournal

    init() {
        journal = PracticeJournal(defaults: defaults)
    }

    var usageFolder: URL { temporary.url.appendingPathComponent("Usage", isDirectory: true) }
    /// Where the run writer keeps `Current` and `Pending`.
    var stateFolder: URL { temporary.url.appendingPathComponent("State", isDirectory: true) }
    var currentFolder: URL { stateFolder.appendingPathComponent("Current", isDirectory: true) }
    var pendingFolder: URL { stateFolder.appendingPathComponent("Pending", isDirectory: true) }
    /// Where journals are made.
    var documents: URL { temporary.url.appendingPathComponent("Documents", isDirectory: true) }

    /// Makes the journal "Clefwise Journal" in `documents`.
    @discardableResult
    func makeJournal() throws -> URL {
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return try journal.create(named: "Clefwise Journal", in: documents)
    }

    func makeWriter() -> RunFileWriter {
        RunFileWriter(folder: stateFolder, journal: journal, device: JournalFixture.device, launch: JournalFixture.launch)
    }

    func makeLog() -> UsageLog {
        UsageLog(folder: usageFolder)
    }

    /// A working file left in `Current` by an earlier launch.
    @discardableResult
    func leaveWorkingFile(_ round: UUID, _ data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: currentFolder, withIntermediateDirectories: true)
        let url = currentFolder.appendingPathComponent("\(round.uuidString.lowercased()).jsonl")
        try data.write(to: url)
        return url
    }

    /// Every file under `folder`, hidden ones too, by its path from there; sorted.
    static func files(in folder: URL) -> [String] {
        let manager = FileManager.default
        return (manager.subpaths(atPath: folder.path) ?? []).filter { path in
            var isFolder: ObjCBool = false
            return manager.fileExists(atPath: folder.appendingPathComponent(path).path, isDirectory: &isFolder)
                && !isFolder.boolValue
        }.sorted()
    }

    /// `data` split into lines, each with its line feed.
    static func lines(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A).map { $0 + 1 } ?? data.endIndex
            lines.append(Data(data[start..<end]))
            start = end
        }
        return lines
    }
}

/// Keeps what the piece library sends the journal.
final class CollectingJournalRecorder: JournalEventRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [(event: UsageEvent, piece: JournalPieceFile?)] = []

    func recordInJournal(_ event: UsageEvent, piece: JournalPieceFile?) {
        lock.withLock { collected.append((event, piece)) }
    }

    var events: [UsageEvent] { lock.withLock { collected.map(\.event) } }
    var pieces: [JournalPieceFile?] { lock.withLock { collected.map(\.piece) } }
}
