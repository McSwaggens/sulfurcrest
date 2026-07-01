import AppKit

/// Global watcher for the right Command key and the Escape key.
///
/// Right Command is keyCode 54 (left Command is 55); `.flagsChanged` fires once
/// per transition. Escape is keyCode 53 (`.keyDown`).
///
/// The raw NSEvent monitor callback runs with no Swift-concurrency executor
/// context, so anything that queries the current executor there —
/// `MainActor.assumeIsolated`, or creating a `Task` — crashes
/// (`swift_task_isCurrentExecutor` → KERN_PROTECTION_FAILURE). So the callback
/// does nothing but `continuation.yield` (thread-safe, no executor check); the
/// events are consumed from a Task that lives in a real main-actor context.
final class RightCommandWatcher {
    enum Event: Sendable {
        case rightCommand(down: Bool)
        case escape
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private static let rightCommandKeyCode: UInt16 = 54
    private static let escapeKeyCode: UInt16 = 53

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    /// Installs the monitors. Needs Accessibility to see events while other apps
    /// are frontmost.
    func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        let continuation = self.continuation

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            Self.forward(event, to: continuation)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            Self.forward(event, to: continuation)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private static func forward(_ event: NSEvent, to continuation: AsyncStream<Event>.Continuation) {
        switch event.type {
        case .flagsChanged where event.keyCode == rightCommandKeyCode:
            continuation.yield(.rightCommand(down: event.modifierFlags.contains(.command)))
        case .keyDown where event.keyCode == escapeKeyCode:
            continuation.yield(.escape)
        default:
            break
        }
    }
}
