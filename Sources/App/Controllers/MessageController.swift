import Vapor
import Fluent

typealias ContactID = Int
typealias UserID = Int

actor MessageController {
    private var defaultLimit: Int { 20 }
    
    private lazy var encoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    private lazy var decoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
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
}

extension MessageController: RouteCollection {
    nonisolated func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts", ":contact_id", "messages")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
        
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
              let userID = try? req.auth.require(Payload.self).userID else {
            try? await ws.close(code: .unexpectedServerError)
            return
        }
        
        let decoder = self.decoder
        let currentWebSocketID = ObjectIdentifier(ws)
        await webSocketStore.add(ws, for: contactID, userID: userID)
        
        ws.onClose.whenComplete { [weak webSocketStore] _ in
            Task {
                if let webSocketStore,
                   let storedWebSocket = await webSocketStore.get(for: contactID, userID: userID),
                   ObjectIdentifier(storedWebSocket) == currentWebSocketID {
                    await webSocketStore.remove(for: contactID, userID: userID)
                }
            }
        }
        
        ws.onText { [weak self] ws, _ in
            try? await self?.close(ws, for: contactID, with: userID)
        }
        
        ws.onBinary { [weak self] ws, buffer in
            guard let self else { return }
            guard let binary = MessageChannelBinary.convert(from: Data(buffer: buffer)) else {
                try? await close(ws, for: contactID, with: userID)
                return
            }
            
            do {
                switch binary.type {
                case .heartbeat:
                    await webSocketStore.updateTimestampNow(for: contactID, userID: userID)
                    let heartbeatResponse = MessageChannelBinary(type: .heartbeat, payload: Data())
                    await send(data: heartbeatResponse.binaryData, by: ws, logger: req.logger)
                case .message:
                    guard let incomingMessage = try? decoder
                        .decode(IncomingMessage.self, from: binary.payload) else {
                        try? await close(ws, for: contactID, with: userID)
                        return
                    }
                    
                    try await handle(
                        incomingMessage,
                        contactID: contactID,
                        userID: userID,
                        logger: req.logger,
                        db: req.db
                    )
                case .readMessages:
                    guard let incomingReadMessage = try? decoder
                        .decode(IncomingReadMessage.self, from: binary.payload) else {
                        try? await close(ws, for: contactID, with: userID)
                        return
                    }
                    
                    try await handle(
                        incomingReadMessage,
                        contactID: contactID,
                        userID: userID,
                        logger: req.logger,
                        db: req.db
                    )
                case .editMessage:
                    guard let editMessage = try? decoder.decode(EditMessage.self, from: binary.payload) else {
                        try? await close(ws, for: contactID, with: userID)
                        return
                    }
                    
                    guard let message = try await messageRepository.getMessage(by: editMessage.messageID, userID: userID),
                          let createdAt = message.createdAt else {
                        throw MessageError.messageNotFound
                    }
                    
                    guard Date.now.timeIntervalSince(createdAt) <= Constants.EDITABLE_MESSAGE_INTERVAL else {
                        throw MessageError.messageUnableEdit
                    }
                    
                    try await messageRepository.editMessage(message, newText: editMessage.text)
                    let messageResponseWithMetadata = try await makeMessageResponseWithMetadata(
                        message,
                        contactID: contactID
                    )
                    
                    let encoded = try await encoder.encode(messageResponseWithMetadata)
                    let messageBinary = MessageChannelBinary(type: .message, payload: encoded)
                    await send(data: messageBinary.binaryData, for: contactID, logger: req.logger)
                case .error:
                    try? await close(ws, for: contactID, with: userID)
                    return
                }
            } catch let error as MessageError {
                let messageChannelError = MessageChannelError(reason: error.reason)
                if let encodedError = try? await encoder.encode(messageChannelError) {
                    let messageBinary = MessageChannelBinary(type: .error, payload: encodedError)
                    await send(data: messageBinary.binaryData, by: ws, logger: req.logger)
                }
            } catch {
                req.logger.error(Logger.Message(stringLiteral: error.localizedDescription))
            }
        }
    }
    
    private func handle(_ incomingMessage: IncomingMessage,
                        contactID: Int,
                        userID: Int,
                        logger: Logger,
                        db: Database) async throws {
        let message = Message(contactID: contactID, senderID: userID, text: incomingMessage.text)
        try await messageRepository.create(message)
        let messageResponseWithMetadata = try await makeMessageResponseWithMetadata(message, contactID: contactID)
        
        let encoded = try encoder.encode(messageResponseWithMetadata)
        let binary = MessageChannelBinary(type: .message, payload: encoded)
        await send(data: binary.binaryData, for: contactID, logger: logger)
        
        try await sendMessagePushNotification(
            contactID: contactID,
            senderID: userID,
            db: db,
            messageResponse: messageResponseWithMetadata
        )
    }
    
    private func handle(_ incomingReadMessage: IncomingReadMessage,
                        contactID: Int,
                        userID: Int,
                        logger: Logger,
                        db: Database) async throws {
        guard let contact = try await contactRepository.findBy(id: contactID, userID: userID) else {
            throw MessageError.contactNotFound
        }
        
        let untilMessageID = incomingReadMessage.untilMessageID
        try await messageRepository.updateUnreadMessageToRead(
            contactID: contactID,
            userID: userID,
            untilMessageID: untilMessageID
        )
        
        let sender = try await contactRepository.anotherUser(contact, for: userID)
        let senderID = try sender.requireID()
        // If sender is connecting, send an UpdatedReadMessagesResponse via webSocket.
        if let senderWebSocket = await webSocketStore.get(for: contactID, userID: senderID) {
            let data = try encoder.encode(UpdatedReadMessagesResponse(
                contactID: contactID,
                untilMessageID: untilMessageID,
                timestamp: .now
            ))
            let binary = MessageChannelBinary(type: .readMessages, payload: data)
            await send(data: binary.binaryData, by: senderWebSocket, logger: logger)
        // If not connecting, fallback to push background notification.
        } else if let deviceToken = sender.deviceToken {
            await apnsHandler.sendReadMessagesNotification(
                deviceToken: deviceToken,
                forUserID: senderID,
                contactID: contactID,
                untilMessageID: untilMessageID
            )
        }
    }
    
    private func makeMessageResponseWithMetadata(_ message: Message,
                                                 contactID: Int) async throws -> MessageResponseWithMetadata {
        let messageID = try message.requireID()
        let metadata = try await messageRepository.getMetadata(
            from: messageID,
            to: messageID,
            contactID: contactID
        )
        return MessageResponseWithMetadata(
            message: try message.toResponse(),
            metadata: .init(previousID: metadata.previousID)
        )
    }
    
    private func send(data: Data,
                      for contactID: ContactID,
                      logger: Logger,
                      retry: UInt = Constants.WEB_SOCKET_SEND_DATA_RETRY_TIMES) async {
        for webSocket in await webSocketStore.get(for: contactID) {
            await send(data: data, by: webSocket, logger: logger, retry: retry)
        }
    }
    
    private func send(data: Data,
                      by webSocket: WebSocket,
                      logger: Logger,
                      retry: UInt = Constants.WEB_SOCKET_SEND_DATA_RETRY_TIMES) async {
        do {
            try await webSocket.send([UInt8](data))
        } catch {
            logger.error(Logger.Message(stringLiteral: error.localizedDescription))
            
            if retry > 0 {
                logger.info(Logger.Message(stringLiteral: "Retry webSocket send..."))
                await send(data: data, by: webSocket, logger: logger, retry: retry - 1)
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
