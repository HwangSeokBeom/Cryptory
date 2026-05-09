import SwiftUI

@main
struct CryptoryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
        guard AppTestEnvironment.isRunningUnitTests == false else {
            AppTabBarAppearance.configure()
            return
        }
        #endif
        FirebaseBootstrapper.configureIfNeeded()
        AppTabBarAppearance.configure()
        _ = AppConfig.current
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        AppLogger.authConfiguration("Apple Sign-In bundleId -> \(bundleID)")
        #if DEBUG
        if bundleID != "com.hwb.Cryptory" {
            assertionFailure("Apple Sign-In must use Bundle ID com.hwb.Cryptory, got \(bundleID)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if AppTestEnvironment.isRunningUnitTests {
                EmptyView()
            } else {
                ContentView()
                    .preferredColorScheme(.dark)
            }
            #else
            ContentView()
                .preferredColorScheme(.dark)
            #endif
        }
    }
}
