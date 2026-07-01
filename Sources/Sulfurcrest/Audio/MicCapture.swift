import AVFoundation

/// Captures microphone audio via `AVCaptureSession` and forwards `Sendable`
/// chunks to a continuation.
///
/// `AVCaptureSession` is the input-only capture stack (the one video-conferencing
/// apps use). Unlike `AVAudioEngine`, it does **not** couple
/// the mic to an output render graph, so a Bluetooth A2DP→HFP switch (AirPods)
/// can't stall it on an input/output sample-rate mismatch — it just delivers the
/// mic's buffers at whatever rate the device is running. All work happens on a
/// private queue; the delegate's sample buffers are converted to mono `Float`
/// `AudioChunk`s (the ASR pump resamples each chunk to 16 kHz).
///
/// Pass `deviceUID` (an `AVCaptureDevice.uniqueID`) to capture from a specific
/// input; nil uses the system default.
final class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "sulfurcrest.miccapture")

    // Owned by `queue`.
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var outputConfigured = false

    /// Starts capture on the private queue; resolves once the session is running.
    /// Safe to call from the main actor.
    func start(deviceUID: String?, feeding continuation: AsyncStream<AudioChunk>.Continuation) async {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                self?.configureAndStart(deviceUID: deviceUID, feeding: continuation)
                resume.resume()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.continuation = nil
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: - Queue-isolated setup

    private func configureAndStart(
        deviceUID: String?, feeding continuation: AsyncStream<AudioChunk>.Continuation
    ) {
        self.continuation = continuation

        let device = deviceUID.flatMap { AVCaptureDevice(uniqueID: $0) }
            ?? AVCaptureDevice.default(for: .audio)
        guard let device else {
            DiagLog.log("mic: no audio capture device available")
            return
        }
        DiagLog.log("mic: capture device=\(device.localizedName)")

        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            DiagLog.log("mic: AVCaptureDeviceInput failed: \(error)")
            session.commitConfiguration()
            return
        }

        if !outputConfigured {
            output.setSampleBufferDelegate(self, queue: queue)
            // Ask for interleaved 32-bit float PCM; the device's own sample rate
            // is kept (read per-buffer) and resampled downstream.
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            if session.canAddOutput(output) { session.addOutput(output) }
            outputConfigured = true
        }
        session.commitConfiguration()

        if !session.isRunning { session.startRunning() }
        DiagLog.log("mic: capture session running=\(session.isRunning)")
    }

    // MARK: - Sample delivery (on `queue`)

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let continuation else { return }
        guard
            let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
        else { return }

        let sampleRate = asbd.mSampleRate
        let channels = Int(asbd.mChannelsPerFrame)
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, channels > 0, sampleRate > 0 else { return }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard status == noErr, let data = audioBufferList.mBuffers.mData else { return }

        let interleaved = data.assumingMemoryBound(to: Float.self)
        var mono = [Float](repeating: 0, count: frames)
        if channels == 1 {
            mono.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.update(from: interleaved, count: frames)
            }
        } else {
            let scale = 1.0 / Float(channels)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += interleaved[frame * channels + channel] }
                mono[frame] = sum * scale
            }
        }
        continuation.yield(AudioChunk(samples: mono, sampleRate: sampleRate))
    }
}
