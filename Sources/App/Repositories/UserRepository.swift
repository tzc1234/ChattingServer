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
    
    func removeDeviceToken(_ deviceToken: String) async throws {
        let users = try await User.query(on: database)
            .filter(\.$deviceToken == deviceToken)
            .all()
            
        for user in users {
            user.deviceToken = nil
            try await user.update(on: database)
        }
    }
}
