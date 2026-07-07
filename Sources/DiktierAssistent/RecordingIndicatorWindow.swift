import AppKit

/// Schwebendes, nicht-aktivierendes Hinweisfenster, das während einer
/// Aufnahme am oberen Bildschirmrand einblendet, welcher Modus läuft und
/// dass Esc die Aufnahme beendet. Existiert, weil das Menüleisten-Icon
/// allein (Tooltip nur bei Hover sichtbar) während des Sprechens nicht
/// zuverlässig wahrgenommen wird.
final class RecordingIndicatorWindow {
    private var panel: NSPanel?

    func show(mode: RecordingMode) {
        hide()

        let text = "●  \(mode.label) läuft – Esc zum Beenden"
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 10
        let size = NSSize(
            width: label.frame.width + horizontalPadding * 2,
            height: label.frame.height + verticalPadding * 2
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = mode.accentColor.withAlphaComponent(0.92).cgColor
        background.layer?.cornerRadius = 10

        label.frame.origin = NSPoint(x: horizontalPadding, y: verticalPadding)
        background.addSubview(label)
        panel.contentView = background

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.maxY - size.height - 12
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
