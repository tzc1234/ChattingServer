import Fluent
import Vapor

struct UserAuthenticator: AsyncBasicAuthenticator {
    func authenticate(basic: BasicAuthorization, for request: Request) async throws {
        guard let user = try await User.query(on: request.db)
            .filter(\.$email == basic.username)
            .first()
        else {
            return
        }

        if try Bcrypt.verify(basic.password, created: user.password) {
            request.auth.login(user)
        }
    }
}
