//
//  CreateMessageEditHistory.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 10/06/2025.
//

import Fluent

struct CreateMessageEditHistory: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(schema)
            .field("id", .int, .identifier(auto: true))
            .field("message_id", .int, .required, .references("messages", "id", onDelete: .cascade))
            .field("previous_text", .string, .required)
            .field("new_text", .string, .required)
            .field("edited_at", .datetime, .required)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(schema).delete()
    }
    
    private var schema: String { MessageEditHistory.schema }
}
