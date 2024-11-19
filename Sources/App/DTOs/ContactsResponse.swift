import Vapor

struct ContactResponse: Content {
    let responder: UserResponse
    let blockedByUserEmail: String?
    let unreadMessageCount: Int
    
    enum CodingKeys: String, CodingKey {
        case responder = "responder"
        case blockedByUserEmail = "blocked_by_user_email"
        case unreadMessageCount = "unread_message_count"
    }
}

struct ContactsResponse: Content {
    let contacts: [ContactResponse]
}
