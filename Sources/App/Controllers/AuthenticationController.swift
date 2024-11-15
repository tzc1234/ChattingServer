import Fluent
import Vapor

struct AuthenticationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let registerRoute = routes.grouped("register")
        registerRoute.post(use: register)
        
        let loginRoute = routes.grouped("login")
        loginRoute.post(use: login)
        
        let meRoute = routes.grouped("me")
            .grouped(JWTUserAuthenticator())
        meRoute.get(use: getCurrentUser)
    }
    
    @Sendable
    private func register(req: Request) async throws -> TokenResponse {
        try RegisterRequest.validate(content: req)
        
        let user = try req.content.decode(RegisterRequest.self).toModel()
        user.password = try await req.password.async.hash(user.password)
        try await user.save(on: req.db)
        
        return try await newTokenResponse(for: user, req: req)
    }
    
    @Sendable
    private func getCurrentUser(req: Request) async throws -> UserResponse {
        let payload = try req.auth.require(Payload.self)
        guard let user = try await User.find(payload.userID, on: req.db) else {
            throw Abort(.notFound, reason: "User was not found", identifier: "user_not_found")
        }
        
        return UserResponse(id: try user.requireID(), name: user.name, email: user.email)
    }
    
    @Sendable
    private func login(req: Request) async throws -> TokenResponse {
        let loginRequest = try req.content.decode(LoginRequest.self)
        
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == loginRequest.email)
            .first(), try await req.password.async.verify(loginRequest.password, created: user.password)
        else {
            throw Abort(.notFound, reason: "User was not found", identifier: "user_not_found")
        }
        
        if let oldRefreshToken = try await RefreshToken.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .first() {
            try await oldRefreshToken.delete(on: req.db)
        }
        
        return try await newTokenResponse(for: user, req: req)
    }
    
    private func newTokenResponse(for user: User, req: Request) async throws -> TokenResponse {
        let accessToken = try await req.jwt.sign(Payload(for: user))
        
        let token = RandomGenerator.generate(bytes: 32)
        let hashedToken = SHA256.hash(data: Data(token.utf8)).hex
        let refreshToken = RefreshToken(token: hashedToken, userID: try user.requireID())
        try await refreshToken.save(on: req.db)
        
        return TokenResponse(user: user.toResponse(), accessToken: accessToken, refreshToken: token)
    }
}
