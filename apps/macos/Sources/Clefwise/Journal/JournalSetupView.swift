import AppKit
import SwiftUI

// The practice journal in the window: the sheet that makes it at first launch, the alert when it
// can't be found, and File ▸ Show Journal in Finder.

/// What the main window shows about the journal: a sheet asking to make one while none is set,
/// or an alert when the one set can't be found. The app delegate makes one, kept for the app's life.
@MainActor @Observable
final class JournalSetup {
    @ObservationIgnored let journal: PracticeJournal
    /// Takes what waited for the journal once there's one; nil in tests that don't need it.
    @ObservationIgnored private let outbox: JournalOutbox?
    @ObservationIgnored private let recorder: UsageRecorder
    /// The usage log already has practice in it, which a new journal brings in.
    @ObservationIgnored let hasPractice: Bool
    /// Called with the journal's folder once the sheet has made it (or taken one already there):
    /// where the usage log so far is brought in. Does nothing until the app sets it.
    @ObservationIgnored var onJournalCreated: (URL) -> Void = { _ in }

    /// The sheet asking to make a journal is up.
    var isAskingToCreate = false
    /// The alert saying the journal can't be found is up.
    var isReportingMissing = false
    /// Why the folder picked with Locate… wasn't taken, said in the alert shown again.
    private(set) var locateError: String?
    /// The journal's folder as last found; nil while there's none (File ▸ Show Journal in Finder
    /// is greyed out).
    private(set) var folder: URL?

    /// `usageFolder` is the usage log's: any day files there are the practice so far.
    init(journal: PracticeJournal, outbox: JournalOutbox?, usageFolder: URL, recorder: UsageRecorder) {
        self.journal = journal
        self.outbox = outbox
        self.recorder = recorder
        hasPractice = !UsageLog.eventFiles(in: usageFolder).isEmpty
        folder = journal.folder
    }

    /// Once the window is up: asks for a journal when none is set, and says so when it can't be
    /// found.
    func checkAtLaunch() {
        folder = journal.folder
        if !journal.isSet {
            isAskingToCreate = true
        } else if folder == nil {
            isReportingMissing = true
        }
    }

    /// The journal's path to show when it can't be found, from the home folder.
    var missingPath: String {
        (journal.lastKnownPath.map { $0 as NSString })?.abbreviatingWithTildeInPath ?? ""
    }

    /// Makes the journal `name` in `parent`, or takes the one already there; then everything that
    /// waited for it goes in, and `onJournalCreated` runs.
    func create(named name: String, in parent: URL) throws {
        let existing = PracticeJournal.existingJournal(named: name, in: parent) != nil
        let made = try journal.create(named: name, in: parent)
        recorder.recordUIAction("createJournal", detail: existing ? "existing" : "new")
        folder = made
        isAskingToCreate = false
        isReportingMissing = false
        outbox?.placePending()
        onJournalCreated(made)
    }

    /// Keeps `chosen` as the journal, found again by the user; throws when it isn't one.
    func use(_ chosen: URL) throws {
        try journal.use(chosen)
        folder = chosen
        locateError = nil
        outbox?.placePending()
    }

    // MARK: - The alert's buttons

    /// Locate…: a folder panel on the window. A folder with `clefwise.json` becomes the journal;
    /// anything else, or cancelling, brings the alert back.
    func locate() {
        recorder.recordUIAction("locateJournal")
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Find your Clefwise journal: the folder with clefwise.json in it."
        panel.prompt = "Use Journal"
        if let path = journal.lastKnownPath {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        Task {
            let response = if let window = NSApp.mainWindow { await panel.beginSheetModal(for: window) }
                           else { panel.runModal() }
            guard response == .OK, let chosen = panel.url else {
                recorder.recordUIAction("locateJournalCancelled")
                reportMissingAgain()
                return
            }
            do {
                try use(chosen)
            } catch {
                locateError = error.localizedDescription
                reportMissingAgain()
            }
        }
    }

    /// Create New…: the sheet, in place of the alert.
    func createNew() {
        recorder.recordUIAction("createNewJournal")
        // Once the alert has gone: one presentation at a time.
        Task { isAskingToCreate = true }
    }

    /// The alert again, unless the journal has come back meanwhile (a disk plugged in).
    private func reportMissingAgain() {
        folder = journal.folder
        guard folder == nil else { return }
        Task { isReportingMissing = true }
    }

    // MARK: - File menu

    /// File ▸ Show Journal in Finder. A journal gone since it was last found brings up the alert.
    func showInFinder() {
        recorder.recordUIAction("showJournal")
        folder = journal.folder
        guard let folder else {
            isReportingMissing = journal.isSet
            return
        }
        NSWorkspace.shared.open(folder)
    }
}

extension View {
    /// The journal's sheet and alert on the main window.
    func journalSetup(_ setup: JournalSetup) -> some View {
        modifier(JournalSetupPresenter(setup: setup))
    }
}

/// Puts up the journal's sheet and alert as `setup` asks, and has it look at launch.
private struct JournalSetupPresenter: ViewModifier {
    @Bindable var setup: JournalSetup

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $setup.isAskingToCreate) {
                JournalCreateSheet(setup: setup)
                    .tint(Theme.accent)
            }
            .alert("Clefwise can't find your journal", isPresented: $setup.isReportingMissing) {
                Button("Locate…") { setup.locate() }
                Button("Create New…") { setup.createNew() }
            } message: {
                Text([setup.missingPath, setup.locateError].compactMap { $0 }.joined(separator: "\n\n"))
            }
            .onAppear { setup.checkAtLaunch() }
    }
}

/// "Your practice journal": asks where to make it, at first launch or with Create New…. Its one
/// button makes it, and nothing else closes it: Clefwise keeps practice nowhere else.
private struct JournalCreateSheet: View {
    let setup: JournalSetup
    @State private var name: String
    @State private var location: URL
    /// The name last suggested, which follows the location until the user types their own.
    @State private var suggestedName: String
    @State private var error: String?

    init(setup: JournalSetup) {
        self.setup = setup
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let suggestion = PracticeJournal.suggestedName(in: documents)
        _location = State(initialValue: documents)
        _name = State(initialValue: suggestion)
        _suggestedName = State(initialValue: suggestion)
    }

    /// The location chosen is a journal already, so it's used as it is and needs no name.
    private var isJournalAlready: Bool { PracticeJournal.isJournal(location) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What the button will do, in a line.
    private var plan: String {
        if isJournalAlready { return "This folder is a journal already, so Clefwise will use it as it is." }
        let folder = Self.shortPath(location.appendingPathComponent(trimmedName))
        if PracticeJournal.existingJournal(named: trimmedName, in: location) != nil {
            return "There's a journal at \(folder) already, so Clefwise will use it as it is."
        }
        return "Clefwise will make the folder \(folder)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your practice journal")
                    .font(.title2.weight(.semibold))
                Text("Clefwise keeps your practice in a practice journal: a folder of plain files that's yours. "
                     + "Back it up or sync it however you like.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 12) {
                GridRow {
                    Text("Name:")
                        .gridColumnAlignment(.trailing)
                    TextField("Name", text: $name)
                        .labelsHidden()
                        .disabled(isJournalAlready)
                }
                GridRow {
                    Text("Location:")
                    HStack {
                        Text(Self.shortPath(location))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(location.path)
                        Spacer()
                        Button("Choose…", action: choose)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(plan)
                if setup.hasPractice {
                    Text("Your practice so far will be copied in.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error)
                    .foregroundStyle(Theme.wrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(PracticeJournal.existingJournal(named: trimmedName, in: location) != nil
                       ? "Use Journal" : "Create Journal", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isJournalAlready && trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Theme.paper)
        .interactiveDismissDisabled()
    }

    private func create() {
        do {
            try setup.create(named: trimmedName, in: location)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A folder panel on the sheet for where the journal goes. A journal picked here is used as it is.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = location
        panel.message = "Choose where to keep your practice journal."
        panel.prompt = "Choose"
        Task {
            let response = if let window = NSApp.keyWindow { await panel.beginSheetModal(for: window) }
                           else { panel.runModal() }
            guard response == .OK, let chosen = panel.url else { return }
            location = chosen
            error = nil
            // A name the user hasn't changed follows the new place.
            if name == suggestedName {
                suggestedName = PracticeJournal.suggestedName(in: chosen)
                name = suggestedName
            }
        }
    }

    /// "~/Documents/Clefwise Journal"
    private static func shortPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
