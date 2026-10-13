import AppKit
import OTMCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let vm: SettingsViewModel
    private let onDone: () -> Void
    private var window: NSWindow?

    init(model: AppModel, onDone: @escaping () -> Void) {
        self.model = model
        self.vm = SettingsViewModel(model: model)
        self.onDone = onDone
        super.init()
    }

    /// Closing (X button or Done) is the single "settings finished" signal.
    func windowWillClose(_ notification: Notification) { onDone() }

    /// Shows Settings; `tab` / `accountId` come from the panel's `openSettings {tab}` (nil = keep the current tab).
    func show(tab: SettingsTab? = nil, accountId: String? = nil) {
        if window == nil {
            let view = SettingsView(model: model, vm: vm) { [weak self] in
                self?.window?.close()
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Glance Settings"
            w.setContentSize(NSSize(width: 640, height: 560))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        vm.open(tab: tab, accountId: accountId)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// "+ New preset…" in the panel: Settings on the New preset sheet with that account pre-selected.
    func showNewPreset(accountId: String?) {
        show()
        vm.openNewPreset(accountId: accountId)
    }
}
