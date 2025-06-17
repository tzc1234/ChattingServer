//
//  AddDeletedAtToMessage.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 17/06/2025.
//

import Fluent

struct AddDeletedAtToMessage: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(schema)
            .field("deleted_at", .datetime)
            .update()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(schema)
            .deleteField("deleted_at")
            .update()
    }
    
    private var schema: String { Message.schema }
}
