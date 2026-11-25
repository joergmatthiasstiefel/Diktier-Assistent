import SwiftUI

struct SettingsView: View {
    @ObservedObject var permissionsState: PermissionsState
    @State private var apiKey: String = KeychainStore.shared.loadAPIKey() ?? ""
    @State private var savedMessage: String?
    @State private var startAtLogin: Bool = LoginItemManager.shared.isEnabled
    @State private var liveTranscript: Bool = AppSettings.showsLiveTranscript
    @State private var termsText: String = Woerterbuch.termsText
    @State private var replacementsText: String = Woerterbuch.replacementsText
    @State private var dictionaryMessage: String?

    var body: some View {
        TabView {
            general
                .tabItem { Text("Allgemein") }
            dictionary
                .tabItem { Text("Wörterbuch") }
        }
        .padding(12)
        .frame(width: 440)
        .onAppear { permissionsState.refresh() }
    }

    private var dictionary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Begriffe")
                .font(.subheadline)
            Text("Namen und Fachbegriffe, die genau so geschrieben werden sollen, je einer pro Zeile. Die Modi 2 bis 5 übernehmen diese Schreibweise.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $termsText)
                .font(.body)
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))

            Text("Feste Ersetzungen")
                .font(.subheadline)
                .padding(.top, 6)
            Text("Für Wörter, die die Spracherkennung immer falsch schreibt. Je eine Regel pro Zeile, links das Gesprochene, rechts die Schreibweise, dazwischen ein Gleichheitszeichen, etwa „n acht n = n8n“. Gilt in allen Modi, auch ohne Glättung.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $replacementsText)
                .font(.body)
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))

            HStack {
                Button("Speichern") {
                    Woerterbuch.termsText = termsText
                    Woerterbuch.replacementsText = replacementsText
                    let terms = Woerterbuch.terms.count
                    let rules = Woerterbuch.replacements.count
                    dictionaryMessage = "Gespeichert: \(terms) \(terms == 1 ? "Begriff" : "Begriffe"), \(rules) \(rules == 1 ? "Ersetzung" : "Ersetzungen")."
                }
                if let dictionaryMessage {
                    Text(dictionaryMessage)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diktier-Assistent – Einstellungen")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Anthropic API-Key")
                    .font(.subheadline)
                SecureField("sk-ant-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Speichern") {
                        KeychainStore.shared.save(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        savedMessage = "Gespeichert."
                    }
                    if let savedMessage {
                        Text(savedMessage)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Berechtigungen")
                    .font(.subheadline)
                permissionRow(title: "Mikrofon", granted: permissionsState.microphoneGranted, action: permissionsState.requestMicrophone)
                permissionRow(title: "Spracherkennung", granted: permissionsState.speechGranted, action: permissionsState.requestSpeech)
                permissionRow(title: "Bedienungshilfen (Einfügen)", granted: permissionsState.accessibilityGranted, action: permissionsState.openAccessibilitySettings)
                permissionRow(title: "Eingabeüberwachung (Hotkey)", granted: permissionsState.inputMonitoringGranted, action: permissionsState.openInputMonitoringSettings)
                Button("Status aktualisieren") { permissionsState.refresh() }
                    .font(.caption)
            }

            Divider()

            Toggle("Bei Anmeldung automatisch starten", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { newValue in
                    LoginItemManager.shared.setEnabled(newValue)
                }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Gesprochenen Text live im Overlay mitlesen", isOn: $liveTranscript)
                    .onChange(of: liveTranscript) { newValue in
                        AppSettings.showsLiveTranscript = newValue
                    }
                Text("""
                Zeigt während der Aufnahme das Roh-Transkript vor der Glättung. \
                Der Text kann sich dabei rückwirkend ändern, weil die Erkennung \
                bereits gesprochene Wörter mit mehr Kontext korrigiert.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("""
            Hotkey: Control+1 (ohne Glättung), Control+2 (Glättung), \
            Control+3 (freundlich), Control+4 (freundlich + Emoji) oder \
            Control+5 (förmlich/Business) startet die Aufnahme, Esc beendet sie.
            """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Text("v1.2")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Circle()
                .fill(granted ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            if !granted {
                Button("Öffnen") { action() }
                    .font(.caption)
            }
        }
    }
}
