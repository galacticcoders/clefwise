import AppKit
import SwiftUI

// The practice journals in the window: the sheet that makes one (at first launch, and for New
// Journal…), the alert when the one in use can't be found, the one when a folder picked to open
// isn't a journal, and the question before one leaves the list.

/// What the main window shows about the journals: a sheet asking to make one, an alert when the
/// one in use can't be found, and the confirmations and refusals that go with them. The app model
/// makes one, kept for the app's life, and makes every change to the journals itself
/// (`AppModel`); this is what's on screen about them.
@MainActor @Observable
final class JournalSetup {
    @ObservationIgnored let registry: JournalRegistry
    @ObservationIgnored private let recorder: UsageRecorder
    /// The usage log already has practice in it, which the first journal on this Mac brings in.
    @ObservationIgnored let hasPractice: Bool

    /// The sheet asking to make a journal is up.
    var isAskingToCreate = false
    /// The sheet can be closed without making one (New Journal…, with a journal in use). At first
    /// launch it can't: Clefwise keeps practice nowhere else.
    private(set) var canCancelCreate = false
    /// The alert saying the journal in use can't be found is up.
    var isReportingMissing = false
    /// Why the folder picked with Locate… wasn't taken, said in the alert shown again.
    var locateError: String?
    /// The folder picked with Open Journal…, when it isn't a journal; its alert is up meanwhile.
    var notAJournal: URL?
    /// The journal waiting for the user to confirm it's to leave the list; its question is up
    /// meanwhile.
    var removing: JournalRecord?
    /// The journal in use's folder as last found; nil while there's none or it can't be found
    /// (File ▸ Show Journal in Finder is greyed out).
    private(set) var folder: URL?

    /// `usageFolder` is the usage log's: any day files there are the practice so far.
    init(registry: JournalRegistry, usageFolder: URL, recorder: UsageRecorder) {
        self.registry = registry
        self.recorder = recorder
        hasPractice = !UsageLog.eventFiles(in: usageFolder).isEmpty
        folder = registry.current.flatMap(registry.folder(for:))
    }

    /// Once the window is up: asks for a journal when there's none, and says so when the one in
    /// use can't be found.
    func checkAtLaunch() {
        lookAgain()
        if registry.current == nil {
            askToCreate(cancellable: false)
        } else if folder == nil {
            isReportingMissing = true
        }
    }

    /// Looks for the journal in use again. With `reportingMissing`, one that can't be found
    /// brings up the alert, once whatever is up now has gone.
    func lookAgain(reportingMissing: Bool = false) {
        folder = registry.current.flatMap(registry.folder(for:))
        if reportingMissing { reportMissingAgain() }
    }

    /// The sheet that makes a journal; `cancellable` when it can be closed without.
    func askToCreate(cancellable: Bool) {
        canCancelCreate = cancellable
        isAskingToCreate = true
    }

    /// The practice so far goes into the journal the sheet makes: it's the first on this Mac to
    /// have it.
    var bringsInPractice: Bool {
        hasPractice && registry.defaults.object(forKey: AppModel.Keys.usageLogBroughtIn) == nil
    }

    // MARK: - The missing alert

    /// The journal in use's path to show when it can't be found, from the home folder.
    var missingPath: String {
        registry.current.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
    }

    /// The journals the alert offers to switch to: every other one on the list.
    var others: [JournalRecord] {
        registry.records.filter { $0.id != registry.currentID }
    }

    /// Create New…: the sheet, in place of the alert.
    func createNew() {
        recorder.recordUIAction("createNewJournal")
        // Once the alert has gone: one presentation at a time.
        Task { askToCreate(cancellable: false) }
    }

    /// Locate… found a folder that wouldn't do: the alert again, saying why.
    func locateFailed(_ reason: String) {
        locateError = reason
        reportMissingAgain()
    }

    /// The alert again, once whatever is up now has gone, unless the journal in use has come back
    /// meanwhile (a disk plugged in) or there's none.
    func reportMissingAgain() {
        folder = registry.current.flatMap(registry.folder(for:))
        guard folder == nil, registry.current != nil else { return }
        Task { isReportingMissing = true }
    }
}

extension View {
    /// The journals' sheet, alerts and questions on the main window.
    func journalSetup(_ model: AppModel) -> some View {
        modifier(JournalSetupPresenter(model: model, setup: model.setup))
    }
}

/// Puts up the journals' sheet, alerts and questions as `setup` asks, and has it look at launch.
private struct JournalSetupPresenter: ViewModifier {
    let model: AppModel
    @Bindable var setup: JournalSetup

    /// How many other journals the missing alert offers to switch to.
    private static let switchChoices = 3

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $setup.isAskingToCreate) {
                JournalCreateSheet(model: model)
                    .tint(Theme.accent)
            }
            .alert("Clefwise can't find your journal", isPresented: $setup.isReportingMissing) {
                Button("Locate…") { model.locateJournal() }
                Button("Create New…") { setup.createNew() }
                let names = model.registry.displayNames
                ForEach(setup.others.prefix(Self.switchChoices)) { other in
                    Button("Switch to “\(names[other.id] ?? other.name)”") {
                        model.switchJournal(to: other, from: "missingAlert")
                    }
                }
            } message: {
                Text([setup.missingPath, setup.locateError].compactMap { $0 }.joined(separator: "\n\n"))
            }
            .alert("That folder isn't a Clefwise journal.", isPresented: isRefusingFolder, presenting: setup.notAJournal) { _ in
                Button("OK") {}
            } message: { folder in
                Text("“\(folder.lastPathComponent)” has no clefwise.json in it. Choose the folder your journal is in, "
                     + "or make a new one with New Journal….")
            }
            .confirmationDialog(removalTitle, isPresented: isConfirmingRemoval, presenting: setup.removing) { record in
                Button("Remove from List", role: .destructive) { model.remove(record) }
                Button("Cancel", role: .cancel) { model.log.recordUIAction("removeJournalCancelled") }
            } message: { record in
                Text(removalMessage(for: record))
            }
            .onAppear { setup.checkAtLaunch() }
    }

    private var isRefusingFolder: Binding<Bool> {
        Binding(get: { setup.notAJournal != nil }, set: { if !$0 { setup.notAJournal = nil } })
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding(get: { setup.removing != nil }, set: { if !$0 { setup.removing = nil } })
    }

    private var removalTitle: String {
        setup.removing.map { "Remove “\($0.name)” from your journals?" } ?? ""
    }

    private func removalMessage(for record: JournalRecord) -> String {
        let place = (URL(fileURLWithPath: record.path).deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        var text = "Clefwise stops using it on this Mac. The folder and everything in it stay as they are, in \(place): "
            + "open it again with Open Journal…, and it starts from the default settings."
        guard record.id == model.registry.currentID else { return text }
        if let next = model.registry.records.first(where: { $0.id != record.id }) {
            text += " Clefwise switches to “\(next.name)”."
        } else {
            text += " Clefwise then asks where to keep a new journal."
        }
        return text
    }
}

/// Asks where to make a journal: "Your practice journal" at first launch (and with Create New…),
/// "A new practice journal" with New Journal…. Its one button makes it; only New Journal…'s has
/// Cancel too: Clefwise keeps practice nowhere else.
private struct JournalCreateSheet: View {
    let model: AppModel
    @State private var name: String
    @State private var location: URL
    /// The name last suggested, which follows the location until the user types their own.
    @State private var suggestedName: String
    @State private var error: String?
    /// Another journal besides the one in use, so the next free name is suggested.
    private let isAnother: Bool

    init(model: AppModel) {
        self.model = model
        isAnother = model.setup.canCancelCreate
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let suggestion = PracticeJournal.suggestedName(in: documents, fresh: isAnother)
        _location = State(initialValue: documents)
        _name = State(initialValue: suggestion)
        _suggestedName = State(initialValue: suggestion)
    }

    private var setup: JournalSetup { model.setup }
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
                Text(isAnother ? "A new practice journal" : "Your practice journal")
                    .font(.title2.weight(.semibold))
                Text(isAnother
                     ? "Each person keeps their own journal, with their own settings and pieces on this Mac. "
                        + "Switch between them from the Journal menu between rounds."
                     : "Clefwise keeps your practice in a practice journal: a folder of plain files that's yours. "
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
                if setup.bringsInPractice {
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
                if setup.canCancelCreate {
                    Button("Cancel", role: .cancel) { model.cancelNewJournal() }
                        .keyboardShortcut(.cancelAction)
                }
                Button(PracticeJournal.existingJournal(named: trimmedName, in: location) != nil
                       ? "Use Journal" : "Create Journal", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isJournalAlready && trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Theme.paper)
        .interactiveDismissDisabled(!setup.canCancelCreate)
    }

    private func create() {
        do {
            try model.createJournal(named: trimmedName, in: location)
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
                suggestedName = PracticeJournal.suggestedName(in: chosen, fresh: isAnother)
                name = suggestedName
            }
        }
    }

    /// "~/Documents/Clefwise Journal"
    private static func shortPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
