import Vapor

struct UserResponse: Content, Equatable {
    let id: Int
    let name: String
    let email: String
    let avatarURL: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }
}
