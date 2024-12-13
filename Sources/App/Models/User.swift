import Foundation
import Fluent

final class User: Model, @unchecked Sendable {
    static let schema = "users"
    
    @ID(custom: "id", generatedBy: .database)
    var id: Int?
    
    @Field(key: "name")
    var name: String
    
    @Field(key: "email")
    var email: String
    
    @Field(key: "password")
    var password: String
    
    @Field(key: "avatar_filename")
    var avatarFilename: String?
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() {}
    
    init(id: Int? = nil, name: String, email: String, password: String, avatarFilename: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.password = password
        self.avatarFilename = avatarFilename
    }
}

extension User {
    func toResponse(avatarLink: (String?) async -> String?) async throws -> UserResponse {
        UserResponse(id: try requireID(), name: name, email: email, avatarURL: await avatarLink(avatarFilename))
    }
}
