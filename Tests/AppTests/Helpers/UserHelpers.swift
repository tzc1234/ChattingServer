import Vapor
import Testing
@testable import App

func createUser(_ app: Application,
                name: String = "a username",
                email: String = "a@email.com",
                hashedPassword: String = "aPassword") async throws -> User {
    let user = User(name: name, email: email, password: hashedPassword)
    try await user.save(on: app.db)
    return user
}

func createUserForTokenResponse(_ app: Application,
                                name: String = "a username",
                                email: String = "a@email.com",
                                hashedPassword: String = "aPassword",
                                avatar: File? = nil) async throws -> TokenResponse {
    let registerRequest = RegisterRequest(name: name, email: email, password: hashedPassword, avatar: avatar)
    var tokenResponse: TokenResponse?
    
    try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
        try req.content.encode(registerRequest)
    }, afterResponse: { res async throws in
        tokenResponse = try res.content.decode(TokenResponse.self)
    })
    
    return tokenResponse!
}

func createUserAndTokenResponse(_ app: Application,
                                name: String = "a username",
                                email: String = "a@email.com",
                                hashedPassword: String = "aPassword",
                                avatarLink: (String?) async -> String? = {_ in nil}) async throws -> TokenResponse {
    let user = try await createUser(app, name: name, email: email, hashedPassword: hashedPassword)
    let (accessToken, refreshToken) = try await generateTokens(for: user, app)
    return await TokenResponse(
        user: user.toResponse(avatarLink: avatarLink),
        accessToken: accessToken,
        refreshToken: refreshToken
    )
}

private func generateTokens(for user: User,
                            _ app: Application) async throws -> (accessToken: String, refreshToken: String) {
    let accessToken = try await app.jwt.keys.sign(Payload(for: user))
    
    let token = RandomGenerator.generate(bytes: 32)
    let hashedToken = SHA256.hash(token)
    let refreshToken = RefreshToken(token: hashedToken, userID: try user.requireID())
    try await refreshToken.create(on: app.db)
    
    return (accessToken, token)
}

func createUserAndAccessToken(_ app: Application,
                              name: String = "a username",
                              email: String = "a@email.com",
                              hashedPassword: String = "aPassword") async throws -> (user: User, accessToken: String) {
    let user = try await createUser(app, name: name, email: email, hashedPassword: hashedPassword)
    let accessToken = try await app.jwt.keys.sign(Payload(for: user))
    return (user, accessToken)
}
