import Vapor

struct AuthenticationController: RouteCollection, Sendable {
    private let userRepository: UserRepository
    private let refreshTokenRepository: RefreshTokenRepository
    private let avatarLinkLoader: AvatarLinkLoader
    private let avatarFilename: @Sendable (String) -> (String)
    private let avatarDirectoryPath: @Sendable () -> (String)
    
    init(userRepository: UserRepository,
         refreshTokenRepository: RefreshTokenRepository,
         avatarLinkLoader: AvatarLinkLoader,
         avatarFilename: @escaping @Sendable (String) -> String,
         avatarDirectoryPath: @escaping @Sendable () -> String) {
        self.userRepository = userRepository
        self.refreshTokenRepository = refreshTokenRepository
        self.avatarLinkLoader = avatarLinkLoader
        self.avatarFilename = avatarFilename
        self.avatarDirectoryPath = avatarDirectoryPath
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
        let request = try req.content.decode(RegisterRequest.self)
        
        var savedAvatarFilename: String?
        if let avatar = request.avatar {
            let filename = avatar.filename
            if !(filename.lowercased().hasSuffix(".jpg") ||
                 filename.lowercased().hasSuffix(".jpeg") ||
                 filename.lowercased().hasSuffix(".png")) {
                throw Abort(.unsupportedMediaType, reason: "Only accept .jpg, .jpeg, or .png files.")
            }
            
            let avatarFilename = avatarFilename(filename)
            let directoryPath = avatarDirectoryPath()
            if !FileManager.default.fileExists(atPath: directoryPath) {
                try FileManager.default.createDirectory(
                    atPath: directoryPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
            try await req.fileio.writeFile(avatar.data, at: directoryPath + avatarFilename)
            
            savedAvatarFilename = avatarFilename
        }
        
        let user = request.toModel()
        user.password = try await req.password.async.hash(user.password)
        user.avatarFilename = savedAvatarFilename
        try await userRepository.create(user)
        
        return try await newTokenResponse(for: user, req: req)
    }
    
    @Sendable
    private func login(req: Request) async throws -> TokenResponse {
        let loginRequest = try req.content.decode(LoginRequest.self)
        guard let user = try await userRepository.findBy(email: loginRequest.email),
                try await req.password.async.verify(loginRequest.password, created: user.password)
        else {
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
                refreshToken.expiresAt > .now
        else {
            throw AuthenticationError.refreshTokenInvalid
        }
        
        let user = try await refreshTokenRepository.getUserFrom(refreshToken)
        try await refreshTokenRepository.delete(refreshToken)
        
        let (newAccessToken, newRefreshToken) = try await newTokens(for: user, req: req)
        return RefreshTokenResponse(accessToken: newAccessToken, refreshToken: newRefreshToken)
    }
    
    private func newTokenResponse(for user: User, req: Request) async throws -> TokenResponse {
        let (accessToken, refreshToken) = try await newTokens(for: user, req: req)
        return TokenResponse(
            user: user.toResponse(avatarLink: avatarLinkLoader.get),
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }
    
    private func newTokens(for user: User, req: Request) async throws -> (accessToken: String, refreshToken: String) {
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
        
        return user.toResponse(avatarLink: avatarLinkLoader.get)
    }
}
