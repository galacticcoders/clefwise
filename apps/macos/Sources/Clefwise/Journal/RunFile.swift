import Foundation

// The files of the practice journal: a folder of plain files the user owns, only ever added to.
// spec/practice-journal.md is the format; this file holds its names, its fixed bytes and the header
// every record starts with.

/// Line 1 of every file in the journal's `runs/` and `events/`: where the record comes from. It
/// isn't an event. See spec/practice-journal.md, "The header".
struct RunFileHeader: Codable, Equatable, Sendable {
    /// The format this version writes and reads.
    static let currentFormat = 1
    /// `platform` for files written by this app.
    static let thisPlatform = "macOS"

    /// The run-file format, now 1. A reader skips a file in a format newer than it knows.
    var format: Int
    /// Run files only: the run's id, the `round` in its events. Nil in event files.
    var run: UUID?
    /// Event files only: the event's id, the `id` of its one event line. Nil in run files.
    var event: UUID?
    /// The installation that wrote the file (`DeviceID`). It never syncs.
    var device: UUID
    /// `macOS`, `iPadOS` or `Linux`.
    var platform: String
    /// As in `appLaunched`.
    var osVersion: String
    var model: String
    /// The app that wrote the file.
    var appVersion: String
    var build: String
    /// As in `appLaunched`. The time zone gives the run's local day.
    var locale: String
    var timeZone: String

    /// The header as written: one line of JSON (keys sorted, slashes not escaped) and a line feed.
    func encodedLine() throws -> Data {
        var line = try Self.encoder.encode(self)
        line.append(0x0A)
        return line
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

// Initialisers live here so the memberwise one stays.
extension RunFileHeader {
    /// The header in a file's first line (with or without its line feed); nil when it isn't one.
    init?(line: Data) {
        guard let header = try? JSONDecoder().decode(Self.self, from: line) else { return nil }
        self = header
    }

    /// A run file's header: the run (`round` in its events), this device, and the app as it
    /// launched (`AppLaunched.current`, or the run's own session's for runs brought in from the
    /// old log).
    init(run: UUID, device: UUID, launch: AppLaunched) {
        self.init(format: Self.currentFormat, run: run, event: nil, device: device, platform: Self.thisPlatform,
                  osVersion: launch.osVersion, model: launch.model, appVersion: launch.appVersion,
                  build: launch.build, locale: launch.locale, timeZone: launch.timeZone)
    }

    /// An event file's header: the event (the `id` of its one line), this device, and the app as it
    /// launched.
    init(event: UUID, device: UUID, launch: AppLaunched) {
        self.init(format: Self.currentFormat, run: nil, event: event, device: device, platform: Self.thisPlatform,
                  osVersion: launch.osVersion, model: launch.model, appVersion: launch.appVersion,
                  build: launch.build, locale: launch.locale, timeZone: launch.timeZone)
    }
}

/// Where things go in a journal, as paths relative to its folder ("/" between components), and
/// which paths belong there at all. See spec/practice-journal.md, "Layout".
enum JournalLayout {
    /// Marks the folder as a journal.
    static let markerName = "clefwise.json"
    /// Exactly `{"format":"clefwise-journal"}` and a line feed.
    static let markerContents = Data("{\"format\":\"clefwise-journal\"}\n".utf8)
    /// Keeps git from changing any bytes, should the journal become a repository.
    static let gitAttributesName = ".gitattributes"
    /// Exactly `* -text` and a line feed.
    static let gitAttributesContents = Data("* -text\n".utf8)
    /// The files at the journal's root, by name, with their exact bytes: written when the journal is
    /// made, and the same in every journal.
    static let rootFiles: [String: Data] = [markerName: markerContents, gitAttributesName: gitAttributesContents]

    static let runsFolder = "runs"
    static let eventsFolder = "events"
    static let piecesFolder = "pieces"
    /// The extensions a score in `pieces/` can have, as `PieceFile.extensions` opens them.
    static let pieceExtensions: Set<String> = ["musicxml", "xml", "mxl"]

    /// What a path in the journal names, when it fits the layout.
    enum File: Equatable {
        case marker
        case gitAttributes
        /// Times come from the name, so they're to the second.
        case run(startedAt: Date, id: UUID)
        case event(at: Date, id: UUID)
        case piece(hash: String, fileExtension: String)
    }

    /// `runs/2026/11/20261105T093112Z-<lowercase run id>.jsonl`: the run's start in UTC (to the
    /// second, rounded down), in folders of that UTC year and month.
    static func runPath(startedAt: Date, run: UUID) -> String {
        recordPath(in: runsFolder, at: startedAt, id: run)
    }

    /// `events/2026/11/20261105T101500Z-<lowercase event id>.jsonl`, like `runPath`, by the event's
    /// `time` and `id`.
    static func eventPath(at time: Date, event: UUID) -> String {
        recordPath(in: eventsFolder, at: time, id: event)
    }

    /// `pieces/<hash>.<ext>`, both lowercased. `hash` is the SHA-256 of the score's bytes in hex;
    /// `fileExtension` comes without its dot.
    static func piecePath(hash: String, fileExtension: String) -> String {
        "\(piecesFolder)/\(hash.lowercased()).\(fileExtension.lowercased())"
    }

    /// Whether a file at `relativePath` belongs in a journal. Readers ignore any that doesn't: a
    /// sync service's conflicted copy, a Finder duplicate ("… 2.jsonl"), `.DS_Store`, an iCloud
    /// placeholder.
    static func fits(_ relativePath: String) -> Bool {
        file(at: relativePath) != nil
    }

    /// What the file at `relativePath` is, or nil when its name doesn't fit the layout. A name fits
    /// only if it's exactly what the layout writes: the right folder, the UTC year and month of the
    /// time in the name, a lowercase id or 64-character hash, and a known extension in lowercase.
    static func file(at relativePath: String) -> File? {
        switch relativePath {
        case markerName: return .marker
        case gitAttributesName: return .gitAttributes
        default: break
        }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, parts[0] == piecesFolder {
            let name = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard name.count == 2, name[0].count == 64, name[0].allSatisfy({ "0123456789abcdef".contains($0) }),
                  pieceExtensions.contains(name[1]) else { return nil }
            return .piece(hash: name[0], fileExtension: name[1])
        }
        guard parts.count == 4, parts[0] == runsFolder || parts[0] == eventsFolder,
              parts[3].hasSuffix(".jsonl") else { return nil }
        // "20261105T093112Z-<36-character id>.jsonl"
        let name = parts[3].dropLast(".jsonl".count)
        guard name.count == 16 + 1 + 36, name.dropFirst(16).first == "-",
              let time = date(fromStamp: String(name.prefix(16))),
              let id = UUID(uuidString: String(name.suffix(36))),
              recordPath(in: parts[0], at: time, id: id) == relativePath else { return nil }
        return parts[0] == runsFolder ? .run(startedAt: time, id: id) : .event(at: time, id: id)
    }

    // MARK: - Names

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func recordPath(in folder: String, at time: Date, id: UUID) -> String {
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
        let year = String(format: "%04d", parts.year ?? 0), month = String(format: "%02d", parts.month ?? 0)
        let stamp = year + month + String(format: "%02dT%02d%02d%02dZ", parts.day ?? 0, parts.hour ?? 0,
                                          parts.minute ?? 0, parts.second ?? 0)
        return "\(folder)/\(year)/\(month)/\(stamp)-\(id.uuidString.lowercased()).jsonl"
    }

    /// "20261105T093112Z" as a time; nil unless it's digits in that shape. An impossible date
    /// (month 13) comes back as some other time, which then won't name the same path.
    private static func date(fromStamp stamp: String) -> Date? {
        let characters = Array(stamp)
        guard characters.count == 16, characters[8] == "T", characters[15] == "Z" else { return nil }
        let digits = characters[0..<8] + characters[9..<15]
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        func number(_ range: Range<Int>) -> Int { Int(String(characters[range]))! }
        let parts = DateComponents(year: number(0..<4), month: number(4..<6), day: number(6..<8),
                                   hour: number(9..<11), minute: number(11..<13), second: number(13..<15))
        return utc.date(from: parts)
    }
}

/// Reading a file from the journal's `runs/` or `events/`.
enum RunFile {
    /// The header (line 1) and the events (every later line) of the file at `url`. A first line
    /// that isn't a header gives a nil header and counts as unreadable; later lines that don't
    /// parse (cut off, from a newer version) are skipped and counted, as the usage log's reader
    /// does. A file that can't be read at all (missing, not downloaded yet) gives nothing. Check
    /// `header.format` against `RunFileHeader.currentFormat` before trusting the events.
    static func read(_ url: URL) -> (header: RunFileHeader?, events: [LoggedEvent], unreadableLines: Int) {
        // Not memory-mapped: a sync service may replace the file while it's read.
        guard let data = try? Data(contentsOf: url) else { return (nil, [], 0) }
        var header: RunFileHeader?
        var isFirstLine = true
        var events: [LoggedEvent] = []
        var unreadable = 0
        UsageLog.forEachLine(in: data) { line in
            if isFirstLine {
                isFirstLine = false
                header = RunFileHeader(line: line)
                if header == nil { unreadable += 1 }
            } else if let event = UsageLog.event(in: line) {
                events.append(event)
            } else {
                unreadable += 1
            }
        }
        return (header, events, unreadable)
    }
}
