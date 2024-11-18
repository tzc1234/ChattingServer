import Fluent

struct CreateMessage: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("messages")
            .field("id", .int, .identifier(auto: true))
            .field("contact_id", .int, .required, .references("contacts", "id", onDelete: .cascade))
            .field("sender_id", .int, .required, .references("users", "id", onDelete: .cascade))
            .field("text", .string, .required)
            .field("created_by", .datetime, .required)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("messages").delete()
    }
}
