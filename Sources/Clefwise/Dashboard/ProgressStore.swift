import Foundation
import Observation

/// What the Progress window shows: the filter, and the report worked out for it from the usage
/// log. Reading and analysing the log happens off the main thread, so practice carries on, and
/// the last report stays on screen until the new one is ready.
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

    /// The app's store: reads `log`, keeps the filter in `defaults`.
    convenience init(defaults: UserDefaults = .standard, log: UsageLog = .shared) {
        self.init(defaults: defaults) { filter in
            // Events still on their way to disk (the round that just ended) count too.
            log.flush()
            let read = UsageLog.readEvents(in: log.folder)
            return ProgressAnalyzer.report(from: read.events, filter: filter, unreadableLines: read.unreadableLines)
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
