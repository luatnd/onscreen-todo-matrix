import OTMCore
import WebKit
import os

/// Hosts the bundled chart (index.html + chart.js) and bridges messages.
@MainActor
final class ChartWebView: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    var onMessage: (([String: Any]) -> Void)?
    private var ready = false
    private var pending: RenderState?
    private var lastState: RenderState?
    private let indexURL: URL
    private let log = Logger(subsystem: "onscreen-todo-matrix", category: "chart")

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        indexURL = Self.chartDirectory().appendingPathComponent("index.html").standardizedFileURL
        super.init()
        webView.navigationDelegate = self
        config.userContentController.add(WeakMessageHandler(self), name: "otm")
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
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
        lastState = state
        guard ready else { pending = state; return }
        guard let data = try? RenderStateBuilder.encoder().encode(state),
              let json = String(data: data, encoding: .utf8) else {
            log.error("render state encoding failed")
            return
        }
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
            log.log("js \(body["level"] as? String ?? "", privacy: .public): \(body["msg"] as? String ?? "", privacy: .public)")
        default:
            onMessage?(body)
        }
    }

    // MARK: - WKNavigationDelegate

    /// The panel only ever shows the bundled index.html; block drops/links that would navigate away.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.request.url?.standardizedFileURL == indexURL
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        pending = lastState
        webView.reload()
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
