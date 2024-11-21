import Fluent

struct CreateMessage: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(schema)
            .field("id", .int, .identifier(auto: true))
            .field("contact_id", .int, .required, .references("contacts", "id", onDelete: .cascade))
            .field("sender_id", .int, .required, .references("users", "id", onDelete: .cascade))
            .field("text", .string, .required)
            .field("is_read", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime, .required)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(schema).delete()
    }
    
    private var schema: String { Message.schema }
}
