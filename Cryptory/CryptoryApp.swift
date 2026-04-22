import SwiftUI

@main
struct CryptoryApp: App {
    init() {
        AppTabBarAppearance.configure()
        _ = AppConfig.current
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
