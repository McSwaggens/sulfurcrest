import AVFoundation
import Foundation

/// Drives the onboarding window: reflects live permission state (polled while
/// the window is open) and performs the grant / open-Settings actions.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var micStatus: AVAuthorizationStatus = Permissions.microphoneStatus
    @Published var accessibilityTrusted: Bool = Permissions.isAccessibilityTrusted

    private var pollTask: Task<Void, Never>?

    /// Re-read both permissions. Cheap and non-prompting.
    func refresh() {
        micStatus = Permissions.microphoneStatus
        accessibilityTrusted = Permissions.isAccessibilityTrusted
    }

    /// Poll ~1.6×/sec so a row flips to green the moment its grant lands —
    /// including when the user toggles the app on in System Settings and
    /// returns. Stopped from the view's `onDisappear`.
    func startPolling() {
        refresh()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard let self else { break }
                self.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Inline system prompt when undetermined; a no-op once the user has
    /// already decided (that case routes through `openMicrophoneSettings`).
    func requestMicrophone() async {
        _ = await Permissions.ensureMicrophone()
        refresh()
    }

    func openMicrophoneSettings() {
        Permissions.openMicrophoneSettings()
    }

    /// Register in the Accessibility list (so the app appears there) then open
    /// the pane so the user can toggle it on.
    func openAccessibilitySettings() {
        Permissions.ensureAccessibility(prompt: false)
        Permissions.openAccessibilitySettings()
    }
}
