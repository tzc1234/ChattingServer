import Vapor

struct ContactResponse: Content, Equatable {
    let id: Int
    let responder: UserResponse
    let blockedByUserID: Int?
    let unreadMessageCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case responder
        case blockedByUserID = "blocked_by_user_id"
        case unreadMessageCount = "unread_message_count"
    }
}

struct ContactsResponse: Content {
    let contacts: [ContactResponse]
}
