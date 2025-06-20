@testable import App
import XCTVapor
import Testing
import Fluent
import Vapor

@Suite("Message routes tests")
struct MessageTests: AppTests {
    @Test("get messages failure without a token")
    func getMessageFailureWithoutToken() async throws {
        try await makeApp { app in
            try await app.test(.GET, messageAPIPath()) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("get messages failure with an invalid token")
    func newContactFailureWithInvalidToken() async throws {
        let invalidToken = "invalid-token"
        
        try await makeApp { app in
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: invalidToken)
            } afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("get messages failure with a non-existed contact")
    func getMessagesFailureWithNonExistedContact() async throws {
        try await makeApp { app in
            let (_, accessToken) = try await createUserAndAccessToken(app)
            
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .notFound)
                #expect(try errorReason(from: res) == "Contact not found")
            }
        }
    }
    
    @Test("get no messages")
    func getNoMessages() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            try await createContact(user: currentUser, anotherUser: anotherUser, db: app.db)
            
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let messagesResponse = try res.content.decode(MessagesResponse.self)
                #expect(messagesResponse.messages.isEmpty)
            }
        }
    }
    
    @Test("last messages must be unread message, message count will differ from limit")
    func getMessagesWithLimit() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let messageDetails = [
                MessageDetail(id: 1, senderID: currentUser.id!, text: "text1", isRead: true, createdAt: .distantPast),
                MessageDetail(id: 2, senderID: anotherUser.id!, text: "text2", isRead: false),
                MessageDetail(id: 3, senderID: currentUser.id!, text: "text3", isRead: false, createdAt: .distantFuture),
                MessageDetail(id: 4, senderID: anotherUser.id!, text: "text4", isRead: false, createdAt: .distantFuture)
            ]
            try await createContact(
                user: currentUser,
                anotherUser: anotherUser,
                messageDetails: messageDetails,
                db: app.db
            )
            
            let limit = 3
            let expectedMessageResponses = messageDetails[0...1].map {
                MessageResponse(
                    id: $0.id,
                    text: $0.text,
                    senderID: $0.senderID,
                    isRead: $0.isRead,
                    createdAt: $0.createdAt,
                    editedAt: nil,
                    deletedAt: nil
                )
            }
            
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.query.encode(MessagesIndexRequest(beforeMessageID: nil, afterMessageID: nil, limit: limit))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let messagesResponse = try res.content.decode(MessagesResponse.self)
                #expect(messagesResponse.messages == expectedMessageResponses)
            }
        }
    }
    
    @Test("get messages with beforeMessageID and limit, pivoted on the first non-current user unread message")
    func getMessagesWithBeforeMessageIDAndLimit() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let messageDetails = [
                MessageDetail(id: 1, senderID: currentUser.id!, isRead: true),
                MessageDetail(id: 2, senderID: currentUser.id!, isRead: true),
                MessageDetail(id: 3, senderID: currentUser.id!, isRead: false),
                MessageDetail(id: 4, senderID: anotherUser.id!, isRead: false), // pivot
                MessageDetail(id: 5, senderID: anotherUser.id!, isRead: false),
                MessageDetail(id: 6, senderID: anotherUser.id!, isRead: false),
                MessageDetail(id: 7, senderID: anotherUser.id!, isRead: false),
            ]
            try await createContact(
                user: currentUser,
                anotherUser: anotherUser,
                messageDetails: messageDetails,
                db: app.db
            )
            
            let expectedMessageResponses = messageDetails
                .filter { [3, 4, 5].contains($0.id) }
                .map {
                    MessageResponse(
                        id: $0.id,
                        text: $0.text,
                        senderID: $0.senderID,
                        isRead: $0.isRead,
                        createdAt: $0.createdAt,
                        editedAt: nil,
                        deletedAt: nil
                    )
                }
            
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.query.encode(MessagesIndexRequest(beforeMessageID: 6, afterMessageID: nil, limit: 3))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let messagesResponse = try res.content.decode(MessagesResponse.self)
                #expect(messagesResponse.messages == expectedMessageResponses)
            }
        }
    }
    
    @Test("get messages with afterMessageID. The first non-current user unread message should be at last when it within the limit")
    func getMessagesWithAfterMessageIDAndLimit() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let messageDetails = [
                MessageDetail(id: 1, senderID: currentUser.id!, isRead: true),
                MessageDetail(id: 2, senderID: currentUser.id!, isRead: true),
                MessageDetail(id: 3, senderID: currentUser.id!, isRead: false),
                MessageDetail(id: 4, senderID: anotherUser.id!, isRead: false),
                MessageDetail(id: 5, senderID: anotherUser.id!, isRead: false),
                MessageDetail(id: 6, senderID: anotherUser.id!, isRead: false),
                MessageDetail(id: 7, senderID: anotherUser.id!, isRead: false),
            ]
            try await createContact(
                user: currentUser,
                anotherUser: anotherUser,
                messageDetails: messageDetails,
                db: app.db
            )
            
            let expectedMessageResponses = messageDetails
                .filter { [2, 3, 4].contains($0.id) }
                .map {
                    MessageResponse(
                        id: $0.id,
                        text: $0.text,
                        senderID: $0.senderID,
                        isRead: $0.isRead,
                        createdAt: $0.createdAt,
                        editedAt: nil,
                        deletedAt: nil
                    )
                }
            
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.query.encode(MessagesIndexRequest(beforeMessageID: nil, afterMessageID: 1, limit: 3))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let messagesResponse = try res.content.decode(MessagesResponse.self)
                #expect(messagesResponse.messages == expectedMessageResponses)
            }
        }
    }
    
    @Test("send message with webSocket successfully")
    func sendMessageWithWebSocketSuccessfully() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        try await makeApp(eventLoopGroup: eventLoopGroup) { app in
            let port = 8084
            app.http.server.configuration.port = port
            
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            try await createContact(
                user: currentUser,
                anotherUser: anotherUser,
                db: app.db
            )
            try await app.startup()
            
            let url = "ws://127.0.0.1:\(port)/\(messageAPIPath("channel"))"
            let promise = eventLoopGroup.next().makePromise(of: ByteBuffer.self)
            var header = HTTPHeaders()
            header.bearerAuthorization = BearerAuthorization(token: accessToken)
            
            let messageText = "Hello, world!"
            let encodedIncomingMessage = try JSONEncoder().encode(IncomingMessage(text: messageText))
            let binary = MessageChannelIncomingBinary(type: .message, payload: encodedIncomingMessage)
            
            let data = try await WebSocket.connect(to: url, headers: header, on: eventLoopGroup.next()) { ws in
                ws.send(binary.binaryData)
                ws.onBinary { ws, buffer in
                    promise.succeed(buffer)
                    ws.close(code: .goingAway).cascadeFailure(to: promise)
                }
            }.flatMap {
                promise.futureResult
            }.flatMapError { error in
                promise.fail(error)
                return promise.futureResult
            }.get()
            
            let outputBinary = try #require(MessageChannelOutgoingBinary.convert(from: Data(buffer: data)))
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(MessageResponseWithMetadata.self, from: outputBinary.payload)
            #expect(decoded.message.text == messageText)
        }
    }
    
    // MARK: - Helpers
    
    private func makeApp(eventLoopGroup: EventLoopGroup? = nil, _ test: (Application) async throws -> ()) async throws {
        try await withApp(
            eventLoopGroup: eventLoopGroup,
            avatarDirectoryPath: "/anyPath",
            avatarFilename: { _ in "any-filename.png" },
            test
        )
    }
    
    @discardableResult
    private func createContact(user: User,
                               anotherUser: User,
                               messageDetails: [MessageDetail] = [],
                               db: Database) async throws -> Contact {
        let contact = try Contact(id: contactID, userID1: user.requireID(), userID2: anotherUser.requireID())
        try await contact.create(on: db)
        
        let pendingMessages = messageDetails.map {
            Message(id: $0.id, contactID: contactID, senderID: $0.senderID, text: $0.text, isRead: $0.isRead)
        }
        try await contact.$messages.create(pendingMessages, on: db)
        
        let messages = try await contact.$messages.get(on: db)
        for i in 0..<messages.count {
            let message = messages[i]
            message.createdAt = messageDetails[i].createdAt
            try await message.update(on: db)
        }
        
        return contact
    }
    
    private func messageAPIPath(_ lastPath: String = "") -> String {
        .apiPath("contacts", "\(contactID)", "messages", lastPath)
    }
    
    private var contactID: Int { 99 }
    
    private struct MessageDetail {
        let id: Int
        let senderID: Int
        let text: String
        let isRead: Bool
        let createdAt: Date
        
        init(id: Int,
             senderID: Int,
             text: String = "any text",
             isRead: Bool = false,
             createdAt: Date = .now.removeTimeIntervalDecimal()) {
            self.id = id
            self.senderID = senderID
            self.text = text
            self.isRead = isRead
            self.createdAt = createdAt
        }
    }
}
