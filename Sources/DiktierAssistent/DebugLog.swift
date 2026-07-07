import Foundation

/// Schreibt Diagnosezeilen zusätzlich in eine feste Datei im Home-Verzeichnis.
/// Existiert, weil NSLog-Ausgaben dieser App beim Start über das App-Bundle
/// (im Gegensatz zum direkten Terminal-Start) nicht zuverlässig über
/// `log show`/`log stream` einsehbar waren - eine eigene Datei ist
/// unabhängig davon direkt auslesbar.
enum DebugLog {
    private static let url = URL(fileURLWithPath: NSHomeDirectory() + "/diktier-debug.log")

    static func write(_ message: String) {
        NSLog("Diktier-Assistent: \(message)")
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }
}
