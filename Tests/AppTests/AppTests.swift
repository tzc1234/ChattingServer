@testable import App
import XCTVapor
import Testing
import Fluent

@Suite("App initial tests", .serialized)
struct AppTests {
    private func withApp(dependenciesContainer: DependenciesContainer = .init(),
                         _ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app, dependenciesContainer: dependenciesContainer)
            try await test(app)
            try await app.autoRevert()
        }
        catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
    
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
