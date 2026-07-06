import AppKit

/// Schreibt Text in die Zwischenablage und simuliert Cmd+V, um ihn in die
/// zuvor fokussierte Anwendung einzufügen. Benötigt Bedienungshilfen-Zugriff.
final class TextInserter {
    private let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

    func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
