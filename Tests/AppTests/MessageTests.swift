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
                
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Contact not found")
            }
        }
    }
    
    @Test("get no messages")
    func getNoMessages() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            try await createContact(user: currentUser, anotherUser: anotherUser, app: app)
            
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let messagesResponse = try res.content.decode(MessagesResponse.self)
                #expect(messagesResponse.messages.isEmpty)
            }
        }
    }
    
    @Test("get messages with limit")
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
                app: app
            )
            
            let limit = 3
            let expectedMessageResponses = messageDetails[..<limit].map {
                MessageResponse(
                    id: $0.id,
                    text: $0.text,
                    senderID: $0.senderID,
                    isRead: $0.isRead,
                    createdAt: $0.createdAt
                )
            }
            
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.query.encode(MessagesIndexRequest(limit: limit))
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
                app: app
            )
            
            let expectedMessageResponses = messageDetails
                .filter { [3, 4, 5].contains($0.id) }
                .map {
                    MessageResponse(
                        id: $0.id,
                        text: $0.text,
                        senderID: $0.senderID,
                        isRead: $0.isRead,
                        createdAt: $0.createdAt
                    )
                }
            
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.query.encode(MessagesIndexRequest(beforeMessageID: 6, limit: 3))
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
                app: app
            )
            
            let expectedMessageResponses = messageDetails
                .filter { [2, 3, 4].contains($0.id) }
                .map {
                    MessageResponse(
                        id: $0.id,
                        text: $0.text,
                        senderID: $0.senderID,
                        isRead: $0.isRead,
                        createdAt: $0.createdAt
                    )
                }
            
            try await app.test(.GET, messageAPIPath()) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.query.encode(MessagesIndexRequest(afterMessageID: 1, limit: 3))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let messagesResponse = try res.content.decode(MessagesResponse.self)
                #expect(messagesResponse.messages == expectedMessageResponses)
            }
        }
    }
    
    @Test("read message failure without a token")
    func readMessageFailureWithoutToken() async throws {
        try await makeApp { app in
            try await app.test(.PATCH, messageAPIPath("read")) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("read message failure with an invalid token")
    func readMessageWithInvalidToken() async throws {
        let invalidToken = "invalid-token"
        
        try await makeApp { app in
            try await app.test(.PATCH, messageAPIPath("read")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: invalidToken)
            } afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("read message failure with a non-existed contact")
    func readMessageFailureWithNonExistedContact() async throws {
        try await makeApp { app in
            let (_, token) = try await createUserAndAccessToken(app)
            
            try await app.test(.PATCH, messageAPIPath("read")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token)
                try req.content.encode(ReadMessageRequest(untilMessageID: 1))
            } afterResponse: { res async throws in
                #expect(res.status == .notFound)
            }
        }
    }
    
    @Test("read message ok with a non-existed messageID")
    func readMessageOKWithNonExistedMessageID() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            try await createContact(
                user: currentUser,
                anotherUser: anotherUser,
                messageDetails: [],
                app: app
            )
            let nonExistedMessageID = 1
            
            try await app.test(.PATCH, messageAPIPath("read")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.content.encode(ReadMessageRequest(untilMessageID: nonExistedMessageID))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
            }
        }
    }
    
    @Test("read all messages until a messageID which belongs to current user (sender not equal current user)")
    func readAllMessageUntilMessageID() async throws {
        try await makeApp { app in
            let (currentUser, accessToken) = try await createUserAndAccessToken(app)
            let anotherUser = try await createUser(app, email: "another@email.com")
            let messageDetails = [
                MessageDetail(id: 1, senderID: currentUser.id!, isRead: false),
                MessageDetail(id: 2, senderID: anotherUser.id!, isRead: false),
                MessageDetail(id: 3, senderID: anotherUser.id!, isRead: false),
                MessageDetail(id: 4, senderID: anotherUser.id!, isRead: false),
            ]
            let contact = try await createContact(
                user: currentUser,
                anotherUser: anotherUser,
                messageDetails: messageDetails,
                app: app
            )
            let untilMessageID = 3
            
            try await app.test(.PATCH, messageAPIPath("read")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.content.encode(ReadMessageRequest(untilMessageID: untilMessageID))
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let messages = try await contact.$messages.get(reload: true, on: app.db)
                #expect(messages[0].isRead == false)
                #expect(messages[1].isRead == true)
                #expect(messages[2].isRead == true)
                #expect(messages[3].isRead == false)
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
                app: app
            )
            
            let url = "ws://localhost:\(port)/\(messageAPIPath("channel"))"
            let promise = eventLoopGroup.next().makePromise(of: ByteBuffer.self)
            var header = HTTPHeaders()
            header.bearerAuthorization = BearerAuthorization(token: accessToken)
            
            let messageText = "Hello, world!"
            let encoded = try JSONEncoder().encode(IncomingMessage(text: messageText))
            
            try await app.startup()
            let data = try await WebSocket.connect(to: url, headers: header, on: eventLoopGroup.next()) { ws in
                ws.send(encoded)
                ws.onBinary { ws, data in
                    promise.succeed(data)
                    ws.close(code: .goingAway).cascadeFailure(to: promise)
                }
            }.flatMap {
                promise.futureResult
            }.flatMapError { error in
                promise.fail(error)
                return promise.futureResult
            }.get()
            
            let decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
            #expect(decoded.text == messageText)
        }
    }
    
    // MARK: - Helpers
    
    private func makeApp(eventLoopGroup: EventLoopGroup? = nil, _ test: (Application) async throws -> ()) async throws {
        try await withApp(
            eventLoopGroup: eventLoopGroup,
            avatarFilename: { _ in "any-filename.png" },
            avatarDirectoryPath: { "/anyPath" },
            webSocketStore: WebSocketStore(),
            test
        )
    }
    
    @discardableResult
    private func createContact(user: User,
                               anotherUser: User,
                               messageDetails: [MessageDetail] = [],
                               app: Application) async throws -> Contact {
        let contact = try Contact(id: contactID, userID1: user.requireID(), userID2: anotherUser.requireID())
        try await contact.create(on: app.db)
        
        let pendingMessages = messageDetails.map {
            Message(id: $0.id, contactID: contactID, senderID: $0.senderID, text: $0.text, isRead: $0.isRead)
        }
        try await contact.$messages.create(pendingMessages, on: app.db)
        
        let messages = try await contact.$messages.get(on: app.db)
        for i in 0..<messages.count {
            let message = messages[i]
            message.createdAt = messageDetails[i].createdAt
            try await message.update(on: app.db)
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
