@testable import App
import XCTVapor
import Testing
import Fluent
import Vapor

@Suite("Authentication routes tests", .serialized)
struct AuthenticationTests: AppTests {
    @Test("register user failure with short name")
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
    
    @Test("register user failure with short password")
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
    
    @Test("register user failure with invalid email")
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
    
    @Test("register user failure with invalid avatar file type")
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
    
    @Test("register user failure with too large avatar file")
    func registerUserWithLargeAvatarFile() async throws {
        try await makeApp { app in
            let largeAvatar = try largeImageFile(app)
            let registerRequest = makeRegisterRequest(avatar: largeAvatar)
            
            try await app.testable(method: .running).test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest, as: .formData)
            }, afterResponse: { res async throws in
                #expect(res.status == .payloadTooLarge)
            })
        }
    }
    
    @Test("register user success")
    func registerUserSuccess() async throws {
        try await makeApp { app in
            let smallAvatar = try smallImageFile(app)
            let registerRequest = makeRegisterRequest(avatar: smallAvatar)
            
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
            try removeUploadedAvatars()
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
    
    // MARK: - Helpers
    
    private func makeApp(_ test: (Application) async throws -> (),
                         afterShutdown: () throws -> Void = {}) async throws {
        try await withApp(
            avatarFilename: { _ in testAvatarFileName },
            avatarDirectoryPath: { testAvatarDirectoryPath() },
            webSocketStore: WebSocketStore(),
            test,
            afterShutdown: afterShutdown
        )
    }
    
    private func makeRegisterRequest(name: String = "a name",
                                     email: String = "a@email.com",
                                     password: String = "password123",
                                     avatar: File? = nil) -> RegisterRequest {
        RegisterRequest(name: name, email: email, password: password, avatar: avatar)
    }
    
    private func removeUploadedAvatars() throws {
        let path = testAvatarDirectoryPath()
        guard FileManager.default.fileExists(atPath: path) else { return }
            
        try FileManager.default.removeItem(atPath: path)
    }
    
    private func uploadedAvatarLink(app: Application) -> String {
        let baseURL = app.http.server.configuration.hostname
        let port = app.http.server.configuration.port
        return "http://\(baseURL):\(port)/\(testAvatarDirectory)/\(testAvatarFileName)"
    }
    
    private func testAvatarDirectoryPath() -> String {
        let components = URL.temporaryDirectory.appending(component: testAvatarDirectory).absoluteString.pathComponents
        let directoryPath = components.dropFirst().map(\.description).joined(separator: "/")
        return "/\(directoryPath)/"
    }
    
    private var testAvatarFileName: String {
        "test_avatar.png"
    }
    
    private var testAvatarDirectory: String {
        "uploaded_avatars"
    }
    
    private func smallImageFile(_ app: Application) throws -> File {
        let fileURL = URL(fileURLWithPath: testResourceDirectory(app) + "small_avatar.png")
        let fileData = try Data(contentsOf: fileURL)
        return File(data: .init(data: fileData), filename: "small_avatar.png")
    }
    
    private func largeImageFile(_ app: Application) throws -> File {
        let fileURL = URL(fileURLWithPath: testResourceDirectory(app) + "more_than_2mb.jpg")
        let fileData = try Data(contentsOf: fileURL)
        return File(data: .init(data: fileData), filename: "more_than_2mb.jpg")
    }
    
    private func testResourceDirectory(_ app: Application) -> String {
        app.directory.workingDirectory + "Tests/AppTests/Resources/"
    }
}
