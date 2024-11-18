import Fluent
import Foundation

final class Message: Model, @unchecked Sendable {
    static let schema = "messages"
    
    @ID(custom: "id", generatedBy: .database)
    var id: Int?
    
    @Parent(key: "contact_id")
    var contact: Contact
    
    @Parent(key: "sender_id")
    var sender: User
    
    @Field(key: "text")
    var text: String
    
    @Timestamp(key: "created_by", on: .create)
    var createdBy: Date?
    
    init() {}
    
    init(id: Int? = nil, senderID: User.IDValue, text: String) {
        self.id = id
        self.$sender.id = senderID
        self.text = text
    }
}
