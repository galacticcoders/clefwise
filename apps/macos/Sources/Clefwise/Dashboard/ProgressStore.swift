import Foundation
import Observation

/// What the Progress window shows: the filter, and the report worked out for it from the practice
/// journal. Reading and analysing happen off the main thread, so practice carries on, and the last
/// report stays on screen until the new one is ready. The app reloads it whenever files arrive in
/// the journal (`AppModel`), so it follows along without Refresh.
@MainActor
@Observable
final class ProgressStore {
    /// Saved, so the window reopens on the same view. A change reloads.
    var filter: ProgressFilter {
        didSet {
            guard filter != oldValue else { return }
            saveFilter()
            reload()
        }
    }
    /// The report on screen: for `filter` once loaded; while reloading, the one before.
    private(set) var report: ProgressReport
    /// False until the first report is in (`report` is an empty placeholder until then).
    private(set) var hasLoaded = false
    private(set) var isLoading = false

    @ObservationIgnored private let defaults: UserDefaults?
    /// Works out the report for a filter. Runs off the main thread.
    @ObservationIgnored private let load: @Sendable (ProgressFilter) -> ProgressReport
    /// A reload asked for while one was running: done once it finishes, however many were asked.
    @ObservationIgnored private var reloadRequested = false

    private static let filterKey = "dashboardFilter"

    /// The app's store for a practice journal: reads what `reader` reads, and keeps the filter in
    /// `defaults`. The reader keeps the files it has read, so a reload reads only the new ones. With
    /// no reader (no journal) every report is empty.
    ///
    /// Runs brought in from the old usage log don't say how many staves their part has, which
    /// Recent rounds needs so a single-staff piece isn't described with a hand. For those, the
    /// `pieceOpened` events in this Mac's usage log (`log`) stand in: read once, at the first
    /// report, decoding only their own lines, and used for nothing else. Runs since the journal
    /// began carry their staves, so later `pieceOpened` events aren't needed.
    convenience init(reader: JournalReader?, defaults: UserDefaults = .standard, log: UsageLog = .shared) {
        let openings = LoggedPieceOpenings(log: log.folder)
        self.init(defaults: defaults) { filter in
            guard let reader else { return .empty(filter) }
            return ProgressAnalyzer.report(from: reader.read(), pieceOpenings: openings.events, filter: filter)
        }
    }

    /// Shows `report` without reading the log, whatever filter is picked: for previews and checks.
    /// Nothing is saved.
    convenience init(showing report: ProgressReport) {
        self.init(defaults: nil, filter: report.filter) { filter in
            var report = report
            report.filter = filter
            return report
        }
        self.report = report
        hasLoaded = true
    }

    /// `load` works out a report for a filter; `defaults` (if any) keeps the filter between launches.
    init(defaults: UserDefaults?, filter: ProgressFilter? = nil,
         load: @escaping @Sendable (ProgressFilter) -> ProgressReport) {
        self.defaults = defaults
        self.load = load
        let saved = defaults?.data(forKey: Self.filterKey).flatMap { try? JSONDecoder().decode(ProgressFilter.self, from: $0) }
        let filter = filter ?? saved ?? ProgressFilter()
        self.filter = filter
        report = .empty(filter)
    }

    /// Works the report out again for the current filter. While one is running, further calls are
    /// folded into a single reload after it.
    func reload() {
        guard !isLoading else {
            reloadRequested = true
            return
        }
        isLoading = true
        let filter = filter
        let load = load
        Task {
            let report = await Task.detached(priority: .userInitiated) { load(filter) }.value
            finishLoading(report, for: filter)
        }
    }

    private func finishLoading(_ report: ProgressReport, for filter: ProgressFilter) {
        isLoading = false
        // A report for a filter no longer picked would show the wrong numbers: the reload that
        // follows replaces the previous one instead.
        if filter == self.filter {
            self.report = report
            hasLoaded = true
        }
        if reloadRequested || filter != self.filter {
            reloadRequested = false
            reload()
        }
    }

    private func saveFilter() {
        defaults?.set(try? JSONEncoder().encode(filter), forKey: Self.filterKey)
    }
}

/// The `pieceOpened` events in a usage log, read the first time they're asked for and then kept:
/// all the journal's dashboard needs from the log (see `ProgressStore.init(reader:…)`). Safe to
/// use from any thread.
final class LoggedPieceOpenings: @unchecked Sendable {
    private let folder: URL
    /// Guards `read`.
    private let lock = NSLock()
    private var read: [LoggedEvent]?

    /// Reads nothing yet.
    init(log folder: URL) {
        self.folder = folder
    }

    /// The log's `pieceOpened` events, in time order, as first read.
    var events: [LoggedEvent] {
        lock.withLock {
            if let read { return read }
            let events = Self.read(in: folder)
            read = events
            return events
        }
    }

    /// Every `pieceOpened` event in the usage log in `folder`, in time order (ties as written).
    /// Only lines holding `"type":"pieceOpened"` are decoded, so a long log is read quickly; lines
    /// that don't parse are skipped.
    static func read(in folder: URL) -> [LoggedEvent] {
        let marker = Data(#""type":"pieceOpened""#.utf8)
        var events: [LoggedEvent] = []
        for url in UsageLog.eventFiles(in: folder) {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            var from = data.startIndex
            while from < data.endIndex, let found = data.range(of: marker, in: from..<data.endIndex) {
                let start = data[..<found.lowerBound].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
                let end = data[found.upperBound...].firstIndex(of: 0x0A) ?? data.endIndex
                if let logged = UsageLog.event(in: data[start..<end]), case .pieceOpened = logged.event {
                    events.append(logged)
                }
                from = end
            }
        }
        return events.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }
}
