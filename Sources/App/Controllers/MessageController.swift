import Fluent
import Vapor
import SQLKit

typealias ContactID = Int
typealias UserID = Int

actor MessageController: RouteCollection {
    private var contactID: ContactID?
    private var senderID: UserID?
    
    private let webSocketStore: WebSocketStore
    
    init(webSocketStore: WebSocketStore) {
        self.webSocketStore = webSocketStore
    }
    
    nonisolated func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts", ":contact_id", "messages")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
        protected.webSocket("channel", shouldUpgrade: updateToMessagesChannel, onUpgrade: messagesChannel)
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
        guard let senderID, let contactID else {
            try? await ws.close(code: .unexpectedServerError)
            return
        }
        
        await webSocketStore.add(ws, for: contactID, with: senderID)
        
        ws.onClose.whenComplete { [weak webSocketStore] _ in
            Task {
                await webSocketStore?.remove(for: contactID, with: senderID)
            }
        }
        
        ws.onText { [weak self] ws, text in
            try? await self?.close(ws, for: contactID, with: senderID)
        }
        
        ws.onBinary { [weak self] ws, data in
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            
            guard let incoming = try? decoder.decode(IncomingMessage.self, from: data) else {
                try? await self?.close(ws, for: contactID, with: senderID)
                return
            }
            
            let message = Message(contactID: contactID, senderID: senderID, text: incoming.text)
            do {
                try await message.save(on: req.db)
                let ongoing = MessageResponse(id: try message.requireID(), text: incoming.text, senderID: senderID, isRead: false)
                let encoded = try encoder.encode(ongoing)
                
                for webSocket in await self?.webSocketStore.get(for: contactID) ?? [] {
                    try await webSocket.send([UInt8](encoded))
                }
            } catch {
                print("error: \(error.localizedDescription)")
            }
        }
    }
    
    private func close(_ ws: WebSocket, for contactID: ContactID, with userID: UserID) async throws {
        try await ws.close(code: .unacceptableData)
        await webSocketStore.remove(for: contactID, with: userID)
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
        
        if let limit = request.limit {
            messageSubquery = messageSubquery.limit(limit)
        }
        
        return messageSubquery.query
    }
    
    private func validateContactID(req: Request) throws -> Int {
        guard let contactIDString = req.parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw Abort(.badRequest, reason: "Contact id invalid", identifier: "contact_id_invalid")
        }
        
        return contactID
    }
    
    private func checkContactExist(userID: UserID, contactID: ContactID, db: Database) async throws {
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
