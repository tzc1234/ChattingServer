@testable import App
import XCTVapor

protocol AppTests {}

extension AppTests {
    func withApp(eventLoopGroup: EventLoopGroup? = nil,
                 avatarDirectoryPath: String,
                 avatarFilename: @escaping @Sendable (String) -> (String),
                 passwordHasher: UserPasswordHasher? = nil,
                 _ test: (Application) async throws -> (),
                 afterShutdown: () throws -> Void = {}) async throws {
        let app = try await Application.make(.testing, eventLoopGroup != nil ? .shared(eventLoopGroup!) : .singleton)
        let di = try DependenciesContainer(
            application: app,
            avatarDirectoryPath: avatarDirectoryPath,
            avatarFilenameMaker: avatarFilename,
            passwordHasher: passwordHasher,
            apnsHandler: DummyAPNSHandler()
        )
        
        do {
            try await configure(app)
            try routes(app, dependenciesContainer: di)
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

actor DummyAPNSHandler: APNSHandler {
    func sendNewContactAddedNotification(deviceToken: String, forUserID: Int, contact: ContactResponse) async {}
    func sendMessageNotification(deviceToken: String, forUserID: Int, contact: ContactResponse, messageText: String) async {}
}
