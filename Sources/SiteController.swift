import AuthenticationServices
import UIKit
import WebKit

final class SiteController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private enum SiteState: String { case loading, offline, browser, ready }

    // The loading screen stays at least this long, so it fades instead of
    // flashing; the fade itself takes `fade`.
    private let minLoading: TimeInterval = 0.9
    private let fade: TimeInterval = 0.4
    private let sessionCookie = "reevun_session"
    private let sessionDays = 60

    private var site: WKWebView!
    private var loading: WKWebView?
    // The loading screen fading out, if one is.
    private var hiding: WKWebView?
    private var shownAt = Date()
    private var state = SiteState.loading
    private var failed = false
    private lazy var signIn = SignIn { [weak self] in self?.view.window ?? ASPresentationAnchor() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        configuration.applicationNameForUserAgent = "ReevunApp/\(version) (ios)"
        site = WKWebView(frame: .zero, configuration: configuration)
        site.navigationDelegate = self
        site.uiDelegate = self
        site.allowsBackForwardNavigationGestures = true
        site.backgroundColor = .white
        site.isOpaque = false
        fill(site)
        showOverlay(.loading)
        dashboard()
    }

    // Between the system bars, as the site expects.
    private func fill(_ child: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            child.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func dashboard() {
        site.load(URLRequest(url: Site.dashboard))
    }

    // MARK: The loading screen

    private func report(_ next: SiteState) {
        state = next
        if let loading { Screens.emit(loading, "siteState", next.rawValue) }
    }

    // The screen over the site, in a given state (made again if it's gone or
    // going).
    private func showOverlay(_ next: SiteState) {
        if loading == nil || loading === hiding {
            let overlay = Screens.view(page: "loading") { [weak self] method, _ in self?.loadingMessage(method) }
            fill(overlay)
            loading = overlay
            shownAt = Date()
        }
        report(next)
    }

    // The site has loaded: the screen fades out (its page does that on
    // "ready"), then goes.
    private func showSite() {
        guard let overlay = loading, overlay !== hiding else { return }
        hiding = overlay
        let wait = max(0, minLoading - Date().timeIntervalSince(shownAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            report(.ready)
            DispatchQueue.main.asyncAfter(deadline: .now() + fade) { [weak self] in
                overlay.removeFromSuperview()
                if self?.loading === overlay { self?.loading = nil }
                if self?.hiding === overlay { self?.hiding = nil }
            }
        }
    }

    private func loadingMessage(_ method: String) -> Any? {
        switch method {
        case "info": return Screens.info()
        case "siteState": return state.rawValue
        case "retry":
            report(.loading)
            dashboard()
        case "reopenSignIn": startSignIn()
        case "cancelSignIn":
            signIn.cancel()
            showSite()
        default: break
        }
        return nil
    }

    // MARK: Signing in

    // While the sign-in sheet is open the app waits on its own screen;
    // signed in, the dashboard loads with the new session.
    private func startSignIn() {
        showOverlay(.browser)
        signIn.start { [weak self] token in
            guard let self else { return }
            guard let token else { return showSite() }
            report(.loading)
            let cookie = HTTPCookie(properties: [
                .domain: Site.url.host!,
                .path: "/",
                .name: sessionCookie,
                .value: token,
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(TimeInterval(sessionDays * 24 * 60 * 60)),
                .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax,
                HTTPCookiePropertyKey("HttpOnly"): "TRUE",
            ])!
            site.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { [weak self] in self?.dashboard() }
        }
    }

    // MARK: Where pages go

    // Reevun pages stay; signing in goes to the sign-in sheet; Reevun ID's
    // pages and other links open in the browser. Whether `url` leaves.
    private func leaves(_ url: URL) -> Bool {
        if Site.stays(url) || ["about", "blob", "data"].contains(url.scheme) { return false }
        if Site.isSignIn(url) { startSignIn() } else if Site.opensOutside(url) { UIApplication.shared.open(url) }
        return true
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // The page itself (or a new window) going elsewhere; what it embeds
        // (frames) is left alone.
        let page = action.targetFrame?.isMainFrame ?? true
        guard page, let url = action.request.url, leaves(url) else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === site else { return }
        failed = false
    }

    // A page that failed (offline, the site down) keeps the screen up in its
    // offline state until a load succeeds. A load replaced by another one,
    // or stopped by the app, isn't one.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === site else { return }
        failed = true
        let error = error as NSError
        let stopped = (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) || (error.domain == WKError.errorDomain && error.code == 102)
        if !stopped { showOverlay(.offline) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === site, !failed, state != .ready else { return }
        showSite()
    }

    // The page process gone (out of memory, say): load again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === site {
            showOverlay(.loading)
            dashboard()
        } else if webView === loading {
            loading?.removeFromSuperview()
            loading = nil
            showOverlay(state)
        }
    }

    // A new window from the site (Discord's bot invite): over the app while
    // it's a Reevun or Discord page, else in the browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url, !leaves(url) else { return nil }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        let controller = UIViewController()
        controller.view = popup
        present(controller, animated: true)
        return popup
    }

    // In the site's six languages, as the rest of the app's own words.
    private static let cancelTitle: String = {
        let titles = ["ru": "Отмена", "de": "Abbrechen", "es": "Cancelar", "tr": "İptal", "zh": "取消"]
        let language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return titles[language] ?? "Cancel"
    }()

    // The site's alert() and confirm(), as the system's own dialogs.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        (presentedViewController ?? self).present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Self.cancelTitle, style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        (presentedViewController ?? self).present(alert, animated: true)
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView !== site { presentedViewController?.dismiss(animated: true) }
    }
}
