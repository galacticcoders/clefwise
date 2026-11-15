import CoreMIDI
import Foundation
import Observation

/// A key going down on a real piano or keyboard plugged in over USB (any MIDI source).
struct MIDIKeyPress: Equatable {
    /// The key, numbered as `Pitch.midiNumber`: 60 is Do(C4).
    var note: Int
    /// How hard it was pressed, 1–127.
    var velocity: Int

    /// The key as the piano on screen names it: black keys are sharps (C♯, never D♭).
    var pitch: Pitch { Pitch(midiNumber: note) }
}

/// Reading key presses out of what a MIDI source sends.
enum MIDIMessages {
    /// The key presses in a run of Universal MIDI Packet words, in order: MIDI 1.0 note-ons
    /// (message type 2, status 9) on any group and channel, with a velocity above 0 (a note-on at 0
    /// is how many keyboards send a note-off). Everything else is passed over a whole message at a
    /// time: note-offs, the pedal and other controllers, and system messages such as the active
    /// sensing a Yamaha sends five times a second.
    static func keyPresses(in words: [UInt32]) -> [MIDIKeyPress] {
        var presses: [MIDIKeyPress] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let type = Int(word >> 28)
            if type == 0x2, (word >> 20) & 0xF == 0x9 {
                let velocity = Int(word & 0x7F)
                if velocity > 0 { presses.append(MIDIKeyPress(note: Int((word >> 8) & 0x7F), velocity: velocity)) }
            }
            index += wordCount(ofType: type)
        }
        return presses
    }

    /// How many 32-bit words a message of this type takes (UMP 1.1).
    static func wordCount(ofType type: Int) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: 2
        case 0xB, 0xC: 3
        default: 4
        }
    }
}

/// The pianos and keyboards plugged in (every MIDI source macOS lists), and their key presses.
/// One for the app, made and started by the `AppDelegate`, which hands the presses to the game in
/// use. Tests never start one, so they don't hear a real piano.
@MainActor @Observable
final class PianoConnection {
    /// The sources listening, by the names macOS gives them ("Digital Piano"), in its order.
    private(set) var names: [String] = []
    /// Each key press, on the main thread, in the order played: a chord's keys come one by one.
    @ObservationIgnored var onKeyPress: ((MIDIKeyPress) -> Void)?
    /// Whenever `names` changes, with the old and new names.
    @ObservationIgnored var onChange: ((_ old: [String], _ new: [String]) -> Void)?

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var port = MIDIPortRef()
    @ObservationIgnored private var sources: [MIDIEndpointRef] = []

    /// Starts listening to every source there is, and to each one plugged in later. Does nothing
    /// if MIDI isn't available, or the second time.
    func start() {
        guard client == 0 else { return }
        let created = MIDIClientCreateWithBlock("Clefwise" as CFString, &client) { [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.connectSources() } }
        }
        guard created == noErr else { client = 0; return }
        // MIDI 1.0: CoreMIDI turns whatever a source speaks into MIDI 1.0 messages.
        let opened = MIDIInputPortCreateWithProtocol(client, "Keys" as CFString, ._1_0, &port) { [weak self] list, _ in
            var presses: [MIDIKeyPress] = []
            for packet in list.unsafeSequence() {
                presses += MIDIMessages.keyPresses(in: Array(MIDIEventPacket.WordCollection(packet)))
            }
            guard !presses.isEmpty else { return }
            // The main queue keeps them in order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for press in presses { self?.onKeyPress?(press) }
                }
            }
        }
        guard opened == noErr else { return }
        connectSources()
    }

    /// Listens to the sources there are now, each once: every connection is dropped and made
    /// again, so a piano unplugged and plugged back in is heard once, not twice.
    private func connectSources() {
        guard port != 0 else { return }
        for source in sources { MIDIPortDisconnectSource(port, source) }
        sources = []
        var names: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard source != 0, !Self.isOffline(source), MIDIPortConnectSource(port, source, nil) == noErr else { continue }
            sources.append(source)
            names.append(Self.name(of: source))
        }
        guard names != self.names else { return }
        let old = self.names
        self.names = names
        onChange?(old, names)
    }

    private static func name(of source: MIDIEndpointRef) -> String {
        for key in [kMIDIPropertyDisplayName, kMIDIPropertyName] {
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(source, key, &name) == noErr, let name = name?.takeRetainedValue() as String?,
               !name.isEmpty {
                return name
            }
        }
        return "MIDI keyboard"
    }

    private static func isOffline(_ source: MIDIEndpointRef) -> Bool {
        var offline: Int32 = 0
        return MIDIObjectGetIntegerProperty(source, kMIDIPropertyOffline, &offline) == noErr && offline != 0
    }
}
