import Fluent
import Vapor

func routes(_ app: Application,
            avatarFilename: @escaping @Sendable (String) -> String,
            avatarDirectoryPath: String,
            passwordHasher: UserPasswordHasher? = nil,
            webSocketStore: WebSocketStore) throws {
    app.get { req async in
        "It works!"
    }
    
    let db = app.db
    let userRepository = UserRepository(database: db)
    let refreshTokenRepository = RefreshTokenRepository(database: db)
    let contactRepository = ContactRepository(database: db)
    
    let avatarFileSaver = AvatarFileSaver(
        application: app,
        filename: avatarFilename,
        directoryPath: avatarDirectoryPath
    )
    let avatarLinkLoader = try AvatarLinkLoader(application: app, directoryPath: avatarDirectoryPath)
    let passwordHasher = passwordHasher ?? DefaultUserPasswordHasher(application: app)
    
    try app.group("api", "v1") { routes in
        try routes.register(collection: AuthenticationController(
            userRepository: userRepository,
            refreshTokenRepository: refreshTokenRepository,
            avatarFileSaver: avatarFileSaver,
            avatarLinkLoader: avatarLinkLoader,
            passwordHasher: passwordHasher
        ))
        try routes.register(collection: ContactController(
            contactRepository: contactRepository,
            userRepository: userRepository,
            avatarLinkLoader: avatarLinkLoader
        ))
        try routes.register(collection: MessageController(webSocketStore: webSocketStore))
    }
}
