import Vapor

struct ReadMessageRequest: Content {
    let untilMessageID: Int
    
    enum CodingKeys: String, CodingKey {
        case untilMessageID = "until_message_id"
    }
}
