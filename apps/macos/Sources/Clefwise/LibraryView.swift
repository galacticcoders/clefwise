import AppKit
import SwiftUI

// The piece library in the window: the start panel's latest pieces, the "Your pieces" sheet with
// all of them, and what the piece panel's Open another… menu and File ▸ Open Recent Piece share.

/// Whether the "Your pieces" sheet is up on the main window. The File menu, both panels and the
/// sheet itself share it.
@MainActor @Observable
final class PieceListSheet {
    static let shared = PieceListSheet()

    var isShown = false

    /// Shows the sheet between rounds; `source` says which control asked, for the usage log.
    func show(from source: String, game: Game) {
        guard game.phase != .playing else {
            NSSound.beep()
            return
        }
        game.recorder.recordUIAction("showAllPieces", detail: source)
        isShown = true
    }
}

// MARK: - Words

extension PieceLibrary.Entry {
    /// The score's title, or its file's name for a score without one.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? originalURL.deletingPathExtension().lastPathComponent : trimmed
    }

    var originalURL: URL { URL(fileURLWithPath: originalPath) }

    /// "~/Music/Scores"
    var originalFolder: String {
        (originalURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    /// Whether the file it was first opened from is still there (Clefwise's copy works either way).
    var originalExists: Bool { FileManager.default.fileExists(atPath: originalPath) }

    /// Whether `game` has this piece open.
    @MainActor
    func isOpen(in game: Game) -> Bool {
        game.isPractisingPiece && game.pieceEntryID == id
    }
}

extension Array where Element == PieceLibrary.Entry {
    /// Each entry's title for a menu or list: the title alone, with the file's name added where two
    /// share a title, and its folder too where they share that as well.
    func distinctTitles() -> [UUID: String] {
        let byTitle = Dictionary(grouping: self) { $0.displayTitle }
        var titles: [UUID: String] = [:]
        for entry in self {
            let title = entry.displayTitle
            guard byTitle[title]!.count > 1 else {
                titles[entry.id] = title
                continue
            }
            let sameFileName = byTitle[title]!.filter { $0.originalURL.lastPathComponent == entry.originalURL.lastPathComponent }
            let file = sameFileName.count > 1 ? (entry.originalPath as NSString).abbreviatingWithTildeInPath
                : entry.originalURL.lastPathComponent
            titles[entry.id] = "\(title) (\(file))"
        }
        return titles
    }
}

enum PieceDates {
    /// "today", "yesterday", "3 days ago", then a date: "12 Oct", or "12 Oct 2025" in another year.
    static func relative(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "today" // a clock put back reads as today too
        case 1: return "yesterday"
        case 2...6: return "\(days) days ago"
        default:
            let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
                .day().month(.abbreviated)
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return date.formatted(sameYear ? style : style.year())
        }
    }
}

// MARK: - Start panel

/// Under the start panel's Practise a piece… row: the latest pieces, a click each to practise one
/// again, and the way to all of them.
struct RecentPiecesSection: View {
    let game: Game
    /// How many of the latest pieces to list; the panel shows fewer when the card is short.
    let count: Int

    static let width: CGFloat = 340

    var body: some View {
        if count == 0 {
            // No room for a row: just the way to them, rather than a heading over nothing.
            Button("Open one of your pieces…") { PieceListSheet.shared.show(from: "startPanel", game: game) }
                .buttonStyle(.link)
                .font(.callout)
                .help("Every piece you've opened, to practise, find or remove one")
        } else {
            rows
        }
    }

    private var rows: some View {
        let entries = Array(game.library.entries.prefix(count))
        let titles = entries.distinctTitles()
        let now = Date.now
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your pieces")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("All pieces…") { PieceListSheet.shared.show(from: "startPanel", game: game) }
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("Every piece you've opened, to practise, find or remove one")
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
            ForEach(entries) { entry in
                Button {
                    PieceFile.open(entry, in: game, from: "startPanel")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.callout)
                            .frame(width: 14)
                        Text(titles[entry.id] ?? entry.displayTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 12)
                        Text(PieceDates.relative(entry.lastOpenedAt, now: now))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .buttonStyle(PieceRowStyle())
                .help("Practise “\(entry.displayTitle)” again (last practised \(PieceDates.relative(entry.lastOpenedAt, now: now)))")
            }
        }
        .multilineTextAlignment(.leading)
        .frame(width: Self.width)
    }
}

/// A row that reads as a link: the accent colour, a tint under the pointer, a darker one pressed.
private struct PieceRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .background(Theme.accent.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.08 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - The sheet

/// "Your pieces": every piece opened, most recently practised first, to open, find in Finder or
/// remove. Esc or Done closes it.
struct PieceListView: View {
    let game: Game
    @State private var search = ""
    /// The piece whose removal is being confirmed.
    @State private var removing: PieceLibrary.Entry?
    @FocusState private var isSearchFocused: Bool

    /// With more pieces than this, a search field helps find one.
    static let searchThreshold = 8

    private var library: PieceLibrary { game.library }
    private var showsSearch: Bool { library.entries.count > Self.searchThreshold }
    private var query: String { showsSearch ? search.trimmingCharacters(in: .whitespaces) : "" }

    private var shownEntries: [PieceLibrary.Entry] {
        guard !query.isEmpty else { return library.entries }
        return library.entries.filter { entry in
            [entry.displayTitle, entry.originalURL.lastPathComponent, entry.originalFolder]
                .contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
            Divider()
            list
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 700)
        .background(Theme.paper)
        .confirmationDialog(removalTitle, isPresented: isConfirmingRemoval, presenting: removing) { entry in
            Button("Remove from List", role: .destructive) {
                game.recorder.recordUIAction("removeLibraryPiece", detail: entry.originalPath)
                library.remove(entry.id)
            }
            Button("Cancel", role: .cancel) {
                game.recorder.recordUIAction("removeLibraryPieceCancelled", detail: entry.originalPath)
            }
        } message: { entry in
            Text(removalMessage(for: entry))
        }
        .onAppear { isSearchFocused = showsSearch }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your pieces")
                    .font(.title2.weight(.semibold))
                Text("Every piece you open is kept here, with its settings, to practise again.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $search, prompt: Text("Title or file name"))
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit(openFirstMatch)
                    if !search.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: 220)
                .background(Theme.keyFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.keyBorder)
                }
                .help("Find a piece by its title, file name or folder; Return opens the first one found")
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let entries = shownEntries
        if library.isEmpty {
            message("No pieces yet", "Pieces you open with Practise a piece… or by dropping a file are kept here.")
        } else if entries.isEmpty {
            message("No pieces match “\(query)”", "Search looks at titles, file names and folders.")
        } else {
            let titles = library.entries.distinctTitles()
            let now = Date.now
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        row(entry, title: titles[entry.id] ?? entry.displayTitle, now: now)
                        if entry.id != entries.last?.id {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
            .frame(maxHeight: 440)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func row(_ entry: PieceLibrary.Entry, title: String, now: Date) -> some View {
        let isOpen = entry.isOpen(in: game)
        let originalExists = entry.originalExists
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(originalLine(for: entry, exists: originalExists))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(originalExists ? entry.originalPath
                          : "The original file is no longer at \(entry.originalPath). Clefwise's own copy still opens.")
                Text(datesLine(for: entry, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // A double click on the words opens the piece too.
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if !isOpen { PieceFile.open(entry, in: game, from: "pieceListDoubleClick") }
            }
            Spacer(minLength: 8)
            HStack(spacing: 14) {
                if originalExists {
                    Button("Show in Finder", systemImage: "folder") {
                        game.recorder.recordUIAction("revealLibraryOriginal", detail: entry.originalPath)
                        NSWorkspace.shared.activateFileViewerSelecting([entry.originalURL])
                    }
                    .help("Show the original file, “\(entry.originalURL.lastPathComponent)”, in Finder")
                }
                Button("Remove…", systemImage: "trash") { removing = entry }
                    .help("Take the piece off this list. The original file isn't touched.")
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .fixedSize()
            if isOpen {
                Text("Open now")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72)
                    .help("You're practising this piece")
            } else {
                Button("Open") {
                    PieceFile.open(entry, in: game, from: query.isEmpty ? "pieceList" : "pieceListSearch")
                }
                .frame(minWidth: 72)
                .help("Practise “\(entry.displayTitle)”")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// "bar-view.musicxml  ·  ~/Music/Scores", saying so when the file has gone.
    private func originalLine(for entry: PieceLibrary.Entry, exists: Bool) -> String {
        let line = "\(entry.originalURL.lastPathComponent)  ·  \(entry.originalFolder)"
        return exists ? line : line + "  (moved or deleted)"
    }

    /// "Added 12 Oct  ·  last practised yesterday"
    private func datesLine(for entry: PieceLibrary.Entry, now: Date) -> String {
        "Added \(PieceDates.relative(entry.addedAt, now: now))  ·  last practised \(PieceDates.relative(entry.lastOpenedAt, now: now))"
    }

    private var footer: some View {
        HStack {
            Text(countText)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") {
                game.recorder.recordUIAction("closeAllPieces")
                PieceListSheet.shared.isShown = false
            }
            .keyboardShortcut(.cancelAction)
            .help("Close the list (Esc)")
        }
    }

    private var countText: String {
        let total = library.entries.count
        let pieces = total == 1 ? "1 piece" : "\(total) pieces"
        guard !query.isEmpty else { return pieces }
        return "\(shownEntries.count) of \(pieces)"
    }

    private func openFirstMatch() {
        guard let first = shownEntries.first(where: { !$0.isOpen(in: game) }) else { return }
        PieceFile.open(first, in: game, from: "pieceListSearch")
    }

    // MARK: Removing

    private var isConfirmingRemoval: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private var removalTitle: String {
        removing.map { "Remove “\($0.displayTitle)” from your pieces?" } ?? ""
    }

    private func removalMessage(for entry: PieceLibrary.Entry) -> String {
        var text = "Clefwise forgets the piece, its practice settings and its own copy. "
            + "The original file, “\(entry.originalURL.lastPathComponent)” in \(entry.originalFolder), isn't touched."
        if entry.isOpen(in: game) { text += " The piece stays open until you open another." }
        return text
    }
}
