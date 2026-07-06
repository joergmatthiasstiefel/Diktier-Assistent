# Diktier-Assistent

Menüleisten-App für macOS: `fn + t` gedrückt halten, Deutsch sprechen,
loslassen – der geglättete Text wird per Claude API ausformuliert und
automatisch in die zuvor aktive App eingefügt.

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
3. Deutsches Sprachpaket: Damit die On-Device-Erkennung funktioniert, muss
   unter Systemeinstellungen → Tastatur → Diktat "Deutsch" aktiviert bzw.
   heruntergeladen sein.

## Wichtiger Hinweis zur fn-Taste

Manche Mac-Tastaturen lösen bei alleinigem, kurzem Druck der fn-Taste eine
Systemfunktion aus (Emoji-Picker, Diktat oder Siri, je nach Einstellung).
Das stört die Kombination `fn + t` in der Praxis nicht, weil dabei eine
zweite Taste gedrückt wird – falls es doch zu Konflikten kommt, unter
Systemeinstellungen → Tastatur → "Drücken der 🌐-Taste, um zu:" auf
"Nichts tun" stellen.

## Funktionsweise (kurz)

- `HotkeyManager` verfolgt den fn-Zustand über `flagsChanged`-Events und
  kombiniert ihn mit keyDown/keyUp von "t" (Push-to-talk, systemweit über
  globale `NSEvent`-Monitore – daher die Berechtigung "Eingabeüberwachung").
- `SpeechTranscriber` nimmt per `AVAudioEngine` auf und transkribiert
  on-device über `SFSpeechRecognizer` (`de-DE`).
- `ClaudeClient` schickt das Rohtranskript an die Anthropic Messages API
  (Modell `claude-haiku-4-5-20251001`) mit der Anweisung, Füllwörter,
  Versprecher und Grammatikfehler zu glätten, ohne den Inhalt zu ändern.
- `TextInserter` schreibt das Ergebnis in die Zwischenablage und simuliert
  `Cmd+V` über `CGEvent` (Bedienungshilfen-Zugriff nötig). Ohne diesen
  Zugriff bleibt der Text nur in der Zwischenablage, die App weist per
  Icon-Hinweis darauf hin.
- Fehlerfälle (keine Internetverbindung, fehlende Berechtigung, leere/
  unverständliche Aufnahme) blinken kurz als gelbes Warn-Icon mit Tooltip
  auf, statt still zu scheitern.

## Nicht enthalten

Keine Code-Signierung mit Developer-ID/Notarisierung – die App wird
lokal ad-hoc signiert (`codesign --sign -`) und ist nur für den eigenen
Rechner gedacht.
