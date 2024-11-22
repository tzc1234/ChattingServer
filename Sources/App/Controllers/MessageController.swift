import Fluent
import Vapor
import SQLKit

typealias ContactID = Int
typealias UserID = Int

actor MessageController: RouteCollection {
    private var defaultLimit: Int { 20 }
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
            .from(messageSubquery(contactID: contactID, userID: userID, request: indexRequest, sql: sql))
            .orderBy("id", .ascending)
            .all()
        return MessagesResponse(messages: try raws.map { try $0.decode(model: MessageResponse.self) })
    }
    
    private func messageSubquery(contactID: ContactID,
                                 userID: UserID,
                                 request: MessagesIndexRequest,
                                 sql: SQLDatabase) async throws -> SQLSubquery {
        var messageSubquery = SQLSubqueryBuilder()
            .column(SQLLiteral.all)
            .from("messages")
            .where("contact_id", .equal, contactID)
        
        let limit = request.limit ?? defaultLimit
        
        messageSubquery = if let beforeMessageId = request.beforeMessageID {
            messageSubquery
                .where("id", .lessThan, beforeMessageId)
                .orderBy("id", .descending)
        } else if let afterMessageId = request.afterMessageID {
            messageSubquery
                .where("id", .greaterThan, afterMessageId)
                .orderBy("id", .ascending)
        } else if let middleMessageID = try await middleMessageID(currentUserID: userID, contactID: contactID, limit: limit, on: sql) {
            messageSubquery
                .where("id", .greaterThanOrEqual, middleMessageID)
                .orderBy("id", .ascending)
        } else {
            messageSubquery
                .orderBy("id", .descending)
        }
        
        return messageSubquery.limit(limit).query
    }
    
    private func middleMessageID(currentUserID: UserID, contactID: ContactID, limit: Int, on sql: SQLDatabase) async throws -> Int? {
        let middle = limit / 2 + 1
        let middleMessageIDAtLast = SQLSubqueryBuilder()
            .column("id")
            .from("messages")
            .where("id", .lessThanOrEqual, firstUnreadMessageID(currentUserID: currentUserID, contactID: contactID))
            .where("contact_id", .equal, contactID)
            .orderBy("id", .descending)
            .limit(middle)
            .query
        
        let extractMiddleMessageID = try await sql.select()
            .column("id")
            .from(middleMessageIDAtLast)
            .orderBy("id", .ascending)
            .limit(1)
            .first()
        return try extractMiddleMessageID?.decode(column: "id", inferringAs: Int.self)
    }
    
    private func firstUnreadMessageID(currentUserID: UserID, contactID: ContactID) -> SQLSubquery {
        SQLSubqueryBuilder()
            .column("id")
            .from("messages")
            .where("contact_id", .equal, contactID)
            .where("sender_id", .notEqual, currentUserID)
            .where("is_read", .equal, false)
            .limit(1)
            .query
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
        guard try await Contact.query(on: db)
            .filter(by: userID)
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
            .filter(by: userID)
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
