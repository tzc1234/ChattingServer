import Vapor
import JWT

struct Payload: JWTPayload {
    let userID: UUID
    let name: String
    let email: String
    
    let exp: ExpirationClaim
    
    init(for user: User) throws {
        self.userID = try user.requireID()
        self.name = user.name
        self.email = user.email
        self.exp = ExpirationClaim(value: .now.addingTimeInterval(.accessTokenLifetime))
    }
    
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
    }
}

extension Payload: Authenticatable {}
