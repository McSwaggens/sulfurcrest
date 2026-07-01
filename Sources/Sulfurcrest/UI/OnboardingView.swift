import AVFoundation
import SwiftUI

/// First-run welcome: introduces the hotkey and walks the user through the two
/// permissions and the one-time model download, with status that turns green
/// live as each step is satisfied. Non-blocking — closable at any time.
struct OnboardingView: View {
    @StateObject private var model = OnboardingModel()
    @ObservedObject private var modelStatus = ModelStatus.shared

    /// Called by "Get Started" so the host can close the window.
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            tips
            Divider()
            VStack(spacing: 14) {
                microphoneRow
                accessibilityRow
                modelRow
            }
            Divider()
            HStack {
                Spacer()
                Button("Get Started") {
                    Settings.shared.hasCompletedOnboarding = true
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Sulfurcrest")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Voice-to-text, anywhere you type.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Hold right ⌘, speak, then release to paste.", systemImage: "command")
            Label("Or tap right ⌘ to toggle · press Esc to cancel.", systemImage: "hand.tap")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private var microphoneRow: some View {
        PermissionRow(
            satisfied: model.micStatus == .authorized,
            title: "Microphone",
            subtitle: "To record your speech."
        ) {
            switch model.micStatus {
            case .authorized:
                grantedLabel
            case .notDetermined:
                Button("Grant") { Task { await model.requestMicrophone() } }
            default:
                Button("Open Settings") { model.openMicrophoneSettings() }
            }
        }
    }

    private var accessibilityRow: some View {
        PermissionRow(
            satisfied: model.accessibilityTrusted,
            title: "Accessibility",
            subtitle: "To paste transcribed text into apps."
        ) {
            if model.accessibilityTrusted {
                grantedLabel
            } else {
                Button("Open Settings") { model.openAccessibilitySettings() }
            }
        }
    }

    private var modelRow: some View {
        PermissionRow(
            satisfied: modelStatus.isLoaded,
            title: "Speech model",
            subtitle: modelSubtitle
        ) {
            if modelStatus.isLoaded {
                Text("Ready").foregroundStyle(.green).font(.callout)
            } else if modelStatus.failed {
                Text("Failed").foregroundStyle(.red).font(.callout)
            } else if let progress = modelStatus.progress {
                ProgressView(value: progress).frame(width: 96)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var grantedLabel: some View {
        Text("Granted").foregroundStyle(.green).font(.callout)
    }

    private var modelSubtitle: String {
        if modelStatus.isLoaded { return "Loaded and ready on the Neural Engine." }
        if modelStatus.failed { return "Couldn’t load — check your connection and relaunch." }
        if let progress = modelStatus.progress, progress < 1 {
            return "Downloading… \(Int(progress * 100))%"
        }
        return "Preparing the on-device model…"
    }
}

/// One permission/step row: status glyph, title + one-line "why", trailing action.
private struct PermissionRow<Trailing: View>: View {
    let satisfied: Bool
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(satisfied ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
    }
}
