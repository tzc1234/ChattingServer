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
    
    // MARK: - Helpers
    
    private func makeApp(_ test: (Application) async throws -> ()) async throws {
        try await withApp(
            avatarFilename: { _ in "any-filename.png" },
            avatarDirectoryPath: { "/anyPath" },
            webSocketStore: WebSocketStore(),
            test
        )
    }
    
    private func messageAPIPath() -> String {
        .apiPath("contacts", "\(contactID)", "messages")
    }
    
    private var contactID: Int { 99 }
}
