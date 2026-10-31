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
/// each staff. Notes and rests get their clef, key and octave shift once the whole part has been
/// read, and then the bars are laid out.
private struct PartReader {
    /// A note or rest as read, before every clef, key and 8va line is known.
    private struct Symbol {
        /// nil for a rest.
        let pitch: Pitch?
        /// The `<accidental>` printed in the score, if it's one we can show.
        let printedAccidental: Accidental?
        let staff: Int
        /// The score's `<voice>`, numbered once the whole part is read.
        let voice: String?
        let measure: Int
        let onset: Double
        /// Quarter notes from the start of the bar.
        let offset: Double
        let duration: Double
        let value: NoteValue
        /// Whether `value` comes from a `<type>` rather than from the duration.
        let hasType: Bool
        let stemUp: Bool?
        let chord: Int
        let tiedToNext: Bool
        let tiedFromPrevious: Bool
        /// Rests only: `<display-step>` and `<display-octave>`, as a written pitch.
        let restDisplay: Pitch?
        /// `<rest measure="yes">`.
        let isMeasureRest: Bool

        /// A note to read: played, so neither a rest nor the held-over end of a tie.
        var isQuestion: Bool { pitch != nil && !tiedFromPrevious }
    }

    /// Where a symbol stands, worked out once the part has been read.
    private struct Placement {
        let clef: Clef
        let key: KeySignature
        let octaveShift: Int
        let voice: Int
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
    /// The `<beam>` levels written on the notes of the chord being read, per staff: every note of a
    /// chord shares them, though some notation apps write them on the chord's first note only.
    private var chordBeams: [Int: [Int: BeamPart]] = [:]
    /// The `<beam>` levels each chord has in the score (level 1 is the eighth beam), by chord id.
    private var writtenBeams: [Int: [Int: BeamPart]] = [:]
    /// Whether the part has a `<beam>` anywhere. Without one, notes are beamed by the beat.
    private var hasBeams = false
    /// The `<time>` each measure gives, by measure number, and whether it's printed there.
    private var timeChanges: [Int: (time: TimeSignature, printed: Bool)] = [:]
    /// nil for a clef we can't show.
    private var clefs = Timeline<Clef?>()
    private var keys = Timeline<KeySignature>()
    private var octaveShifts = Timeline<Int>()
    /// Every note and rest we could draw, in document order.
    private var symbols: [Symbol] = []
    /// Start and length of each finished measure, in quarter notes.
    private var bars: [(start: Double, length: Double)] = []
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
        bars.append((measureStart, measureLength / divisions))
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
        // A time signature for one staff only is rare; take staff 1's, or failing that the first.
        let times = attributes.children(named: "time")
        if let time = times.first(where: { ($0.intAttribute("number") ?? 1) == 1 }) ?? times.first,
           let signature = Self.timeSignature(time) {
            timeChanges[measureCount] = (signature, time.attributes["print-object"] != "no")
        }
    }

    /// From a `<time>`: composite beats (3+2) and several fractions (3/8 + 2/4) are added up. nil
    /// for `<senza-misura>` and for anything unreadable, which leave the time signature as it was.
    private static func timeSignature(_ time: Element) -> TimeSignature? {
        guard !time.has("senza-misura") else { return nil }
        let beats = time.children(named: "beats").map { beats -> Int? in
            let parts = beats.value.split(separator: "+").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            return parts.isEmpty || parts.contains { $0 <= 0 } ? nil : parts.reduce(0, +)
        }
        let beatTypes = time.children(named: "beat-type").map { Int($0.value) }
        guard !beats.isEmpty, beats.count == beatTypes.count else { return nil }
        var total = 0, unit = 1
        for (count, beatType) in zip(beats, beatTypes) {
            guard let count, let beatType, beatType > 0 else { return nil }
            // Counted in the shortest beat so far: 3/8 + 2/4 is 7/8.
            let common = unit / gcd(unit, beatType) * beatType
            total = total * (common / unit) + count * (common / beatType)
            unit = common
        }
        let symbol: TimeSignature.Symbol = switch (time.attributes["symbol"], total, unit) {
        case ("common", 4, 4): .common
        case ("cut", 2, 2): .cut
        default: .numbers
        }
        return TimeSignature(beats: total, beatType: unit, symbol: symbol)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

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
            chordBeams = [:]
            if !note.has("grace") { advance(by: note.double("duration") ?? 0) }
        }
        if note.has("beam") { hasBeams = true }

        // Neither drawn nor read: ornaments, cues for another instrument, and hidden notes.
        guard !note.has("grace"), !note.has("cue"), note.attributes["print-object"] != "no" else { return }
        let staff = note.int("staff") ?? 1
        let rest = note.child("rest")
        // The held-over end of a tie is drawn, but it isn't played again, so it isn't read.
        let tiedFromPrevious = rest == nil && Self.continuesTie(note)
        // Rests aren't beamed. A chord's beams count even when written on a note that isn't drawn.
        if rest == nil {
            chordBeams[staff, default: [:]].merge(Self.beamLevels(note)) { first, _ in first }
            if let id = chordIDs[staff] { writtenBeams[id] = chordBeams[staff] }
        }

        let pitch: Pitch?
        let chord: Int
        if rest != nil {
            pitch = nil
            nextChordID += 1
            chord = nextChordID
        } else {
            guard let pitchElement = note.child("pitch") else {
                if note.has("unpitched"), !tiedFromPrevious { skippedNoteCount += 1 }
                return
            }
            guard let letter = pitchElement.string("step").flatMap(\.first).flatMap(NoteLetter.init(character:)),
                  let octave = pitchElement.int("octave") else { return }
            // Double sharps and flats, and microtones, have no sign we can draw.
            guard let accidental = Accidental(alter: pitchElement.double("alter") ?? 0) else {
                if !tiedFromPrevious { skippedNoteCount += 1 }
                return
            }
            pitch = Pitch(letter, octave, accidental)
            if let id = chordIDs[staff] {
                chord = id
            } else {
                nextChordID += 1
                chord = nextChordID
                chordIDs[staff] = chord
                writtenBeams[chord] = chordBeams[staff]
            }
        }

        let duration = (note.double("duration") ?? 0) / divisions
        let type = note.string("type").flatMap(NoteValue.Kind.init(musicXMLType:))
        let display = rest.flatMap { rest -> Pitch? in
            guard let letter = rest.string("display-step").flatMap(\.first).flatMap(NoteLetter.init(character:)),
                  let octave = rest.int("display-octave") else { return nil }
            return Pitch(letter, octave)
        }
        let stemUp: Bool? = switch note.string("stem") {
        case "up": true
        case "down": false
        default: nil
        }
        symbols.append(Symbol(
            pitch: pitch,
            printedAccidental: pitch == nil ? nil : note.child("accidental").flatMap(Self.printedAccidental),
            staff: staff, voice: note.string("voice").flatMap { $0.isEmpty ? nil : $0 }, measure: measureCount,
            onset: measureStart + start / divisions, offset: start / divisions, duration: duration,
            value: type.map { NoteValue($0, dots: note.children(named: "dot").count) }
                ?? NoteValue.nearest(toQuarters: Self.writtenLength(of: note, duration: duration)),
            hasType: type != nil, stemUp: stemUp, chord: chord,
            tiedToNext: rest == nil && Self.startsTie(note), tiedFromPrevious: tiedFromPrevious,
            restDisplay: display, isMeasureRest: rest?.attributes["measure"] == "yes"))
    }

    /// How long a note is written, in quarter notes: a triplet eighth lasts a third of a beat but
    /// is written as an eighth, so `<time-modification>` is undone.
    private static func writtenLength(of note: Element, duration: Double) -> Double {
        guard let modification = note.child("time-modification"),
              let actual = modification.double("actual-notes"), let normal = modification.double("normal-notes"),
              actual > 0, normal > 0 else { return duration }
        return duration * actual / normal
    }

    /// A note's `<beam>` elements by level (`number`, 1 when it gives none).
    private static func beamLevels(_ note: Element) -> [Int: BeamPart] {
        var levels: [Int: BeamPart] = [:]
        for beam in note.children(named: "beam") {
            let level = beam.intAttribute("number") ?? 1
            guard let part = BeamPart(musicXML: beam.text), level > 0, levels[level] == nil else { continue }
            levels[level] = part
        }
        return levels
    }

    private static func continuesTie(_ note: Element) -> Bool {
        let tied = note.children(named: "notations").flatMap { $0.children(named: "tied") }
        return note.children(named: "tie").contains { $0.attributes["type"] == "stop" }
            || tied.contains { ["stop", "continue"].contains($0.attributes["type"]) }
    }

    private static func startsTie(_ note: Element) -> Bool {
        let tied = note.children(named: "notations").flatMap { $0.children(named: "tied") }
        return note.children(named: "tie").contains { $0.attributes["type"] == "start" }
            || tied.contains { ["start", "continue"].contains($0.attributes["type"]) }
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
        let clefs = self.clefs.lookup(), keys = self.keys.lookup(), octaveShifts = self.octaveShifts.lookup()
        // Before any `<clef>`, assume a grand staff: treble on top, bass below.
        func clefInForce(at time: Double, staff: Int) -> Clef? {
            clefs.value(at: time, staff: staff) ?? (staff == 1 ? .treble : .bass)
        }
        func keyInForce(at time: Double, staff: Int) -> KeySignature {
            keys.value(at: time, staff: staff) ?? .cMajor
        }

        var skipped = skippedNoteCount
        let voices = voiceNumbers()
        var placements = [Placement?](repeating: nil, count: symbols.count)
        var notes: [ScoreNote] = []
        // For each of `notes`, its index in `symbols`.
        var noteSymbols: [Int] = []
        // A measure left open by a file that ends early still gets its bar.
        let bars = self.bars.count < measureCount ? self.bars + [(measureStart, measureLength / divisions)] : self.bars
        var symbolsInBar = [[Int]](repeating: [], count: bars.count)

        for (index, symbol) in symbols.enumerated() {
            guard let clef = clefInForce(at: symbol.onset, staff: symbol.staff) else {
                if symbol.isQuestion { skipped += 1 }
                continue
            }
            let key = keyInForce(at: symbol.onset, staff: symbol.staff)
            let placement = Placement(clef: clef, key: key,
                                      octaveShift: octaveShifts.value(at: symbol.onset, staff: symbol.staff) ?? 0,
                                      voice: voices[index])
            placements[index] = placement
            if symbolsInBar.indices.contains(symbol.measure - 1) { symbolsInBar[symbol.measure - 1].append(index) }
            guard let pitch = symbol.pitch, symbol.isQuestion else { continue }
            notes.append(ScoreNote(pitch: pitch, clef: clef, keySignature: key,
                                   printedAccidental: Self.sign(for: pitch, printed: symbol.printedAccidental, in: key),
                                   octaveShift: placement.octaveShift, staff: symbol.staff,
                                   measure: symbol.measure, onset: symbol.onset, chord: symbol.chord))
            noteSymbols.append(index)
        }
        guard !notes.isEmpty else { return nil }

        var symbolIndices = [Int?](repeating: nil, count: symbols.count)
        var measures: [ScoreMeasure] = []
        measures.reserveCapacity(bars.count)
        var time: TimeSignature?
        for (bar, members) in symbolsInBar.enumerated() {
            let (start, length) = bars[bar]
            let timeChange = timeChanges[bar + 1]
            if let timeChange { time = timeChange.time }
            let signs = barSigns(members, placements: placements)
            let ordered = members.sorted { drawsBefore($0, $1, placements: placements) }
            for (position, index) in ordered.enumerated() { symbolIndices[index] = position }
            let staves = (1...max(1, staffCount)).map { staff in
                ScoreMeasure.StaffStart(clef: clefInForce(at: start, staff: staff),
                                        keySignature: keyInForce(at: start, staff: staff))
            }
            var drawn = ordered.map { index -> BarSymbol in
                let symbol = symbols[index], placement = placements[index]!
                let fillsBar = symbol.isMeasureRest || (symbol.pitch == nil && !symbol.hasType && length > 0
                    && abs(symbol.offset) < 1e-9 && symbol.duration >= length - 1e-9)
                return BarSymbol(pitch: symbol.pitch, clef: placement.clef, staff: symbol.staff, voice: placement.voice,
                                 offset: symbol.offset, duration: symbol.duration, value: symbol.value,
                                 octaveShift: placement.octaveShift, accidental: signs[index], stemUp: symbol.stemUp,
                                 chord: symbol.chord, tiedToNext: symbol.tiedToNext,
                                 tiedFromPrevious: symbol.tiedFromPrevious,
                                 restPosition: symbol.restDisplay.map(placement.clef.position(of:)),
                                 isWholeBarRest: fillsBar)
            }
            let beams = hasBeams
                ? beamsAsWritten(members, placements: placements)
                : Beaming.byBeat(drawn, time: time, barLength: length, isFirstBar: bar == 0)
            for index in drawn.indices where !drawn[index].isRest {
                drawn[index].beams = beams[drawn[index].chord] ?? []
            }
            measures.append(ScoreMeasure(number: bar + 1, start: start, length: length, staves: staves, symbols: drawn,
                                         time: time, printsTime: timeChange?.printed ?? false))
        }
        for (note, index) in noteSymbols.enumerated() { notes[note].symbolIndex = symbolIndices[index] }

        let ordered = notes.enumerated().sorted { a, b in
            (a.element.onset, -a.element.staff, a.element.pitch.midiNumber, a.offset)
                < (b.element.onset, -b.element.staff, b.element.pitch.midiNumber, b.offset)
        }
        return ScorePart(name: name, notes: ordered.map(\.element), measures: measures, measureCount: measureCount,
                         staffCount: staffCount, skippedNoteCount: skipped)
    }

    /// The score's voices as numbers: `<voice>3</voice>` is 3, no voice is 1, and voices named
    /// otherwise get numbers above every numbered one, in the order they first appear.
    private func voiceNumbers() -> [Int] {
        let highest = symbols.compactMap { $0.voice.flatMap { Int($0) } }.filter { $0 > 0 }.max() ?? 1
        var named: [String: Int] = [:]
        return symbols.map { symbol in
            guard let voice = symbol.voice else { return 1 }
            if let number = Int(voice), number > 0 { return number }
            if let number = named[voice] { return number }
            let number = highest + named.count + 1
            named[voice] = number
            return number
        }
    }

    /// The beams the score writes for a bar's notes, by chord id, keeping only groups that can be
    /// drawn. A group follows its voice in the order the score writes it, so one that strays onto
    /// the other staff (cross-staff beaming) is seen whole and dropped.
    private func beamsAsWritten(_ members: [Int], placements: [Placement?]) -> [Int: [BeamPart]] {
        var voices: [Int: [Beaming.Note]] = [:]
        var seen = Set<Int>()
        for index in members {
            let symbol = symbols[index]
            guard symbol.pitch != nil, let voice = placements[index]?.voice, seen.insert(symbol.chord).inserted else { continue }
            voices[voice, default: []].append(Beaming.Note(chord: symbol.chord, staff: symbol.staff, offset: symbol.offset,
                                                           duration: symbol.duration, value: symbol.value, isRest: false))
        }
        var beams: [Int: [BeamPart]] = [:]
        for notes in voices.values {
            beams.merge(Beaming.written(notes) { writtenBeams[$0] ?? [:] }) { first, _ in first }
        }
        return beams
    }

    /// Draw order within a bar: by offset, then staff, then voice, rests first, then low to high.
    private func drawsBefore(_ a: Int, _ b: Int, placements: [Placement?]) -> Bool {
        let x = symbols[a], y = symbols[b]
        if x.offset != y.offset { return x.offset < y.offset }
        if x.staff != y.staff { return x.staff < y.staff }
        let voiceX = placements[a]?.voice ?? 1, voiceY = placements[b]?.voice ?? 1
        if voiceX != voiceY { return voiceX < voiceY }
        switch (x.pitch, y.pitch) {
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(p), .some(q)) where p != q:
            return (p.midiNumber, p.diatonicIndex) < (q.midiNumber, q.diatonicIndex)
        default: return a < b
        }
    }

    /// The sign each note of a bar prints there, by the usual rule: on each staff, a sign holds for
    /// its letter and written octave until the bar line, starting from the key signature. The
    /// score's own sign always prints (courtesy signs included); otherwise a note prints its
    /// accidental when it differs from the one in force. The held-over end of a tie prints only
    /// a sign the score gives it and leaves the signs in force alone.
    private func barSigns(_ members: [Int], placements: [Placement?]) -> [Int: Accidental] {
        var signs: [Int: Accidental] = [:]
        let notesByStaff = Dictionary(grouping: members.filter { symbols[$0].pitch != nil }) { symbols[$0].staff }
        for staffNotes in notesByStaff.values {
            // In time order, low to high within a chord and across voices.
            let ordered = staffNotes.sorted { a, b in
                let x = symbols[a], y = symbols[b], p = x.pitch!, q = y.pitch!
                return (x.offset, p.midiNumber, p.diatonicIndex, a) < (y.offset, q.midiNumber, q.diatonicIndex, b)
            }
            // The accidental in force for each written staff step (letter and octave as written).
            var inForce: [Int: Accidental] = [:]
            for index in ordered {
                let symbol = symbols[index], pitch = symbol.pitch!, placement = placements[index]!
                let printed = symbol.printedAccidental == pitch.accidental ? symbol.printedAccidental : nil
                if symbol.tiedFromPrevious {
                    signs[index] = printed
                    continue
                }
                let step = pitch.diatonicIndex - 7 * placement.octaveShift
                let current = inForce[step] ?? placement.key.accidental(for: pitch.letter)
                signs[index] = printed ?? (pitch.accidental != current ? pitch.accidental : nil)
                inForce[step] = pitch.accidental
            }
        }
        return signs
    }

    /// The score's own sign; failing that, the one the pitch needs against the key signature. Only
    /// one note is on screen, so an F♯ whose sharp was printed earlier in the bar still shows ♯.
    private static func sign(for pitch: Pitch, printed: Accidental?, in key: KeySignature) -> Accidental? {
        if let printed, printed == pitch.accidental { return printed }
        return pitch.accidental == key.accidental(for: pitch.letter) ? nil : pitch.accidental
    }
}

/// How a bar's notes are beamed: as the score's `<beam>` elements say, keeping only groups the bar
/// view can draw, or, in a part that has none, by the beat.
private enum Beaming {
    /// A note (a chord counted once) or a rest, as beaming sees it.
    struct Note {
        let chord: Int
        let staff: Int
        /// Quarter notes from the start of the bar.
        let offset: Double
        let duration: Double
        let value: NoteValue
        let isRest: Bool
    }

    private static let tolerance = 1e-6

    // MARK: Beams from the score

    /// The beams each note of one voice keeps, by chord id. `notes` are the voice's notes in a bar,
    /// a chord once, in the order the score writes them; `written` gives a chord's `<beam>` levels.
    /// Level 1 has to begin, continue and end within the bar. A group that doesn't (it never ends,
    /// it has no begin, a note in it has no level 1 beam) or that can't be drawn is dropped, and
    /// its notes get flags.
    static func written(_ notes: [Note], levels written: (Int) -> [Int: BeamPart]) -> [Int: [BeamPart]] {
        var beams: [Int: [BeamPart]] = [:]
        var group: [Note] = []
        // The group being read started with a continue rather than a begin.
        var stray = false
        for note in notes {
            switch written(note.chord)[1] {
            case .begin?:
                // A group still open never ended: it's dropped.
                group = [note]
                stray = false
            case .continue?:
                if group.isEmpty { stray = true }
                group.append(note)
            case .end?:
                guard !group.isEmpty else { continue }
                group.append(note)
                if !stray, let parts = checked(group, levels: written) {
                    for (note, parts) in zip(group, parts) { beams[note.chord] = parts }
                }
                group = []
                stray = false
            case .forwardHook?, .backwardHook?, nil:
                // It breaks the group being read, which is dropped.
                group = []
                stray = false
            }
        }
        return beams
    }

    /// A written group's beams level by level, or nil when the bar view can't draw them: notes on
    /// both staves (cross-staff beaming), out of time order, or without a flag (a quarter or
    /// longer); a level missing under a written one; or a higher level that isn't begin…end runs
    /// and hooks along the beam under it. When the levels don't match the notes' flags (sixteenths
    /// with one beam), level 1 stays and the others are worked out from the note values.
    private static func checked(_ group: [Note], levels written: (Int) -> [Int: BeamPart]) -> [[BeamPart]]? {
        guard group.count >= 2, Set(group.map(\.staff)).count == 1,
              zip(group, group.dropFirst()).allSatisfy({ $0.offset + tolerance < $1.offset }),
              group.allSatisfy({ $0.value.flags > 0 }) else { return nil }
        var parts: [[BeamPart]] = []
        for note in group {
            let levels = written(note.chord)
            let inOrder = (1...max(1, levels.count)).compactMap { levels[$0] }
            guard inOrder.count == levels.count else { return nil }
            parts.append(inOrder)
        }
        let deepest = parts.map(\.count).max() ?? 1
        for level in stride(from: 2, through: deepest, by: 1) {
            var open = false
            for note in parts {
                guard note.count >= level else {
                    if open { return nil }
                    continue
                }
                let part = note[level - 1], under = note[level - 2]
                switch part {
                case .begin, .continue:
                    // A beam to the next note needs the one under it to go there too.
                    guard open == (part == .continue), under == .begin || under == .continue else { return nil }
                    open = true
                case .end:
                    guard open else { return nil }
                    open = false
                case .forwardHook:
                    guard !open, [.begin, .continue, .forwardHook].contains(under) else { return nil }
                case .backwardHook:
                    guard !open, [.continue, .end, .backwardHook].contains(under) else { return nil }
                }
            }
            if open { return nil }
        }
        if zip(group, parts).contains(where: { $0.value.flags != $1.count }) { return levels(for: group) }
        return parts
    }

    // MARK: Beams by the beat

    /// Beams for one bar of a part that writes none, by chord id. Within each beat, two or more
    /// notes in a row on one staff and voice that have flags (eighths or shorter) are beamed, with
    /// no rest, longer note or gap between them. A note that runs into the next beat isn't beamed.
    /// Beats count from the start of the bar, or back from the end of a pickup (a first bar
    /// shorter than its time signature). No time signature means 4/4.
    static func byBeat(_ symbols: [BarSymbol], time: TimeSignature?, barLength: Double, isFirstBar: Bool) -> [Int: [BeamPart]] {
        let time = time ?? TimeSignature(beats: 4, beatType: 4)
        let beat = beatLength(of: time)
        let fullBar = Double(time.beats) * 4 / Double(time.beatType)
        let origin = isFirstBar && barLength > 0 && barLength + tolerance < fullBar
            ? barLength - beat * (barLength / beat - tolerance).rounded(.up) : 0

        // Each staff and voice's notes and rests, a chord once, by offset.
        var lines: [[Int]: [Note]] = [:]
        var seen = Set<Int>()
        for symbol in symbols where seen.insert(symbol.chord).inserted {
            lines[[symbol.staff, symbol.voice], default: []].append(
                Note(chord: symbol.chord, staff: symbol.staff, offset: symbol.offset, duration: symbol.duration,
                     value: symbol.value, isRest: symbol.isRest))
        }
        var beams: [Int: [BeamPart]] = [:]
        for line in lines.values {
            for group in groups(in: line, beat: beat, origin: origin) {
                for (note, parts) in zip(group, levels(for: group)) { beams[note.chord] = parts }
            }
        }
        return beams
    }

    /// One beat in quarter notes: a dotted quarter in 6/8, 9/8 and 12/8 (a dotted eighth in 6/16…),
    /// otherwise the beat-type note (a quarter in 4/4, a half in 2/2, an eighth in 3/8).
    static func beatLength(of time: TimeSignature) -> Double {
        let note = 4 / Double(time.beatType)
        return [6, 9, 12].contains(time.beats) && time.beatType >= 8 ? 3 * note : note
    }

    /// Runs of two or more notes with flags that follow on from each other within one beat.
    private static func groups(in line: [Note], beat: Double, origin: Double) -> [[Note]] {
        var groups: [[Note]] = [], group: [Note] = []
        var groupBeat = 0.0
        for note in line {
            let beatIndex = ((note.offset - origin) / beat + tolerance).rounded(.down)
            let beamable = !note.isRest && note.value.flags > 0
                && note.offset + note.duration - origin <= (beatIndex + 1) * beat + tolerance
            let follows = group.last.map { beatIndex == groupBeat && abs($0.offset + $0.duration - note.offset) < tolerance } ?? true
            if !beamable || !follows {
                if group.count >= 2 { groups.append(group) }
                group = []
            }
            if beamable {
                group.append(note)
                groupBeat = beatIndex
            }
        }
        if group.count >= 2 { groups.append(group) }
        return groups
    }

    /// The beams of a group of two or more notes with flags. Level 1 joins them all. Level k joins
    /// each run of two or more notes with k flags or more; a note with k flags whose neighbours have
    /// fewer gets a hook instead.
    static func levels(for group: [Note]) -> [[BeamPart]] {
        var parts = group.indices.map { [$0 == 0 ? BeamPart.begin : $0 == group.count - 1 ? .end : .continue] }
        let deepest = group.map(\.value.flags).max() ?? 1
        for level in stride(from: 2, through: deepest, by: 1) {
            var first = 0
            while first < group.count {
                guard group[first].value.flags >= level else {
                    first += 1
                    continue
                }
                var last = first
                while last + 1 < group.count, group[last + 1].value.flags >= level { last += 1 }
                if last > first {
                    parts[first].append(.begin)
                    for index in first + 1 ..< last { parts[index].append(.continue) }
                    parts[last].append(.end)
                } else {
                    parts[first].append(hook(at: first, in: group, under: parts[first][level - 2], level: level))
                }
                first = last + 1
            }
        }
        return parts
    }

    /// A hook points along the beam under it. Where that goes both ways, it points back to a dotted
    /// note before it (a dotted eighth and a sixteenth), and otherwise forward.
    private static func hook(at index: Int, in group: [Note], under: BeamPart, level: Int) -> BeamPart {
        switch under {
        case .begin, .forwardHook:
            return .forwardHook
        case .end, .backwardHook:
            return .backwardHook
        case .continue:
            // The note before has the flags of the level under this one: an eighth for a sixteenth's hook.
            let plain = pow(0.5, Double(level - 1))
            return group[index - 1].value.quarters > plain + tolerance ? .backwardHook : .forwardHook
        }
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

    /// For looking values up once every change is in: each staff's changes in time order.
    func lookup() -> Lookup {
        let ordered = changes.indices
            .sorted { (changes[$0].time, $0) < (changes[$1].time, $1) }
            .map { changes[$0] }
        var byStaff: [Int: [(time: Double, value: Value)]] = [:]
        for staff in Set(changes.compactMap(\.staff)) {
            byStaff[staff] = ordered.filter { ($0.staff ?? staff) == staff }.map { ($0.time, $0.value) }
        }
        return Lookup(byStaff: byStaff, everyStaff: ordered.filter { $0.staff == nil }.map { ($0.time, $0.value) })
    }

    struct Lookup {
        /// In time order; of two at the same time, the earlier written first.
        let byStaff: [Int: [(time: Double, value: Value)]]
        /// The changes that name no staff, for staves no change names.
        let everyStaff: [(time: Double, value: Value)]

        /// The latest change at or before `time` for `staff`; of two at the same time, the later written.
        func value(at time: Double, staff: Int) -> Value? {
            let changes = byStaff[staff] ?? everyStaff
            var low = 0, high = changes.count
            while low < high {
                let middle = (low + high) / 2
                if changes[middle].time <= time { low = middle + 1 } else { high = middle }
            }
            return low > 0 ? changes[low - 1].value : nil
        }
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
