import AuthenticationServices
import CryptoKit
import Foundation

// Signing in happens in the browser, not in the app: the app opens Reevun
// ID's id.reevun.app/app?challenge=…&state=… in the system's sign-in sheet
// (with Safari's sign-ins). There the person signs in (or already is) and
// confirms; Reevun ID sends the sheet to reevun://signed-in?state=…&code=…,
// which hands the app a one-time code. Only this app can trade it for a
// session: the code is bound to the challenge, and the secret behind it
// (the verifier) never leaves the app (PKCE).
final class SignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private let anchor: () -> ASPresentationAnchor

    init(anchor: @escaping () -> ASPresentationAnchor) {
        self.anchor = anchor
    }

    // `done` gets the session token, or nil (cancelled or refused), on the
    // main thread.
    func start(done: @escaping (String?) -> Void) {
        session?.cancel()
        let verifier = Self.random(32)
        let challenge = Self.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.random(24)
        var url = URLComponents(url: Site.idURL.appendingPathComponent("app"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "challenge", value: challenge), URLQueryItem(name: "state", value: state)]
        let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "reevun") { callback, _ in
            let items = callback.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
            let value = { (name: String) in items.first { $0.name == name }?.value }
            guard callback?.host == "signed-in", value("state") == state, let code = value("code") else {
                return DispatchQueue.main.async { done(nil) }
            }
            Self.redeem(code: code, verifier: verifier) { token in DispatchQueue.main.async { done(token) } }
        }
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    func cancel() {
        session?.cancel()
        session = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor()
    }

    private static func redeem(code: String, verifier: String, done: @escaping (String?) -> Void) {
        var request = URLRequest(url: Site.apiURL.appendingPathComponent("v1/auth/code"), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code, "client": "app", "verifier": verifier])
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = body["token"] as? String, !token.isEmpty else { return done(nil) }
            done(token)
        }.resume()
    }

    private static func random(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return encode(Data(bytes))
    }

    private static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
