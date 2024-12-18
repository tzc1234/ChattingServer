import Vapor

struct MessagesIndexRequest: Content {
    let beforeMessageID: Int?
    let afterMessageID: Int?
    let limit: Int?
    
    enum CodingKeys: String, CodingKey {
        case beforeMessageID = "before_message_id"
        case afterMessageID = "after_message_id"
        case limit
    }
}
