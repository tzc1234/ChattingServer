import Foundation
import Fluent

final class Contact: Model, @unchecked Sendable {
    static let schema = "contacts"
    
    @ID(custom: "id", generatedBy: .database)
    var id: Int?
    
    @Parent(key: "user_id1")
    var user1: User
    
    @Parent(key: "user_id2")
    var user2: User
    
    @OptionalParent(key: "blocked_by")
    var blockedBy: User?
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Children(for: \.$contact)
    var messages: [Message]
    
    init() {}
    
    init(id: Int? = nil, userID1: User.IDValue, userID2: User.IDValue, blockedByUserID: User.IDValue? = nil) {
        self.id = id
        self.$user1.id = userID1
        self.$user2.id = userID2
        self.$blockedBy.id = blockedByUserID
    }
}
