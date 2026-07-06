import AppKit
import Combine

/// Beobachtbarer Berechtigungsstatus für die Einstellungs-UI.
final class PermissionsState: ObservableObject {
    @Published var microphoneGranted = false
    @Published var speechGranted = false
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false

    private let manager = PermissionsManager.shared

    func refresh() {
        microphoneGranted = manager.microphoneStatus() == .authorized
        speechGranted = manager.speechRecognitionStatus() == .authorized
        accessibilityGranted = manager.isAccessibilityTrusted(prompt: false)
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    func requestMicrophone() {
        if manager.microphoneStatus() == .notDetermined {
            manager.requestMicrophoneAccess { [weak self] _ in self?.refresh() }
        } else {
            manager.openMicrophoneSettings()
        }
    }

    func requestSpeech() {
        if manager.speechRecognitionStatus() == .notDetermined {
            manager.requestSpeechRecognitionAccess { [weak self] _ in self?.refresh() }
        } else {
            manager.openSpeechRecognitionSettings()
        }
    }

    func openAccessibilitySettings() {
        _ = manager.isAccessibilityTrusted(prompt: true)
        manager.openAccessibilitySettings()
    }

    func openInputMonitoringSettings() {
        _ = CGRequestListenEventAccess()
        manager.openInputMonitoringSettings()
    }
}
