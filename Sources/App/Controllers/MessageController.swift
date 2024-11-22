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
        protected.webSocket("channel", shouldUpgrade: upgradeToMessagesChannel, onUpgrade: messagesChannel)
        protected.patch("read", use: readMessages)
    }
    
    @Sendable
    private func index(req: Request) async throws -> MessagesResponse {
        let contactID = try validateContactID(req: req)
        let indexRequest = try req.query.decode(MessagesIndexRequest.self)
        let userID = try req.auth.require(Payload.self).userID
        
        try await checkContactExist(userID: userID, contactID: contactID, db: req.db)
        
        guard let sql = req.db as? SQLDatabase else {
            throw MessageError.databaseError
        }
            
        let raws = try await sql.select()
            .column(SQLLiteral.all)
            .from(messageSubquery(contactID: contactID, request: indexRequest))
            .orderBy("id", .ascending)
            .all()
        return MessagesResponse(messages: try raws.map { try $0.decode(model: MessageResponse.self) })
    }
    
    private func messageSubquery(contactID: ContactID, request: MessagesIndexRequest) -> SQLSubquery {
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
    
    @Sendable
    private func upgradeToMessagesChannel(req: Request) async throws -> HTTPHeaders? {
        let userID = try req.auth.require(Payload.self).userID
        let contactID = try validateContactID(req: req)
        try await checkContactExist(userID: userID, contactID: contactID, db: req.db)
        
        self.contactID = contactID
        self.senderID = userID
        
        return [:]
    }
    
    @Sendable
    private func messagesChannel(req: Request, ws: WebSocket) async {
        guard let contactID, let senderID else {
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
                
                let messageResponse = MessageResponse(
                    id: try message.requireID(),
                    text: message.text,
                    senderID: senderID,
                    isRead: message.isRead,
                    createdAt: message.createdAt
                )
                let data = try encoder.encode(messageResponse)
                await self?.send(data: [UInt8](data), for: contactID, logger: req.logger, retry: 1)
            } catch {
                req.logger.error(Logger.Message(stringLiteral: error.localizedDescription))
            }
        }
    }
    
    private func send(data: [UInt8], for contactID: ContactID, logger: Logger, retry: UInt = 0) async {
        for webSocket in await webSocketStore.get(for: contactID) {
            do {
                try await webSocket.send(data)
            } catch {
                logger.error(Logger.Message(stringLiteral: error.localizedDescription))
                
                if retry > 0 {
                    logger.info(Logger.Message(stringLiteral: "Retry webSocket send..."))
                    await send(data: data, for: contactID, logger: logger, retry: retry - 1)
                }
            }
        }
    }
    
    private func close(_ ws: WebSocket, for contactID: ContactID, with userID: UserID) async throws {
        try await ws.close(code: .unacceptableData)
        await webSocketStore.remove(for: contactID, with: userID)
    }
    
    private func validateContactID(req: Request) throws -> ContactID {
        guard let contactIDString = req.parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw MessageError.contactIDInvalid
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
            throw MessageError.contactNotFound
        }
    }
    
    @Sendable
    private func readMessages(req: Request) async throws -> Response {
        let userID = try req.auth.require(Payload.self).userID
        let contactID = try validateContactID(req: req)
        let untilMessageID = try req.content.decode(ReadMessageRequest.self).untilMessageID
        
        guard let contact = try await Contact.query(on: req.db)
            .group(.or, { group in
                group.filter(\.$user1.$id == userID).filter(\.$user2.$id == userID)
            })
            .filter(\.$id == contactID)
            .first()
        else {
            throw MessageError.contactNotFound
        }
        
        try await contact.$messages
            .query(on: req.db)
            .filter(\.$id <= untilMessageID)
            .filter(\.$sender.$id != userID)
            .filter(\.$isRead == false)
            .set(\.$isRead, to: true)
            .update()
        
        return Response()
    }
}
