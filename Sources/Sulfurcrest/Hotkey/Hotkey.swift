import AppKit

/// A user-recorded dictation trigger.
///
/// Two shapes, distinguished by `isModifierOnly`:
///   - **Modifier-only** — the trigger *is* a modifier key (e.g. Right Command,
///     `keyCode 54`, no extra flags). Reproduces the original right-⌘ behavior
///     and can't be swallowed (a lone modifier types nothing anyway).
///   - **Regular key + modifiers** — e.g. Space + ⌃⌥. Captured system-wide and
///     swallowed so it doesn't leak into the frontmost app.
///
/// Plain value type so the `CGEventTap` callback (which runs with no
/// Swift-concurrency executor context) can read a snapshot safely.
struct Hotkey: Equatable, Sendable {
    /// Virtual keycode of the trigger key (`kVK_*`).
    var keyCode: UInt16
    /// Raw value of the required modifiers. Only the four in `relevantModifiers`
    /// are ever stored; 0 for a modifier-only trigger.
    var modifiersRaw: UInt

    /// Right Command, matching the app's original hardcoded hotkey.
    static let `default` = Hotkey(keyCode: 54, modifiersRaw: 0)

    /// The only modifiers we compare/store. Deliberately *not*
    /// `.deviceIndependentFlagsMask`, which also carries capsLock / function /
    /// numericPad — keeping those would desync the recorder (NSEvent flags) from
    /// the tap (CGEvent flags) for arrow keys, function keys, and caps-locked
    /// input.
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRaw).intersection(Self.relevantModifiers)
    }

    /// Virtual keycodes of the modifier keys (both sides, plus Fn/Globe).
    static let modifierKeyCodes: Set<UInt16> = [55, 54, 56, 60, 59, 62, 58, 61, 63, 179]

    var isModifierOnly: Bool { Self.modifierKeyCodes.contains(keyCode) }

    /// For a modifier-only trigger: the flag whose presence means "pressed".
    var modifierOnlyFlag: NSEvent.ModifierFlags? {
        switch keyCode {
        case 55, 54: return .command
        case 56, 60: return .shift
        case 59, 62: return .control
        case 58, 61: return .option
        case 63, 179: return .function
        default: return nil
        }
    }

    /// Human-readable label, e.g. "⌃⌥Space", "Right Command".
    var displayString: String {
        if isModifierOnly { return Self.modifierKeyName(keyCode) }
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }
}

// MARK: - Keycode → name

extension Hotkey {
    static func modifierKeyName(_ code: UInt16) -> String {
        switch code {
        case 54: return "Right Command"
        case 55: return "Left Command"
        case 60: return "Right Shift"
        case 56: return "Left Shift"
        case 62: return "Right Control"
        case 59: return "Left Control"
        case 61: return "Right Option"
        case 58: return "Left Option"
        case 63, 179: return "Fn (Globe)"
        default: return "Key \(code)"
        }
    }

    static func keyName(_ code: UInt16) -> String {
        if let n = specialNames[code] { return n }
        if let l = letters[code] { return l }
        if let d = digits[code] { return d }
        return "Key \(code)"
    }

    // Verified against HIToolbox/Events.h (ANSI layout). A layout-correct label
    // would need UCKeyTranslate; a static table is plenty for a settings label.
    private static let letters: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z",
    ]
    private static let digits: [UInt16: String] = [
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9",
    ]
    private static let specialNames: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown", 117: "Fwd Delete",
    ]
}
