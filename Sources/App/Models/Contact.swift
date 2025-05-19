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
    func toResponse(currentUserID: Int,
                    contactRepository: ContactRepository,
                    avatarLink: (String?) async -> String?) async throws -> ContactResponse {
        guard let createdAt, let lastUpdate = try await contactRepository.lastUpdateFor(self) else {
            throw ContactError.databaseError
        }
        
        return try await ContactResponse(
            id: requireID(),
            responder: contactRepository.responderFor(self, by: currentUserID).toResponse(avatarLink: avatarLink),
            blockedByUserID: $blockedBy.id,
            unreadMessageCount: contactRepository.unreadMessagesCountFor(self, senderIsNot: currentUserID),
            createdAt: createdAt,
            lastUpdate: lastUpdate,
            lastMessage: contactRepository.lastMessageFor(self, senderIsNot: currentUserID)?.toResponse()
        )
    }
}
