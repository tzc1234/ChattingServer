import Vapor

struct AuthenticationController: RouteCollection {
    private let userRepository: UserRepository
    private let refreshTokenRepository: RefreshTokenRepository
    private let avatarFileSaver: AvatarFileSaver
    private let avatarLinkLoader: AvatarLinkLoader
    private let passwordHasher: UserPasswordHasher
    
    init(userRepository: UserRepository,
         refreshTokenRepository: RefreshTokenRepository,
         avatarFileSaver: AvatarFileSaver,
         avatarLinkLoader: AvatarLinkLoader,
         passwordHasher: UserPasswordHasher) {
        self.userRepository = userRepository
        self.refreshTokenRepository = refreshTokenRepository
        self.avatarFileSaver = avatarFileSaver
        self.avatarLinkLoader = avatarLinkLoader
        self.passwordHasher = passwordHasher
    }
    
    func boot(routes: RoutesBuilder) throws {
        routes.on(.POST, "register", body: .collect(maxSize: "1mb"), use: register)
        routes.post("login", use: login)
        routes.post("refreshToken", use: refreshToken)
        
        routes.grouped("me")
            .group(AccessTokenGuardMiddleware(), UserAuthenticator()) { route in
                route.get(use: getCurrentUser)
            }
    }
    
    @Sendable
    private func register(req: Request) async throws -> TokenResponse {
        try RegisterRequest.validate(content: req)
        let registerRequest = try req.content.decode(RegisterRequest.self)
        
        var savedAvatarFilename: String?
        if let avatar = registerRequest.avatar {
            do {
                savedAvatarFilename = try await avatarFileSaver.save(avatar)
            } catch let error as AvatarFileSaver.Error {
                throw Abort(.unsupportedMediaType, reason: error.reason)
            } catch {
                throw error
            }
        }
        
        let user = registerRequest.toUserModel()
        user.password = try await passwordHasher.hash(user.password)
        user.avatarFilename = savedAvatarFilename
        try await userRepository.create(user)
        
        return try await newTokenResponse(for: user, req: req)
    }
    
    @Sendable
    private func login(req: Request) async throws -> TokenResponse {
        let loginRequest = try req.content.decode(LoginRequest.self)
        guard let user = try await userRepository.findBy(email: loginRequest.email),
              try await passwordHasher.verify(loginRequest.password, hashed: user.password) else {
            throw AuthenticationError.userNotFound
        }
        
        try await refreshTokenRepository.deleteBy(userID: user.requireID())
        
        return try await newTokenResponse(for: user, req: req)
    }
    
    @Sendable
    private func refreshToken(req: Request) async throws -> RefreshTokenResponse {
        let refreshRequest = try req.content.decode(RefreshTokenRequest.self)
        let hashedRefreshToken = SHA256.hash(refreshRequest.refreshToken)
        
        guard let refreshToken = try await refreshTokenRepository.findBy(token: hashedRefreshToken),
                refreshToken.expiresAt > .now else {
            throw AuthenticationError.refreshTokenInvalid
        }
        
        let user = try await refreshTokenRepository.getUserFrom(refreshToken)
        try await refreshTokenRepository.delete(refreshToken)
        
        let (newAccessToken, newRefreshToken) = try await generateNewTokens(for: user, req: req)
        return RefreshTokenResponse(accessToken: newAccessToken, refreshToken: newRefreshToken)
    }
    
    private func newTokenResponse(for user: User, req: Request) async throws -> TokenResponse {
        let (accessToken, refreshToken) = try await generateNewTokens(for: user, req: req)
        return await TokenResponse(
            user: user.toResponse { [weak avatarLinkLoader] filename in
                guard let filename else { return nil }
                
                return await avatarLinkLoader?.get(filename: filename)
            },
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }
    
    private func generateNewTokens(for user: User,
                                   req: Request) async throws -> (accessToken: String, refreshToken: String) {
        let accessToken = try await req.jwt.sign(Payload(for: user))
        
        let token = RandomGenerator.generate(bytes: 32)
        let hashedToken = SHA256.hash(token)
        let refreshToken = RefreshToken(token: hashedToken, userID: try user.requireID())
        try await refreshTokenRepository.create(refreshToken)
        
        return (accessToken, token)
    }
    
    @Sendable
    private func getCurrentUser(req: Request) async throws -> UserResponse {
        let userID = try req.auth.require(Payload.self).userID
        guard let user = try await userRepository.findBy(id: userID) else {
            throw AuthenticationError.userNotFound
        }
        
        return await user.toResponse { [weak avatarLinkLoader] filename in
            guard let filename else { return nil }
            
            return await avatarLinkLoader?.get(filename: filename)
        }
    }
}
