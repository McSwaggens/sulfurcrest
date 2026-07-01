import AVFoundation

/// A chunk of mono audio captured from the microphone.
///
/// Carries only `Sendable` values (`[Float]` + sample rate) so it can cross the
/// realtime audio thread → actor boundary safely. The non-`Sendable`
/// `AVAudioPCMBuffer` is rebuilt on the consuming side via `AudioBufferFactory`.
struct AudioChunk: Sendable {
    let samples: [Float]
    let sampleRate: Double

    init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// Extracts mono Float32 samples from a tap buffer. Runs on the audio thread.
    init?(buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }

        let channels = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        if channels <= 1 {
            mono.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.update(from: channelData[0], count: frames)
            }
        } else {
            // Downmix to mono by averaging channels.
            let scale = 1.0 / Float(channels)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += channelData[channel][frame] }
                mono[frame] = sum * scale
            }
        }
        self.samples = mono
        self.sampleRate = sampleRate
    }
}

/// Rebuilds an `AVAudioPCMBuffer` from a `Sendable` `AudioChunk`.
///
/// The buffer is freshly constructed at the call site and handed straight to the
/// ASR actor, so it forms a disconnected region (no aliasing) and is safe to send.
/// FluidAudio resamples it to 16 kHz mono internally.
enum AudioBufferFactory {
    static func make(_ chunk: AudioChunk) -> AVAudioPCMBuffer? {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: chunk.sampleRate,
                channels: 1,
                interleaved: false),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(chunk.samples.count))
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
        chunk.samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: chunk.samples.count)
        }
        return buffer
    }
}
