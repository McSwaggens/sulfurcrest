import Foundation

/// Opt-in append-only file logger for diagnostics. Disabled unless the app is
/// launched with `--debug` or `SULFURCREST_DEBUG=1`, in which case it writes to
/// ~/Library/Logs/Sulfurcrest.log. Messages use `@autoclosure` so nothing is
/// built when logging is off.
enum DiagLog {
    static let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Sulfurcrest.log")

    static let isEnabled: Bool =
        CommandLine.arguments.contains("--debug")
        || ProcessInfo.processInfo.environment["SULFURCREST_DEBUG"] == "1"

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message())\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: data)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
