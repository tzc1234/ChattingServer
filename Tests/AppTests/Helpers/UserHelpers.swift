import Vapor
import Testing
@testable import App

func createUser(_ app: Application,
                name: String = "a username",
                email: String = "a@email.com",
                password: String = "aPassword") async throws -> User {
    let user = User(name: name, email: email, password: password)
    try await user.save(on: app.db)
    return user
}

func createUserForTokenResponse(_ app: Application,
                                name: String = "a username",
                                email: String = "a@email.com",
                                password: String = "aPassword",
                                avatar: File? = nil) async throws -> TokenResponse {
    let registerRequest = RegisterRequest(name: name, email: email, password: password, avatar: avatar)
    var tokenResponse: TokenResponse?
    
    try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
        try req.content.encode(registerRequest)
    }, afterResponse: { res async throws in
        tokenResponse = try res.content.decode(TokenResponse.self)
    })
    
    return tokenResponse!
}

func createUserAndAccessToken(_ app: Application,
                              sourceLocation: SourceLocation = #_sourceLocation) async throws
-> (user: User, accessToken: String) {
    let token = try await createUserForTokenResponse(app)
    let currentUser = try #require(try await User.find(token.user.id!, on: app.db), sourceLocation: sourceLocation)
    return (currentUser, token.accessToken)
}
