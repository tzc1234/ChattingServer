//
//  AddEditedAtToMessage.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 10/06/2025.
//

import Fluent

struct AddEditedAtToMessage: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(schema)
            .field("edited_at", .datetime)
            .update()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(schema)
            .deleteField("edited_at")
            .update()
    }
    
    private var schema: String { Message.schema }
}
