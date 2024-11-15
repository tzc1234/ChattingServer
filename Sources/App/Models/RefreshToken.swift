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

extension RefreshToken {
    static func generate(for user: User) throws -> RefreshToken {
        let random = [UInt8].random(count: 32).base64
        let token = try RefreshToken(token: random, userID: user.requireID())
        return token
    }
}

extension RefreshToken {
    func toDTO(db: Database) async throws -> RefreshTokenDTO {
        try await $user.load(on: db)
        return RefreshTokenDTO(token: token, user: user.toDTO().toPublic())
    }
}
