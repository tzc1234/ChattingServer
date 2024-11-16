import Fluent
import Vapor

struct AuthenticationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.group("register") { registerRoute in
            registerRoute.post(use: register)
        }
        
        routes.group("login") { loginRoute in
            loginRoute.post(use: login)
        }
        
        routes.grouped("me")
            .grouped(AccessTokenGuardMiddleware())
            .group(UserAuthenticator()) { route in
                route.get(use: getCurrentUser)
            }
        
        routes.group("refreshToken") { route in
            route.post(use: refreshToken)
        }
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
    
    @Sendable
    private func refreshToken(req: Request) async throws -> RefreshTokenResponse {
        let refreshRequest = try req.content.decode(RefreshTokenRequest.self)
        let hashedRefreshToken = SHA256.hash(data: Data(refreshRequest.refreshToken.utf8)).hex
        
        guard let refreshToken = try await RefreshToken.query(on: req.db)
            .filter(\.$token == hashedRefreshToken)
            .first()
        else {
            throw Abort(.unauthorized, reason: "refresh token invalid", identifier: "refresh_token_invalid")
        }
        
        guard refreshToken.expiresAt > .now else {
            throw Abort(.unauthorized, reason: "refresh token expired", identifier: "refresh_token_expired")
        }
        
        let user = try await refreshToken.$user.get(on: req.db)
        try await refreshToken.delete(on: req.db)
        
        let (newAccessToken, newRefreshToken) = try await newTokens(for: user, req: req)
        return RefreshTokenResponse(accessToken: newAccessToken, refreshToken: newRefreshToken)
    }
    
    private func newTokenResponse(for user: User, req: Request) async throws -> TokenResponse {
        let (accessToken, refreshToken) = try await newTokens(for: user, req: req)
        return TokenResponse(user: user.toResponse(), accessToken: accessToken, refreshToken: refreshToken)
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
