import Foundation

/// User-facing settings, persisted in UserDefaults (the app's bundle domain).
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    static let defaultPreviewInterval = 0.22
    static let defaultRevealDelayMs = 60.0
    static let defaultAutoStopEnabled = false        // off by default
    static let defaultAutoStopSilence = 2.0          // seconds

    /// Seconds of new audio between live-preview re-transcriptions. Smaller =
    /// words appear sooner (more real-time) at the cost of more CPU.
    @Published var previewInterval: Double {
        didSet { defaults.set(previewInterval, forKey: Keys.previewInterval) }
    }

    /// Delay between consecutive words fading into the HUD.
    @Published var revealDelayMs: Double {
        didSet { defaults.set(revealDelayMs, forKey: Keys.revealDelayMs) }
    }

    /// Whether the first-run onboarding window has been dismissed via "Get
    /// Started". Drives whether onboarding auto-appears at launch.
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// UID of the input device to capture from, or nil for the system default.
    /// Pinning to the built-in mic avoids the Bluetooth A2DP→HFP switch (AirPods
    /// dropping to call quality) while dictating.
    @Published var inputDeviceUID: String? {
        didSet { defaults.set(inputDeviceUID, forKey: Keys.inputDeviceUID) }
    }

    /// Finish a hands-free (tap-to-start) session automatically after silence.
    @Published var autoStopEnabled: Bool {
        didSet { defaults.set(autoStopEnabled, forKey: Keys.autoStopEnabled) }
    }

    /// Seconds of continuous silence before a hands-free session auto-finishes.
    @Published var autoStopSilence: Double {
        didSet { defaults.set(autoStopSilence, forKey: Keys.autoStopSilence) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let previewInterval = "previewInterval"
        static let revealDelayMs = "revealDelayMs"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let inputDeviceUID = "inputDeviceUID"
        static let autoStopEnabled = "autoStopEnabled"
        static let autoStopSilence = "autoStopSilence"
    }

    private init() {
        previewInterval = defaults.object(forKey: Keys.previewInterval) as? Double
            ?? Self.defaultPreviewInterval
        revealDelayMs = defaults.object(forKey: Keys.revealDelayMs) as? Double
            ?? Self.defaultRevealDelayMs
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        inputDeviceUID = defaults.string(forKey: Keys.inputDeviceUID)
        autoStopEnabled = defaults.object(forKey: Keys.autoStopEnabled) as? Bool
            ?? Self.defaultAutoStopEnabled
        autoStopSilence = defaults.object(forKey: Keys.autoStopSilence) as? Double
            ?? Self.defaultAutoStopSilence
    }
}
