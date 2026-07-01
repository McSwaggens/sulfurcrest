import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var inputDevices = AudioDevices.inputs()

    /// Tag for the "System Default" row (empty == nil UID).
    private static let systemDefaultTag = ""

    var body: some View {
        Form {
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { inputDevices = AudioDevices.inputs() }
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
