import Fluent
import Vapor
import SQLKit

actor MessageController: RouteCollection {
    private var defaultLimit: Int { 20 }
    private var contactID: Int?
    private var senderID: Int?
    
    nonisolated func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts", ":contact_id", "messages")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
        protected.webSocket(shouldUpgrade: updateToMessagesChannel, onUpgrade: messagesChannel)
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
    
    @Sendable
    private func updateToMessagesChannel(req: Request) async throws -> HTTPHeaders? {
        let payload = try req.auth.require(Payload.self)
        let contactID = try validateContactID(req: req)
        try await checkContactExist(userID: payload.userID, contactID: contactID, db: req.db)
        
        self.contactID = contactID
        self.senderID = payload.userID
        
        return HTTPHeaders([])
    }
    
    @Sendable
    private func messagesChannel(req: Request, ws: WebSocket) async {
        ws.onClose.whenComplete { _ in
            // TODO: close all ws
        }
        
        ws.onText { ws, text in
            try? await ws.close(code: .unacceptableData)
        }
        
        ws.onBinary { [senderID, contactID] ws, data in
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            
            guard let incoming = try? decoder.decode(IncomingMessage.self, from: data),
                  let senderID,
                  let contactID else {
                try? await ws.close(code: .unacceptableData)
                return
            }
            
            print("Incoming text: \(incoming.text)")
            
            let message = Message(contactID: contactID, senderID: senderID, text: incoming.text)
            do {
                try await message.save(on: req.db)
                let ongoing = MessageResponse(id: try message.requireID(), text: incoming.text, senderID: senderID, isRead: false)
                let encoded = try encoder.encode(ongoing)
                
                try await ws.send([UInt8](encoded))
            } catch {
                print("error: \(error.localizedDescription)")
            }
        }
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
