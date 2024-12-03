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
    
    @Test("get messages failure with invalid token")
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
    
    @Test("get messages failure with an invalid contactID")
    func getMessagesFailureWithInvalidContactID() async throws {
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
    
    // MARK: - Helpers
    
    private func makeApp(_ test: (Application) async throws -> ()) async throws {
        try await withApp(
            avatarFilename: { _ in "any-filename.png" },
            avatarDirectoryPath: { "/anyPath" },
            webSocketStore: WebSocketStore(),
            test
        )
    }
    
    private func createContact(user: User,
                               anotherUser: User,
                               messageDetails: [MessageDetail] = [],
                               app: Application) async throws {
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
    }
    
    private func messageAPIPath() -> String {
        .apiPath("contacts", "\(contactID)", "messages")
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
