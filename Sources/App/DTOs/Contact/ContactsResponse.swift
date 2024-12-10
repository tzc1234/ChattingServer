import Vapor

struct ContactResponse: Content {
    let id: Int
    let responder: UserResponse
    let blockedByUserID: Int?
    let unreadMessageCount: Int
    let lastUpdate: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case responder
        case blockedByUserID = "blocked_by_user_id"
        case unreadMessageCount = "unread_message_count"
        case lastUpdate = "last_update"
    }
}

struct ContactsResponse: Content {
    let contacts: [ContactResponse]
}
