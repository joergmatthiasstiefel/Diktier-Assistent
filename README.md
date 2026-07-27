# Diktier-Assistent

Menüleisten-App für macOS: Hotkey drücken, Deutsch sprechen, mit Esc beenden
– der Text wird je nach gewähltem Modus unverändert oder per Claude API
umformuliert und automatisch in die zuvor aktive App eingefügt.

## Installation

Diese Schritte funktionieren auf jedem Mac, nicht nur dem, auf dem die App
entstanden ist. Die Anleitung lässt sich auch direkt einer KI wie Claude Code
geben, die einen dann Schritt für Schritt durchführt.

1. **Voraussetzung prüfen**: macOS 13 (Ventura) oder neuer, sowie die Xcode
   Command Line Tools. Falls letztere noch fehlen:
   ```bash
   xcode-select --install
   ```
   Das öffnet einen eigenen Apple-Installationsdialog (einmalig, je nach
   Internetverbindung 5–15 Minuten, muss manuell bestätigt werden).

2. **Repo herunterladen**:
   ```bash
   git clone https://github.com/joergmatthiasstiefel/Diktier-Assistent.git
   cd Diktier-Assistent
   ```

3. **Bauen und signieren**:
   ```bash
   ./build.sh
   ```
   Legt beim allerersten Mal automatisch ein eigenes, lokales
   Signatur-Zertifikat an – dafür fragt macOS einmalig per Passwort oder
   Touch ID nach. Das ist normal und sorgt dafür, dass App-Berechtigungen
   auch nach künftigen Neubauten erhalten bleiben, statt nach jedem Build neu
   erteilt werden zu müssen.

4. **In den Programme-Ordner verschieben und starten** (nötig für
   dauerhaften Hintergrundbetrieb und den "Bei Anmeldung starten"-Schalter):
   ```bash
   cp -R "Diktier-Assistent.app" /Applications/
   open "/Applications/Diktier-Assistent.app"
   ```

5. **Anthropic-API-Key besorgen und eintragen**: Auf
   [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
   einloggen (ggf. Account anlegen) → "Create Key" → Key kopieren. Dann in
   der App: Menüleisten-Icon → Einstellungen… → Key einfügen → Speichern.
   Der Key landet in der macOS-Keychain, nie in einer Datei.

6. **Berechtigungen erteilen**: macOS fragt beim ersten Start nach Mikrofon
   und Spracherkennung. Für Bedienungshilfen (zum Einfügen) und
   Eingabeüberwachung (für den globalen Hotkey) öffnet die App die
   passenden Systemeinstellungen-Seiten automatisch; Status ist in den
   Einstellungen der App sichtbar (grüner/roter Punkt).

7. **Deutsches Sprachpaket aktivieren**: Damit die Spracherkennung
   funktioniert, muss unter Systemeinstellungen → Tastatur → Diktat
   "Deutsch" aktiviert bzw. heruntergeladen sein.

## Hotkeys & Modi

Control+1 bis Control+5 starten die Aufnahme im jeweiligen Modus (Toggle,
kein Halten nötig), Esc beendet sie:

| Hotkey     | Modus                | Verhalten |
|------------|-----------------------|-----------|
| Control+1  | Ohne Glättung          | Transkript wird unverändert eingefügt, kein Claude-Aufruf |
| Control+2  | Glättung               | Füllwörter/Versprecher entfernt, Grammatik korrigiert |
| Control+3  | Freundlich             | wie Glättung, zusätzlich sehr freundlicher Ton, Schimpfwörter werden ausnahmslos ersetzt |
| Control+4  | Freundlich + Emoji     | wie Modus 3, zusätzlich sparsam platzierte Emojis |
| Control+5  | Förmlich/Business      | knapper, sehr professioneller Ton, konsequente Sie-Form, Fachbegriffe wo hilfreich, bewusst nicht "KI-glatt" formuliert |

Während der Aufnahme zeigen Menüleisten-Icon (farbcodiert je Modus) und ein
schwebendes Overlay am oberen Bildschirmrand an, dass aufgenommen wird und
dass Esc sie beendet. Wird während einer laufenden Aufnahme eine andere
Modus-Kombination gedrückt, wird sie geschluckt, aber ignoriert – ein
Moduswechsel ist erst nach Esc möglich.

## Funktionsweise (kurz)

- `HotkeyManager` erkennt Control+1…4 (Start) und Esc (Stopp) systemweit
  über einen `CGEventTap` (daher die Berechtigung "Eingabeüberwachung").
  Esc wird nur geschluckt, solange eine Aufnahme läuft, damit das normale
  Esc-Verhalten in anderen Apps sonst unangetastet bleibt.
- `SpeechTranscriber` nimmt per `AVAudioEngine` auf und transkribiert über
  `SFSpeechRecognizer` (`de-DE`). Bevorzugt On-Device, erlaubt macOS aber
  bei Bedarf den Ausweich auf die robustere serverbasierte Erkennung –
  rein On-Device lieferte bei schneller/undeutlicher Sprache öfters ein
  leeres Transkript.
- `ClaudeClient` schickt das Rohtranskript an die Anthropic Messages API,
  mit einem modusabhängigen System-Prompt und Modell (`RecordingMode.swift`):
  Glättung läuft auf `claude-haiku-4-5-20251001`, die kreativeren
  Freundlich-Modi auf `claude-sonnet-5`, um Grammatikfehler bei der
  stärkeren Umformulierung zu vermeiden.
- `TextInserter` schreibt das Ergebnis in die Zwischenablage und simuliert
  `Cmd+V` über `CGEvent` (Bedienungshilfen-Zugriff nötig). Ohne diesen
  Zugriff bleibt der Text nur in der Zwischenablage, die App weist per
  Icon-Hinweis darauf hin.
- Fehlerfälle (keine Internetverbindung, fehlende Berechtigung, leere/
  unverständliche Aufnahme, fehlender API-Key) blinken kurz als gelbes
  Warn-Icon mit Tooltip auf, statt still zu scheitern, und werden
  zusätzlich in `~/diktier-debug.log` protokolliert (`DebugLog.swift`) –
  NSLog-Ausgaben dieser App waren über `log show`/`log stream` beim
  Start über das App-Bundle nicht zuverlässig einsehbar.

## Nicht enthalten

Keine Code-Signierung mit Apple Developer-ID und keine Notarisierung – ein
fertig gebautes `.app`-Bundle lässt sich deshalb nicht einfach als Download
verteilen (macOS würde es beim ersten Start blockieren). Wer die App selbst
aus dem Quellcode baut (siehe "Installation" oben), bekommt aber ein
funktionsfähiges, lokal signiertes Bundle auf jedem Mac – das Blockieren
betrifft nur Binärdateien, die aus dem Internet heruntergeladen wurden,
nicht lokal kompilierte.
