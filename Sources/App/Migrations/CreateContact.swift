import Fluent

struct CreateContact: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(schema)
            .field("id", .int, .identifier(auto: true))
            .field("user_id1", .int, .required, .references("users", "id", onDelete: .cascade))
            .field("user_id2", .int, .required, .references("users", "id", onDelete: .cascade))
            .field("blocked_by_user_id", .int, .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime, .required)
            .unique(on: "user_id1", "user_id2")
            .constraint(.custom("CHECK(user_id1 < user_id2)"))
            .constraint(.custom("CHECK(blocked_by_user_id = user_id1 OR blocked_by_user_id = user_id2)"))
            .create()
    }
    
    func revert(on database: any FluentKit.Database) async throws {
        try await database.schema(schema).delete()
    }
    
    private var schema: String { Contact.schema }
}
