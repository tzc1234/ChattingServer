@testable import App
import XCTVapor
import Testing

@Suite("Localhost initial tests")
struct LocalhostTests: AppTests {
    @Test("Test localhost Route")
    func localhostRoute() async throws {
        try await withApp { app in
            try await app.test(.GET, "", afterResponse: { response async in
                #expect(response.status == .ok)
                #expect(response.body.string == "It works!")
            })
        }
    }
    
    // MARK: - Helpers
    
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        try await withApp(
            avatarDirectoryPath: "/anyPath",
            avatarFilename: { $0 },
            test
        )
    }
}
