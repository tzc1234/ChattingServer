import Fluent

struct CreateRefreshToken: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("refresh_tokens")
            .id()
            .field("token", .string, .required)
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("issued_at", .date)
            .field("expires_at", .date)
            .unique(on: "token")
            .unique(on: "user_id")
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("tokens").delete()
    }
}
