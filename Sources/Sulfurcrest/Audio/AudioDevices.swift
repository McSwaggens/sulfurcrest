import AVFoundation

/// A selectable microphone input device (backed by `AVCaptureDevice`).
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// `AVCaptureDevice.uniqueID` — stable across reconnects; this is persisted
    /// and used to re-select the device for capture.
    let id: String
    let name: String
    var uid: String { id }
}

/// Enumerates audio input devices via `AVCaptureDevice` so the Settings picker
/// and `MicCapture` (both `AVCaptureSession`-based) speak the same identifiers.
enum AudioDevices {
    static func inputs() -> [AudioInputDevice] {
        discovery().devices.map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    private static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified)
    }
}
