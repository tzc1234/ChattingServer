import Foundation
import Fluent
import Vapor

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
    func toResponse(app: Application) -> UserResponse {
        UserResponse(
            id: id,
            name: name,
            email: email,
            avatar: avatarLink(app: app)
        )
    }
    
    private func avatarLink(app: Application) -> String? {
        guard let avatarFilename else { return nil }
        
        let filePath = app.directory.publicDirectory + Constants.AVATARS_DIRECTORY + avatarFilename
        guard FileManager.default.fileExists(atPath: filePath) else { return nil }
        
        let baseURL = app.http.server.configuration.hostname
        let port = app.http.server.configuration.port
        return "http://\(baseURL):\(port)/\(Constants.AVATARS_DIRECTORY)\(avatarFilename)"
    }
}
