import Fluent
import Vapor

let webSocketStore = WebSocketStore()

func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }
    
    try app.group("api", "v1") { routes in
        try routes.register(collection: AuthenticationController())
        try routes.register(collection: ContactController())
        try routes.register(collection: MessageController(webSocketStore: webSocketStore))
    }
}
