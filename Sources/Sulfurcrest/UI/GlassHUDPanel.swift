import AppKit
import ApplicationServices
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
        centerOnFocusedScreen()
        orderFrontRegardless()
    }

    /// Show a transient status message (no live transcript / recording dot).
    func showMessage(_ message: String) {
        model.reset()
        model.isListening = false
        model.statusMessage = message
        centerOnFocusedScreen()
        orderFrontRegardless()
    }

    /// Center the panel on the display that holds the currently focused window,
    /// so the HUD appears where the user is actually working on a multi-display
    /// setup. `.canJoinAllSpaces` already keeps it on the active Space; this only
    /// picks the right screen. Falls back to the screen under the cursor, then
    /// the main screen.
    private func centerOnFocusedScreen() {
        let screen = focusedScreen() ?? NSScreen.main
        guard let screen else { center(); return }
        let visible = screen.visibleFrame
        var f = frame
        f.origin.x = visible.midX - f.width / 2
        f.origin.y = visible.midY - f.height / 2
        setFrame(f, display: true)
    }

    /// The screen containing the focused window of the frontmost app (via the
    /// Accessibility API), or the screen under the mouse cursor.
    private func focusedScreen() -> NSScreen? {
        if let center = focusedWindowCenter(),
           let match = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return match
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    /// Center point of the frontmost app's focused window in Cocoa (bottom-left
    /// origin) global coordinates, or nil if it can't be determined.
    private func focusedWindowCenter() -> NSPoint? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return nil }
        let app = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        let axWindow = window as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }

        // AX coordinates are top-left origin (y grows down), relative to the top
        // of the primary display. Convert the window center to Cocoa's
        // bottom-left global space to match against NSScreen frames.
        guard let primary = NSScreen.screens.first else { return nil }
        let axCenter = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        return NSPoint(x: axCenter.x, y: primary.frame.maxY - axCenter.y)
    }

    func dismiss() {
        model.isListening = false
        orderOut(nil)
    }
}
