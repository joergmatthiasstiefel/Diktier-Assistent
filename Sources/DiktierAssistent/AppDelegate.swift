import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let transcriber = SpeechTranscriber()
    private let claudeClient = ClaudeClient()
    private let textInserter = TextInserter()
    private let permissionsState = PermissionsState()
    private let recordingIndicator = RecordingIndicatorWindow()
    private var settingsWindowController: SettingsWindowController?

    private enum State {
        case idle, recording, processing
    }

    private var state: State = .idle {
        didSet { updateIcon() }
    }

    /// Modus der gerade laufenden bzw. zuletzt gestarteten Aufnahme.
    private var activeMode: RecordingMode = .smooth

    /// Bleibt true, bis ein Claude-Aufruf wieder erfolgreich ist. Anders als
    /// die übrigen Fehler (die nur 3 Sekunden aufblinken) ist das hier
    /// dauerhaft sichtbar, weil man sonst leicht weiterdiktiert, ohne zu
    /// merken, dass Modus 2-4 gar nicht mehr ankommen.
    private var creditExhausted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotkey()
        setupLiveTranscript()
        requestInitialPermissions()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        let menu = NSMenu()
        let headerItem = NSMenuItem(title: "Diktier-Assistent", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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

    private func cleanUpAndInsert(_ transcript: String, mode: RecordingMode) {
        guard let systemPrompt = mode.claudeSystemPrompt else {
            state = .idle
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                flash(symbol: "waveform.slash", tooltip: "Keine verständliche Sprache erkannt.")
                return
            }
            deliver(trimmed)
            return
        }

        guard let apiKey = KeychainStore.shared.loadAPIKey(), !apiKey.isEmpty else {
            DebugLog.write("Kein API-Key im Schlüsselbund hinterlegt (Modus '\(mode.label)').")
            state = .idle
            flash(symbol: "key.slash", tooltip: "Kein API-Key hinterlegt. Bitte in den Einstellungen eintragen.")
            openSettings()
            return
        }

        claudeClient.cleanUp(transcript: transcript, apiKey: apiKey, systemPrompt: systemPrompt, model: mode.claudeModel) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.state = .idle
                switch result {
                case .success(let cleanedText):
                    self.creditExhausted = false
                    self.deliver(cleanedText)
                case .failure(.emptyTranscript):
                    DebugLog.write("Leeres Transkript beim Claude-Aufruf in Modus '\(mode.label)'.")
                    self.flash(symbol: "waveform.slash", tooltip: "Keine verständliche Sprache erkannt.")
                case .failure(let error):
                    DebugLog.write("Claude-Fehler in Modus '\(mode.label)': \(error.localizedDescription)")
                    if error.localizedDescription.lowercased().contains("credit balance") {
                        self.creditExhausted = true
                        self.updateIcon()
                    } else {
                        self.flash(symbol: "wifi.exclamationmark", tooltip: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func deliver(_ text: String) {
        if PermissionsManager.shared.isAccessibilityTrusted(prompt: false) {
            textInserter.insert(text)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
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
        switch state {
        case .idle where creditExhausted:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Guthaben aufgebraucht")
            button.title = " Guthaben aufgebraucht"
            button.contentTintColor = .systemRed
            button.toolTip = "Anthropic-Guthaben aufgebraucht. Bitte in der Anthropic Console aufladen. Modus 1 (ohne Glättung) funktioniert weiterhin ohne Claude-Aufruf."
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
