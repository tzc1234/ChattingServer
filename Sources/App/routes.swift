import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }
    
    try app.group("api", "v1") { routes in
        try routes.register(collection: TodoController())
        try routes.register(collection: AuthenticationController())
    }
}
