@testable import App
import XCTVapor

protocol AppTests {
    func withApp(_ test: (Application) async throws -> ()) async throws
    func withApp(dependenciesContainer: DependenciesContainer,
                 _ test: (Application) async throws -> ()) async throws
}

extension AppTests {
    func withApp(_ test: (Application) async throws -> ()) async throws {
        try await withApp(dependenciesContainer: DependenciesContainer(), test)
    }
    
    func withApp(dependenciesContainer: DependenciesContainer,
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
}
