import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init(permissionsState: PermissionsState) {
        let view = SettingsView(permissionsState: permissionsState)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Diktier-Assistent"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
