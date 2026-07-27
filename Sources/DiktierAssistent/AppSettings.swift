import Foundation

/// Einstellungen ohne Geheimnischarakter. Die liegen bewusst in den
/// UserDefaults statt in der Keychain - dort steht nur der API-Key.
enum AppSettings {
    private static let liveTranscriptKey = "showLiveTranscript"

    /// Live-Vorschau des Roh-Transkripts im Aufnahme-Overlay. Standardmäßig
    /// an, aber abschaltbar: Der Erkenner korrigiert bereits gesprochene
    /// Wörter nachträglich, sobald mehr Kontext vorliegt, wodurch der Text
    /// sichtbar springt. Wen das beim Sprechen stört, der schaltet es aus.
    static var showsLiveTranscript: Bool {
        get {
            guard UserDefaults.standard.object(forKey: liveTranscriptKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: liveTranscriptKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: liveTranscriptKey) }
    }
}
