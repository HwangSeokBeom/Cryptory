import SwiftUI

@main
struct CryptoryApp: App {
    init() {
        AppTabBarAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
