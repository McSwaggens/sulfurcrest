import SwiftUI

/// One displayed word. Stable `id` (its position) keeps SwiftUI from re-animating
/// a word when a later re-transcription revises it in place.
struct DisplayWord: Identifiable, Equatable {
    let id: Int
    var text: String
}

/// Observable state backing the live transcription HUD.
///
/// Transcription previews arrive as whole strings; this model reveals their words
/// one at a time (so a preview that jumps several words ahead still streams in
/// word-by-word), while revising already-shown words in place.
@MainActor
final class TranscriptModel: ObservableObject {
    @Published private(set) var words: [DisplayWord] = []
    @Published var isListening = false
    @Published var statusMessage: String?
    /// Live microphone input level (0...1) driving the meter "cursor".
    @Published var inputLevel: Float = 0

    private var target: [String] = []
    private var revealTask: Task<Void, Never>?

    /// Set the latest full transcript; new words stream in, revisions apply in place.
    func setTranscript(_ text: String) {
        statusMessage = nil
        target = text.split(separator: " ").map(String.init)

        // Revise already-revealed words in place.
        for index in words.indices where index < target.count {
            if words[index].text != target[index] { words[index].text = target[index] }
        }
        // If a revision shortened the transcript, drop the extra trailing words.
        if words.count > target.count {
            words.removeLast(words.count - target.count)
        }
        startRevealing()
    }

    private func startRevealing() {
        guard revealTask == nil else { return }
        revealTask = Task { @MainActor in
            while words.count < target.count {
                let next = words.count
                withAnimation(.easeOut(duration: 0.22)) {
                    words.append(DisplayWord(id: next, text: target[next]))
                }
                try? await Task.sleep(for: .milliseconds(Int(Settings.shared.revealDelayMs)))
            }
            revealTask = nil
        }
    }

    func reset() {
        revealTask?.cancel()
        revealTask = nil
        words = []
        target = []
        statusMessage = nil
        inputLevel = 0
    }
}
