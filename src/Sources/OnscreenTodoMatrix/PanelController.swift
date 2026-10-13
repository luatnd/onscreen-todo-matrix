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
        if !panel.setFrameUsingName("GlancePanel") {
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            if let visible { panel.setFrame(Self.defaultFrame(in: visible, minSize: panel.minSize), display: false) }
            else { panel.center() }
        }
        panel.setFrameAutosaveName("GlancePanel")
        model.$renderState
            .sink { [weak self] state in
                self?.chart.render(state)
                self?.apply(state.settings)
            }
            .store(in: &bag)
    }

    /// 75% of the visible frame, centered, never below minSize.
    static func defaultFrame(in visible: NSRect, minSize: NSSize) -> NSRect {
        let w = max(minSize.width, (visible.width * 0.75).rounded())
        let h = max(minSize.height, (visible.height * 0.75).rounded())
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
