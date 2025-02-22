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
        app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    }
    
    app.passwords.use(.bcrypt)

    let secret = Environment.get("JWT_SECRET_KEY")!
    await app.jwt.keys.add(hmac: HMACKey(from: secret), digestAlgorithm: .sha256)
    
    app.migrations.add(CreateUser())
    app.migrations.add(CreateRefreshToken())
    app.migrations.add(CreateContact())
    app.migrations.add(CreateMessage())
    try await app.autoMigrate()
}
