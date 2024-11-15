import NIOSSL
import Fluent
import FluentSQLiteDriver
import Vapor
import JWT

public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.databases.use(DatabaseConfigurationFactory.sqlite(.file("db.sqlite")), as: .sqlite)
    app.passwords.use(.bcrypt)

    let secret = Environment.get("JWT_SECRET_KEY")!
    await app.jwt.keys.add(hmac: HMACKey(from: secret), digestAlgorithm: .sha256)
    
    app.migrations.add(CreateTodo())
    app.migrations.add(CreateUser())
    app.migrations.add(CreateRefreshToken())
    try await app.autoMigrate()
    
    try routes(app)
}
