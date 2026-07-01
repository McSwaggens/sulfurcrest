import Foundation

/// User-facing settings, persisted in UserDefaults (the app's bundle domain).
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    static let defaultPreviewInterval = 0.22
    static let defaultRevealDelayMs = 60.0

    /// Seconds of new audio between live-preview re-transcriptions. Smaller =
    /// words appear sooner (more real-time) at the cost of more CPU.
    @Published var previewInterval: Double {
        didSet { defaults.set(previewInterval, forKey: Keys.previewInterval) }
    }

    /// Delay between consecutive words fading into the HUD.
    @Published var revealDelayMs: Double {
        didSet { defaults.set(revealDelayMs, forKey: Keys.revealDelayMs) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let previewInterval = "previewInterval"
        static let revealDelayMs = "revealDelayMs"
    }

    private init() {
        previewInterval = defaults.object(forKey: Keys.previewInterval) as? Double
            ?? Self.defaultPreviewInterval
        revealDelayMs = defaults.object(forKey: Keys.revealDelayMs) as? Double
            ?? Self.defaultRevealDelayMs
    }
}
