import Vapor

typealias ContactID = Int
typealias UserID = Int

actor MessageController {
    private var defaultLimit: Int { 20 }
    private var contactID: ContactID?
    private var senderID: UserID?
    
    private let contactRepository: ContactRepository
    private let messageRepository: MessageRepository
    private let webSocketStore: WebSocketStore
    
    init(contactRepository: ContactRepository, messageRepository: MessageRepository, webSocketStore: WebSocketStore) {
        self.contactRepository = contactRepository
        self.messageRepository = messageRepository
        self.webSocketStore = webSocketStore
    }
    
    @Sendable
    private func index(req: Request) async throws -> MessagesResponse {
        let contactID = try validateContactIDFormat(req: req)
        let userID = try req.auth.require(Payload.self).userID
        let indexRequest = try req.query.decode(MessagesIndexRequest.self)
        
        guard try await contactRepository.isContactExited(id: contactID, withUserID: userID) else {
            throw MessageError.contactNotFound
        }
        
        let messages = try await messageRepository.getMessages(
            contactID: contactID,
            userID: userID,
            messageID: MessageRepository.MessageID(indexRequest: indexRequest),
            limit: indexRequest.limit ?? defaultLimit
        )
        return MessagesResponse(messages: try messages.map { try $0.toResponse() })
    }
    
    @Sendable
    private func readMessages(req: Request) async throws -> Response {
        let userID = try req.auth.require(Payload.self).userID
        let contactID = try validateContactIDFormat(req: req)
        let untilMessageID = try req.content.decode(ReadMessageRequest.self).untilMessageID
        
        guard try await contactRepository.isContactExited(id: contactID, withUserID: userID) else {
            throw MessageError.contactNotFound
        }
        
        try await messageRepository.updateUnreadMessageToRead(
            contactID: contactID,
            userID: userID,
            untilMessageID: untilMessageID
        )
        
        return Response()
    }
    
    private func validateContactIDFormat(req: Request) throws -> ContactID {
        guard let contactIDString = req.parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw MessageError.contactIDInvalid
        }
        
        return contactID
    }
}

extension MessageController: RouteCollection {
    nonisolated func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts", ":contact_id", "messages")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
        protected.patch("read", use: readMessages)
        
        let protectedWebSocket = protected.grouped(MessageChannelContactValidationMiddleware(contactRepository: contactRepository))
        protectedWebSocket.webSocket("channel", shouldUpgrade: upgradeToMessagesChannel, onUpgrade: messagesChannel)
    }
}

extension MessageController {
    @Sendable
    private func upgradeToMessagesChannel(req: Request) async throws -> HTTPHeaders? {
        senderID = try req.auth.require(Payload.self).userID
        contactID = try validateContactIDFormat(req: req)
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
            Task { await webSocketStore?.remove(for: contactID, with: senderID) }
        }
        
        ws.onText { [weak self] ws, text in
            try? await self?.close(ws, for: contactID, with: senderID)
        }
        
        ws.onBinary { [weak self] ws, data in
            guard let self else { return }
            
            guard let incoming = try? JSONDecoder().decode(IncomingMessage.self, from: data) else {
                try? await close(ws, for: contactID, with: senderID)
                return
            }
            
            let message = Message(contactID: contactID, senderID: senderID, text: incoming.text)
            do {
                try await messageRepository.create(message)
                
                let messageResponse = MessageResponse(
                    id: try message.requireID(),
                    text: message.text,
                    senderID: senderID,
                    isRead: message.isRead,
                    createdAt: message.createdAt
                )
                
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(messageResponse)
                
                await send(
                    data: [UInt8](data),
                    for: contactID,
                    logger: req.logger,
                    retry: Constants.WEB_SOCKET_SEND_DATA_RETRY_TIMES
                )
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
}

private extension Message {
    func toResponse() throws -> MessageResponse {
        try MessageResponse(
            id: requireID(),
            text: text,
            senderID: $sender.id,
            isRead: isRead,
            createdAt: createdAt
        )
    }
}

private extension MessageRepository.MessageID {
    init?(indexRequest: MessagesIndexRequest) {
        if let beforeID = indexRequest.beforeMessageID {
            self = .before(beforeID)
            return
        }
        
        if let afterID = indexRequest.afterMessageID {
            self = .after(afterID)
            return
        }
        
        return nil
    }
}
