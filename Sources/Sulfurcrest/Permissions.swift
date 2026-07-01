import AVFoundation
import ApplicationServices

/// Thin wrappers around the TCC permissions this app needs:
/// Accessibility (global hotkey monitor + synthetic ⌘V) and Microphone.
enum Permissions {
    /// Returns whether the process is trusted for Accessibility, optionally
    /// opening the system prompt / Settings pane when it is not.
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        // Key string is kAXTrustedCheckOptionPrompt ("AXTrustedCheckOptionPrompt").
        let options = ["AXTrustedCheckOptionPrompt" as CFString: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Requests microphone access, surfacing the system prompt on first call.
    static func ensureMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}
