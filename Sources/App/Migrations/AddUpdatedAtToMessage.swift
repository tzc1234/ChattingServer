//
//  AddUpdatedAtToMessage.swift
//  ChattingServer
//
//  Created by Tsz-Lung on 16/06/2025.
//

import Fluent
import SQLKit

struct AddUpdatedAtToMessage: AsyncMigration {
    enum Error: Swift.Error {
        case databaseConversion
    }
    
    func prepare(on database: Database) async throws {
        try await database.schema(schema)
            .field("updated_at", .datetime)
            .update()
            
        guard let sqlDatabase = database as? SQLDatabase else { throw Error.databaseConversion }
        
        let sql: SQLQueryString = """
            UPDATE messages
            SET updated_at = IFNULL(edited_at, created_at)
            WHERE updated_at IS NULL
        """
        try await sqlDatabase.raw(sql).run()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(schema)
            .deleteField("updated_at")
            .update()
    }
    
    private var schema: String { Message.schema }
}
