import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The app's side of the usage log: what it's running on, the window's size, the File menu's
// usage data items, and clicks no other event captures.

extension AppLaunched {
    /// This launch: the app and macOS versions, the Mac, its locale and time zone, the main screen.
    @MainActor
    static var current: AppLaunched {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return AppLaunched(
            // `swift run` has no bundle to say.
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "dev",
            build: info?["CFBundleVersion"] as? String ?? "dev",
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            model: modelIdentifier ?? "unknown",
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            screen: NSScreen.main.map { Size(width: $0.frame.width, height: $0.frame.height) }
        )
    }

    /// "Mac15,12"
    private static var modelIdentifier: String? {
        var length = 0
        guard sysctlbyname("hw.model", nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        guard sysctlbyname("hw.model", &bytes, &length, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}

extension UsageRecorder {
    /// A button or menu item used that no other event captures.
    func recordUIAction(_ name: String, detail: String? = nil) {
        record(.uiAction(UIAction(name: name, detail: detail)))
    }
}

extension Binding where Value: Equatable {
    /// The same binding, also logging `name` with `detail` of the new value whenever the control
    /// it drives changes it. The game logs the setting itself; this says which control did it.
    func recordingChanges(as name: String, to recorder: UsageRecorder, detail: @escaping (Value) -> String) -> Binding {
        Binding(get: { wrappedValue }, set: { newValue in
            if newValue != wrappedValue { recorder.recordUIAction(name, detail: detail(newValue)) }
            wrappedValue = newValue
        })
    }
}

extension Binding where Value == Bool {
    /// For toggles: the detail is "on" or "off".
    func recordingChanges(as name: String, to recorder: UsageRecorder) -> Binding {
        recordingChanges(as: name, to: recorder) { $0 ? "on" : "off" }
    }
}

/// File ▸ Export Usage Data… and Show Usage Data in Finder. Neither touches the game, so both
/// work mid-round.
@MainActor
enum UsageData {
    /// Asks where to save, then writes everything logged so far into a zip there and shows it in Finder.
    static func export() {
        UsageLog.shared.recordUIAction("exportUsageData")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().format(Date())
        panel.nameFieldStringValue = "Clefwise usage \(day).zip"
        guard let window = NSApp.mainWindow else {
            if panel.runModal() == .OK, let url = panel.url { export(to: url) }
            return
        }
        Task {
            if await panel.beginSheetModal(for: window) == .OK, let url = panel.url { export(to: url) }
        }
    }

    static func export(to destination: URL) {
        // Events can still be on their way to disk; the export reads the files.
        UsageLog.shared.flush()
        do {
            try UsageExport.export(UsageLog.shared, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            show(error, as: "Couldn't export the usage data")
        }
    }

    static func showInFinder() {
        UsageLog.shared.recordUIAction("showUsageData")
        let folder = UsageLog.shared.folder
        do {
            // Nothing may be written yet, and Finder can't show a folder that isn't there.
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch {
            show(error, as: "Couldn't show the usage data")
        }
    }

    private static func show(_ error: Error, as message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        if let window = NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

/// Logs the window's size once it's up, and again each time it settles after a change.
struct WindowSizeRecorder: NSViewRepresentable {
    let recorder: UsageRecorder

    func makeNSView(context: Context) -> NSView { WindowSizeView(recorder: recorder) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowSizeView: NSView {
    /// A drag-resize sends a stream of sizes; only the one it rests at is logged.
    private static let settleTime: Duration = .seconds(1)

    private let recorder: UsageRecorder
    private var lastSize: CGSize?
    private var pendingRecord: Task<Void, Never>?

    init(recorder: UsageRecorder) {
        self.recorder = recorder
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Only watches; clicks go to whatever is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize),
                                               name: NSWindow.didResizeNotification, object: window)
        windowDidResize()
    }

    @objc private func windowDidResize() {
        pendingRecord?.cancel()
        pendingRecord = Task { [weak self] in
            try? await Task.sleep(for: Self.settleTime)
            guard !Task.isCancelled else { return }
            self?.recordSize()
        }
    }

    /// The whole window in points, title bar and toolbar included, as it compares with the screen.
    private func recordSize() {
        guard let size = window?.frame.size else { return }
        if let lastSize, abs(size.width - lastSize.width) < 1, abs(size.height - lastSize.height) < 1 { return }
        lastSize = size
        recorder.record(.windowResized(WindowResized(size: Size(width: size.width, height: size.height))))
    }
}
