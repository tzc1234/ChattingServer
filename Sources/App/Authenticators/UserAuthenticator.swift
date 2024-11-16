import Vapor
import JWT

struct UserAuthenticator: JWTAuthenticator {
    func authenticate(jwt: Payload, for request: Request) async throws {
        request.auth.login(jwt)
    }
}
