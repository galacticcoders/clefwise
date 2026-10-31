import Foundation

/// Packs the usage log into one zip for analysing elsewhere: the raw event files (the source of
/// truth), CSV tables built from them, the settings and stats saved now, and SCHEMA.md
/// describing it all.
enum UsageExport {
    /// Writes everything in `log` to a zip at `destination`, replacing any file there. Reads the
    /// whole log, which after years of use takes a few seconds: call it off the main thread.
    /// `defaults` holds the saved settings and stats; local-time columns are in `timeZone`.
    static func export(_ log: UsageLog, to destination: URL, defaults: UserDefaults = .standard,
                       timeZone: TimeZone = .current) throws {
        log.flush()
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory
            .appendingPathComponent("Clefwise export \(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: work) }

        let now = Date()
        let times = TimeFormat(timeZone: timeZone)
        let top = work.appendingPathComponent("Clefwise usage \(times.day(now))", isDirectory: true)
        let eventsFolder = top.appendingPathComponent("events", isDirectory: true)

        // Tables come from the copies, so they match the raw files even if the app logs more meanwhile.
        let copies = try step("copy the event files") {
            try fileManager.createDirectory(at: eventsFolder, withIntermediateDirectories: true)
            return try UsageLog.eventFiles(in: log.folder).map { file in
                let copy = eventsFolder.appendingPathComponent(file.lastPathComponent)
                try fileManager.copyItem(at: file, to: copy)
                return copy
            }
        }
        let counts = try step("write the tables") { try writeTables(from: copies, to: top, times: times) }
        try step("write the saved settings and stats") {
            for (key, name) in savedValues {
                try writeSaved(key, from: defaults, to: top.appendingPathComponent(name))
            }
        }
        try step("write SCHEMA.md") {
            let skipped = counts.unreadable == 0 ? "" : ", skipping \(counts.unreadable) unreadable line"
                + (counts.unreadable == 1 ? "" : "s")
            let header = """
                # Clefwise usage data

                Exported \(times.local(now) ?? "") (\(timeZone.identifier)): \(counts.events) events \
                from \(copies.count) day files\(skipped).


                """
            try Data((header + schema).utf8).write(to: top.appendingPathComponent("SCHEMA.md"))
        }
        let archive = work.appendingPathComponent("export.zip")
        try step("compress the export") { try zip(top, to: archive) }
        try step("save “\(destination.lastPathComponent)”") {
            var isFolder: ObjCBool = false
            if fileManager.fileExists(atPath: destination.path, isDirectory: &isFolder) {
                guard !isFolder.boolValue else {
                    throw UsageExportError(step: "replace “\(destination.lastPathComponent)”", reason: "It's a folder.")
                }
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: archive, to: destination)
        }
    }

    /// The UserDefaults keys `Game` saves under (its private `Keys`), and the files they go to.
    private static let savedValues = [("settings", "settings.json"), ("noteStats", "note-stats.json"),
                                      ("bestScores", "best-scores.json")]

    /// Runs one step, so a failure says which step it was.
    private static func step<T>(_ name: String, _ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as UsageExportError {
            throw error
        } catch {
            throw UsageExportError(step: name, reason: error.localizedDescription)
        }
    }

    /// Pretty-printed, or `{}` when nothing is saved yet.
    private static func writeSaved(_ key: String, from defaults: UserDefaults, to url: URL) throws {
        var json = Data("{}".utf8)
        if let data = defaults.data(forKey: key),
           let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
           let pretty = try? JSONSerialization.data(withJSONObject: value,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]) {
            json = pretty
        }
        json.append(0x0A)
        try json.write(to: url)
    }

    private static func zip(_ folder: URL, to archive: URL) throws {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // No resource forks, extended attributes or quarantine: plain files any unzip tool reads.
        ditto.arguments = ["-c", "-k", "--keepParent", "--norsrc", "--noqtn", folder.path, archive.path]
        let errors = Pipe()
        ditto.standardError = errors
        ditto.standardOutput = FileHandle.nullDevice
        try ditto.run()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw UsageExportError(step: "compress the export",
                                   reason: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Tables

    /// Writes answers.csv while reading the log, then rounds.csv and sessions.csv.
    private static func writeTables(from files: [URL], to folder: URL, times: TimeFormat) throws -> (events: Int, unreadable: Int) {
        let answers = try CSVWriter(url: folder.appendingPathComponent("answers.csv"), columns: answerColumns(times))
        var tables = Tables()
        let unreadable = try UsageLog.forEachEvent(in: files) { event in
            if let row = tables.add(event) { try answers.write(row) }
        }
        try answers.close()
        try CSVWriter.write(tables.rounds, columns: roundColumns(times), to: folder.appendingPathComponent("rounds.csv"))
        try CSVWriter.write(tables.sessions, columns: sessionColumns(times), to: folder.appendingPathComponent("sessions.csv"))
        return (tables.events, unreadable)
    }

    private static func answerColumns(_ times: TimeFormat) -> [Column<AnswerRow>] { [
        Column("localTime") { times.local($0.time) },
        Column("time") { times.iso($0.time) },
        Column("session") { $0.session.uuidString },
        Column("round") { $0.answer.round.uuidString },
        Column("question") { $0.answer.question.uuidString },
        Column("questionIndex") { $0.question?.index },
        Column("clef") { $0.question?.clef },
        Column("pitch") { $0.question?.pitch.name },
        Column("pitchMidi") { $0.question?.pitch.midi },
        Column("written") { $0.question?.written.name },
        Column("position") { $0.question?.position },
        Column("keyFifths") { $0.question?.keyFifths },
        Column("printedAccidental") { $0.question?.printedAccidental },
        Column("octaveShift") { $0.question?.octaveShift },
        Column("pieceBar") { $0.question?.pieceNote?.measure },
        Column("pieceStaff") { $0.question?.pieceNote?.staff },
        Column("barView") { $0.question?.barView },
        Column("barStaves") { $0.question?.barStaves?.map(String.init).joined(separator: " ") },
        Column("naming") { $0.question?.naming ?? setting("naming", in: $0.round?.settings) },
        Column("input") { $0.question?.input ?? setting("answerInput", in: $0.round?.settings) },
        Column("source") { $0.answer.source.rawValue },
        Column("answerLetter") { $0.answer.letter },
        Column("answerAccidental") { $0.answer.accidental },
        Column("answerName") { $0.answer.name },
        Column("answerPitch") { $0.answer.pitch?.name },
        Column("answerMidi") { $0.answer.pitch?.midi },
        Column("correct") { $0.answer.correct },
        Column("wrongOctave") { $0.answer.wrongOctave },
        Column("responseMs") { $0.answer.responseMs },
        Column("keystrokes") { $0.answer.keystrokes.count },
        Column("rejectedKeystrokes") { row in row.answer.keystrokes.filter { $0.result == .rejected }.count },
        Column("scoreAfter") { $0.answer.scoreAfter },
        Column("streakAfter") { $0.answer.streakAfter },
        Column("hintsVisible") { $0.question?.hintsVisible },
        Column("keyNamesVisible") { $0.question?.keyNamesVisible },
        Column("pickChance") { $0.question?.pickChance },
        Column("mode") { setting("mode", in: $0.round?.settings) },
        Column("clefChoice") { setting("clefChoice", in: $0.round?.settings) },
        Column("range") { setting("range", in: $0.round?.settings) },
        Column("keySetting") { keySetting(in: $0.round?.settings) },
        Column("addsAccidentals") { setting("addsAccidentals", in: $0.round?.settings) },
        Column("pieceTitle") { $0.round?.piece?.title },
    ] }

    private static func roundColumns(_ times: TimeFormat) -> [Column<RoundRow>] { [
        Column("startLocalTime") { times.local($0.startTime) },
        Column("startTime") { times.iso($0.startTime) },
        Column("endLocalTime") { times.local($0.endTime) },
        Column("endTime") { times.iso($0.endTime) },
        Column("session") { $0.session.uuidString },
        Column("round") { $0.id.uuidString },
        Column("via") { $0.start?.via.rawValue },
        Column("mode") { setting("mode", in: $0.start?.settings) },
        Column("clefChoice") { setting("clefChoice", in: $0.start?.settings) },
        Column("range") { setting("range", in: $0.start?.settings) },
        Column("keySetting") { keySetting(in: $0.start?.settings) },
        Column("keyFifths") { $0.start?.keyFifths },
        Column("addsAccidentals") { setting("addsAccidentals", in: $0.start?.settings) },
        Column("naming") { setting("naming", in: $0.start?.settings) },
        Column("answerInput") { setting("answerInput", in: $0.start?.settings) },
        Column("pieceTitle") { $0.start?.piece?.title },
        Column("piecePart") { $0.start?.piece?.part },
        Column("pieceHand") { $0.start?.piece?.hand },
        Column("pieceOrder") { $0.start?.piece?.order },
        Column("pieceStartBar") { $0.start?.piece?.startBar },
        Column("pieceOneNotePerChord") { $0.start?.piece?.oneNotePerChord },
        Column("pieceNotes") { $0.start?.piece?.noteCount },
        Column("endReason") { $0.end?.reason.rawValue },
        Column("durationMs") { $0.end?.durationMs },
        Column("score") { $0.end?.score },
        Column("attempts") { $0.end?.attempts },
        Column("accuracy") { ratio($0.end?.score, $0.end?.attempts) },
        Column("bestStreak") { $0.end?.bestStreak },
        Column("averageResponseMs") { $0.end?.averageResponseMs },
        Column("bestScore") { $0.end?.bestScore },
        Column("isNewBest") { $0.end?.isNewBest },
        Column("notesToReview") { $0.end?.notesToReview.joined(separator: " ") },
        Column("answers") { $0.answers },
    ] }

    private static func sessionColumns(_ times: TimeFormat) -> [Column<SessionRow>] { [
        Column("launchLocalTime") { times.local($0.start) },
        Column("launchTime") { times.iso($0.start) },
        Column("quitLocalTime") { times.local($0.quitTime) },
        Column("quitTime") { times.iso($0.quitTime) },
        Column("session") { $0.id.uuidString },
        Column("durationSeconds") { rounded($0.durationSeconds, places: 3) },
        Column("foregroundSeconds") { $0.foregroundSeconds.map { rounded($0, places: 3) } },
        Column("appVersion") { $0.launch?.appVersion },
        Column("build") { $0.launch?.build },
        Column("osVersion") { $0.launch?.osVersion },
        Column("model") { $0.launch?.model },
        Column("locale") { $0.launch?.locale },
        Column("timeZone") { $0.launch?.timeZone },
        Column("events") { $0.events },
        Column("rounds") { $0.rounds },
        Column("answers") { $0.answers },
        Column("correct") { $0.correct },
        Column("accuracy") { ratio($0.correct, $0.answers) },
    ] }

    private static func ratio(_ part: Int?, _ whole: Int?) -> Double? {
        guard let part, let whole, whole > 0 else { return nil }
        return rounded(Double(part) / Double(whole), places: 4)
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    /// A value from a round's saved settings by key path ("piece.hand"), as cell text.
    private static func setting(_ path: String, in settings: JSONValue?) -> String? {
        var value = settings
        for key in path.split(separator: ".") {
            guard case .object(let object)? = value else { return nil }
            value = object[String(key)]
        }
        switch value {
        case nil, .null?: return nil
        case .bool(let flag)?: return flag ? "true" : "false"
        case .number(let number)?: return number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case .string(let text)?: return text
        case let other?: return (try? LoggedEvent.encoder.encode(other)).map { String(decoding: $0, as: UTF8.self) }
        }
    }

    /// The key setting, saved as `{"fixed":{"_0":{"fifths":2}}}` or `{"random":{}}`: "2" or "random".
    private static func keySetting(in settings: JSONValue?) -> String? {
        guard case .object(let settings)? = settings, case .object(let key)? = settings["key"] else { return nil }
        if key["random"] != nil { return "random" }
        return setting("fixed._0.fifths", in: .object(key)) ?? setting("key", in: .object(settings))
    }

    /// A field per RFC 4180: in quotes when it holds a comma, quote or line break, quotes doubled.
    static func csvField(_ text: String) -> String {
        guard text.utf8.contains(where: { $0 == UInt8(ascii: ",") || $0 == UInt8(ascii: "\"") || $0 == 0x0A || $0 == 0x0D }) else {
            return text
        }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Why an export failed, worded for an alert.
struct UsageExportError: LocalizedError {
    /// What couldn't be done, e.g. "compress the export".
    let step: String
    let reason: String

    var errorDescription: String? { "Couldn't export the usage data: couldn't \(step). \(reason)" }
    var failureReason: String? { reason }
}

// MARK: - Building the tables

/// One answers.csv row: the answer, the question it answered and its round's start.
private struct AnswerRow {
    let time: Date
    let session: UUID
    let answer: AnswerGiven
    let question: QuestionShown?
    let round: RoundStarted?
}

private struct RoundRow {
    let id: UUID
    let session: UUID
    var startTime: Date?
    var start: RoundStarted?
    var endTime: Date?
    var end: RoundEnded?
    var answers = 0
}

private struct SessionRow {
    let id: UUID
    let firstTime: Date
    var lastTime: Date
    var launch: AppLaunched?
    var launchTime: Date?
    var quit: AppTerminated?
    var quitTime: Date?
    /// Nil until the session logs an `appActivity`.
    var activeSeconds: Double?
    var activeSince: Date?
    var events = 0, rounds = 0, answers = 0, correct = 0

    var start: Date { launchTime ?? firstTime }
    /// As the app measured it; for a session that didn't quit cleanly (or is still going), up to its last event.
    var durationSeconds: Double { quit?.sessionSeconds ?? lastTime.timeIntervalSince(start) }

    var foregroundSeconds: Double? {
        guard let activeSeconds else { return nil }
        return activeSeconds + (activeSince.map { (quitTime ?? lastTime).timeIntervalSince($0) } ?? 0)
    }

    mutating func setActive(_ active: Bool, at time: Date) {
        if active {
            if activeSince == nil { activeSince = time }
        } else if let since = activeSince ?? (activeSeconds == nil ? start : nil) {
            // Becoming inactive before ever becoming active means the app was active since launch.
            activeSeconds = (activeSeconds ?? 0) + time.timeIntervalSince(since)
            activeSince = nil
        }
        activeSeconds = activeSeconds ?? 0
    }
}

/// Everything the tables need, gathered in one pass over the log. Answers go straight out to
/// answers.csv; rounds and sessions (a few a day) are kept for the end, and questions until
/// their round ends.
private struct Tables {
    private(set) var rounds: [RoundRow] = []
    private(set) var sessions: [SessionRow] = []
    private(set) var events = 0
    private var roundIndex: [UUID: Int] = [:]
    private var sessionIndex: [UUID: Int] = [:]
    private var questions: [UUID: QuestionShown] = [:]
    private var questionsByRound: [UUID: [UUID]] = [:]

    /// Takes in one event; returns its answers.csv row when it's an answer.
    mutating func add(_ logged: LoggedEvent) -> AnswerRow? {
        events += 1
        let session = sessionRow(for: logged)
        switch logged.event {
        case .appLaunched(let launch):
            sessions[session].launch = launch
            sessions[session].launchTime = logged.time
        case .appTerminated(let quit):
            sessions[session].quit = quit
            sessions[session].quitTime = logged.time
        case .appActivity(let activity):
            sessions[session].setActive(activity.active, at: logged.time)
        case .roundStarted(let start):
            sessions[session].rounds += 1
            let round = roundRow(start.round, in: logged.session)
            rounds[round].start = start
            rounds[round].startTime = logged.time
        case .questionShown(let question):
            questions[question.question] = question
            questionsByRound[question.round, default: []].append(question.question)
        case .answerGiven(let answer):
            sessions[session].answers += 1
            if answer.correct { sessions[session].correct += 1 }
            let round = roundRow(answer.round, in: logged.session)
            rounds[round].answers += 1
            return AnswerRow(time: logged.time, session: logged.session, answer: answer,
                             question: questions[answer.question], round: rounds[round].start)
        case .roundEnded(let end):
            let round = roundRow(end.round, in: logged.session)
            rounds[round].end = end
            rounds[round].endTime = logged.time
            for question in questionsByRound.removeValue(forKey: end.round) ?? [] { questions[question] = nil }
        default:
            break
        }
        return nil
    }

    private mutating func sessionRow(for logged: LoggedEvent) -> Int {
        let index: Int
        if let known = sessionIndex[logged.session] {
            index = known
        } else {
            index = sessions.count
            sessions.append(SessionRow(id: logged.session, firstTime: logged.time, lastTime: logged.time))
            sessionIndex[logged.session] = index
        }
        sessions[index].events += 1
        sessions[index].lastTime = max(sessions[index].lastTime, logged.time)
        return index
    }

    private mutating func roundRow(_ id: UUID, in session: UUID) -> Int {
        if let index = roundIndex[id] { return index }
        roundIndex[id] = rounds.count
        rounds.append(RoundRow(id: id, session: session))
        return rounds.count - 1
    }
}

/// How the tables write times: like the log (UTC, ISO 8601 with milliseconds), and as local
/// wall-clock time for reading at a glance.
private struct TimeFormat {
    private let isoFormatter = ISO8601DateFormatter()
    private let localFormatter = DateFormatter()
    private let dayFormatter = DateFormatter()

    init(timeZone: TimeZone) {
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (formatter, format) in [(localFormatter, "yyyy-MM-dd HH:mm:ss.SSS"), (dayFormatter, "yyyy-MM-dd")] {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = format
        }
    }

    func iso(_ date: Date?) -> String? { date.map(isoFormatter.string(from:)) }
    func local(_ date: Date?) -> String? { date.map(localFormatter.string(from:)) }
    func day(_ date: Date) -> String { dayFormatter.string(from: date) }
}

// MARK: - CSV

/// What a CSV cell can hold; nil is an empty cell.
private protocol CSVField {
    var csvText: String { get }
}

extension String: CSVField { fileprivate var csvText: String { self } }
extension Int: CSVField { fileprivate var csvText: String { String(self) } }
extension Double: CSVField { fileprivate var csvText: String { String(self) } }
extension Bool: CSVField { fileprivate var csvText: String { self ? "true" : "false" } }
extension Optional: CSVField where Wrapped: CSVField { fileprivate var csvText: String { self?.csvText ?? "" } }

/// A CSV column: its header, and how a row fills it in.
private struct Column<Row> {
    let name: String
    let value: (Row) -> any CSVField

    init(_ name: String, _ value: @escaping (Row) -> any CSVField) {
        self.name = name
        self.value = value
    }
}

/// Writes a CSV file a row at a time, in 64 KB chunks: RFC 4180 (CRLF line ends), UTF-8 without a BOM.
private final class CSVWriter<Row> {
    private let columns: [Column<Row>]
    private let handle: FileHandle
    private var buffer = ""

    init(url: URL, columns: [Column<Row>]) throws {
        try Data().write(to: url)
        handle = try FileHandle(forWritingTo: url)
        self.columns = columns
        try writeLine(columns.map(\.name))
    }

    static func write(_ rows: [Row], columns: [Column<Row>], to url: URL) throws {
        let writer = try CSVWriter(url: url, columns: columns)
        for row in rows { try writer.write(row) }
        try writer.close()
    }

    func write(_ row: Row) throws {
        try writeLine(columns.map { $0.value(row).csvText })
    }

    func close() throws {
        try flushBuffer()
        try handle.close()
    }

    private func writeLine(_ fields: [String]) throws {
        buffer += fields.map(UsageExport.csvField).joined(separator: ",")
        buffer += "\r\n"
        if buffer.utf8.count >= 1 << 16 { try flushBuffer() }
    }

    private func flushBuffer() throws {
        try handle.write(contentsOf: Data(buffer.utf8))
        buffer = ""
    }
}
