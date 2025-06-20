import NIOSSL
import Fluent
import FluentSQLiteDriver
import Vapor
import JWT

func configure(_ app: Application) async throws {
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let hostname = Environment.get("HOSTNAME") ?? ""
        app.http.server.configuration.hostname = hostname.isEmpty ? "127.0.0.1" : hostname
        
        app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    }
    
    app.passwords.use(.bcrypt)

    guard let secret = Environment.get("JWT_SECRET_KEY") else {
        fatalError("JWT secret key not found")
    }
    
    await app.jwt.keys.add(hmac: HMACKey(from: secret), digestAlgorithm: .sha256)
    
    app.migrations.add(CreateUser())
    app.migrations.add(CreateRefreshToken())
    app.migrations.add(CreateContact())
    app.migrations.add(CreateMessage())
    app.migrations.add(AddDeviceTokenToUser())
    app.migrations.add(CreateMessageEditHistory())
    app.migrations.add(AddEditedAtToMessage())
    app.migrations.add(AddUpdatedAtToMessage())
    app.migrations.add(AddDeletedAtToMessage())
    try await app.autoMigrate()
}
