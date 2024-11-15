import Vapor
import JWT

struct Payload: JWTPayload {
    // JWT required
    let subject: SubjectClaim
    let expiration: ExpirationClaim
    
    // Custom data
    let email: String
    
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expiration = "exp"
        case email = "email"
    }
    
    init(for user: User) throws {
        self.subject = SubjectClaim(value: try user.requireID().uuidString)
        self.expiration = ExpirationClaim(value: .now.addingTimeInterval(.accessTokenLifetime))
        self.email = user.email
    }
    
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try expiration.verifyNotExpired()
    }
}

extension Payload: Authenticatable {}

extension Payload {
    var userID: UUID? {
        UUID(uuidString: subject.value)
    }
}
