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
            try await app.test(.GET, .apiPath("contacts", ":contacts", "messages")) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func makeApp(_ test: (Application) async throws -> ()) async throws {
        try await withApp(
            avatarFilename: { _ in "filename.png" },
            avatarDirectoryPath: { "/anyPath" },
            webSocketStore: WebSocketStore(),
            test
        )
    }
}
