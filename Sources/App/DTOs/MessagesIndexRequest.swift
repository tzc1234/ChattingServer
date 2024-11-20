import Vapor

struct MessagesIndexRequest: Content {
    var beforeMessageID: Int?
    var afterMessageID: Int?
    var limit: Int?
    
    enum CodingKeys: String, CodingKey {
        case beforeMessageID = "before_message_id"
        case afterMessageID = "after_message_id"
        case limit
    }
}
