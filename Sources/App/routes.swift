import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }
    
    try app.group("api", "v1") { api in
        try api.register(collection: TodoController())
        try api.register(collection: AuthenticationController())
    }
}
