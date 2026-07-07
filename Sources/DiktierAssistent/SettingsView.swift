import SwiftUI

struct SettingsView: View {
    @ObservedObject var permissionsState: PermissionsState
    @State private var apiKey: String = KeychainStore.shared.loadAPIKey() ?? ""
    @State private var savedMessage: String?
    @State private var startAtLogin: Bool = LoginItemManager.shared.isEnabled

    var body: some View {
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

            Text("""
            Hotkey: Control+1 (ohne Glättung), Control+2 (Glättung), \
            Control+3 (freundlich) oder Control+4 (freundlich + Emoji) startet \
            die Aufnahme, Esc beendet sie.
            """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { permissionsState.refresh() }
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
