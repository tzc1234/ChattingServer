import Fluent
import Vapor
import SQLKit

struct MessageController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts", ":contact_id", "messages")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
        protected.webSocket(shouldUpgrade: updateToMessagesChannel, onUpgrade: messagesChannel)
    }
    
    @Sendable
    private func updateToMessagesChannel(req: Request) async throws -> HTTPHeaders? {
        let payload = try req.auth.require(Payload.self)
        let contactID = try validateContactID(req: req)
        try await checkContactExist(userID: payload.userID, contactID: contactID, db: req.db)
        return HTTPHeaders([])
    }
    
    @Sendable
    private func messagesChannel(req: Request, ws: WebSocket) async {
        
        
    }
    
    @Sendable
    private func index(req: Request) async throws -> MessagesResponse {
        let contactID = try validateContactID(req: req)
        let indexRequest = try req.query.decode(MessagesIndexRequest.self)
        let payload = try req.auth.require(Payload.self)
        try await checkContactExist(userID: payload.userID, contactID: contactID, db: req.db)
        
        guard let sql = req.db as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "database error", identifier: "database_error")
        }
            
        let raws = try await sql.select()
            .column(SQLLiteral.all)
            .from(messageSubquery(contactID: contactID, request: indexRequest))
            .orderBy("id", .ascending)
            .all()
        return MessagesResponse(messages: try raws.map { try $0.decode(model: MessageResponse.self) })
    }
    
    private func messageSubquery(contactID: Int, request: MessagesIndexRequest) -> SQLSubquery {
        var messageSubquery = SQLSubqueryBuilder()
            .column(SQLLiteral.all)
            .from("messages")
            .where("contact_id", .equal, contactID)
        
        if let beforeMessageId = request.beforeMessageID {
            messageSubquery = messageSubquery
                .where("id", .lessThan, beforeMessageId)
                .orderBy("id", .descending)
        } else if let afterMessageId = request.afterMessageID {
            messageSubquery = messageSubquery
                .where("id", .greaterThan, afterMessageId)
                .orderBy("id", .ascending)
        }
        
        return messageSubquery.limit(request.limit ?? defaultLimit).query
    }
    
    private func validateContactID(req: Request) throws -> Int {
        guard let contactIDString = req.parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw Abort(.badRequest, reason: "Contact id invalid", identifier: "contact_id_invalid")
        }
        
        return contactID
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

extension Message {
    func toResponse(db: Database) async throws -> MessageResponse {
        let sender = try await $sender.get(on: db)
        return MessageResponse(id: try requireID(), text: text, senderID: try sender.requireID(), isRead: isRead)
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
