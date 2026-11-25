import AppKit
import ApplicationServices

/// Text links und rechts vom Cursor im Feld, in das diktiert wird.
struct FocusedField {
    var textBefore = ""
    var textAfter = ""
}

/// Liest beim Start einer Aufnahme das fokussierte Textfeld der vorderen App
/// über die Bedienungshilfen, die die App fürs Einfügen ohnehin braucht.
/// Passwortfelder werden nie gelesen. Jeder Aufruf gibt nach kurzer Zeit auf,
/// damit eine hängende App kein Diktat aufhält.
///
/// Nach dem Vorbild von Blitztext (FocusedFieldReader.swift, MIT-Lizenz),
/// gekürzt auf das, was die Anpassung an den Cursor braucht.
enum FocusedFieldReader {
    private static let beforeLimit = 2_000
    private static let afterLimit = 600

    /// Chromium-, Electron- und Firefox-Apps bauen ihren Bedienungshilfen-Baum
    /// für Webseiten erst auf Anfrage.
    private static let browsersNeedingManualAccessibility: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "org.chromium.Chromium",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.mozilla.firefox",
    ]

    /// Gilt für jeden Bedienungshilfen-Aufruf dieses Prozesses; Standard wären
    /// sechs Sekunden.
    private static let timeoutIsSet: Void = {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.12)
    }()

    /// Text um den Cursor der vorderen App, oder nil, wenn das Feld ein
    /// Passwortfeld ist, keinen lesbaren Text hat oder keinen Cursor meldet.
    static func frontmostField() -> FocusedField? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        _ = timeoutIsSet
        let element = AXUIElementCreateApplication(app.processIdentifier)
        if let bundleID = app.bundleIdentifier, browsersNeedingManualAccessibility.contains(bundleID) {
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        guard let focused = axElement(element, kAXFocusedUIElementAttribute),
              (attribute(focused, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole,
              let value = attribute(focused, kAXValueAttribute) as? String,
              let range = selectedRange(focused) else {
            return nil
        }

        let text = value as NSString
        guard range.location >= 0, range.length >= 0, range.location + range.length <= text.length else {
            return nil
        }
        return FocusedField(
            textBefore: String(text.substring(to: range.location).suffix(beforeLimit)),
            textAfter: String(text.substring(from: range.location + range.length).prefix(afterLimit))
        )
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func axElement(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}
