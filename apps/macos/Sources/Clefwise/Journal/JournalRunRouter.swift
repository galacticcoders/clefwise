import Foundation

// One usage log, several journals: each run's lines go to the run-file writer of the journal that
// was in use when it started. See spec/practice-journal.md, "Several journals".

/// The usage log's one line sink (`UsageLog.lineSink`, set once at launch). It hands each line to
/// the run-file writer of the journal in use (`target`), which changes between rounds when the
/// user switches journals (`retarget(to:)`). A run's lines all go to the writer that took its
/// `roundStarted`, until its `roundEnded`, even should the journal change in between. With no
/// journal in use, lines go nowhere but the usage log.
final class JournalRunRouter: RunLineSink, @unchecked Sendable {
    /// Guards `target` and `run`: lines come on the usage log's queue, switches on the main thread.
    private let lock = NSLock()
    private var target: RunFileWriter?
    /// The run going on, and the writer it goes to.
    private var run: (round: UUID, writer: RunFileWriter)?

    init(target: RunFileWriter?) {
        self.target = target
    }

    /// The writer the next run goes to.
    var writer: RunFileWriter? {
        lock.withLock { target }
    }

    /// Sends the next run to `writer`; nil for none (no journal in use: runs get no file). Lines
    /// already recorded may still be waiting on the usage log's queue, and go to whichever writer is
    /// the target when they're written: flush the log first, so each goes where it belongs.
    func retarget(to writer: RunFileWriter?) {
        lock.withLock { target = writer }
    }

    /// A run brought back at launch, whose working file `writer` has open again
    /// (`RunFileWriting.inspectAtLaunch()`): its lines go there until its `roundEnded`.
    func continueRun(_ round: UUID, in writer: RunFileWriter) {
        lock.withLock { run = (round, writer) }
    }

    func lineLogged(_ line: Data, _ event: LoggedEvent) {
        let writer = lock.withLock { () -> RunFileWriter? in
            if case .roundStarted(let started) = event.event {
                run = target.map { (started.round, $0) }
            }
            let writer = run?.writer ?? target
            if case .roundEnded(let ended) = event.event, ended.round == run?.round {
                run = nil
            }
            return writer
        }
        writer?.lineLogged(line, event)
    }
}
