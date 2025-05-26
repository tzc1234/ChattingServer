import Vapor
import Fluent

typealias ContactID = Int
typealias UserID = Int

actor MessageController {
    private var defaultLimit: Int { 20 }
    
    private let contactRepository: ContactRepository
    private let messageRepository: MessageRepository
    private let webSocketStore: WebSocketStore
    private let avatarLinkLoader: AvatarLinkLoader
    private let apnsHandler: APNSHandler
    
    init(contactRepository: ContactRepository,
         messageRepository: MessageRepository,
         webSocketStore: WebSocketStore,
         avatarLinkLoader: AvatarLinkLoader,
         apnsHandler: APNSHandler) {
        self.contactRepository = contactRepository
        self.messageRepository = messageRepository
        self.webSocketStore = webSocketStore
        self.avatarLinkLoader = avatarLinkLoader
        self.apnsHandler = apnsHandler
    }
    
    @Sendable
    private func index(req: Request) async throws -> MessagesResponse {
        let contactID = try ValidatedContactID(req.parameters).value
        let userID = try req.auth.require(Payload.self).userID
        let indexRequest = try req.query.decode(MessagesIndexRequest.self)
        
        guard try await contactRepository.isContactExited(id: contactID, withUserID: userID) else {
            throw MessageError.contactNotFound
        }
        
        let messageID = MessageRepository.MessageID(indexRequest: indexRequest)
        let messages = try await messageRepository.getMessages(
            contactID: contactID,
            userID: userID,
            messageID: messageID,
            limit: indexRequest.limit ?? defaultLimit
        )
        
        let metadata: MessageRepository.Metadata? =
            if let beginID = try messages.first?.requireID(), let endID = try messages.last?.requireID() {
                try await messageRepository.getMetadata(from: beginID, to: endID, contactID: contactID)
            } else {
                nil
            }
        
        return MessagesResponse(
            messages: try messages.map { try $0.toResponse() },
            metadata: .init(previousID: metadata?.previousID, nextID: metadata?.nextID)
        )
    }
    
    @Sendable
    private func readMessages(req: Request) async throws -> Response {
        let userID = try req.auth.require(Payload.self).userID
        let contactID = try ValidatedContactID(req.parameters).value
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
}

extension MessageController: RouteCollection {
    nonisolated func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts", ":contact_id", "messages")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
        protected.patch("read", use: readMessages)
        
        let protectedWebSocket = protected
            .grouped(MessageChannelContactValidationMiddleware(contactRepository: contactRepository))
        protectedWebSocket.webSocket("channel", shouldUpgrade: upgradeToMessagesChannel, onUpgrade: messagesChannel)
    }
}

extension MessageController {
    @Sendable
    private func upgradeToMessagesChannel(req: Request) async throws -> HTTPHeaders? {
        let userID = try req.auth.require(Payload.self).userID
        let contactID = try ValidatedContactID(req.parameters).value
        guard (try? await contactRepository.findBy(id: contactID, userID: userID)) != nil else {
            throw ContactError.contactNotFound
        }
        
        // User is already connected on other devices.
        if let previousConnectedWS = await webSocketStore.get(for: contactID, userID: userID) {
            // Close and remove the previous one.
            try? await previousConnectedWS.close(code: .goingAway)
            await webSocketStore.remove(for: contactID, userID: userID)
        }
        
        return [:]
    }
    
    @Sendable
    private func messagesChannel(req: Request, ws: WebSocket) async {
        guard let contactID = try? ValidatedContactID(req.parameters).value,
              let senderID = try? req.auth.require(Payload.self).userID else {
            try? await ws.close(code: .unexpectedServerError)
            return
        }
        
        let webSocketID = ObjectIdentifier(ws)
        await webSocketStore.add(ws, for: contactID, userID: senderID)
        
        ws.onClose.whenComplete { [weak webSocketStore] _ in
            Task {
                if let webSocketStore,
                   let storedWebSocket = await webSocketStore.get(for: contactID, userID: senderID),
                   ObjectIdentifier(storedWebSocket) == webSocketID {
                    await webSocketStore.remove(for: contactID, userID: senderID)
                }
            }
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
            
            do {
                let message = Message(contactID: contactID, senderID: senderID, text: incoming.text)
                try await messageRepository.create(message)
                guard let messageCreatedAt = message.createdAt else { throw MessageError.databaseError }
                
                let messageID = try message.requireID()
                let metadata = try await messageRepository.getMetadata(
                    from: messageID,
                    to: messageID,
                    contactID: contactID
                )
                let messageResponse = MessageResponse(
                    id: messageID,
                    text: message.text,
                    senderID: senderID,
                    isRead: message.isRead,
                    createdAt: messageCreatedAt
                )
                let messageResponseWithMetadata = MessageResponseWithMetadata(
                    message: messageResponse,
                    metadata: .init(previousID: metadata.previousID)
                )
                
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(messageResponseWithMetadata)
                
                await send(
                    data: [UInt8](data),
                    for: contactID,
                    logger: req.logger,
                    retry: Constants.WEB_SOCKET_SEND_DATA_RETRY_TIMES
                )
                
                try await sendMessagePushNotification(
                    contactID: contactID,
                    senderID: senderID,
                    db: req.db,
                    messageResponse: messageResponseWithMetadata
                )
            } catch {
                req.logger.error(Logger.Message(stringLiteral: error.localizedDescription))
            }
        }
    }
    
    private func send(data: [UInt8], for contactID: ContactID, logger: Logger, retry: UInt) async {
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
        await webSocketStore.remove(for: contactID, userID: userID)
    }
    
    private func sendMessagePushNotification(contactID: ContactID,
                                             senderID: UserID,
                                             db: Database,
                                             messageResponse: MessageResponseWithMetadata) async throws {
        guard let contact = try await contactRepository.findBy(id: contactID, userID: senderID) else { return }
        
        let receiver = try await contactRepository.anotherUser(contact, for: senderID)
        guard let receiverID = receiver.id, let receiverDeviceToken = receiver.deviceToken else { return }
        
        // Only send notification when receiver is not chatting with sender.
        guard await !webSocketStore.isExisted(for: contactID, userID: receiverID) else { return }
        
        await apnsHandler.sendMessageNotification(
            deviceToken: receiverDeviceToken,
            forUserID: receiverID,
            contact: try contactResponse(contact, for: receiverID, with: messageResponse),
            messageText: messageResponse.message.text
        )
    }
    
    private func contactResponse(_ contact: Contact,
                                 for userID: Int,
                                 with messageResponse: MessageResponseWithMetadata) async throws -> ContactResponse {
        try await contact.toResponse(
            currentUserID: userID,
            contactRepository: contactRepository,
            lastMessage: messageResponse,
            avatarLink: avatarLinkLoader.avatarLink()
        )
    }
}

private extension MessageRepository.MessageID {
    init?(indexRequest: MessagesIndexRequest) {
        if let afterID = indexRequest.afterMessageID, let beforeID = indexRequest.beforeMessageID {
            self = .betweenExcluded(from: afterID, to: beforeID)
            return 
        }
        
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
