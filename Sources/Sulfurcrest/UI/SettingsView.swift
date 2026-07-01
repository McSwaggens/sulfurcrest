import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
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
