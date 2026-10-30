import AVFoundation

/// A tiny additive synth: plays a soft, piano-like tone for a pitch, plus a dull "miss" sound.
final class Synth {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var isConnected = false

    func play(_ pitch: Pitch) {
        schedule(buffer(for: pitch.midiNumber) { tone(frequency: pitch.frequency) })
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
        // Harmonic number and relative loudness; higher harmonics die away faster, like a struck string.
        let harmonics: [(Double, Double)] = [(1, 1.0), (2, 0.45), (3, 0.22), (4, 0.1), (5, 0.05)]
        return render(duration: 1.3) { t in
            harmonics.reduce(0) { sum, harmonic in
                sum + harmonic.1 * sin(2 * .pi * frequency * harmonic.0 * t) * exp(-t * (2.2 + harmonic.0 * 1.3))
            } * 0.28
        }
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
