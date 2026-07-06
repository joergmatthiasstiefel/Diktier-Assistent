import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let transcriber = SpeechTranscriber()
    private let claudeClient = ClaudeClient()
    private let textInserter = TextInserter()
    private let permissionsState = PermissionsState()
    private var settingsWindowController: SettingsWindowController?

    private enum State {
        case idle, recording, processing
    }

    private var state: State = .idle {
        didSet { updateIcon() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotkey()
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
        hotkeyManager.onStart = { [weak self] in self?.beginRecording() }
        hotkeyManager.onStop = { [weak self] in self?.endRecording() }
        hotkeyManager.start()
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

    private func beginRecording() {
        guard state == .idle else { return }

        let manager = PermissionsManager.shared
        guard manager.microphoneStatus() == .authorized, manager.speechRecognitionStatus() == .authorized else {
            flash(symbol: "exclamationmark.triangle", tooltip: "Mikrofon- oder Spracherkennungs-Zugriff fehlt. Siehe Einstellungen.")
            openSettings()
            return
        }

        state = .recording
        do {
            try transcriber.startRecording()
        } catch {
            state = .idle
            flash(symbol: "exclamationmark.triangle", tooltip: "Aufnahme konnte nicht gestartet werden: \(error)")
        }
    }

    private func endRecording() {
        guard state == .recording else { return }
        state = .processing
        transcriber.stopRecording { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let transcript):
                self.cleanUpAndInsert(transcript)
            case .failure(let error):
                self.state = .idle
                self.handle(transcriberError: error)
            }
        }
    }

    private func cleanUpAndInsert(_ transcript: String) {
        guard let apiKey = KeychainStore.shared.loadAPIKey(), !apiKey.isEmpty else {
            state = .idle
            flash(symbol: "key.slash", tooltip: "Kein API-Key hinterlegt. Bitte in den Einstellungen eintragen.")
            openSettings()
            return
        }

        claudeClient.cleanUp(transcript: transcript, apiKey: apiKey) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.state = .idle
                switch result {
                case .success(let cleanedText):
                    self.deliver(cleanedText)
                case .failure(.emptyTranscript):
                    self.flash(symbol: "waveform.slash", tooltip: "Keine verständliche Sprache erkannt.")
                case .failure(let error):
                    self.flash(symbol: "wifi.exclamationmark", tooltip: error.localizedDescription)
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
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Bereit")
            button.contentTintColor = nil
            button.toolTip = "Diktier-Assistent – fn + t halten zum Diktieren"
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Aufnahme läuft")
            button.contentTintColor = .systemRed
            button.toolTip = "Aufnahme läuft…"
        case .processing:
            button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Verarbeite…")
            button.contentTintColor = .systemOrange
            button.toolTip = "Text wird verarbeitet…"
        }
    }

    private func flash(symbol: String, tooltip: String) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
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
