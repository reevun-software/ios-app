import WebKit

// The app's own screens (reevun-software/app-core, one self-contained page
// built into the app as screens.html), the same as in every Reevun app.
// They're served at reevun-app://screens/ and talk to the app through the
// "reevun" message handler; answers and events go back through
// window.reevunNative.receive. The site's web view has neither.
enum Screens {
    static let scheme = "reevun-app"

    static func view(page: String, handle: @escaping (String, [Any]) -> Any?) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(PageHandler(), forURLScheme: scheme)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.configuration.userContentController.add(Bridge(view: view, handle: handle), name: "reevun")
        view.isOpaque = false
        view.backgroundColor = .white
        view.scrollView.isScrollEnabled = false
        view.load(URLRequest(url: URL(string: "\(scheme)://screens/#\(page)")!))
        return view
    }

    // An event for a screen: "siteState".
    static func emit(_ view: WKWebView, _ event: String, _ data: Any) {
        send(view, ["event": event, "data": data])
    }

    static func send(_ view: WKWebView, _ message: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: message), let text = String(data: json, encoding: .utf8) else { return }
        view.evaluateJavaScript("window.reevunNative && window.reevunNative.receive(\(text))")
    }

    // What every screen asks first.
    static func info() -> [String: Any] {
        [
            "platform": "ios",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "locale": Locale.preferredLanguages.first ?? "en",
            "titleBar": ["insetLeft": 0, "windowButtons": false],
        ]
    }

    private final class PageHandler: NSObject, WKURLSchemeHandler {
        func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
            guard let file = Bundle.main.url(forResource: "screens", withExtension: "html"), let data = try? Data(contentsOf: file) else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
            task.didReceive(data)
            task.didFinish()
        }

        func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
    }

    // Kept by the content controller; it keeps the view weakly (no cycle).
    private final class Bridge: NSObject, WKScriptMessageHandler {
        weak var view: WKWebView?
        let handle: (String, [Any]) -> Any?

        init(view: WKWebView, handle: @escaping (String, [Any]) -> Any?) {
            self.view = view
            self.handle = handle
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let view, message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == Screens.scheme,
                  let text = message.body as? String, let data = text.data(using: .utf8),
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = body["method"] as? String else { return }
            let result = handle(method, body["args"] as? [Any] ?? [])
            if let id = body["id"] { Screens.send(view, ["id": id, "result": result ?? NSNull()]) }
        }
    }
}
