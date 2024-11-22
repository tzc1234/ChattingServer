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
    
    @OptionalParent(key: "blocked_by_user_id")
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

extension Contact {
    func unreadMessagesCount(db: Database) async throws -> Int {
        try await unreadMessageQuery(db: db).count()
    }
    
    private func unreadMessageQuery(db: Database) -> QueryBuilder<Message> {
        $messages.query(on: db).filter(\.$isRead == false)
    }
}

extension QueryBuilder<Contact> {
    func filter(by userID: Int) -> Self {
        group(.or, { group in
            group.filter(\.$user1.$id == userID).filter(\.$user2.$id == userID)
        })
    }
}
