import AppKit
import Combine
import OTMCore

/// NSPanel that can take keyboard focus without activating the app.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: FloatingPanel
    let chart = ChartWebView()
    private let model: AppModel
    private var bag = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        super.init()
        panel.title = "onscreen-todo-matrix"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 320)
        panel.contentView = chart.webView
        panel.delegate = self
        if !panel.setFrameUsingName("OTMPanel") { panel.center() }
        panel.setFrameAutosaveName("OTMPanel")
        model.$renderState
            .sink { [weak self] state in
                self?.chart.render(state)
                self?.apply(state.settings)
            }
            .store(in: &bag)
    }

    private func apply(_ q: QuickSettings) {
        panel.level = q.alwaysOnTop ? .floating : .normal
        panel.alphaValue = CGFloat(q.panelOpacity / 100)
    }

    var isShown: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow { hide() } else { show() }
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(chart.webView)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Task { await model.refresh(.focus) }
    }
}
