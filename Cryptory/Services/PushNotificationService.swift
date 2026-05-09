import Foundation
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@MainActor
enum FirebaseBootstrapper {
    private static let lock = NSLock()
    private static var didAttemptConfigure = false
    private static var configureSucceeded = false
    private static var didLogConfigurationState = false

    @discardableResult
    static func configureIfNeeded() -> Bool {
        lock.lock()
        if didAttemptConfigure {
            let configured = configureSucceeded
            lock.unlock()
            logConfigurationStateIfNeeded(reason: configured ? nil : "previous_configure_failed")
            return configured
        }
        didAttemptConfigure = true
        lock.unlock()

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            AppLogger.debug(.network, "[Firebase] configure skipped reason=missing_google_service_info")
            setConfigured(false)
            logConfigurationStateIfNeeded(reason: "missing_google_service_info")
            return false
        }

        FirebaseApp.configure()
        let configured = FirebaseApp.app() != nil
        setConfigured(configured)
        AppLogger.debug(.network, "[Firebase] configure status=\(configured ? "configured" : "failed")")
        logConfigurationStateIfNeeded()
        return configured
    }

    static var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return configureSucceeded
    }

    private static func setConfigured(_ configured: Bool) {
        lock.lock()
        configureSucceeded = configured
        lock.unlock()
    }

    private static func logConfigurationStateIfNeeded(reason: String? = nil) {
        lock.lock()
        guard didLogConfigurationState == false else {
            lock.unlock()
            return
        }
        didLogConfigurationState = true
        lock.unlock()

        let app = FirebaseApp.app()
        let configured = app != nil
        let projectID = app?.options.projectID ?? "nil"
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        let suffix = reason.map { " reason=\($0)" } ?? ""
        AppLogger.configuration("[FirebaseConfig] configured=\(configured) projectId=\(projectID) bundleId=\(bundleID)\(suffix)")
    }
}

protocol FCMTokenRegistrarProtocol {
    func register(token: String, session: AuthSession) async throws
    func delete(token: String, session: AuthSession) async throws
}

final class FCMTokenRegistrar: FCMTokenRegistrarProtocol {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func register(token: String, session: AuthSession) async throws {
        _ = try await client.requestJSON(
            path: client.configuration.pushFCMTokenPath,
            method: "POST",
            body: ["token": token, "platform": "ios"],
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
        AppLogger.debug(.network, "[Push] token register success")
    }

    func delete(token: String, session: AuthSession) async throws {
        _ = try await client.requestJSON(
            path: client.configuration.pushFCMTokenPath,
            method: "DELETE",
            body: ["token": token, "platform": "ios"],
            accessRequirement: .authenticatedRequired,
            accessToken: session.accessToken
        )
    }
}

@MainActor
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    private let registrar: FCMTokenRegistrarProtocol
    private var currentSession: AuthSession?
    private var pendingToken: String?

    init(registrar: FCMTokenRegistrarProtocol = FCMTokenRegistrar()) {
        self.registrar = registrar
        super.init()
    }

    func configure() {
        guard FirebaseBootstrapper.configureIfNeeded() else {
            UNUserNotificationCenter.current().delegate = self
            AppLogger.debug(.network, "[Push] firebase_unavailable messaging_skipped=true")
            return
        }
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }

    func requestAuthorizationAndRegister() {
        guard FirebaseBootstrapper.isConfigured else {
            AppLogger.debug(.network, "[Push] registration skipped reason=firebase_unconfigured")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                AppLogger.debug(.network, "[Push] permission status=\(settings.authorizationStatus.debugName)")
                if granted || settings.authorizationStatus == .provisional || settings.authorizationStatus == .authorized {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
    }

    func updateAPNSToken(_ deviceToken: Data) {
        guard FirebaseBootstrapper.isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    func bindSession(_ session: AuthSession?) {
        currentSession = session
        if let session, let token = pendingToken {
            Task { try? await registrar.register(token: token, session: session) }
        }
    }

    func cleanupForLogout(previousSession: AuthSession?) {
        currentSession = nil
        guard let token = pendingToken, let session = previousSession else { return }
        Task { try? await registrar.delete(token: token, session: session) }
    }

    private func handleFCMToken(_ token: String) {
        pendingToken = token
        AppLogger.debug(.network, "[Push] fcm token received exists=true length=\(token.count)")
        guard let session = currentSession else { return }
        Task { try? await registrar.register(token: token, session: session) }
    }
}

extension PushNotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, fcmToken.isEmpty == false else {
            AppLogger.debug(.network, "[Push] fcm token received exists=false length=0")
            return
        }
        handleFCMToken(fcmToken)
    }
}

extension PushNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let type = userInfo["type"] as? String ?? "-"
        let symbol = userInfo["symbol"] as? String ?? "-"
        AppLogger.debug(.network, "[Push] notification received type=\(type) symbol=\(symbol)")
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationRouter.shared.route(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
}

@MainActor
final class NotificationRouter {
    static let shared = NotificationRouter()
    var onPriceAlert: ((PushPriceAlertRoute) -> Void)?

    func route(userInfo: [AnyHashable: Any]) {
        guard (userInfo["type"] as? String) == "PRICE_ALERT",
              let exchangeRaw = userInfo["exchange"] as? String,
              let exchange = Exchange(rawValue: exchangeRaw.lowercased()),
              let symbol = userInfo["symbol"] as? String else { return }
        let quote = MarketQuoteCurrency(rawValue: (userInfo["quoteCurrency"] as? String ?? "KRW").uppercased()) ?? .krw
        AppLogger.debug(.network, "[Push] notification received type=PRICE_ALERT symbol=\(symbol)")
        onPriceAlert?(PushPriceAlertRoute(exchange: exchange, symbol: symbol, quoteCurrency: quote, alertId: userInfo["alertId"] as? String))
    }
}

struct PushPriceAlertRoute {
    let exchange: Exchange
    let symbol: String
    let quoteCurrency: MarketQuoteCurrency
    let alertId: String?
}

private extension UNAuthorizationStatus {
    var debugName: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }
}
