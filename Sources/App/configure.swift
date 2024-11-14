import NIOSSL
import Fluent
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.databases.use(DatabaseConfigurationFactory.sqlite(.file("db.sqlite")), as: .sqlite)

    app.migrations.add(CreateTodo())
    app.migrations.add(CreateUserTable())
    
    try routes(app)
}
