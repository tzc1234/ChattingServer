import Vapor

struct ContactResponse: Content {
    let id: Int
    let responder: UserResponse
    let blockedByUserID: Int?
    let unreadMessageCount: Int
    let createdAt: Date
    let lastUpdate: Date
    let lastMessage: MessageResponse?
    
    enum CodingKeys: String, CodingKey {
        case id
        case responder
        case blockedByUserID = "blocked_by_user_id"
        case unreadMessageCount = "unread_message_count"
        case createdAt = "created_at"
        case lastUpdate = "last_update"
        case lastMessage = "last_message"
    }
}

struct ContactsResponse: Content {
    let contacts: [ContactResponse]
}
