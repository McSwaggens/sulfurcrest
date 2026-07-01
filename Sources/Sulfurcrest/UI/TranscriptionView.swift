import SwiftUI

/// The glass HUD content: a recording dot plus the live transcript. Words flow
/// and wrap, each fades in as it is revealed, and the view reports its natural
/// height so the window can grow to fit.
struct TranscriptionView: View {
    @ObservedObject var model: TranscriptModel
    var onHeightChange: @MainActor (CGFloat) -> Void = { _ in }

    static let width: CGFloat = 480

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(model.isListening ? Color.red : Color.secondary)
                .frame(width: 9, height: 9)
                .opacity(model.isListening ? 1 : 0.4)
                .padding(.top, 6)

            content
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: Self.width, alignment: .topLeading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self) { height in
            Task { @MainActor in onHeightChange(height) }
        }
    }

    @ViewBuilder private var content: some View {
        if let message = model.statusMessage {
            Text(message).foregroundStyle(.secondary)
        } else if model.words.isEmpty {
            Text(model.isListening ? "Listening…" : "").foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 6, lineSpacing: 4) {
                ForEach(model.words) { word in
                    WordView(text: word.text)
                }
            }
        }
    }
}

/// A single transcript word that fades in when it first appears.
private struct WordView: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Text(text)
            .foregroundStyle(.primary)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.28)) { shown = true }
            }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
