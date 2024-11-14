import Foundation
import Fluent

final class Token: Model, @unchecked Sendable {
    static let schema = "tokens"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "token_value")
    var tokenValue: String
    
    @Parent(key: "user_id")
    var user: User
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() {}
    
    init(id: UUID? = nil, tokenValue: String, userID: User.IDValue) {
        self.id = id
        self.tokenValue = tokenValue
        self.$user.id = userID
    }
}

extension Token {
    static func generate(for user: User) throws -> Token {
        let random = [UInt8].random(count: 32).base64
        let token = try Token(tokenValue: random, userID: user.requireID())
        return token
    }
}

extension Token {
    func toDTO(db: Database) async throws -> TokenDTO {
        try await $user.load(on: db)
        return TokenDTO(value: tokenValue, user: user.toDTO().toPublic())
    }
}
