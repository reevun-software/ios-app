import Foundation

// The site, marked as the app in its user agent (it then opens on the
// dashboard). Pages that open inside the app: the site itself and the other
// Reevun sites, and Discord's bot invite. Reevun ID (signing in, account
// settings) opens in the browser, as does anything else.
enum Site {
    static let url = URL(string: "https://reevun.app")!
    static let dashboard = URL(string: "https://reevun.app/dashboard")!
    static let idURL = URL(string: "https://id.reevun.app")!
    static let apiURL = URL(string: "https://api.reevun.app")!

    private static func inAppHost(_ host: String) -> Bool {
        host == "reevun.app" || host.hasSuffix(".reevun.app") || host == "discord.com" || host == "www.discord.com"
    }

    // The site's "Sign in" (the API's single sign-on for reevun.app): in the
    // app that is the sign-in in the browser instead.
    static func isSignIn(_ url: URL) -> Bool {
        url.scheme == "https" && url.path == "/v1/auth/app/sso"
    }

    static func stays(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        return inAppHost(host) && host != idURL.host && !isSignIn(url)
    }

    static func opensOutside(_ url: URL) -> Bool {
        url.scheme == "https" || url.scheme == "mailto"
    }
}
