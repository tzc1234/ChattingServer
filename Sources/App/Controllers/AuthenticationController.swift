import Vapor

struct AuthenticationController {
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
        do {
            user.password = try await passwordHasher.hash(user.password)
            user.avatarFilename = savedAvatarFilename
            try await userRepository.create(user)
        } catch {
            if let savedAvatarFilename {
                try? await avatarFileSaver.delete(savedAvatarFilename)
            }
            
            throw error
        }
        
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
        return TokenResponse(
            user: try await makeUserResponse(by: user),
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
        
        return try await makeUserResponse(by: user)
    }
    
    @Sendable
    private func updateCurrentUser(req: Request) async throws -> UserResponse {
        try UpdateUserRequest.validate(content: req)
        let request = try req.content.decode(UpdateUserRequest.self)
        let userID = try req.auth.require(Payload.self).userID
        guard let user = try await userRepository.findBy(id: userID) else { throw AuthenticationError.userNotFound }
        
        user.name = request.name
        let oldAvatarFilename = user.avatarFilename
        var newAvatarFilename: String?
        
        if let avatar = request.avatar {
            do {
                newAvatarFilename = try await avatarFileSaver.save(avatar)
                user.avatarFilename = newAvatarFilename
            } catch let error as AvatarFileSaver.Error {
                throw Abort(.unsupportedMediaType, reason: error.reason)
            } catch {
                throw error
            }
        }
        
        do {
            // Make sure user update success before delete the old avatar.
            try await user.update(on: req.db)
            if let oldAvatarFilename, newAvatarFilename != nil {
                try? await avatarFileSaver.delete(oldAvatarFilename)
            }
        } catch {
            // Delete the new avatar file if user update error occurred.
            if let newAvatarFilename { try? await avatarFileSaver.delete(newAvatarFilename) }
            throw error
        }
        
        return try await makeUserResponse(by: user)
    }
    
    @Sendable
    private func makeUserResponse(by user: User) async throws -> UserResponse {
        try await user.toResponse { [weak avatarLinkLoader] filename in
            guard let filename else { return nil }
            
            return await avatarLinkLoader?.get(filename: filename)
        }
    }
    
    @Sendable
    private func updateDeviceToken(req: Request) async throws -> Response {
        try UpdateDeviceTokenRequest.validate(content: req)
        let deviceToken = try req.content.decode(UpdateDeviceTokenRequest.self).deviceToken
        let userID = try req.auth.require(Payload.self).userID
        guard let user = try await userRepository.findBy(id: userID) else {
            throw AuthenticationError.userNotFound
        }
        
        if user.deviceToken != deviceToken {
            try await userRepository.remove(deviceToken)
            user.deviceToken = deviceToken
            try await user.update(on: req.db)
        }
        
        return Response()
    }
}

extension AuthenticationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.on(.POST, "register", body: .collect(maxSize: Constants.REGISTER_PAYLOAD_MAX_SIZE), use: register)
        routes.post("login", use: login)
        routes.post("refreshToken", use: refreshToken)
        
        routes.grouped("me")
            .group(AccessTokenGuardMiddleware(), UserAuthenticator()) { route in
                route.get(use: getCurrentUser)
                route.on(.PUT, body: .collect(maxSize: Constants.REGISTER_PAYLOAD_MAX_SIZE), use: updateCurrentUser)
                route.post("deviceToken", use: updateDeviceToken)
            }
    }
}
