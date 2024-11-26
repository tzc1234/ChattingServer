import Fluent
import Vapor

struct AuthenticationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.on(.POST, "register", body: .collect(maxSize: "1mb"), use: register)
        
        routes.group("login") { loginRoute in
            loginRoute.post(use: login)
        }
        
        routes.group("refreshToken") { route in
            route.post(use: refreshToken)
        }
        
        routes.grouped("me")
            .grouped(AccessTokenGuardMiddleware())
            .group(UserAuthenticator()) { route in
                route.get(use: getCurrentUser)
            }
    }
    
    @Sendable
    private func register(req: Request) async throws -> TokenResponse {
        try RegisterRequest.validate(content: req)
        let request = try req.content.decode(RegisterRequest.self)
        
        var savedAvatarFilename: String?
        if let avatar = request.avatar {
            let filename = avatar.filename
            if !(filename.lowercased().hasSuffix(".jpg") ||
                 filename.lowercased().hasSuffix(".jpeg") ||
                 filename.lowercased().hasSuffix(".png")) {
                throw Abort(.unsupportedMediaType, reason: "Only accept .jpg, .jpeg, or .png files.")
            }
            
            let imageFilename = "\(Date().timeIntervalSince1970)_\(filename)"
            let imageFilePath = req.application.directory.publicDirectory + Constants.AVATARS_DIRECTORY + imageFilename
            try await req.fileio.writeFile(avatar.data, at: imageFilePath)
            
            savedAvatarFilename = imageFilename
        }
        
        let user = request.toModel()
        user.password = try await req.password.async.hash(user.password)
        user.avatarFilename = savedAvatarFilename
        try await user.save(on: req.db)
        
        return try await newTokenResponse(for: user, req: req)
    }
    
    @Sendable
    private func login(req: Request) async throws -> TokenResponse {
        let loginRequest = try req.content.decode(LoginRequest.self)
        
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == loginRequest.email)
            .first(), try await req.password.async.verify(loginRequest.password, created: user.password)
        else {
            throw AuthenticationError.userNotFound
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
        let hashedRefreshToken = SHA256.hash(refreshRequest.refreshToken)
        
        guard let refreshToken = try await RefreshToken.query(on: req.db)
            .filter(\.$token == hashedRefreshToken)
            .first(), refreshToken.expiresAt > .now
        else {
            throw AuthenticationError.refreshTokenInvalid
        }
        
        let user = try await refreshToken.$user.get(on: req.db)
        try await refreshToken.delete(on: req.db)
        
        let (newAccessToken, newRefreshToken) = try await newTokens(for: user, req: req)
        return RefreshTokenResponse(accessToken: newAccessToken, refreshToken: newRefreshToken)
    }
    
    private func newTokenResponse(for user: User, req: Request) async throws -> TokenResponse {
        let (accessToken, refreshToken) = try await newTokens(for: user, req: req)
        return TokenResponse(
            user: user.toResponse(app: req.application),
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }
    
    private func newTokens(for user: User, req: Request) async throws -> (accessToken: String, refreshToken: String) {
        let accessToken = try await req.jwt.sign(Payload(for: user))
        
        let token = RandomGenerator.generate(bytes: 32)
        let hashedToken = SHA256.hash(token)
        let refreshToken = RefreshToken(token: hashedToken, userID: try user.requireID())
        try await refreshToken.save(on: req.db)
        
        return (accessToken, token)
    }
    
    @Sendable
    private func getCurrentUser(req: Request) async throws -> UserResponse {
        let payload = try req.auth.require(Payload.self)
        guard let user = try await User.find(payload.userID, on: req.db) else {
            throw AuthenticationError.userNotFound
        }
        
        return user.toResponse(app: req.application)
    }
}
