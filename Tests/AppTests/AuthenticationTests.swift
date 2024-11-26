@testable import App
import XCTVapor
import Testing
import Fluent
import Vapor

@Suite("Authenication routes tests")
struct AuthenicationTests: AppTests {
    @Test("register user failure with short name")
    func registerUserWithShortName() async throws {
        let shortName = "a"
        let registerRequest = makeRegisterRequest(name: shortName)
        
        try await withApp { app in
            try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorData.self)
                #expect(error.reason == "name is less than minimum of 3 character(s)")
            })
        }
    }
    
    @Test("register user failure with short password")
    func registerUserWithShortPassword() async throws {
        let shortPassword = "p"
        let registerRequest = makeRegisterRequest(password: shortPassword)
        
        try await withApp { app in
            try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorData.self)
                #expect(error.reason == "password is less than minimum of 3 character(s)")
            })
        }
    }
    
    @Test("register user failure with invalid email")
    func registerUserWithInvalidEmail() async throws {
        let invalidEmail = "a.com"
        let registerRequest = makeRegisterRequest(email: invalidEmail)
        
        try await withApp { app in
            try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorData.self)
                #expect(error.reason == "email is not a valid email address")
            })
        }
    }
    
    @Test("register user failure with invalid avatar file type")
    func registerUserWithInvalidAvatarFileType() async throws {
        let fileData = "test".data(using: .utf8)!
        let file = File(data: .init(data: fileData), filename: "test.txt")
        let registerRequest = makeRegisterRequest(avatar: file)
        
        try await withApp { app in
            try await app.test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .unsupportedMediaType)
                let error = try res.content.decode(ErrorData.self)
                #expect(error.reason == "Only accept .jpg, .jpeg, or .png files.")
            })
        }
    }
    
    @Test("register user failure with too large avatar file")
    func registerUserWithLargeAvatarFile() async throws {
        try await withApp { app in
            let file = try largeImageFile(app)
            let registerRequest = makeRegisterRequest(avatar: file)
            
            try await app.testable(method: .running).test(.POST, .apiPath("register"), beforeRequest: { req in
                try req.content.encode(registerRequest, as: .formData)
            }, afterResponse: { res async throws in
                #expect(res.status == .payloadTooLarge)
            })
        }
    }
    
    // MARK: - Helpers
    
    private func makeRegisterRequest(name: String = "a name",
                                     email: String = "a@email.com",
                                     password: String = "password123",
                                     avatar: File? = nil) -> RegisterRequest {
        RegisterRequest(name: name, email: email, password: password, avatar: avatar)
    }
    
    private func largeImageFile(_ app: Application) throws -> File {
        let fileURL = URL(fileURLWithPath: testResourceDirectory(app) + "more_than_2mb.jpg")
        let fileData = try Data(contentsOf: fileURL)
        return File(data: .init(data: fileData), filename: "more_than_2mb.jpg")
    }
    
    private func testResourceDirectory(_ app: Application) -> String {
        app.directory.workingDirectory + "/Tests/AppTests/Resources/"
    }
}
