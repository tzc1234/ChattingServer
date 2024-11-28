@testable import App
import XCTVapor

protocol AppTests {}

extension AppTests {
    func withApp(_ test: (Application) async throws -> ()) async throws {
        try await withApp(
            avatarFilename: { $0 },
            avatarDirectoryPath: { "avatarDirectory" },
            webSocketStore: WebSocketStore(),
            test
        )
    }
    
    func withApp(avatarFilename: @escaping @Sendable (String) -> (String),
                 avatarDirectoryPath: @escaping @Sendable () -> (String),
                 webSocketStore: WebSocketStore,
                 _ test: (Application) async throws -> (),
                 afterShutdown: () throws -> Void = {}) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try routes(
                app,
                avatarFilename: avatarFilename,
                avatarDirectoryPath: avatarDirectoryPath,
                webSocketStore: webSocketStore
            )
            try await test(app)
            try await app.autoRevert()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
        try afterShutdown()
    }
}
