import AppKit

// Headless diagnostic: load the model from cache and report, then exit.
if CommandLine.arguments.contains("--selftest") {
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            try await ASRService.shared.warmUp { _ in }
            print("SELFTEST_OK: model loaded")
        } catch {
            print("SELFTEST_FAIL: \(error)")
        }
        done.signal()
    }
    done.wait()
    exit(0)
}

// Headless pipeline test: feed generated audio through begin → feed → end.
if CommandLine.arguments.contains("--selftest-asr") {
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            try await ASRService.shared.warmUp { _ in }
            let continuation = try await ASRService.shared.beginSession(previewInterval: 0.22)
            let sampleRate = 16_000.0
            let total = Int(sampleRate * 2)
            let chunkSize = 1_600
            var idx = 0
            while idx < total {
                let end = min(idx + chunkSize, total)
                let samples = (idx..<end).map { 0.05 * sinf(2 * Float.pi * 220 * Float($0) / Float(sampleRate)) }
                continuation.yield(AudioChunk(samples: samples, sampleRate: sampleRate))
                idx = end
            }
            let final = try await ASRService.shared.endSession()
            print("SELFTEST_ASR_OK final=\"\(final)\"")
        } catch {
            print("SELFTEST_ASR_FAIL \(error)")
        }
        done.signal()
    }
    done.wait()
    exit(0)
}

// Agent app: no Dock icon, lives in the menu bar (also declared via LSUIElement).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
