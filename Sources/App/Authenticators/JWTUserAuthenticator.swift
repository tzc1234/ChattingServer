import Vapor
import JWT

struct JWTUserAuthenticator: JWTAuthenticator {
    func authenticate(jwt: Payload, for request: Request) async throws {
        request.auth.login(jwt)
    }
}
