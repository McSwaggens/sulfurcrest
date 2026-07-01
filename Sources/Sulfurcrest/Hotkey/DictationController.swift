import AppKit
import Foundation

/// Drives dictation from the right-Command key and Escape.
///
/// Two clearly separated layers keep fast key presses from ever racing or wedging
/// the UI:
///   - **Intent layer** (synchronous): interprets key events into high-level
///     commands using only plain flags. Never touches the HUD/mic/ASR.
///   - **Execution layer** (one serial async task): the only place that starts/stops
///     sessions and shows/hides the HUD, running one command fully before the next
///     — so sessions can't overlap and the HUD can't get stuck.
///
/// One key drives two styles: hold ≥ `holdThreshold` then release = push-to-talk;
/// a quick tap latches recording on until the next tap (toggle).
@MainActor
final class DictationController {
    private let hud = GlassHUDPanel()
    private let mic = MicCapture()
    private let asr = ASRService.shared
    private let watcher = RightCommandWatcher()

    // MARK: Intent layer (synchronous)
    private var physicalDown = false
    private var active = false
    private var toggledOn = false
    private var downAt: Date?
    private var isModelReady = false
    private var flashWork: DispatchWorkItem?
    private let holdThreshold: TimeInterval = 0.35

    // MARK: Execution layer (serial)
    private enum Command { case start, stop, cancel }
    private let commands: AsyncStream<Command>
    private let commandContinuation: AsyncStream<Command>.Continuation
    private var sessionActive = false

    private var started = false

    init() {
        (commands, commandContinuation) = AsyncStream.makeStream()
    }

    func setModelReady(_ ready: Bool) {
        isModelReady = ready
    }

    /// Installs the hotkey monitors and starts the consumers. Call once.
    func start() {
        guard !started else { return }
        started = true
        watcher.start()

        // Key events → intent state machine.
        let events = watcher.events
        Task { [weak self] in
            for await event in events { self?.handle(event) }
        }

        // Serial command processor: one command fully handled before the next.
        let commands = self.commands
        Task { [weak self] in
            for await command in commands { await self?.run(command) }
        }

        // Live transcript → HUD.
        Task { [weak self] in
            for await display in ASRService.shared.displayStream {
                self?.hud.model.setTranscript(display.combined)
            }
        }
    }

    // MARK: - Intent layer (synchronous, instant)

    private func handle(_ event: RightCommandWatcher.Event) {
        switch event {
        case .rightCommand(let down):
            down ? commandKeyDown() : commandKeyUp()
        case .escape:
            escape()
        }
    }

    private func commandKeyDown() {
        guard !physicalDown else { return }   // dedup repeated flagsChanged
        physicalDown = true
        downAt = Date()
        guard isModelReady else {
            flash("Loading model…")
            return
        }
        if !active {
            active = true
            commandContinuation.yield(.start)
        }
    }

    private func commandKeyUp() {
        guard physicalDown else { return }
        physicalDown = false
        guard active else { return }
        let held = Date().timeIntervalSince(downAt ?? Date())
        if held >= holdThreshold || toggledOn {
            active = false
            toggledOn = false
            commandContinuation.yield(.stop)
        } else {
            toggledOn = true   // first quick tap latches on until the next tap
        }
    }

    private func escape() {
        guard active else { return }
        active = false
        toggledOn = false
        commandContinuation.yield(.cancel)
    }

    // MARK: - Execution layer (serial async)

    private func run(_ command: Command) async {
        switch command {
        case .start:
            guard !sessionActive else { return }
            sessionActive = true
            flashWork?.cancel()
            hud.present()
            do {
                let continuation = try await asr.beginSession(
                    previewInterval: Settings.shared.previewInterval)
                await mic.start(
                    deviceUID: Settings.shared.inputDeviceUID, feeding: continuation)
            } catch {
                sessionActive = false
                await asr.cancelSession()
                flash("Microphone unavailable")
                NSLog("Sulfurcrest: failed to start dictation: \(error)")
            }

        case .stop:
            guard sessionActive else { return }
            sessionActive = false
            mic.stop()
            hud.dismiss()
            let text = (try? await asr.endSession()) ?? ""
            if !text.isEmpty { Paster.paste(text) }   // nothing transcribed → do nothing

        case .cancel:
            guard sessionActive else { return }
            sessionActive = false
            mic.stop()
            hud.dismiss()
            await asr.cancelSession()
        }
    }

    /// Briefly show a status message in the HUD, then auto-dismiss. Only used when
    /// no session HUD is on screen.
    private func flash(_ message: String) {
        guard !sessionActive else { return }
        flashWork?.cancel()
        hud.showMessage(message)
        let work = DispatchWorkItem { [weak self] in self?.hud.dismiss() }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}
