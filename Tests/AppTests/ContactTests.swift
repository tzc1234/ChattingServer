@testable import App
import XCTVapor
import Testing
import Fluent
import Vapor

@Suite("Contact routes tests")
struct ContactTests: AppTests {
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
    
    // MARK: - Helpers
    
    private func makeApp(_ test: (Application) async throws -> ()) async throws {
        try await withApp(
            avatarFilename: { _ in "any-avatar-name" },
            avatarDirectoryPath: { "/any-path/" },
            webSocketStore: WebSocketStore(),
            test,
            afterShutdown: {}
        )
    }
          
    private func createUser(_ app: Application,
                            name: String = "a username",
                            email: String = "a@email.com",
                            password: String = "aPassword") async throws -> User {
        let user = User(name: name, email: email, password: password)
        try await user.save(on: app.db)
        return user
    }
    
    private func createUserForTokenResponse(_ app: Application,
                                            name: String = "a username",
                                            email: String = "a@email.com",
                                            password: String = "aPassword") async throws -> TokenResponse {
        let registerRequest = RegisterRequest(name: name, email: email, password: password, avatar: nil)
        var tokenResponse: TokenResponse?
        
        try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
            try req.content.encode(registerRequest)
        }, afterResponse: { res async throws in
            tokenResponse = try res.content.decode(TokenResponse.self)
        })
        
        return tokenResponse!
    }
}
