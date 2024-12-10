import Fluent

actor UserRepository {
    private let database: Database
    
    init(database: Database) {
        self.database = database
    }
    
    func create(_ user: User) async throws {
        try await user.create(on: database)
    }
    
    func findBy(id: Int) async throws -> User? {
        try await User.find(id, on: database)
    }
    
    func findBy(email: String) async throws -> User? {
        try await User.query(on: database)
            .filter(\.$email == email)
            .first()
    }
}
