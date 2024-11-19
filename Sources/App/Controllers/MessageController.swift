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
        let payload = try req.auth.require(Payload.self)
        let userID = payload.userID
        
        guard let contactIDString = req.parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw Abort(.notFound, reason: "Contact id invalid", identifier: "contact_id_invalid")
        }
        
        guard let contact = try await Contact.query(on: req.db).group(.or, { group in
            group.filter(\.$user1.$id == userID).filter(\.$user2.$id == userID)
        })
            .filter(\.$id == contactID)
            .with(\.$messages)
            .first()
        else {
            throw Abort(.notFound, reason: "Contact not found", identifier: "contact_not_found")
        }
        
        return try await contact.messages.toResponse(db: req.db)
    }
}

extension Message {
    func toResponse(db: Database) async throws -> MessageResponse {
        let sender = try await $sender.get(on: db)
        return MessageResponse(text: text, sender: sender.toResponse(), isRead: isRead)
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
