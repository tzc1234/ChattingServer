import Fluent
import Vapor

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let register = routes.grouped("register")
        register.post(use: create)
        
        let login = routes.grouped("login")
            .grouped(UserAuthenticator())
            .grouped(User.guardMiddleware())
        login.post(use: handleLogin)
    }
    
    @Sendable
    private func create(req: Request) async throws -> TokenDTO {
        try UserDTO.validate(content: req)
        
        let user = try req.content.decode(UserDTO.self).toModel()
        user.password = try Bcrypt.hash(user.password)
        try await user.save(on: req.db)
        
        return try await newToken(for: user, db: req.db)
    }
    
    @Sendable
    private func handleLogin(req: Request) async throws -> TokenDTO {
        let user = try req.auth.require(User.self)
        
        guard let existedToken = try await Token.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .first()
        else {
            return try await newToken(for: user, db: req.db)
        }
        
        return try await existedToken.toDTO(db: req.db)
    }
    
    private func newToken(for user: User, db: Database) async throws -> TokenDTO {
        let newToken = try Token.generate(for: user)
        try await newToken.save(on: db)
        return try await newToken.toDTO(db: db)
    }
}
