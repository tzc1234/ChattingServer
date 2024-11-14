import Fluent
import Vapor

struct UserController: RouteCollection {
    func boot(routes: any Vapor.RoutesBuilder) throws {
        let user = routes.grouped("user")
        
        user.post(use: create)
    }
    
    @Sendable
    func create(req: Request) async throws -> UserDTO {
        try UserDTO.validate(content: req)
        
        let user = try req.content.decode(UserDTO.self).toModel()
        user.password = try Bcrypt.hash(user.password)
        try await user.save(on: req.db)
        
        return user.toDTO()
    }
}
