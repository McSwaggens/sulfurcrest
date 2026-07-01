import AVFoundation

/// Captures microphone audio with `AVAudioEngine` and forwards ordered mono
/// chunks to a `Sendable` continuation. The tap runs on a realtime audio thread;
/// `continuation.yield` is thread-safe and preserves order.
@MainActor
final class MicCapture {
    private let engine = AVAudioEngine()
    private var isRunning = false

    /// Installs the input tap and starts the engine, feeding `continuation`.
    /// Throws if the engine fails to start (e.g. no input device / mic denied).
    func start(feeding continuation: AsyncStream<AudioChunk>.Continuation) throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        DiagLog.log("mic.start: sampleRate=\(sampleRate) channels=\(format.channelCount) micAuth=\(micAuth)")

        // The tap fires on a realtime audio thread, so the block MUST be
        // non-isolated. Typing it `@Sendable` keeps it off the main actor —
        // otherwise the Swift runtime asserts main-actor isolation here and traps.
        let block: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            if let chunk = AudioChunk(buffer: buffer, sampleRate: sampleRate) {
                continuation.yield(chunk)
            }
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: block)

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}
