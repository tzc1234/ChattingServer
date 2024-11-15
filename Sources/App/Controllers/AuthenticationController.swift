import Fluent
import Vapor

struct AuthenticationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let registerRoute = routes.grouped("register")
        registerRoute.post(use: register)
        
        let loginRoute = routes.grouped("login")
            .grouped(UserAuthenticator())
            .grouped(User.guardMiddleware())
        loginRoute.post(use: login)
    }
    
    @Sendable
    private func register(req: Request) async throws -> RegisterResponse {
        try RegisterRequest.validate(content: req)
        
        let user = try req.content.decode(RegisterRequest.self).toModel()
        user.password = try Bcrypt.hash(user.password)
        try await user.save(on: req.db)
        
        let (accessToken, refreshToken) = try await newTokens(for: user, req: req)
        return RegisterResponse(user: user.toResponse(), accessToken: accessToken, refreshToken: refreshToken)
    }
    
    @Sendable
    private func login(req: Request) async throws -> RefreshTokenDTO {
        let user = try req.auth.require(User.self)
        
        guard let existedToken = try await RefreshToken.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .first()
        else {
            return try await newToken(for: user, db: req.db)
        }
        
        return try await existedToken.toDTO(db: req.db)
    }
    
    private func newToken(for user: User, db: Database) async throws -> RefreshTokenDTO {
        let newToken = try RefreshToken.generate(for: user)
        try await newToken.save(on: db)
        return try await newToken.toDTO(db: db)
    }
    
    private func newTokens(for user: User, req: Request) async throws -> (accessToken: String, refreshToken: String) {
        let accessToken = try await req.jwt.sign(Payload(for: user))
        
        let token = RandomGenerator.generate(bytes: 32)
        let hashedToken = SHA256.hash(data: Data(token.utf8)).hex
        let refreshToken = RefreshToken(token: hashedToken, userID: try user.requireID())
        try await refreshToken.save(on: req.db)
        
        return (accessToken, token)
    }
}
