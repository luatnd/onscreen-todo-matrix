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

    func show() {
        if window == nil {
            let view = SettingsView(model: model, vm: vm) { [weak self] in
                self?.window?.close()
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "onscreen-todo-matrix Settings"
            w.setContentSize(NSSize(width: 640, height: 560))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Task { await vm.loadFields() }
    }
}
