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
    
    @Field(key: "is_read")
    var isRead: Bool
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    @Children(for: \.$message)
    var editHistories: [MessageEditHistory]
    
    @Field(key: "edited_at")
    var editedAt: Date?
    
    @Field(key: "deleted_at")
    var deletedAt: Date?
    
    init() {}
    
    init(id: Int? = nil, contactID: Contact.IDValue, senderID: User.IDValue, text: String, isRead: Bool = false) {
        self.id = id
        self.$contact.id = contactID
        self.$sender.id = senderID
        self.text = text
        self.isRead = isRead
        self.editedAt = nil
        self.deletedAt = nil
    }
}

extension Message {
    func toResponse() throws -> MessageResponse {
        guard let createdAt else { throw MessageError.databaseError }
        
        return try MessageResponse(
            id: requireID(),
            text: deletedAt == nil ? text : Constants.MESSAGE_DELETED_TEXT,
            senderID: $sender.id,
            isRead: isRead,
            createdAt: createdAt,
            editedAt: editedAt,
            deletedAt: deletedAt
        )
    }
}
