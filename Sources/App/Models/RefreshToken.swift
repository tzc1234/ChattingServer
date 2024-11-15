import Foundation
import Fluent

final class RefreshToken: Model, @unchecked Sendable {
    static let schema = "refresh_tokens"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "token")
    var token: String
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "issued_at")
    var issuedAt: Date
    
    @Field(key: "expires_at")
    var expiresAt: Date
    
    init() {}
    
    init(id: UUID? = nil,
         token: String,
         userID: User.IDValue,
         issuedAt: Date = .now,
         expiresAt: Date = .now.addingTimeInterval(.refreshTokenLifetime)) {
        self.id = id
        self.token = token
        self.$user.id = userID
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }
}
