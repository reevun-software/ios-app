import SwiftUI

// Reevun for iPhone and iPad: reevun.app in the app, with the app's own
// loading and offline screens over it until it has loaded (or while the
// sign-in sheet is open). Light, as the site.
@main
struct ReevunApp: App {
    var body: some Scene {
        WindowGroup {
            SiteView()
                .background(Color.white.ignoresSafeArea())
                .preferredColorScheme(.light)
        }
    }
}

struct SiteView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SiteController { SiteController() }
    func updateUIViewController(_ controller: SiteController, context: Context) {}
}
