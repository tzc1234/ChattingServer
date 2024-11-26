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
    func toResponse(app: Application, avatarDirectoryPath: String) -> UserResponse {
        UserResponse(
            id: id,
            name: name,
            email: email,
            avatarURL: avatarLink(app: app, avatarDirectoryPath: avatarDirectoryPath)
        )
    }
    
    private func avatarLink(app: Application, avatarDirectoryPath: String) -> String? {
        guard let avatarFilename else { return nil }
        guard !avatarDirectoryPath.isEmpty else { return nil }
        
        let filePath = avatarDirectoryPath + avatarFilename
        guard FileManager.default.fileExists(atPath: filePath) else { return nil }
        
        let baseURL = app.http.server.configuration.hostname
        let port = app.http.server.configuration.port
        let lastComponent = avatarDirectoryPath.pathComponents.last!.description
        return "http://\(baseURL):\(port)/\(lastComponent)/\(avatarFilename)"
    }
}
