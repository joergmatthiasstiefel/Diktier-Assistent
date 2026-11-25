import AppKit
import SwiftUI

/// Kurzanleitung. Erscheint beim ersten Start von selbst und danach über
/// „Kurzanleitung…“ im Menü der Menüleiste.
struct AnleitungView: View {
    private struct Modus: Identifiable {
        let taste: String
        let name: String
        let wirkung: String
        var id: String { taste }
    }

    private let modi: [Modus] = [
        Modus(taste: "Control + 1", name: "Ohne Glättung", wirkung: "Text genau so, wie er erkannt wurde. Ohne KI, ohne Schlüssel."),
        Modus(taste: "Control + 2", name: "Glättung", wirkung: "Füllwörter und Versprecher raus, Grammatik und Satzzeichen richtig."),
        Modus(taste: "Control + 3", name: "Freundlich", wirkung: "Wie Glättung, dazu ein freundlicher Ton."),
        Modus(taste: "Control + 4", name: "Freundlich + Emoji", wirkung: "Wie Freundlich, dazu ein paar Emojis."),
        Modus(taste: "Control + 5", name: "Förmlich/Business", wirkung: "Knapp und geschäftlich, immer in der Sie-Form."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("So bedienst du den Diktier-Assistenten")
                    .font(.title2.bold())

                abschnitt("Diktieren in drei Schritten") {
                    schritt(1, "Klick in das Feld, in das der Text soll, etwa in eine Mail.")
                    schritt(2, "Drück Control und eine Zahl von 1 bis 5 und sprich. Oben am Bildschirm siehst du, welcher Modus läuft und was erkannt wird.")
                    schritt(3, "Drück Esc, wenn du fertig bist. Nach ein bis zwei Sekunden steht der Text an der Stelle, an der der Cursor war.")
                }

                abschnitt("Die fünf Modi") {
                    ForEach(modi) { modus in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(modus.taste)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 100, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(modus.name).bold()
                                Text(modus.wirkung)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                abschnitt("Gut zu wissen") {
                    punkt("Du darfst dich beim Sprechen verbessern. Aus „am Mittwoch, nein, Donnerstag“ wird in den Modi 2 bis 5 „am Donnerstag“.")
                    punkt("Mitten im Satz passt sich der Text an: Er beginnt klein und bekommt keinen Schlusspunkt.")
                    punkt("Was du vorher kopiert hattest, ist nach dem Diktat wieder in der Zwischenablage.")
                    punkt("Klappt die KI nicht (kein Internet, kein Guthaben), liegt dein wortgenauer Text in der Zwischenablage. Einfügen mit Befehl + V.")
                    punkt("Im Menü hinter dem Mikrofon-Symbol oben rechts findest du den letzten Text, den wortgenauen Text und den Verlauf der letzten 20 Diktate.")
                    punkt("Namen, die oft falsch geschrieben werden, trägst du unter Einstellungen → Wörterbuch ein.")
                    punkt("Das Mikrofon-Symbol zeigt den Stand: farbig während der Aufnahme, Sanduhr während der Verarbeitung, ein Warnzeichen bei einem Problem. Zeig mit der Maus darauf, dann steht dort, was los ist.")
                    punkt("Die Modi 2 bis 5 brauchen Internet und einen Anthropic-Schlüssel (Einstellungen). Modus 1 kommt ohne Schlüssel aus.")
                }

                Text("Diese Anleitung findest du jederzeit im Menü hinter dem Mikrofon-Symbol unter „Kurzanleitung…“.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 620)
    }

    @ViewBuilder
    private func abschnitt<Inhalt: View>(_ titel: String, @ViewBuilder inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titel).font(.headline)
            inhalt()
        }
    }

    private func schritt(_ nummer: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(nummer).").bold().frame(width: 18, alignment: .trailing)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func punkt(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").frame(width: 18, alignment: .trailing)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

final class AnleitungWindowController: NSWindowController {
    private static let shownKey = "anleitungGezeigt"

    /// Beim allerersten Start zeigen, danach nur noch auf Wunsch.
    static var wasShown: Bool {
        get { UserDefaults.standard.bool(forKey: shownKey) }
        set { UserDefaults.standard.set(newValue, forKey: shownKey) }
    }

    convenience init() {
        let hosting = NSHostingController(rootView: AnleitungView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Kurzanleitung"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        Self.wasShown = true
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
