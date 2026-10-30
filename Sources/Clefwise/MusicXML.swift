import Foundation

/// Problems reading a score, worded for the person who picked the file.
struct ScoreImportError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

enum MusicXMLImporter {
    /// Reads an uncompressed MusicXML file (.musicxml, .xml) or a compressed one (.mxl).
    static func load(from url: URL) throws -> Score {
        let fileName = url.lastPathComponent
        guard let data = try? Data(contentsOf: url) else {
            throw ScoreImportError(message: "“\(fileName)” couldn't be opened.")
        }
        // .mxl is a zip; go by the content, since compressed files are sometimes named .xml.
        let xml = data.starts(with: [0x50, 0x4B]) ? try unzippedScore(at: url) : data
        return try parse(xml, fileName: fileName, fallbackTitle: url.deletingPathExtension().lastPathComponent)
    }

    private static func parse(_ data: Data, fileName: String, fallbackTitle: String) throws -> Score {
        let reader = ScoreReader()
        let parser = XMLParser(data: data)
        // Every MusicXML file names a DTD on musicxml.org; never go and fetch it.
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        let parsed = parser.parse()

        switch reader.root {
        case "score-partwise":
            break
        case "score-timewise":
            throw ScoreImportError(message: "“\(fileName)” is timewise MusicXML, which Clefwise can't read. "
                                   + "Export it again from your notation app as regular (partwise) MusicXML.")
        default:
            throw ScoreImportError(message: "“\(fileName)” isn't a MusicXML file.")
        }
        guard parsed else {
            throw ScoreImportError(message: "“\(fileName)” looks damaged and couldn't be read.")
        }
        guard !reader.parts.isEmpty else {
            throw ScoreImportError(message: "“\(fileName)” has no notes in treble or bass clef to practise.")
        }
        let title = [reader.workTitle, reader.movementTitle].compactMap { $0 }.first { !$0.isEmpty }
        return Score(title: title ?? fallbackTitle, parts: reader.parts)
    }

    /// Unpacks an .mxl into a temporary folder and reads the score named in its container.xml.
    private static func unzippedScore(at url: URL) throws -> Data {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("Clefwise-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: folder) }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", url.path, folder.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            throw ScoreImportError(message: "“\(url.lastPathComponent)” couldn't be unpacked.")
        }
        guard ditto.terminationStatus == 0 else {
            throw ScoreImportError(message: "“\(url.lastPathComponent)” couldn't be unpacked; it may be damaged.")
        }
        guard let scoreURL = rootfile(in: folder) ?? firstScoreFile(in: folder),
              let data = try? Data(contentsOf: scoreURL) else {
            throw ScoreImportError(message: "“\(url.lastPathComponent)” doesn't contain a MusicXML score.")
        }
        return data
    }

    private static func rootfile(in folder: URL) -> URL? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("META-INF/container.xml")) else { return nil }
        let finder = RootfileFinder()
        let parser = XMLParser(data: data)
        parser.delegate = finder
        _ = parser.parse()
        guard let path = finder.path else { return nil }
        // Only follow the container's path if it stays inside the unpacked folder.
        let inside = folder.resolvingSymlinksInPath().path + "/"
        let url = folder.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(inside), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// For archives without a usable container.xml: the first .xml or .musicxml outside META-INF.
    private static func firstScoreFile(in folder: URL) -> URL? {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                   options: .skipsHiddenFiles)?.allObjects.compactMap { $0 as? URL } ?? []
        return files
            .filter { ["xml", "musicxml"].contains($0.pathExtension.lowercased()) }
            .filter { !$0.pathComponents.contains("META-INF") && !$0.pathComponents.contains("__MACOSX") }
            .min { $0.path < $1.path }
    }
}

/// A piece of the document kept in memory: one `<note>`, `<attributes>`, `<direction>`… at a
/// time, so large scores are read without building a tree of the whole file.
private final class Element {
    let name: String
    let attributes: [String: String]
    var children: [Element] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    var value: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    func child(_ name: String) -> Element? { children.first { $0.name == name } }
    func children(named name: String) -> [Element] { children.filter { $0.name == name } }
    func has(_ name: String) -> Bool { child(name) != nil }
    func string(_ name: String) -> String? { child(name)?.value }
    func int(_ name: String) -> Int? { string(name).flatMap { Int($0) } }
    func double(_ name: String) -> Double? { string(name).flatMap { Double($0) } }
    func intAttribute(_ name: String) -> Int? { attributes[name].flatMap { Int($0) } }
}

/// Streams through a score-partwise document, handing each measure's contents to a `PartReader`.
private final class ScoreReader: NSObject, XMLParserDelegate {
    private(set) var root: String?
    private(set) var workTitle: String?
    private(set) var movementTitle: String?
    private(set) var parts: [ScorePart] = []

    private var partNames: [String: String] = [:]
    private var partIndex = 0
    private var part: PartReader?
    /// Names of the open elements, outermost first.
    private var path: [String] = []
    /// The element being kept and its open descendants, innermost last.
    private var kept: [Element] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        defer { path.append(name) }
        if let parent = kept.last {
            let element = Element(name: name, attributes: attributes)
            parent.children.append(element)
            kept.append(element)
            return
        }
        switch (path.count, name) {
        case (0, _):
            root = name
            if name != "score-partwise" { parser.abortParsing() }
        case (1, "work"), (1, "movement-title"), (1, "part-list"):
            kept.append(Element(name: name, attributes: attributes))
        case (1, "part"):
            partIndex += 1
            part = PartReader(name: attributes["id"].flatMap { partNames[$0] } ?? "Part \(partIndex)")
        case (2, "measure") where path[1] == "part":
            part?.beginMeasure()
        case (3, "note"), (3, "attributes"), (3, "direction"), (3, "backup"), (3, "forward"):
            if path[2] == "measure" { kept.append(Element(name: name, attributes: attributes)) }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        kept.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        path.removeLast()
        if let element = kept.popLast() {
            if kept.isEmpty { read(element) }
            return
        }
        switch (path.count, name) {
        case (2, "measure"):
            part?.endMeasure()
        case (1, "part"):
            if let finished = part?.finish() { parts.append(finished) }
            part = nil
        default:
            break
        }
    }

    private func read(_ element: Element) {
        switch element.name {
        case "work":
            workTitle = element.string("work-title")
        case "movement-title":
            movementTitle = element.value
        case "part-list":
            for scorePart in element.children(named: "score-part") {
                if let id = scorePart.attributes["id"], let name = scorePart.string("part-name"), !name.isEmpty {
                    partNames[id] = name
                }
            }
        default:
            part?.read(element)
        }
    }
}

/// Follows one `<part>`: the position within each measure, and the clef, key and 8va lines on
/// each staff. Notes get their clef, key and octave shift once the whole part has been read.
private struct PartReader {
    private struct Note {
        let pitch: Pitch
        /// The `<accidental>` printed in the score, if it's one we can show.
        let accidental: Accidental?
        let staff: Int
        let measure: Int
        let onset: Double
        let chord: Int
    }

    let name: String
    private var staffCount = 1
    private var measureCount = 0
    private var divisions = 1.0
    /// Quarter notes from the start of the piece to the current measure.
    private var measureStart = 0.0
    /// Within the current measure, in divisions: kept as whole numbers so notes that start
    /// together on different staves compare equal.
    private var position = 0.0
    private var measureLength = 0.0
    private var chordStart = 0.0
    /// Chord id for each staff of the chord being read; a chord on two staves is two chords.
    private var chordIDs: [Int: Int] = [:]
    private var nextChordID = 0
    /// nil for a clef we can't show.
    private var clefs = Timeline<Clef?>()
    private var keys = Timeline<KeySignature>()
    private var octaveShifts = Timeline<Int>()
    private var notes: [Note] = []
    private var skippedNoteCount = 0

    init(name: String) {
        self.name = name
    }

    private var now: Double { measureStart + position / divisions }

    mutating func beginMeasure() {
        measureCount += 1
        position = 0
        measureLength = 0
    }

    /// A measure lasts as long as its longest voice, so a pickup bar is only as long as its notes.
    mutating func endMeasure() {
        measureStart += measureLength / divisions
    }

    mutating func read(_ element: Element) {
        switch element.name {
        case "attributes": readAttributes(element)
        case "direction": readDirection(element)
        case "note": readNote(element)
        case "backup": position = max(0, position - (element.double("duration") ?? 0))
        case "forward": advance(by: element.double("duration") ?? 0)
        default: break
        }
    }

    private mutating func advance(by duration: Double) {
        position += duration
        measureLength = max(measureLength, position)
    }

    private mutating func readAttributes(_ attributes: Element) {
        if let newDivisions = attributes.double("divisions"), newDivisions > 0 {
            let scale = newDivisions / divisions
            position *= scale
            measureLength *= scale
            chordStart *= scale
            divisions = newDivisions
        }
        if let staves = attributes.int("staves"), staves > 0 {
            staffCount = staves
        }
        for key in attributes.children(named: "key") {
            guard let fifths = key.int("fifths"), (-7...7).contains(fifths) else { continue }
            // Without a number the key applies to every staff.
            keys.set(KeySignature(fifths: fifths), at: now, staff: key.intAttribute("number"))
        }
        for clef in attributes.children(named: "clef") {
            clefs.set(Self.clef(clef), at: now, staff: clef.intAttribute("number") ?? 1)
        }
    }

    /// Treble is G on line 2 and bass F on line 4; anything else (alto, tenor, a treble with an
    /// 8 below, percussion, tablature) is a clef we can't show.
    private static func clef(_ clef: Element) -> Clef? {
        if let octaveChange = clef.int("clef-octave-change"), octaveChange != 0 { return nil }
        switch (clef.string("sign"), clef.int("line")) {
        case ("G", nil), ("G", 2): return .treble
        case ("F", nil), ("F", 4): return .bass
        default: return nil
        }
    }

    /// 8va and 8vb lines. A shift "down" means the notes are written lower than their `<pitch>`,
    /// which is how an 8va line reads; the pitch itself is always as played.
    private mutating func readDirection(_ direction: Element) {
        let time = now + (direction.double("offset") ?? 0) / divisions
        let staff = direction.int("staff") ?? 1
        for type in direction.children(named: "direction-type") {
            for shift in type.children(named: "octave-shift") {
                let octaves = max(1, ((shift.intAttribute("size") ?? 8) - 1) / 7)
                switch shift.attributes["type"] {
                case "down": octaveShifts.set(octaves, at: time, staff: staff)
                case "up": octaveShifts.set(-octaves, at: time, staff: staff)
                case "stop": octaveShifts.set(0, at: time, staff: staff)
                default: break
                }
            }
        }
    }

    private mutating func readNote(_ note: Element) {
        let start: Double
        if note.has("chord") {
            start = chordStart
        } else {
            start = position
            chordStart = position
            chordIDs = [:]
            if !note.has("grace") { advance(by: note.double("duration") ?? 0) }
        }

        // Not notes to read: rests, ornaments, cues for another instrument, hidden notes,
        // and the held-over end of a tie, which isn't played again.
        guard !note.has("rest"), !note.has("grace"), !note.has("cue"),
              note.attributes["print-object"] != "no", !Self.continuesTie(note) else { return }
        guard let pitch = note.child("pitch") else {
            if note.has("unpitched") { skippedNoteCount += 1 }
            return
        }
        guard let letter = pitch.string("step").flatMap(\.first).flatMap(NoteLetter.init(character:)),
              let octave = pitch.int("octave") else { return }
        // Double sharps and flats, and microtones, have no sign we can draw.
        guard let accidental = Accidental(alter: pitch.double("alter") ?? 0) else {
            skippedNoteCount += 1
            return
        }

        let staff = note.int("staff") ?? 1
        let chord: Int
        if let id = chordIDs[staff] {
            chord = id
        } else {
            nextChordID += 1
            chord = nextChordID
            chordIDs[staff] = chord
        }
        notes.append(Note(pitch: Pitch(letter, octave, accidental),
                          accidental: note.child("accidental").flatMap(Self.printedAccidental),
                          staff: staff, measure: measureCount, onset: measureStart + start / divisions, chord: chord))
    }

    private static func continuesTie(_ note: Element) -> Bool {
        let tied = note.children(named: "notations").flatMap { $0.children(named: "tied") }
        return note.children(named: "tie").contains { $0.attributes["type"] == "stop" }
            || tied.contains { ["stop", "continue"].contains($0.attributes["type"]) }
    }

    private static func printedAccidental(_ accidental: Element) -> Accidental? {
        guard accidental.attributes["print-object"] != "no" else { return nil }
        switch accidental.value {
        case "sharp": return .sharp
        case "flat": return .flat
        case "natural": return .natural
        default: return nil
        }
    }

    func finish() -> ScorePart? {
        var skipped = skippedNoteCount
        var result: [ScoreNote] = []
        for note in notes {
            guard let clef = clef(at: note.onset, staff: note.staff) else {
                skipped += 1
                continue
            }
            let key = keys.value(at: note.onset, staff: note.staff) ?? .cMajor
            result.append(ScoreNote(pitch: note.pitch, clef: clef, keySignature: key,
                                    printedAccidental: Self.sign(for: note, in: key),
                                    octaveShift: octaveShifts.value(at: note.onset, staff: note.staff) ?? 0,
                                    staff: note.staff, measure: note.measure, onset: note.onset, chord: note.chord))
        }
        guard !result.isEmpty else { return nil }

        let ordered = result.enumerated().sorted { a, b in
            (a.element.onset, -a.element.staff, a.element.pitch.midiNumber, a.offset)
                < (b.element.onset, -b.element.staff, b.element.pitch.midiNumber, b.offset)
        }
        return ScorePart(name: name, notes: ordered.map(\.element), measureCount: measureCount,
                         staffCount: staffCount, skippedNoteCount: skipped)
    }

    /// Before any `<clef>`, assume a grand staff: treble on top, bass below.
    private func clef(at time: Double, staff: Int) -> Clef? {
        clefs.value(at: time, staff: staff) ?? (staff == 1 ? .treble : .bass)
    }

    /// The score's own sign; failing that, the one the pitch needs against the key signature. Only
    /// one note is on screen, so an F♯ whose sharp was printed earlier in the bar still shows ♯.
    private static func sign(for note: Note, in key: KeySignature) -> Accidental? {
        if let printed = note.accidental, printed == note.pitch.accidental { return printed }
        return note.pitch.accidental == key.accidental(for: note.pitch.letter) ? nil : note.pitch.accidental
    }
}

/// A setting that changes partway through a part (clef, key, 8va line), per staff. Looked up by
/// time rather than document order, so a change written in one voice also holds for another
/// voice of that staff written after a `<backup>`.
private struct Timeline<Value> {
    private var changes: [(time: Double, staff: Int?, value: Value)] = []

    /// A nil staff means every staff.
    mutating func set(_ value: Value, at time: Double, staff: Int?) {
        changes.append((time, staff, value))
    }

    /// The latest change at or before `time` for `staff`; of two at the same time, the later written.
    func value(at time: Double, staff: Int) -> Value? {
        var latest: (time: Double, value: Value)?
        for change in changes where change.time <= time && (change.staff ?? staff) == staff {
            if change.time >= latest?.time ?? -.infinity { latest = (change.time, change.value) }
        }
        return latest?.value
    }
}

/// Finds the score's path in an .mxl's META-INF/container.xml.
private final class RootfileFinder: NSObject, XMLParserDelegate {
    private(set) var path: String?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if name == "rootfile", path == nil { path = attributes["full-path"] }
    }
}

private extension Accidental {
    /// From a MusicXML `<alter>`; nil for double sharps and flats and for microtones.
    init?(alter: Double) {
        guard let semitones = Int(exactly: alter), let accidental = Accidental(rawValue: semitones) else { return nil }
        self = accidental
    }
}
