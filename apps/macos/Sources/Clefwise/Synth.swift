import AVFoundation

/// A tiny additive synth: plays a soft, piano-like tone for a pitch, plus a dull "miss" sound.
final class Synth {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var chordBuffers: [[Int]: AVAudioPCMBuffer] = [:]
    private var isConnected = false

    func play(_ pitch: Pitch) {
        schedule(buffer(for: pitch.midiNumber) { tone(frequency: pitch.frequency) })
    }

    /// Several notes struck together. One note plays as `play(_:)` does.
    func play(_ pitches: [Pitch]) {
        guard pitches.count > 1 else {
            if let pitch = pitches.first { play(pitch) }
            return
        }
        let key = pitches.map(\.midiNumber).sorted()
        if chordBuffers[key] == nil {
            let frequencies = pitches.map(\.frequency)
            // Softer per note as the chord grows, so it sounds about as loud as one note.
            let gain = 1 / Double(frequencies.count).squareRoot()
            chordBuffers[key] = render(duration: 1.3) { t in
                frequencies.reduce(0) { $0 + Self.toneSample(frequency: $1, at: t) } * gain
            }
        }
        schedule(chordBuffers[key]!)
    }

    func playMiss() {
        schedule(buffer(for: -1) { thud() })
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        if !isConnected {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isConnected = true
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func buffer(for key: Int, make: () -> AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        if let cached = buffers[key] { return cached }
        let buffer = make()
        buffers[key] = buffer
        return buffer
    }

    private func tone(frequency: Double) -> AVAudioPCMBuffer {
        render(duration: 1.3) { t in Self.toneSample(frequency: frequency, at: t) }
    }

    /// One note's sound at time `t`. Harmonic number and relative loudness; higher harmonics die
    /// away faster, like a struck string.
    private static func toneSample(frequency: Double, at t: Double) -> Double {
        let harmonics: [(Double, Double)] = [(1, 1.0), (2, 0.45), (3, 0.22), (4, 0.1), (5, 0.05)]
        return harmonics.reduce(0) { sum, harmonic in
            sum + harmonic.1 * sin(2 * .pi * frequency * harmonic.0 * t) * exp(-t * (2.2 + harmonic.0 * 1.3))
        } * 0.28
    }

    private func thud() -> AVAudioPCMBuffer {
        render(duration: 0.22) { t in
            (sin(2 * .pi * 140 * t) + 0.3 * sin(2 * .pi * 280 * t)) * exp(-t * 16) * 0.3
        }
    }

    private func render(duration: Double, sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            // Short fade in and out to avoid clicks.
            let envelope = min(1, t / 0.006) * min(1, (duration - t) / 0.05)
            data[frame] = Float(sample(t) * envelope)
        }
        return buffer
    }
}
