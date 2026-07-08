# Diktier-Assistent

Menüleisten-App für macOS: Hotkey drücken, Deutsch sprechen, mit Esc beenden
– der Text wird je nach gewähltem Modus unverändert oder per Claude API
umformuliert und automatisch in die zuvor aktive App eingefügt.

## Bauen & starten

```bash
./build.sh
open "Diktier-Assistent.app"
```

Für dauerhaften Hintergrundbetrieb und den "Bei Anmeldung starten"-Schalter
in den Einstellungen die App vorher nach `/Applications` kopieren:

```bash
cp -R "Diktier-Assistent.app" /Applications/
```

Danach `/Applications/Diktier-Assistent.app` starten.

## Erster Start

1. API-Key: Menüleisten-Icon → Einstellungen… → Anthropic API-Key eintragen
   → Speichern. Der Key landet in der Keychain, nicht in einer Datei.
2. Berechtigungen: macOS fragt beim ersten Start nach Mikrofon und
   Spracherkennung. Für Bedienungshilfen (zum Einfügen) und
   Eingabeüberwachung (für den globalen Hotkey) öffnet die App die
   passenden Systemeinstellungen-Seiten automatisch; Status ist in den
   Einstellungen der App sichtbar (grüner/roter Punkt).
3. Deutsches Sprachpaket: Damit die Spracherkennung funktioniert, muss
   unter Systemeinstellungen → Tastatur → Diktat "Deutsch" aktiviert bzw.
   heruntergeladen sein.

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

Keine Code-Signierung mit Developer-ID/Notarisierung – die App wird
lokal ad-hoc signiert (`codesign --sign -`) und ist nur für den eigenen
Rechner gedacht.
