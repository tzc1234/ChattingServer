@testable import App
import XCTVapor
import Testing
import Fluent
import Vapor

@Suite("Authentication routes tests")
struct AuthenticationTests: AppTests, AvatarFileHelpers {
    @Test("register user failure with a short name")
    func registerUserWithShortName() async throws {
        let shortName = "a"
        let registerRequest = makeRegisterRequest(name: shortName)
        
        try await makeApp { app in
            try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "name is less than minimum of 3 character(s)")
            })
        }
    }
    
    @Test("register user failure with a short password")
    func registerUserWithShortPassword() async throws {
        let shortPassword = "p"
        let registerRequest = makeRegisterRequest(password: shortPassword)
        
        try await makeApp { app in
            try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "password is less than minimum of 3 character(s)")
            })
        }
    }
    
    @Test("register user failure with an invalid email")
    func registerUserWithInvalidEmail() async throws {
        let invalidEmail = "a.com"
        let registerRequest = makeRegisterRequest(email: invalidEmail)
        
        try await makeApp { app in
            try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "email is not a valid email address")
            })
        }
    }
    
    @Test("register user failure with an invalid avatar file type")
    func registerUserWithInvalidAvatarFileType() async throws {
        let fileData = "test".data(using: .utf8)!
        let file = File(data: .init(data: fileData), filename: "test.txt")
        let registerRequest = makeRegisterRequest(avatar: file)
        
        try await makeApp { app in
            try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .unsupportedMediaType)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Only accept .jpg, .jpeg, or .png files.")
            })
        }
    }
    
    @Test("register user failure with a too large avatar file")
    func registerUserWithLargeAvatarFile() async throws {
        try await makeApp { app in
            let largeAvatar = try largeImageFile(app)
            let registerRequest = makeRegisterRequest(avatar: largeAvatar)
            
            try await app.testable(method: .running(port: 8082)).test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest, as: .formData)
            }, afterResponse: { res async throws in
                #expect(res.status == .payloadTooLarge)
            })
        }
    }
    
    @Test("register user success")
    func registerUserSuccess() async throws {
        try await makeApp { app in
            let smallEnoughAvatar = try avatarFile(app)
            let registerRequest = makeRegisterRequest(avatar: smallEnoughAvatar)
            
            try await app.testable(method: .running).test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest, as: .formData)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let token = try res.content.decode(TokenResponse.self)
                #expect(token.user.name == registerRequest.name)
                #expect(token.user.email == registerRequest.email)
                #expect(token.user.avatarURL == uploadedAvatarLink(app: app))
            })
        } afterShutdown: {
            try removeUploadedAvatar(filename: testAvatarFileName)
        }
    }
    
    @Test("login failure with an non-exist user")
    func loginANonExistUser() async throws {
        let loginRequest = LoginRequest(email: "non-exist@email.com", password: "non-exist")
        
        try await makeApp { app in
            try await app.test(.POST, .apiPath("login"), beforeRequest: { req in
                try req.content.encode(loginRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .notFound)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "User not found")
            })
        }
    }
    
    @Test("login success and generate new tokens")
    func loginSuccess() async throws {
        let username = "a username"
        let password = "aPassword"
        let email = "a@email.com"
        let loginRequest = LoginRequest(email: email, password: password)
        
        try await makeApp { app in
            let oldToken = try await createTokenResponse(
                app,
                name: username,
                email: email,
                hashedPassword: password
            )
            
            try await app.test(.POST, .apiPath("login"), beforeRequest: { req in
                try req.content.encode(loginRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let newToken = try res.content.decode(TokenResponse.self)
                #expect(newToken.user == oldToken.user)
                #expect(newToken.accessToken != oldToken.accessToken, "Expect a new access token")
                #expect(newToken.refreshToken != oldToken.refreshToken, "Expect a new refresh token")
            })
        }
    }
    
    @Test("refresh token failure with an invalid refresh token")
    func refreshTokenFailureWithInvalidToken() async throws {
        let invalidRefreshToken = "invalid-refresh-token"
        let refreshTokenRequest = RefreshTokenRequest(refreshToken: invalidRefreshToken)
        
        try await makeApp { app in
            try await app.test(.POST, .apiPath("refreshToken"), beforeRequest: { req in
                try req.content.encode(refreshTokenRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Refresh token invalid")
            })
        }
    }
    
    @Test("refresh token failure with an expired refresh token")
    func refreshTokenFailureWithExpiredToken() async throws {
        try await makeApp { app in
            let expiredToken = "expired-token"
            try await createAnExpiredRefreshToken(app, token: expiredToken)
            let refreshTokenRequest = RefreshTokenRequest(refreshToken: expiredToken)
            
            try await app.test(.POST, .apiPath("refreshToken"), beforeRequest: { req in
                try req.content.encode(refreshTokenRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Refresh token invalid")
            })
        }
    }
    
    @Test("refresh token success")
    func refreshTokenSuccess() async throws {
        try await makeApp { app in
            let oldToken = try await createTokenResponse(app)
            let refreshTokenRequest = RefreshTokenRequest(refreshToken: oldToken.refreshToken)
            
            try await app.test(.POST, .apiPath("refreshToken"), beforeRequest: { req in
                try req.content.encode(refreshTokenRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let newToken = try res.content.decode(RefreshTokenResponse.self)
                #expect(newToken.accessToken != oldToken.accessToken, "Expect a new access token")
                #expect(newToken.refreshToken != oldToken.refreshToken, "Expect a new refresh token")
            })
        }
    }
    
    @Test("get current user failure with no access token")
    func getCurrentUserFailureWithNoAccessToken() async throws {
        try await makeApp { app in
            try await app.test(.GET, .apiPath("me"), afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "Access token invalid")
            })
        }
    }
    
    @Test("get current user failure with an expired payload")
    func getCurrentUserFailureWithExpiredPayload() async throws {
        try await makeApp { app in
            let user = try await createUser(app)
            let expiredPayload = try Payload(for: user, expiration: .distantPast)
            let expiredAccessToken = try await app.jwt.keys.sign(expiredPayload)
            
            try await app.test(.GET, .apiPath("me"), beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: expiredAccessToken)
            }, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            })
        }
    }
    
    @Test("get current user failure when user not found")
    func getCurrentUserFailureWhenUserNotFound() async throws {
        try await makeApp { app in
            let userNotFound = User(id: 1, name: "not found", email: "not-found@email.com", password: "aPassword")
            let notFoundPayload = try Payload(for: userNotFound)
            let notFoundAccessToken = try await app.jwt.keys.sign(notFoundPayload)
            
            try await app.test(.GET, .apiPath("me"), beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: notFoundAccessToken)
            }, afterResponse: { res async throws in
                #expect(res.status == .notFound)
                let error = try res.content.decode(ErrorResponse.self)
                #expect(error.reason == "User not found")
            })
        }
    }
    
    @Test("get current user success")
    func getCurrentUserSuccess() async throws {
        try await makeApp { app in
            let user = try await createUser(app)
            let payload = try Payload(for: user)
            let accessToken = try await app.jwt.keys.sign(payload)
            
            try await app.test(.GET, .apiPath("me"), beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let userResponse = try res.content.decode(UserResponse.self)
                #expect(userResponse.id == user.id)
                #expect(userResponse.name == user.name)
                #expect(userResponse.email == user.email)
            })
        }
    }
    
    // MARK: - Helpers
    
    private func makeApp(_ test: (Application) async throws -> (),
                         afterShutdown: () throws -> Void = {}) async throws {
        try await withApp(
            avatarFilename: { _ in testAvatarFileName },
            avatarDirectoryPath: testAvatarDirectoryPath,
            passwordHasher: UserPasswordHasherStub(),
            webSocketStore: WebSocketStore(),
            test,
            afterShutdown: afterShutdown
        )
    }
    
    private func createAnExpiredRefreshToken(_ app: Application, token: String) async throws {
        let user = try await createUser(app)
        let hashedRefreshToken = SHA256.hash(token)
        let refreshToken = RefreshToken(token: hashedRefreshToken, userID: user.id!, expiresAt: .distantPast)
        try await refreshToken.save(on: app.db)
    }
    
    private func makeRegisterRequest(name: String = "a username",
                                     email: String = "a@email.com",
                                     password: String = "aPassword",
                                     avatar: File? = nil) -> RegisterRequest {
        RegisterRequest(name: name, email: email, password: password, avatar: avatar)
    }
    
    private func uploadedAvatarLink(app: Application) -> String {
        let baseURL = app.http.server.configuration.hostname
        let port = app.http.server.configuration.port
        return "http://\(baseURL):\(port)/\(testAvatarDirectory)/\(testAvatarFileName)"
    }
    
    private var testAvatarFileName: String {
        "test_avatar.png"
    }
    
    private func largeImageFile(_ app: Application) throws -> File {
        let fileURL = URL(fileURLWithPath: testResourceDirectory(app) + "more_than_2mb.jpg")
        let fileData = try Data(contentsOf: fileURL)
        return File(data: .init(data: fileData), filename: "more_than_2mb.jpg")
    }
    
    private actor UserPasswordHasherStub: UserPasswordHasher {
        func hash(_ password: String) async throws -> String {
            password
        }
        
        func verify(_ password: String, hashed: String) async throws -> Bool {
            true
        }
    }
}
