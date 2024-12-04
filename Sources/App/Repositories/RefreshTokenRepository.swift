import Fluent

actor RefreshTokenRepository {
    private let database: Database
    
    init(database: Database) {
        self.database = database
    }
    
    func create(_ refreshToken: RefreshToken) async throws {
        try await refreshToken.create(on: database)
    }
    
    func findBy(userID: Int) async throws -> RefreshToken? {
        try await RefreshToken.query(on: database)
            .filter(\.$user.$id == userID)
            .first()
    }
    
    func findBy(token: String) async throws -> RefreshToken? {
        try await RefreshToken.query(on: database)
            .filter(\.$token == token)
            .first()
    }
    
    func getUserFrom(_ refreshToken: RefreshToken) async throws -> User {
        try await refreshToken.$user.get(on: database)
    }
    
    func delete(_ refreshToken: RefreshToken) async throws {
        try await refreshToken.delete(on: database)
    }
    
    func deleteBy(userID: Int) async throws {
        try await findBy(userID: userID)?.delete(on: database)
    }
}
