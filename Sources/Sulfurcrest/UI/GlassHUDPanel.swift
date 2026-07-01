import AppKit
import SwiftUI

/// A small, centered, click-through glass panel that floats above all apps and
/// never steals focus (`.nonactivatingPanel` + `canBecomeKey == false`). It grows
/// vertically to fit the transcript, staying centered on screen.
@MainActor
final class GlassHUDPanel: NSPanel {
    let model = TranscriptModel()
    private var host: NSHostingView<TranscriptionView>!

    private let minHeight: CGFloat = 64
    private let maxHeight: CGFloat = 360

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: TranscriptionView.width, height: 64),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 26
        blur.layer?.masksToBounds = true

        // Darkening tint over the blur (clipped to the rounded shape by the blur's
        // masksToBounds), giving the HUD a deeper, more solid background.
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(tint)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            tint.topAnchor.constraint(equalTo: blur.topAnchor),
            tint.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])

        host = NSHostingView(
            rootView: TranscriptionView(model: model, onHeightChange: { [weak self] height in
                self?.applyContentHeight(height)
            }))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        contentView = blur
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Resize to fit the transcript, keeping the panel's center fixed.
    private func applyContentHeight(_ height: CGFloat) {
        let target = max(minHeight, min(ceil(height), maxHeight))
        guard abs(frame.height - target) > 0.5 else { return }
        var f = frame
        let centerY = f.midY
        f.size.height = target
        f.origin.y = centerY - target / 2
        setFrame(f, display: true)
    }

    /// Show centered without activating this app.
    func present() {
        model.reset()
        model.isListening = true
        center()
        orderFrontRegardless()
    }

    /// Show a transient status message (no live transcript / recording dot).
    func showMessage(_ message: String) {
        model.reset()
        model.isListening = false
        model.statusMessage = message
        center()
        orderFrontRegardless()
    }

    func dismiss() {
        model.isListening = false
        orderOut(nil)
    }
}
