import Fluent
import Vapor

func routes(_ app: Application,
            avatarFilename: @escaping @Sendable (String) -> String,
            avatarDirectoryPath: @escaping @Sendable () -> String,
            webSocketStore: WebSocketStore) throws {
    app.get { req async in
        "It works!"
    }
    
    let db = app.db
    let userRepository = UserRepository(database: db)
    let refreshTokenRepository = RefreshTokenRepository(database: db)
    let contactRepository = ContactRepository(database: db)
    
    try app.group("api", "v1") { routes in
        try routes.register(collection: AuthenticationController(
            userRepository: userRepository,
            refreshTokenRepository: refreshTokenRepository,
            avatarFilename: avatarFilename,
            avatarDirectoryPath: avatarDirectoryPath)
        )
        try routes.register(collection: ContactController(
            contactRepository: contactRepository,
            userRepository: userRepository,
            avatarDirectoryPath: avatarDirectoryPath
        ))
        try routes.register(collection: MessageController(webSocketStore: webSocketStore))
    }
}
