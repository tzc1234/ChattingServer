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
    
    // MARK: - Helpers
    
    private func makeApp(_ test: (Application) async throws -> ()) async throws {
        try await withApp(
            avatarFilename: { _ in "any-filename.png" },
            avatarDirectoryPath: { "/anyPath" },
            webSocketStore: WebSocketStore(),
            test
        )
    }
    
    @discardableResult
    private func createContact(user: User,
                               anotherUser: User,
                               app: Application) async throws -> Contact {
        let contact = try Contact(id: contactID, userID1: user.requireID(), userID2: anotherUser.requireID())
        try await contact.create(on: app.db)
        return contact
    }
    
    private func messageAPIPath() -> String {
        .apiPath("contacts", "\(contactID)", "messages")
    }
    
    private var contactID: Int { 99 }
}
