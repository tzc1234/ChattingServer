import Fluent
import Vapor

func routes(_ app: Application,
            avatarFilename: @escaping @Sendable (String) -> String,
            avatarDirectoryPath: @escaping @Sendable () -> String,
            webSocketStore: WebSocketStore) throws {
    app.get { req async in
        "It works!"
    }
    
    try app.group("api", "v1") { routes in
        try routes.register(collection: AuthenticationController(
            avatarFilename: avatarFilename,
            avatarDirectoryPath: avatarDirectoryPath)
        )
        try routes.register(collection: ContactController())
        try routes.register(collection: MessageController(webSocketStore: webSocketStore))
    }
}
