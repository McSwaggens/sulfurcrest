import AppKit
import CoreAudio

/// Pauses system media when a dictation session starts (so it doesn't bleed into
/// the recording) and resumes it when the session ends.
///
/// **Why the media key.** macOS 15.4 closed the now-playing daemon to unprivileged
/// processes: the private MediaRemote framework's reads *and* command sends silently
/// no-op (confirmed by OpenWhispr's shipping helper, which hard-bails to the media
/// key on ≥15.4). So on current macOS the only mechanism that actually works is the
/// hardware Play/Pause key, posted synthetically via `CGEvent` — the same
/// Accessibility-backed channel `Paster` uses for ⌘V (no extra permission prompt).
///
/// **The catch.** The media key is a *toggle*, and macOS gives no way to read
/// whether media is playing, so a blind toggle can *start* paused media. We reduce
/// that with a CoreAudio guard: the caller only toggles when audio is actually
/// running (`isOutputActive()`), and only toggles back to resume what it paused.
/// The one residual gap — media you *just* paused yourself, whose output stream is
/// still warm — can't be closed without the detection macOS blocks.
@MainActor
enum MediaController {
    /// `NX_KEYTYPE_PLAY` from `<IOKit/hidsystem/ev_keymap.h>` (a C macro not bridged
    /// into Swift), hardcoded.
    private static let playPauseKey: Int32 = 16

    /// Post the system Play/Pause key (a toggle). Used for both pause and resume.
    static func togglePlayPause() {
        func key(_ down: Bool) {
            let data1 = (Int(playPauseKey) << 16) | ((down ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1)   // subtype 8 = NX_SUBTYPE_AUX_CONTROL_BUTTONS
            event?.cgEvent?.post(tap: .cgSessionEventTap)
        }
        key(true)
        key(false)
        DiagLog.log("media: sent play/pause key")
    }

    /// Whether the default output device is running I/O — a proxy for "audio is
    /// playing." Public CoreAudio. Not exact (an app can hold the stream open
    /// briefly while paused), so it only *gates* the toggle, cutting the footgun for
    /// idle and long-paused media. Our mic capture is *input*, so it never registers
    /// as output here.
    static func isOutputActive() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return (status == noErr && device != 0) ? device : nil
    }
}
