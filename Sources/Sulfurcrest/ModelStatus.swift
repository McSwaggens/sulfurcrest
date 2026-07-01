import Foundation

/// Observable mirror of the one-time speech-model download/load so the
/// onboarding window can show live progress.
///
/// The single warm-up runs in `AppDelegate`; `ASRService.warmUp` is idempotent
/// (a second call returns early with no progress callbacks), so onboarding
/// *observes* this shared state rather than starting its own load.
@MainActor
final class ModelStatus: ObservableObject {
    static let shared = ModelStatus()

    /// Download progress in 0…1, or nil before the first progress callback
    /// (e.g. while the model loads from cache).
    @Published var progress: Double?
    @Published var isLoaded = false
    @Published var failed = false

    private init() {}

    func markLoaded() {
        progress = 1
        isLoaded = true
        failed = false
    }
}
