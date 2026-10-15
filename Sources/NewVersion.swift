import Foundation

// Whether a newer version of the app is out (the API knows each app's
// latest release). Can't tell - offline, say - counts as no.
enum NewVersion {
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    // `done` on the main thread.
    static func check(platform: String, done: @escaping (Bool) -> Void) {
        let request = URLRequest(url: Site.apiURL.appendingPathComponent("v1/apps/latest"), timeoutInterval: 8)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let versions = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let newer = (versions?[platform] as? String).map { isNewer($0, than: current) } ?? false
            DispatchQueue.main.async { done(newer) }
        }.resume()
    }

    // "1.0.12" over "1.0.9", part by part.
    static func isNewer(_ latest: String, than installed: String) -> Bool {
        let a = latest.split(separator: ".").compactMap { Int($0) }
        let b = installed.split(separator: ".").compactMap { Int($0) }
        guard !a.isEmpty, !b.isEmpty else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
