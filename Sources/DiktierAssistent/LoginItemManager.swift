import Foundation
import ServiceManagement

/// Registriert die App als Anmeldeobjekt, damit sie dauerhaft im Hintergrund
/// läuft. Funktioniert zuverlässig nur, wenn die App aus einem stabilen Pfad
/// (z. B. /Applications) gestartet wird.
final class LoginItemManager {
    static let shared = LoginItemManager()

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Diktier-Assistent: Login-Item Fehler: \(error)")
        }
    }
}
