import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let transcriber = SpeechTranscriber()
    private let claudeClient = ClaudeClient()
    private let textInserter = TextInserter()
    private let permissionsState = PermissionsState()
    private let recordingIndicator = RecordingIndicatorWindow()
    private var settingsWindowController: SettingsWindowController?
    private var anleitungWindowController: AnleitungWindowController?

    private enum State {
        case idle, recording, processing
    }

    private var state: State = .idle {
        didSet { updateIcon() }
    }

    /// Modus der gerade laufenden bzw. zuletzt gestarteten Aufnahme.
    private var activeMode: RecordingMode = .smooth

    /// Text links und rechts vom Cursor im Zielfeld, gelesen beim Start der
    /// Aufnahme. nil, wenn die App das Feld nicht lesen kann; dann wird der
    /// Text eingefügt wie bisher.
    private var activeField: FocusedField?
    /// Zählt die Aufnahmen hoch, damit ein spät eintreffendes Leseergebnis
    /// einer älteren Aufnahme nicht die neue überschreibt.
    private var recordingNumber = 0

    /// Fehler, die jeden weiteren Claude-Aufruf ebenfalls scheitern lassen.
    /// Anders als die übrigen Fehler (die nur 3 Sekunden aufblinken) bleiben
    /// sie in der Menüleiste stehen, bis ein Claude-Aufruf wieder gelingt
    /// (beim Schlüssel auch: bis ein neuer gespeichert wird). Sonst
    /// diktiert man weiter, ohne zu merken, dass Modus 2-5 nichts liefern.
    private enum PersistentProblem {
        case creditExhausted, invalidAPIKey
    }

    private var persistentProblem: PersistentProblem? {
        didSet { updateIcon() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(forName: KeychainStore.apiKeyDidChange, object: nil, queue: .main) { [weak self] _ in
            if self?.persistentProblem == .invalidAPIKey { self?.persistentProblem = nil }
        }
        setupEditMenu()
        setupStatusItem()
        setupHotkey()
        setupLiveTranscript()
        requestInitialPermissions()
        if !AnleitungWindowController.wasShown { openAnleitung() }
    }

    // MARK: - Setup

    /// Menüleisten-Apps haben kein Hauptmenü. Ohne ein Bearbeiten-Menü
    /// erreichen Befehlstaste+V/C/X/A die Textfelder nicht, man kann dann
    /// etwa keinen API-Key aus der Zwischenablage einfügen. Das Menü bleibt
    /// unsichtbar (.accessory), seine Tastenkürzel wirken trotzdem.
    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Bearbeiten")
        editMenu.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
    }

    /// Das Menü wird bei jedem Öffnen neu gebaut, damit der Verlauf aktuell ist.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let headerItem = NSMenuItem(title: "Diktier-Assistent", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let entries = Verlauf.eintraege
        if let last = entries.first {
            let copyLast = NSMenuItem(title: "Letzten Text kopieren", action: #selector(copyFromMenu(_:)), keyEquivalent: "")
            copyLast.target = self
            copyLast.representedObject = last.ergebnis
            copyLast.toolTip = last.ergebnis
            menu.addItem(copyLast)

            if last.wortgenau != last.ergebnis {
                let copyRaw = NSMenuItem(title: "Wortgenau kopieren (statt \(last.modus))", action: #selector(copyFromMenu(_:)), keyEquivalent: "")
                copyRaw.target = self
                copyRaw.representedObject = last.wortgenau
                copyRaw.toolTip = last.wortgenau
                menu.addItem(copyRaw)
            }

            let historyItem = NSMenuItem(title: "Verlauf", action: nil, keyEquivalent: "")
            let historyMenu = NSMenu(title: "Verlauf")
            let timeFormat = DateFormatter()
            timeFormat.dateFormat = "dd.MM. HH:mm"
            for entry in entries {
                let oneLine = entry.ergebnis.replacingOccurrences(of: "\n", with: " ")
                let preview = oneLine.count > 50 ? String(oneLine.prefix(50)) + "…" : oneLine
                let item = NSMenuItem(
                    title: "\(timeFormat.string(from: entry.zeit)) · \(entry.modus): \(preview)",
                    action: #selector(copyFromMenu(_:)), keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.ergebnis
                item.toolTip = entry.ergebnis
                historyMenu.addItem(item)
            }
            historyMenu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Verlauf löschen", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            historyMenu.addItem(clearItem)
            historyItem.submenu = historyMenu
            menu.addItem(historyItem)
            menu.addItem(.separator())
        }

        let anleitungItem = NSMenuItem(title: "Kurzanleitung…", action: #selector(openAnleitung), keyEquivalent: "")
        anleitungItem.target = self
        menu.addItem(anleitungItem)

        let settingsItem = NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func setupHotkey() {
        hotkeyManager.onStart = { [weak self] mode in
            DebugLog.write("HotkeyManager.onStart, mode=\(mode)")
            self?.beginRecording(modeValue: mode)
        }
        hotkeyManager.onStop = { [weak self] in
            DebugLog.write("HotkeyManager.onStop")
            self?.endRecording()
        }
        hotkeyManager.start()
    }

    private func setupLiveTranscript() {
        transcriber.onPartialTranscript = { [weak self] text in
            self?.recordingIndicator.update(transcript: text)
        }
    }

    private func requestInitialPermissions() {
        let manager = PermissionsManager.shared
        permissionsState.refresh()

        if manager.microphoneStatus() == .notDetermined {
            manager.requestMicrophoneAccess { [weak self] _ in self?.permissionsState.refresh() }
        }
        if manager.speechRecognitionStatus() == .notDetermined {
            manager.requestSpeechRecognitionAccess { [weak self] _ in self?.permissionsState.refresh() }
        }
        if !manager.isAccessibilityTrusted(prompt: false) {
            _ = manager.isAccessibilityTrusted(prompt: true)
        }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }

    // MARK: - Recording flow

    private func beginRecording(modeValue: Int) {
        guard state == .idle, let mode = RecordingMode(rawValue: modeValue) else { return }

        let manager = PermissionsManager.shared
        guard manager.microphoneStatus() == .authorized, manager.speechRecognitionStatus() == .authorized else {
            flash(symbol: "exclamationmark.triangle", tooltip: "Mikrofon- oder Spracherkennungs-Zugriff fehlt. Siehe Einstellungen.")
            openSettings()
            return
        }

        activeMode = mode
        readActiveField()
        state = .recording
        recordingIndicator.show(mode: mode, liveTranscript: AppSettings.showsLiveTranscript)
        do {
            try transcriber.startRecording()
        } catch {
            state = .idle
            recordingIndicator.hide()
            flash(symbol: "exclamationmark.triangle", tooltip: "Aufnahme konnte nicht gestartet werden: \(error)")
        }
    }

    private func endRecording() {
        guard state == .recording else { return }
        DebugLog.write("endRecording() – Modus '\(activeMode.label)', rufe transcriber.stopRecording auf.")
        state = .processing
        recordingIndicator.hide()
        transcriber.stopRecording { [weak self] result in
            guard let self else { return }
            DebugLog.write("stopRecording-Completion erreicht, result=\(result)")
            switch result {
            case .success(let transcript):
                self.cleanUpAndInsert(transcript, mode: self.activeMode)
            case .failure(let error):
                self.state = .idle
                self.handle(transcriberError: error)
            }
        }
    }

    private func readActiveField() {
        recordingNumber += 1
        let number = recordingNumber
        activeField = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let field = FocusedFieldReader.frontmostField()
            DispatchQueue.main.async {
                guard let self, self.recordingNumber == number else { return }
                self.activeField = field
            }
        }
    }

    private func cleanUpAndInsert(_ transcript: String, mode: RecordingMode) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Feste Ersetzungen gelten in jedem Modus, auch ohne Glättung.
        let wordForWord = Woerterbuch.applyReplacements(to: trimmed)

        guard let systemPrompt = mode.systemPrompt(protectedTerms: Woerterbuch.protectedTerms) else {
            state = .idle
            guard !wordForWord.isEmpty else {
                flash(symbol: "waveform.slash", tooltip: "Keine verständliche Sprache erkannt.")
                return
            }
            Verlauf.hinzufuegen(modus: mode.label, wortgenau: wordForWord, ergebnis: wordForWord)
            deliver(wordForWord)
            return
        }

        guard let apiKey = KeychainStore.shared.loadAPIKey(), !apiKey.isEmpty else {
            DebugLog.write("Kein API-Key im Schlüsselbund hinterlegt (Modus '\(mode.label)').")
            state = .idle
            keepWordForWord(wordForWord, reason: "Kein API-Key hinterlegt.", symbol: "key.slash")
            openSettings()
            return
        }

        claudeClient.cleanUp(transcript: wordForWord, apiKey: apiKey, systemPrompt: systemPrompt, model: mode.claudeModel) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.state = .idle
                switch result {
                case .success(let cleanedText):
                    self.persistentProblem = nil
                    switch RewriteGuard.checked(cleanedText, source: wordForWord) {
                    case .success(let text):
                        Verlauf.hinzufuegen(modus: mode.label, wortgenau: wordForWord, ergebnis: text)
                        self.deliver(text)
                    case .failure(let problem):
                        DebugLog.write("Prüfung in Modus '\(mode.label)' verworfen: \(problem.message)")
                        self.keepWordForWord(wordForWord, reason: problem.message, symbol: "exclamationmark.bubble")
                    }
                case .failure(.emptyTranscript):
                    DebugLog.write("Leeres Transkript beim Claude-Aufruf in Modus '\(mode.label)'.")
                    self.flash(symbol: "waveform.slash", tooltip: "Keine verständliche Sprache erkannt.")
                case .failure(let error):
                    DebugLog.write("Claude-Fehler in Modus '\(mode.label)': \(error.localizedDescription)")
                    if error.localizedDescription.lowercased().contains("credit balance") {
                        self.persistentProblem = .creditExhausted
                        self.keepWordForWord(wordForWord, reason: nil, symbol: nil)
                    } else if case .badResponse(let code, _) = error, code == 401 {
                        // 401 = Schlüssel gelöscht, gesperrt oder falsch abgetippt.
                        self.persistentProblem = .invalidAPIKey
                        self.keepWordForWord(wordForWord, reason: nil, symbol: nil)
                    } else {
                        self.keepWordForWord(wordForWord, reason: error.localizedDescription, symbol: "wifi.exclamationmark")
                    }
                }
            }
        }
    }

    /// Wenn der Claude-Schritt scheitert, geht das Diktat nicht verloren: Der
    /// wortgenaue Text kommt in die Zwischenablage und in den Verlauf.
    /// Eingefügt wird er bewusst nicht, man hatte ja einen anderen Modus
    /// gewählt. Ohne `reason` zeigt die Menüleiste schon einen dauerhaften Hinweis.
    private func keepWordForWord(_ text: String, reason: String?, symbol: String?) {
        guard !text.isEmpty else { return }
        textInserter.copy(text)
        Verlauf.hinzufuegen(modus: "Wortgenau", wortgenau: text, ergebnis: text)
        if let reason, let symbol {
            flash(symbol: symbol, tooltip: reason + " Der wortgenaue Text liegt in der Zwischenablage.")
        }
    }

    private func deliver(_ dictated: String) {
        // Leerzeichen, Groß- und Kleinschreibung und Schlusspunkt passend zum
        // Text am Cursor, nur an den Rändern des Diktats.
        let text = activeField.map { InsertionFitter.fit(dictated, before: $0.textBefore, after: $0.textAfter) } ?? dictated
        if PermissionsManager.shared.isAccessibilityTrusted(prompt: false) {
            textInserter.insert(text)
        } else {
            textInserter.copy(text)
            flash(symbol: "exclamationmark.triangle", tooltip: "Bedienungshilfen-Zugriff fehlt: Text wurde nur in die Zwischenablage kopiert.")
        }
    }

    private func handle(transcriberError: SpeechTranscriber.TranscriberError) {
        DebugLog.write("Transkriptionsfehler in Modus '\(activeMode.label)': \(transcriberError)")
        switch transcriberError {
        case .emptyResult:
            flash(symbol: "waveform.slash", tooltip: "Keine verständliche Sprache erkannt.")
        case .recognizerUnavailable:
            flash(symbol: "exclamationmark.triangle", tooltip: "Spracherkennung derzeit nicht verfügbar (Sprachpaket Deutsch installiert?).")
        case .audioEngineFailure(let error):
            flash(symbol: "exclamationmark.triangle", tooltip: "Audiofehler: \(error.localizedDescription)")
        case .recognitionFailure(let error):
            flash(symbol: "exclamationmark.triangle", tooltip: "Erkennung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        // Mit Text braucht das Symbol Platz, sonst wird der Hinweis abgeschnitten.
        statusItem.length = (state == .idle && persistentProblem != nil)
            ? NSStatusItem.variableLength : NSStatusItem.squareLength
        switch state {
        case .idle where persistentProblem == .creditExhausted:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Guthaben aufgebraucht")
            button.title = " Guthaben aufgebraucht"
            button.contentTintColor = .systemRed
            button.toolTip = "Anthropic-Guthaben aufgebraucht. Bitte in der Anthropic Console aufladen. Modus 1 (ohne Glättung) funktioniert weiterhin ohne Claude-Aufruf. Bei den anderen Modi liegt der wortgenaue Text jeweils in der Zwischenablage."
        case .idle where persistentProblem == .invalidAPIKey:
            button.image = NSImage(systemSymbolName: "key.slash", accessibilityDescription: "API-Key ungültig")
            button.title = " API-Key ungültig"
            button.contentTintColor = .systemRed
            button.toolTip = "Anthropic lehnt den hinterlegten API-Key ab (gelöscht oder gesperrt). Bitte unter console.anthropic.com einen neuen anlegen und in den Einstellungen speichern. Modus 1 (ohne Glättung) funktioniert weiterhin. Bei den anderen Modi liegt der wortgenaue Text jeweils in der Zwischenablage."
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Bereit")
            button.title = ""
            button.contentTintColor = nil
            button.toolTip = "Diktier-Assistent – Control+1…5 zum Diktieren"
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Aufnahme läuft")
            button.title = ""
            button.contentTintColor = activeMode.accentColor
            button.toolTip = "Aufnahme läuft (\(activeMode.label)) – Esc zum Beenden"
        case .processing:
            button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Verarbeite…")
            button.title = ""
            button.contentTintColor = .systemOrange
            button.toolTip = "Text wird verarbeitet…"
        }
    }

    private func flash(symbol: String, tooltip: String) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.title = ""
        button.contentTintColor = .systemYellow
        button.toolTip = tooltip

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.state == .idle else { return }
            self.updateIcon()
        }
    }

    // MARK: - Menu actions

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(permissionsState: permissionsState)
        }
        settingsWindowController?.show()
    }

    @objc private func openAnleitung() {
        if anleitungWindowController == nil {
            anleitungWindowController = AnleitungWindowController()
        }
        anleitungWindowController?.show()
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        textInserter.copy(text)
    }

    @objc private func clearHistory() {
        Verlauf.loeschen()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
