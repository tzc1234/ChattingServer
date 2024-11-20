import Vapor

struct MessageResponse: Content {
    let id: Int
    let text: String
    let senderID: Int
    let isRead: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case senderID = "sender_id"
        case isRead = "is_read"
    }
}

struct MessagesResponse: Content {
    let messages: [MessageResponse]
}
