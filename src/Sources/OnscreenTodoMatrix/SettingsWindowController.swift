import AppKit
import OTMCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let vm: SettingsViewModel
    private let onDone: () -> Void
    private var window: NSWindow?

    init(model: AppModel, onDone: @escaping () -> Void) {
        self.model = model
        self.vm = SettingsViewModel(model: model)
        self.onDone = onDone
    }

    func show() {
        if window == nil {
            let view = SettingsView(model: model, vm: vm) { [weak self] in
                self?.window?.close()
                self?.onDone()
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "onscreen-todo-matrix Settings"
            w.setContentSize(NSSize(width: 640, height: 560))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Task { await vm.loadFields() }
    }
}
