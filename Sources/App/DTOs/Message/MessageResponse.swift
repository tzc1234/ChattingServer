import Vapor

struct MessageResponse: Content, Equatable {
    let id: Int
    let text: String
    let senderID: Int
    let isRead: Bool
    let createdAt: Date
    let editedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case senderID = "sender_id"
        case isRead = "is_read"
        case createdAt = "created_at"
        case editedAt = "edited_at"
    }
}

struct MessagesResponse: Content {
    struct Metadata: Content {
        let previousID: Int?
        let nextID: Int?
        
        enum CodingKeys: String, CodingKey {
            case previousID = "previous_id"
            case nextID = "next_id"
        }
    }
    
    let messages: [MessageResponse]
    let metadata: Metadata
}
