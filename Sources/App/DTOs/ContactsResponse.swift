import Vapor

struct ContactResponse: Content {
    let responder: UserResponse
    let blockedByUserEmail: String?
    
    enum CodingKeys: String, CodingKey {
        case responder = "responder"
        case blockedByUserEmail = "blocked_by_user_email"
    }
}

struct ContactsResponse: Content {
    let contacts: [ContactResponse]
}
