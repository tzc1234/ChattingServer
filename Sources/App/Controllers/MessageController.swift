import Fluent
import Vapor

struct MessageController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts", ":contact_id", "messages")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
    }
    
    @Sendable
    func index(req: Request) async throws -> MessagesResponse {
        guard let contactIDString = req.parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw Abort(.badRequest, reason: "Contact id invalid", identifier: "contact_id_invalid")
        }
        
        let request = try req.query.decode(MessagesIndexRequest.self)
        let payload = try req.auth.require(Payload.self)
        try await checkContactExist(userID: payload.userID, contactID: contactID, db: req.db)
        
        let messageQuery = Message.query(on: req.db)
            .filter(\.$contact.$id == contactID)
            .limit(request.limit ?? defaultLimit)
        
        let messages = try await {
            if let beforeMessageId = request.beforeMessageID {
                let tempMessages = try await messageQuery.filter(\.$id < beforeMessageId).sort(.id, .descending).all()
                return try tempMessages.sorted(by: { try $0.requireID() < $1.requireID() })
            } else if let afterMessageId = request.afterMessageID {
                return try await messageQuery.filter(\.$id > afterMessageId).sort(.id, .ascending).all()
            } else {
                return try await messageQuery.sort(.id, .ascending).all()
            }
        }()
        return try await messages.toResponse(db: req.db)
    }
    
    private func checkContactExist(userID: Int, contactID: Int, db: Database) async throws {
        guard try await Contact.query(on: db).group(.or, { group in
                group.filter(\.$user1.$id == userID).filter(\.$user2.$id == userID)
            })
            .filter(\.$id == contactID)
            .count() > 0
        else {
            throw Abort(.notFound, reason: "Contact not found", identifier: "contact_not_found")
        }
    }
    
    private var defaultLimit: Int { 20 }
}

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

extension Message {
    func toResponse(db: Database) async throws -> MessageResponse {
        let sender = try await $sender.get(on: db)
        return MessageResponse(text: text, senderID: try sender.requireID(), isRead: isRead)
    }
}

extension [Message] {
    func toResponse(db: Database) async throws -> MessagesResponse {
        var messageResponses = [MessageResponse]()
        for message in self {
            try await messageResponses.append(message.toResponse(db: db))
        }
        return MessagesResponse(messages: messageResponses)
    }
}
