import Fluent
import Vapor

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let user = routes.grouped("user")
        user.post(use: create)
        
        let userAuth = routes.grouped("login")
            .grouped(UserAuthenticator())
            .grouped(User.guardMiddleware())
        userAuth.post(use: login)
    }
    
    @Sendable
    func create(req: Request) async throws -> UserDTO.Public {
        try UserDTO.validate(content: req)
        
        let user = try req.content.decode(UserDTO.self).toModel()
        user.password = try Bcrypt.hash(user.password)
        try await user.save(on: req.db)
        
        return user.toDTO().toPublic()
    }
    
    @Sendable
    func login(req: Request) async throws -> TokenDTO {
        let user = try req.auth.require(User.self)
        
        guard let existedToken = try await Token.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .first()
        else {
            let newToken = try Token.generate(for: user)
            try await newToken.save(on: req.db)
            return try await newToken.toDTO(db: req.db)
        }
        
        return try await existedToken.toDTO(db: req.db)
    }
}
