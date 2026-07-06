import AppKit
import CoreGraphics

/// Erkennt die Tastenkombination fn + t systemweit und unterdrückt dabei das
/// t-KeyDown/KeyUp, damit es nicht zusätzlich als Zeichen in der gerade
/// fokussierten Anwendung landet. `NSEvent`-Monitore können Events nur
/// beobachten, nicht schlucken - dafür wird ein `CGEventTap` benötigt.
///
/// `fn` erzeugt nur `flagsChanged`-Events (keinen keyDown), deshalb wird der
/// fn-Zustand separat mitgeführt und mit dem keyDown/keyUp von "t" kombiniert
/// (push-to-talk: Start bei t-down während fn aktiv ist, Stop sobald t oder
/// fn losgelassen wird).
///
/// Benötigt die Berechtigung "Eingabeüberwachung" (Input Monitoring), sonst
/// kann der Event-Tap nicht erstellt werden bzw. liefert keine Events.
final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var fnIsDown = false
    private var comboActive = false

    /// kVK_ANSI_T
    private let tKeyCode: Int64 = 17

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

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
        fnIsDown = false
        comboActive = false
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

        case .flagsChanged:
            let wasDown = fnIsDown
            fnIsDown = event.flags.contains(.maskSecondaryFn)
            if wasDown && !fnIsDown {
                endComboIfNeeded()
            }
            return Unmanaged.passRetained(event)

        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventKeycode) == tKeyCode else {
                return Unmanaged.passRetained(event)
            }
            guard fnIsDown else { return Unmanaged.passRetained(event) }

            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat && !comboActive {
                comboActive = true
                let callback = onStart
                DispatchQueue.main.async { callback?() }
            }
            return nil // "t" schlucken, solange fn gehalten wird

        case .keyUp:
            guard event.getIntegerValueField(.keyboardEventKeycode) == tKeyCode else {
                return Unmanaged.passRetained(event)
            }
            let wasComboActive = comboActive
            endComboIfNeeded()
            return wasComboActive ? nil : Unmanaged.passRetained(event)

        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func endComboIfNeeded() {
        guard comboActive else { return }
        comboActive = false
        let callback = onStop
        DispatchQueue.main.async { callback?() }
    }
}
