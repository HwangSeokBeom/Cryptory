import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        if AppTestEnvironment.isRunningUnitTests || AppTestEnvironment.isRunningUITests {
            return true
        }
        #endif
        PushNotificationService.shared.configure()
        PushNotificationService.shared.requestAuthorizationAndRegister()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationService.shared.updateAPNSToken(deviceToken)
    }
}
