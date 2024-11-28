@testable import App
import XCTVapor
import Testing
import Fluent
import Vapor

@Suite("Contact routes tests")
struct ContactTests: AppTests, AvatarFileHelpers {
    @Test("new contact failure without token")
    func newContactFailureWithoutToken() async throws {
        try await makeApp { app in
            try await app.test(.POST, .apiPath("contacts")) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("new contact failure with invalid token")
    func newContactFailureWithInvalidToken() async throws {
        let invalidToken = "invalid-valid-token"
        
        try await makeApp { app in
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: invalidToken)
            } afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    @Test("new contact failure with non-exist responder email")
    func newContactFailureWithNonExistResponderEmail() async throws {
        try await makeApp { app in
            let nonExistResponderEmail = "non-exist@email.com"
            let contactRequest = ContactRequest(responderEmail: nonExistResponderEmail)
            let accessToken = try await createUserForTokenResponse(app).accessToken
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .notFound)
            }
        }
    }
    
    @Test("new contact failure with responder is as same as current user")
    func mewContactFailureWithResponderSameAsCurrentUser() async throws {
        try await makeApp { app in
            let token = try await createUserForTokenResponse(app)
            let currentUserEmail = token.user.email
            let contactRequest = ContactRequest(responderEmail: currentUserEmail)
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token.accessToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .conflict)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Responder cannot be the same as current user")
            }
        }
    }
    
    @Test("new contact success with currentUserID < responderID")
    func mewContactSuccessWithCurrentUserIDSmallerThanResponderID() async throws {
        let avatarFilename = "test-avatar.png"
        try await makeApp(avatarFilename: avatarFilename) { app in
            let currentUserToken = try await createUserForTokenResponse(app)
            let responderToken = try await createUserForTokenResponse(
                app,
                email: "responder@email.com",
                avatar: avatarFile(app)
            )
            let contactRequest = ContactRequest(responderEmail: responderToken.user.email)
            
            try #require(currentUserToken.user.id! < responderToken.user.id!)
            try #require(responderToken.user.avatarURL != nil)
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let response = try res.content.decode(ContactsResponse.self)
                let contacts = response.contacts
                #expect(contacts.count == 1)
                
                let contact = try #require(contacts.first)
                expect(contact: contact, as: responderToken.user)
            }
        } afterShutdown: {
            try removeUploadedAvatar(filename: avatarFilename)
        }
    }
    
    @Test("new contact success with currentUserID > responderID")
    func mewContactSuccessWithCurrentUserIDBiggerThanResponderID() async throws {
        let avatarFilename = "test-avatar2.png"
        try await makeApp(avatarFilename: avatarFilename) { app in
            let responderToken = try await createUserForTokenResponse(
                app,
                email: "responder@email.com",
                avatar: avatarFile(app)
            )
            let currentUserToken = try await createUserForTokenResponse(app)
            let contactRequest = ContactRequest(responderEmail: responderToken.user.email)
            
            try #require(currentUserToken.user.id! > responderToken.user.id!)
            try #require(responderToken.user.avatarURL != nil)
            
            try await app.test(.POST, .apiPath("contacts")) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: currentUserToken.accessToken)
                try req.content.encode(contactRequest)
            } afterResponse: { res async throws in
                #expect(res.status == .ok)
                
                let response = try res.content.decode(ContactsResponse.self)
                let contacts = response.contacts
                #expect(contacts.count == 1)
                
                let contact = try #require(contacts.first)
                expect(contact: contact, as: responderToken.user)
            }
        } afterShutdown: {
            try removeUploadedAvatar(filename: avatarFilename)
        }
    }
    
    // MARK: - Helpers
    
    private func makeApp(avatarFilename: String = "filename.png",
                         _ test: (Application) async throws -> (),
                         afterShutdown: () throws -> Void = {}) async throws {
        try await withApp(
            avatarFilename: { _ in avatarFilename },
            avatarDirectoryPath: { testAvatarDirectoryPath },
            webSocketStore: WebSocketStore(),
            test,
            afterShutdown: afterShutdown
        )
    }
    
    private func expect(contact: ContactResponse,
                        as responder: UserResponse,
                        sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(contact.responder.email == responder.email, sourceLocation: sourceLocation)
        #expect(contact.responder.name == responder.name, sourceLocation: sourceLocation)
        #expect(contact.responder.id == responder.id, sourceLocation: sourceLocation)
        #expect(contact.responder.avatarURL == responder.avatarURL, sourceLocation: sourceLocation)
        #expect(contact.blockedByUserID == nil, sourceLocation: sourceLocation)
        #expect(contact.unreadMessageCount == 0, sourceLocation: sourceLocation)
    }
    
    private func createUserForTokenResponse(_ app: Application,
                                            name: String = "a username",
                                            email: String = "a@email.com",
                                            password: String = "aPassword",
                                            avatar: File? = nil) async throws -> TokenResponse {
        let registerRequest = RegisterRequest(name: name, email: email, password: password, avatar: avatar)
        var tokenResponse: TokenResponse?
        
        try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
            try req.content.encode(registerRequest)
        }, afterResponse: { res async throws in
            tokenResponse = try res.content.decode(TokenResponse.self)
        })
        
        return tokenResponse!
    }
}
