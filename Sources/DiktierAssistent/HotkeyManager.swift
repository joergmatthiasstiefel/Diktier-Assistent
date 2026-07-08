import AppKit
import CoreGraphics

/// Erkennt systemweit Control+1…5 (Aufnahme starten, je nach Modus) und Esc
/// (Aufnahme beenden). Anders als beim früheren fn+t-Push-to-Talk ist das
/// hier ein Toggle: ein einzelner Tastendruck startet, Esc beendet - kein
/// Halten nötig. `NSEvent`-Monitore können Events nur beobachten, nicht
/// schlucken - dafür wird ein `CGEventTap` benötigt.
///
/// Esc wird nur geschluckt, solange eine Aufnahme läuft, damit das normale
/// Esc-Verhalten in anderen Apps (Dialoge schließen etc.) sonst nicht
/// beeinträchtigt wird. Wird während einer laufenden Aufnahme erneut eine
/// Control+Ziffer-Kombination gedrückt, wird die Ziffer geschluckt (damit
/// sie nicht im Text landet), aber der Moduswechsel ignoriert - dafür muss
/// die laufende Aufnahme erst per Esc beendet werden.
///
/// Benötigt die Berechtigung "Eingabeüberwachung" (Input Monitoring), sonst
/// kann der Event-Tap nicht erstellt werden bzw. liefert keine Events.
final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var isRecording = false
    /// Tastencodes, deren keyDown geschluckt wurde und deren zugehöriges
    /// keyUp deshalb ebenfalls geschluckt werden muss.
    private var suppressedKeyCodes = Set<Int64>()

    /// kVK_Escape
    private let escapeKeyCode: Int64 = 53
    /// kVK_ANSI_1 … kVK_ANSI_5, jeweils dem Aufnahmemodus zugeordnet.
    private let modeKeyCodes: [Int64: Int] = [
        18: 1,
        19: 2,
        20: 3,
        21: 4,
        23: 5,
    ]

    /// Aufnahmemodus (1-5), siehe `RecordingMode`.
    var onStart: ((Int) -> Void)?
    var onStop: (() -> Void)?

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            NSLog("Diktier-Assistent: CGEventTap konnte nicht erstellt werden. Fehlt die Berechtigung 'Eingabeüberwachung'?")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRecording = false
        suppressedKeyCodes.removeAll()
    }

    /// Läuft auf dem Event-Tap-Thread (Hauptthread, da an CFRunLoopGetMain()
    /// gehängt). `nil` als Rückgabe unterdrückt die Weiterleitung des Events.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Vom System deaktiviert (z. B. bei Überlastung) - reaktivieren,
            // sonst bleibt der Hotkey dauerhaft tot.
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

            if keyCode == escapeKeyCode {
                if suppressedKeyCodes.contains(keyCode) {
                    return nil // Wiederholung, während Esc gehalten wird
                }
                guard isRecording, !isRepeat else { return Unmanaged.passRetained(event) }
                suppressedKeyCodes.insert(keyCode)
                isRecording = false
                let callback = onStop
                DispatchQueue.main.async { callback?() }
                return nil
            }

            if let mode = modeKeyCodes[keyCode] {
                guard event.flags.contains(.maskControl) else { return Unmanaged.passRetained(event) }
                if !suppressedKeyCodes.contains(keyCode) {
                    suppressedKeyCodes.insert(keyCode)
                    if !isRecording && !isRepeat {
                        isRecording = true
                        let callback = onStart
                        DispatchQueue.main.async { callback?(mode) }
                    }
                }
                return nil // Ziffer schlucken, egal ob Start ausgelöst oder ignoriert
            }

            return Unmanaged.passRetained(event)

        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if suppressedKeyCodes.remove(keyCode) != nil {
                return nil
            }
            return Unmanaged.passRetained(event)

        default:
            return Unmanaged.passRetained(event)
        }
    }
}
