import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @StateObject private var recorder = HotkeyRecorder()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var inputDevices = AudioDevices.inputs()

    /// Tag for the "System Default" row (empty == nil UID).
    private static let systemDefaultTag = ""

    var body: some View {
        Form {
            Section("Hotkey") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Dictation trigger")
                        Spacer()
                        Text(settings.hotkey.displayString)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack {
                        Button(recorder.isRecording ? "Press keys… (Esc to cancel)" : "Record shortcut") {
                            if recorder.isRecording {
                                recorder.cancel()
                            } else {
                                recorder.begin { settings.hotkey = $0 }
                            }
                        }
                        Button("Reset to Right ⌘") { settings.hotkey = .default }
                            .disabled(settings.hotkey == .default)
                    }
                    Text("Hold to talk, or tap to toggle. A single modifier (like "
                        + "Right ⌘) triggers on press and release; a key combo "
                        + "(like ⌃⌥Space) is captured system-wide and won't type "
                        + "into other apps. Escape always cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Microphone") {
                Picker("Input device", selection: Binding(
                    get: { settings.inputDeviceUID ?? Self.systemDefaultTag },
                    set: { settings.inputDeviceUID = $0.isEmpty ? nil : $0 })
                ) {
                    Text("System Default").tag(Self.systemDefaultTag)
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                Text("Which mic dictation records from. AirPods and other Bluetooth "
                    + "headsets work, but macOS drops them to call quality while "
                    + "recording — pick your built-in mic to keep their audio crisp "
                    + "and improve accuracy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Live preview") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Update rate")
                        Spacer()
                        Text(String(format: "%.1f / sec", 1.0 / settings.previewInterval))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { 1.0 / settings.previewInterval },
                            set: { settings.previewInterval = 1.0 / $0 }),
                        in: 1...10)
                    Text("How often the transcription refreshes while you speak. "
                        + "Higher feels more real-time but uses more CPU.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Word reveal speed")
                        Spacer()
                        Text("\(Int(settings.revealDelayMs)) ms")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.revealDelayMs, in: 0...150, step: 5)
                    Text("Delay between words fading into the window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, isOn in setLaunchAtLogin(isOn) }

                Toggle("Auto-stop when you stop speaking", isOn: $settings.autoStopEnabled)

                if settings.autoStopEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Stop after")
                            Spacer()
                            Text(String(format: "%.1f s of silence", settings.autoStopSilence))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.autoStopSilence, in: 0.5...5.0, step: 0.5)
                        Text("Only for hands-free (tap-to-start) dictation. Holding the "
                            + "hotkey still stops when you release it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { inputDevices = AudioDevices.inputs() }
        .onDisappear { recorder.cancel() }   // don't leave the live tap gated if closed mid-record
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Sulfurcrest: launch-at-login toggle failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Captures the next key combo the user presses, for the Settings "Record
/// shortcut" button.
///
/// Uses a local `NSEvent` monitor (returning nil to swallow) rather than a
/// first-responder view: local monitors run before menu key-equivalents, so
/// recording a ⌘-combo won't fire a menu item or beep. While recording, the live
/// `HotkeyMonitor` tap is gated so capturing a key doesn't also start dictation.
@MainActor
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    private var monitor: Any?
    private var onCommit: ((Hotkey) -> Void)?
    /// Keycode of a modifier pressed with no regular key yet — becomes a
    /// modifier-only hotkey if released alone.
    private var pendingModifier: UInt16?

    func begin(onCommit: @escaping (Hotkey) -> Void) {
        guard !isRecording else { return }
        isRecording = true
        pendingModifier = nil
        self.onCommit = onCommit
        HotkeyMonitor.shared.setRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.consume(event)
            return nil   // swallow so the keystroke can't leak into the form
        }
    }

    func cancel() { stop() }

    private func consume(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 { cancel(); return }   // Escape is reserved for cancel
            let mods = event.modifierFlags.intersection(Hotkey.relevantModifiers)
            guard !mods.isEmpty else { return }           // reject a bare key (would hijack typing)
            commit(Hotkey(keyCode: event.keyCode, modifiersRaw: mods.rawValue))

        case .flagsChanged:
            let mods = event.modifierFlags.intersection(Hotkey.relevantModifiers)
            if Hotkey.modifierKeyCodes.contains(event.keyCode), !mods.isEmpty, pendingModifier == nil {
                pendingModifier = event.keyCode                       // a modifier went down
            } else if let down = pendingModifier, mods.isEmpty {
                commit(Hotkey(keyCode: down, modifiersRaw: 0))        // all released → modifier-only
            }

        default:
            break
        }
    }

    private func commit(_ hotkey: Hotkey) {
        onCommit?(hotkey)
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onCommit = nil
        pendingModifier = nil
        isRecording = false
        HotkeyMonitor.shared.setRecording(false)
    }
}
