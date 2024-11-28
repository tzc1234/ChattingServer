import Vapor
import JWT

struct Payload: JWTPayload {
    // JWT required
    let subject: SubjectClaim
    let expiration: ExpirationClaim
    
    // Custom data
    let userID: Int
    let email: String
    
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expiration = "exp"
        case userID = "user_id"
        case email = "email"
    }
    
    init(for user: User, expiration: Date = .now.addingTimeInterval(.accessTokenLifetime)) throws {
        let id = try user.requireID()
        self.subject = SubjectClaim(value: String(id))
        self.expiration = ExpirationClaim(value: expiration)
        self.userID = id
        self.email = user.email
    }
    
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try expiration.verifyNotExpired()
    }
}

extension Payload: Authenticatable {}
