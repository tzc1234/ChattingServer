import Fluent

struct CreateRefreshToken: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(schema)
            .field("id", .int, .identifier(auto: true))
            .field("token", .string, .required)
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("issued_at", .datetime, .required)
            .field("expires_at", .datetime, .required)
            .unique(on: "token")
            .unique(on: "user_id")
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(schema).delete()
    }
    
    private var schema: String { RefreshToken.schema }
}
