import Vapor

protocol UserPasswordHasher: Sendable {
    func hash(_ password: String) async throws -> String
    func verify(_ password: String, hashed: String) async throws -> Bool
}

actor DefaultUserPasswordHasher: UserPasswordHasher {
    private let application: Application
    
    init(application: Application) {
        self.application = application
    }
    
    func hash(_ password: String) async throws -> String {
        try await application.password.async.hash(password)
    }
    
    func verify(_ password: String, hashed: String) async throws -> Bool {
        try await application.password.async.verify(password, created: hashed)
    }
}
