@testable import App
import XCTVapor
import Testing
import Fluent

@Suite("Localhost initial tests", .serialized)
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
}
