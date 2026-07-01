import AVFoundation
import CoreML
import FluidAudio
import Foundation

/// Live transcript for the HUD. `combined` is what is shown / pasted.
struct TranscriptDisplay: Sendable {
    let confirmed: String
    let volatile: String

    var combined: String {
        [confirmed, volatile].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum ASRServiceError: Error {
    case notLoaded
}

/// Owns the resident Parakeet model and runs dictation sessions.
///
/// Accuracy comes from transcribing the *whole* utterance with full context
/// (Parakeet chunks long audio internally, with overlap+merge). The live HUD is
/// driven by re-transcribing the growing buffer a few times a second — the same
/// accurate engine, just on the audio captured so far — so the preview never
/// churns or disagrees with the final pasted text.
actor ASRService {
    static let shared = ASRService()

    /// English, lowest WER. Swap to `.v3` for multilingual.
    static let modelVersion: AsrModelVersion = .v2

    private var manager: AsrManager?
    private var current: Session?

    /// App-lifetime channel of live transcript updates for the UI (single consumer).
    nonisolated let displayStream: AsyncStream<TranscriptDisplay>
    private nonisolated let displayContinuation: AsyncStream<TranscriptDisplay>.Continuation

    var isLoaded: Bool { manager != nil }

    init() {
        (displayStream, displayContinuation) = AsyncStream<TranscriptDisplay>.makeStream()
    }

    /// Downloads (first run only) and loads the model into memory. Idempotent.
    func warmUp(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard manager == nil else { return }
        // Pin inference to the Apple Neural Engine (CPU only as fallback for ops
        // the ANE can't run; the mel preprocessor stays CPU by design). This is
        // FluidAudio's current default too, but set explicitly so it can't drift.
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let models = try await AsrModels.downloadAndLoad(
            configuration: configuration,
            version: Self.modelVersion,
            encoderComputeUnits: .cpuAndNeuralEngine,
            progressHandler: { p in progress(p.fractionCompleted) })
        let mgr = AsrManager(config: .default)
        try await mgr.loadModels(models)
        manager = mgr
    }

    /// Begins a session and returns the continuation the mic feeds.
    /// `previewInterval` is the seconds of new audio between live re-transcriptions.
    func beginSession(previewInterval: Double) async throws -> AsyncStream<AudioChunk>.Continuation {
        guard let manager else { throw ASRServiceError.notLoaded }
        if current != nil { await teardown() }

        let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream()
        let display = displayContinuation
        DiagLog.log("session: begin")

        // Accumulate mic audio (resampled to 16 kHz once per chunk) and re-transcribe
        // the growing buffer for the live preview. Returns the full buffer so
        // endSession can run the authoritative final pass over all of it.
        let pump = Task.detached(priority: .userInitiated) { () -> [Float] in
            let converter = AudioConverter()
            var samples: [Float] = []
            var sincePreview = 0
            for await chunk in audioStream {
                if let resampled = try? converter.resample(chunk.samples, from: chunk.sampleRate) {
                    samples.append(contentsOf: resampled)
                }
                sincePreview += chunk.samples.count
                if Double(sincePreview) >= chunk.sampleRate * previewInterval, !samples.isEmpty {
                    sincePreview = 0
                    if let text = await Self.transcribe(samples, manager: manager), !text.isEmpty {
                        display.yield(TranscriptDisplay(confirmed: text, volatile: ""))
                    }
                }
            }
            return samples
        }

        current = Session(audioContinuation: audioContinuation, pump: pump)
        return audioContinuation
    }

    /// Ends the session and returns the accurate final transcript (full-audio pass).
    func endSession() async throws -> String {
        guard let session = current, let manager else { return "" }
        current = nil
        session.audioContinuation.finish()

        let samples = await session.pump.value
        guard !samples.isEmpty else {
            DiagLog.log("session: end, final=\"\"")
            return ""
        }
        let text = await Self.transcribe(samples, manager: manager) ?? ""
        let cleaned = Self.cleanup(text)
        DiagLog.log("session: end, final=\"\(cleaned)\"")
        return cleaned
    }

    /// Abandon the current session without transcribing or returning any text.
    func cancelSession() async {
        await teardown()
    }

    private func teardown() async {
        guard let session = current else { return }
        current = nil
        session.audioContinuation.finish()
        session.pump.cancel()
    }

    /// One-shot transcription of 16 kHz mono samples with a fresh decoder state.
    private static func transcribe(_ samples16k: [Float], manager: AsrManager) async -> String? {
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        guard let result = try? await manager.transcribe(samples16k, decoderState: &state) else {
            return nil
        }
        return result.text
    }

    /// Tidy whitespace and the repeated trailing "." that trailing silence produces.
    private static func cleanup(_ raw: String) -> String {
        var s = raw
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.replacingOccurrences(of: " .", with: ".")
        while s.contains("..") { s = s.replacingOccurrences(of: "..", with: ".") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Session {
        let audioContinuation: AsyncStream<AudioChunk>.Continuation
        let pump: Task<[Float], Never>
    }
}
