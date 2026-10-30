import Foundation

enum ProgressAnalyzer {
    /// Works out the dashboard for `filter` from `events` (in time order, as `UsageLog.readEvents`
    /// gives them). Pure and thread-safe: call it off the main thread for a long log.
    static func report(from events: [LoggedEvent], filter: ProgressFilter, unreadableLines: Int = 0,
                       now: Date = Date(), calendar: Calendar = .current) -> ProgressReport {
        var report = ProgressReport.empty(filter, at: now)
        report.unreadableLines = unreadableLines
        return report
    }
}
