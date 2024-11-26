@testable import App
import XCTVapor
import Testing
import Fluent

@Suite("Authenication routes tests")
struct AuthenicationTests: AppTests {
    @Test("register user failure with short name")
    func registerUserWithShortName() async throws {
        let shortName = "a"
        let registerRequest = makeRegisterRequest(name: shortName)
        
        try await withApp { app in
            try await app.test(.POST, "api/v1/register", beforeRequest: { req in
                try req.content.encode(registerRequest)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let error = try res.content.decode(ErrorData.self)
                #expect(error.reason == "name is less than minimum of 3 character(s)")
            })
        }
    }
    
    // MARK: - Helpers
    private func makeRegisterRequest(name: String = "a name",
                                     email: String = "a@email.com",
                                     password: String = "password123",
                                     avatar: File? = nil) -> RegisterRequest {
        RegisterRequest(id: nil, name: name, email: email, password: password, avatar: avatar)
    }
}
