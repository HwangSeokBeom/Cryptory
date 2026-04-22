import Foundation
import GoogleSignIn
import UIKit

struct GoogleSignInCredential: Equatable {
    let idToken: String
    let email: String?
    let displayName: String?
}

protocol GoogleSignInProviding {
    @MainActor
    func signIn(presenting viewController: UIViewController) async throws -> GoogleSignInCredential

    @MainActor
    func signOut()

    @MainActor
    func handleOpenURL(_ url: URL) -> Bool
}

@MainActor
final class LiveGoogleSignInProvider: GoogleSignInProviding {
    static let shared = LiveGoogleSignInProvider()

    private let clientID = "142113558371-t5s22ri6gjl5aur76s81910gf2hb8p09.apps.googleusercontent.com"

    private init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    func signIn(presenting viewController: UIViewController) async throws -> GoogleSignInCredential {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        guard let idToken = result.user.idToken?.tokenString, idToken.isEmpty == false else {
            throw NetworkServiceError.parsingFailed("구글 인증 토큰을 확인할 수 없어요.")
        }

        return GoogleSignInCredential(
            idToken: idToken,
            email: result.user.profile?.email,
            displayName: result.user.profile?.name
        )
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func handleOpenURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
