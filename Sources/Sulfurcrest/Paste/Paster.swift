import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Inserts text into the frontmost app by placing it on the pasteboard and
/// synthesizing ⌘V, then restoring the previous pasteboard contents.
///
/// Requires Accessibility permission to post the synthetic keystroke. This app
/// never activates itself, so focus stays with the target app and the paste lands
/// where the user's cursor is.
@MainActor
enum Paster {
    static func paste(_ text: String) {
        guard !text.isEmpty else { return }
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        DiagLog.log("paste: len=\(text.count) axTrusted=\(AXIsProcessTrusted()) front=\(frontApp)")
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        let ok = pasteboard.clearContents()
        let setOK = pasteboard.setString(text, forType: .string)
        DiagLog.log("paste: clipboard changeCount=\(ok) setString=\(setOK)")

        // Brief delay so the target observes the new pasteboard before ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postCommandV()
            DiagLog.log("paste: posted Cmd+V")
        }
        // Restore the user's prior clipboard once the paste has been read.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            restore(saved, to: pasteboard)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        pasteboard.pasteboardItems?.map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let value = item.data(forType: type) { data[type] = value }
            }
            return data
        } ?? []
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        guard !saved.isEmpty else { return }
        pasteboard.clearContents()
        let items = saved.compactMap { dict -> NSPasteboardItem? in
            guard !dict.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, value) in dict { item.setData(value, forType: type) }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
