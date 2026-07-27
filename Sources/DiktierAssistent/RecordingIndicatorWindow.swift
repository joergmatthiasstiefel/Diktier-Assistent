import AppKit

/// Schwebendes, nicht-aktivierendes Hinweisfenster, das während einer
/// Aufnahme am oberen Bildschirmrand einblendet, welcher Modus läuft und
/// dass Esc die Aufnahme beendet. Existiert, weil das Menüleisten-Icon
/// allein (Tooltip nur bei Hover sichtbar) während des Sprechens nicht
/// zuverlässig wahrgenommen wird.
///
/// Bei aktiver Live-Vorschau zeigt es darunter zusätzlich das laufende
/// Roh-Transkript, damit man beim Sprechen mitlesen kann, ob die Erkennung
/// einen richtig verstanden hat. Das Fenster wächst dabei nach unten, die
/// Oberkante bleibt stehen; ältere Wörter laufen oben aus dem Text.
final class RecordingIndicatorWindow {
    private var panel: NSPanel?
    private var backgroundView: NSView?
    private var headerLabel: NSTextField?
    private var transcriptLabel: NSTextField?
    private var showsLiveTranscript = false

    /// Feste Breite der Live-Ansicht. Schmaler wird der Text unruhig, weil
    /// dann jede nachträgliche Korrektur des Erkenners den Zeilenumbruch
    /// des gesamten Absatzes verschiebt.
    private let liveWidth: CGFloat = 560
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 10
    private let headerSpacing: CGFloat = 8
    /// Höhenlimit für den Live-Text, entspricht etwa vier Zeilen.
    private let maxTranscriptHeight: CGFloat = 84
    private let transcriptFont = NSFont.systemFont(ofSize: 15, weight: .regular)


    func show(mode: RecordingMode, liveTranscript: Bool) {
        hide()
        showsLiveTranscript = liveTranscript

        let header = NSTextField(labelWithString: "●  \(mode.label) läuft – Esc zum Beenden")
        header.font = .systemFont(ofSize: 13, weight: .medium)
        header.textColor = liveTranscript ? NSColor.white.withAlphaComponent(0.85) : .white
        header.alignment = liveTranscript ? .center : .left

        let transcript = NSTextField(wrappingLabelWithString: "")
        transcript.font = transcriptFont
        transcript.textColor = .white
        transcript.isSelectable = false
        transcript.isHidden = true

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: liveWidth, height: 44),
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

        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = mode.accentColor.withAlphaComponent(0.92).cgColor
        background.layer?.cornerRadius = 10
        background.addSubview(header)
        background.addSubview(transcript)
        panel.contentView = background

        self.panel = panel
        self.backgroundView = background
        self.headerLabel = header
        self.transcriptLabel = transcript

        relayout()
        panel.orderFrontRegardless()
    }

    /// Aktualisiert die Live-Vorschau. Ohne aktive Vorschau oder nach dem
    /// Ausblenden ein No-op - Zwischenergebnisse treffen gelegentlich noch
    /// ein, nachdem die Aufnahme bereits beendet wurde.
    func update(transcript text: String) {
        guard showsLiveTranscript, let transcriptLabel, panel != nil else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        transcriptLabel.stringValue = tail(of: trimmed)
        transcriptLabel.isHidden = false
        relayout()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        backgroundView = nil
        headerLabel = nil
        transcriptLabel = nil
        showsLiveTranscript = false
    }

    // MARK: - Layout

    private func relayout() {
        guard let panel, let backgroundView, let headerLabel, let transcriptLabel else { return }

        headerLabel.sizeToFit()
        let headerNaturalSize = headerLabel.frame.size
        let contentWidth = showsLiveTranscript
            ? liveWidth - horizontalPadding * 2
            : ceil(headerNaturalSize.width)
        let headerHeight = ceil(headerNaturalSize.height)

        let transcriptHeight = transcriptLabel.isHidden
            ? 0
            : min(maxTranscriptHeight, height(of: transcriptLabel.stringValue, width: contentWidth))
        let spacing = transcriptLabel.isHidden ? 0 : headerSpacing

        let totalWidth = contentWidth + horizontalPadding * 2
        let totalHeight = verticalPadding * 2 + headerHeight + spacing + transcriptHeight

        backgroundView.frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        headerLabel.frame = NSRect(
            x: horizontalPadding,
            y: totalHeight - verticalPadding - headerHeight,
            width: contentWidth,
            height: headerHeight
        )
        transcriptLabel.preferredMaxLayoutWidth = contentWidth
        transcriptLabel.frame = NSRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: contentWidth,
            height: transcriptHeight
        )

        guard let screen = NSScreen.main else { return }
        let origin = NSPoint(
            x: screen.visibleFrame.midX - totalWidth / 2,
            y: screen.visibleFrame.maxY - totalHeight - 12
        )
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: totalWidth, height: totalHeight)), display: true)
    }

    /// Kürzt den Text von vorn, bis er ins Höhenlimit passt. Angezeigt wird
    /// also immer das Ende des Diktats, weil dort steht, was gerade
    /// gesprochen wird.
    private func tail(of text: String) -> String {
        let width = liveWidth - horizontalPadding * 2
        var candidate = Substring(text)
        var truncated = false

        // Lange Diktate erst grob kürzen, damit die wortweise Feinsuche
        // unten nicht bei jedem Zwischenergebnis den ganzen Text abläuft.
        if candidate.count > 400 {
            candidate = candidate.suffix(400)
            truncated = true
            if let space = candidate.firstIndex(of: " ") {
                candidate = candidate[candidate.index(after: space)...]
            }
        }

        while height(of: (truncated ? "… " : "") + candidate, width: width) > maxTranscriptHeight {
            guard let space = candidate.firstIndex(of: " ") else { break }
            candidate = candidate[candidate.index(after: space)...]
            truncated = true
        }

        return truncated ? "… " + candidate : String(candidate)
    }

    /// Misst mit genau dem Label, das den Text später auch zeichnet, und
    /// zwar über `sizeThatFits`. Dessen `intrinsicContentSize` meldet bei
    /// umbrechenden Textfeldern eine zu geringe Höhe (gemessen: 76 statt 90
    /// Punkte für fünf Zeilen), wodurch die letzte Zeile unsichtbar
    /// unterhalb des Fensterrands landete.
    private func height(of text: String, width: CGFloat) -> CGFloat {
        guard let transcriptLabel else { return 0 }
        transcriptLabel.stringValue = text
        let fitted = transcriptLabel.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude))
        return ceil(fitted.height)
    }
}
