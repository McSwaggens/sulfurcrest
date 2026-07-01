import AppKit
import os

/// Global keyboard monitor that turns the user's configured hotkey into clean
/// down/up (+ Escape) events, and SWALLOWS a regular-key combo so it doesn't
/// leak into the frontmost app.
///
/// Uses a `CGEventTap` (needs Accessibility). Unlike an `NSEvent` monitor, a tap
/// can consume events by returning nil — required so a combo like ⌃⌥Space
/// doesn't also type into whatever app is focused.
///
/// The tap runs on a dedicated high-priority thread, not the main run loop: it
/// sits in the path of every system keystroke, so a stall on the consumer side
/// must never delay typing. The thread also retries `tapCreate` until
/// Accessibility is granted, so the hotkey starts working without a relaunch.
///
/// The tap callback is `@convention(c)` and runs with NO Swift-concurrency
/// executor context, so it must only do plain work + `continuation.yield`. It
/// must never create a `Task` or call `MainActor.assumeIsolated` there — that
/// queries the current executor and crashes (`swift_task_isCurrentExecutor` →
/// KERN_PROTECTION_FAILURE). It reads a lock-guarded snapshot and never touches
/// @MainActor state.
final class HotkeyMonitor: @unchecked Sendable {
    static let shared = HotkeyMonitor()

    enum Event: Sendable {
        case hotkey(down: Bool)
        case escape
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    /// Cross-thread state: written on the main actor (`updateHotkey`,
    /// `setRecording`) and on the tap thread. `matchActive`/`modifierDown` track
    /// whether we've emitted a `down` we still owe an `up` for; `pressedKeyCode`
    /// is the physical key we keep swallowing (incl. autorepeat) until its keyUp.
    private struct State {
        var hotkey: Hotkey = .default
        var recording = false
        var matchActive = false
        var modifierDown = false
        var pressedKeyCode: Int64?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    private var tap: CFMachPort?
    private var tapThread: Thread?
    private static let escapeKeyCode: Int64 = 53

    private init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    // MARK: - Configuration (main actor)

    /// Swap in a new hotkey. If a press was in flight, emit the matching `up` so
    /// dictation can't wedge on, and forget the physical key we were swallowing.
    func updateHotkey(_ hk: Hotkey) {
        let wasDown = state.withLock { st -> Bool in
            let down = st.matchActive || st.modifierDown
            st.hotkey = hk
            st.matchActive = false
            st.modifierDown = false
            st.pressedKeyCode = nil
            return down
        }
        if wasDown { continuation.yield(.hotkey(down: false)) }
    }

    /// While the Settings recorder is capturing, the live tap must not fire
    /// dictation; it passes every event straight through. Starting a recording
    /// mid-press emits the pending `up` so dictation doesn't stay on.
    func setRecording(_ on: Bool) {
        let wasDown = state.withLock { st -> Bool in
            let down = on && (st.matchActive || st.modifierDown)
            st.recording = on
            if on {
                st.matchActive = false
                st.modifierDown = false
                st.pressedKeyCode = nil
            }
            return down
        }
        if wasDown { continuation.yield(.hotkey(down: false)) }
    }

    // MARK: - Lifecycle

    /// Spins up the tap thread. Idempotent.
    func start() {
        guard tapThread == nil else { return }
        let thread = Thread { [weak self] in self?.runTapThread() }
        thread.name = "com.sulfurcrest.hotkey-tap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    /// Runs on the dedicated thread: create the tap (retrying until Accessibility
    /// is granted), then service its run loop until stopped.
    private func runTapThread() {
        while !installTap() {
            if Thread.current.isCancelled { return }
            Thread.sleep(forTimeInterval: 1.0)   // wait for Accessibility, then retry
        }
        CFRunLoopRun()
    }

    private func installTap() -> Bool {
        let mask: CGEventMask =
            ((1 as UInt64) << CGEventType.keyDown.rawValue)
            | ((1 as UInt64) << CGEventType.keyUp.rawValue)
            | ((1 as UInt64) << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: refcon)
        else {
            return false   // Accessibility not granted yet — caller retries.
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - Tap callback (executor-free, on the tap thread)

    /// Returns true to swallow the event, false to pass it through.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        // The system disables a tap that is too slow or during heavy input; the
        // only fix is to re-enable it from here.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        let snapshot = state.withLock { $0 }
        if snapshot.recording { return false }   // Settings recorder owns the keyboard.

        let code = event.getIntegerValueField(.keyboardEventKeycode)

        // Escape → cancel. Always pass through (as before).
        if type == .keyDown, code == Self.escapeKeyCode {
            continuation.yield(.escape)
            return false
        }

        let hk = snapshot.hotkey

        if hk.isModifierOnly {
            // A lone modifier: down = its flag is now present. Never swallow —
            // suppressing a bare modifier is neither possible nor desirable.
            if type == .flagsChanged, code == Int64(hk.keyCode), let flag = hk.modifierOnlyFlag {
                let down = event.flags.contains(Self.cgFlag(for: flag))
                state.withLock { $0.modifierDown = down }
                continuation.yield(.hotkey(down: down))
            }
            return false
        }

        // Regular key + exact modifiers. Once the physical key is down we swallow
        // everything it emits (incl. autorepeat) until its keyUp, regardless of
        // modifier changes, so nothing leaks into the frontmost app.
        let flags = Self.deviceIndependent(event.flags)
        switch type {
        case .keyDown:
            if let pressed = snapshot.pressedKeyCode, code == pressed {
                return true   // swallow autorepeat of the held hotkey key
            }
            if snapshot.pressedKeyCode == nil, code == Int64(hk.keyCode), flags == hk.modifiers {
                state.withLock { $0.pressedKeyCode = code; $0.matchActive = true }
                continuation.yield(.hotkey(down: true))
                return true
            }
            return false

        case .keyUp:
            if let pressed = snapshot.pressedKeyCode, code == pressed {
                let wasActive = snapshot.matchActive
                state.withLock { $0.pressedKeyCode = nil; $0.matchActive = false }
                if wasActive { continuation.yield(.hotkey(down: false)) }
                return true
            }
            return false

        case .flagsChanged:
            // A required modifier was released before the key → end dictation, but
            // keep swallowing the still-held key until it comes up.
            if snapshot.matchActive, flags != hk.modifiers {
                state.withLock { $0.matchActive = false }
                continuation.yield(.hotkey(down: false))
            }
            return false

        default:
            return false
        }
    }

    // MARK: - Flag mapping

    /// The four relevant modifiers, mapped from CGEvent to NSEvent flags so the
    /// comparison matches `Hotkey.modifiers`. Everything else (capsLock, fn,
    /// numericPad) is dropped.
    static func deviceIndependent(_ cg: CGEventFlags) -> NSEvent.ModifierFlags {
        var f = NSEvent.ModifierFlags()
        if cg.contains(.maskCommand) { f.insert(.command) }
        if cg.contains(.maskShift) { f.insert(.shift) }
        if cg.contains(.maskAlternate) { f.insert(.option) }
        if cg.contains(.maskControl) { f.insert(.control) }
        return f
    }

    /// CGEvent flag for a single NSEvent modifier (used for modifier-only
    /// detection, incl. Fn which `deviceIndependent` intentionally omits).
    static func cgFlag(for flag: NSEvent.ModifierFlags) -> CGEventFlags {
        switch flag {
        case .command: return .maskCommand
        case .shift: return .maskShift
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .function: return .maskSecondaryFn
        default: return []
        }
    }
}

/// Top-level C callback (captures nothing). Recovers the monitor from `userInfo`.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
