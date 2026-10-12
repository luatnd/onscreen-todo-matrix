import OTMCore
import WebKit
import os

/// Hosts the bundled chart (index.html + chart.js) and bridges messages.
@MainActor
final class ChartWebView: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    var onMessage: (([String: Any]) -> Void)?
    private var ready = false
    private var pending: RenderState?
    private let log = Logger(subsystem: "onscreen-todo-matrix", category: "chart")

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(WeakMessageHandler(self), name: "otm")
        let dir = Self.chartDirectory()
        webView.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
    }

    /// App bundle `Contents/Resources/chart`, or `chart/dist` in the source tree when run via `swift run`.
    static func chartDirectory() -> URL {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("chart"),
           FileManager.default.fileExists(atPath: res.appendingPathComponent("index.html").path) {
            return res
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("chart/dist")
    }

    func render(_ state: RenderState) {
        guard ready else { pending = state; return }
        guard let data = try? RenderStateBuilder.encoder().encode(state),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.otm && window.otm.render(\(json))") { [log] _, error in
            if let error { log.error("render failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            if let p = pending { pending = nil; render(p) }
        case "log":
            log.log("js \(String(describing: body["level"]), privacy: .public): \(String(describing: body["msg"]), privacy: .public)")
        default:
            onMessage?(body)
        }
    }
}

/// Breaks the WKUserContentController → handler retain cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
