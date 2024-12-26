import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(schema)
            .field("id", .int, .identifier(auto: true))
            .field("name", .string, .required)
            .field("email", .string, .required, .custom("COLLATE NOCASE"))
            .field("password", .string, .required)
            .field("avatar_filename", .string)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "email")
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(schema).delete()
    }
    
    private var schema: String { User.schema }
}
