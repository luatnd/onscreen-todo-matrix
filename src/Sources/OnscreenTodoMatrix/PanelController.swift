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
        panel.title = "Glance"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 320)
        panel.contentView = chart.webView
        panel.delegate = self
        if !panel.setFrameUsingName("GlancePanel2") {
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            if let visible { panel.setFrame(Self.defaultFrame(in: visible, minSize: panel.minSize), display: false) }
            else { panel.center() }
        }
        panel.setFrameAutosaveName("GlancePanel2")
        model.$renderState
            .sink { [weak self] state in
                self?.chart.render(state)
                self?.apply(state.settings)
            }
            .store(in: &bag)
    }

    /// 1120x875 (640x500 + 75%), clamped to the visible frame, centered, never below minSize.
    static func defaultFrame(in visible: NSRect, minSize: NSSize) -> NSRect {
        let w = max(minSize.width, min(1120, visible.width))
        let h = max(minSize.height, min(875, visible.height))
        return NSRect(x: visible.midX - w / 2, y: visible.midY - h / 2, width: w, height: h).integral
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
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(chart.webView)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Task { await model.refresh(.focus) }
    }
}
