import Foundation
import Fluent
import SQLKit

actor ContactRepository {
    private let database: Database
    
    init(database: Database) {
        self.database = database
    }
    
    enum Error: Swift.Error {
        case databaseConversion
    }
    
    func getContacts(for currentUserID: Int, before: Date?, limit: Int) async throws -> [Contact] {
        let contactTable = SQLQualifiedTable(Contact.schema, space: Contact.space)
        let messageTable = SQLQualifiedTable(Message.schema, space: Message.space)
        
        let contactIDColumn = SQLColumn(SQLLiteral.string("id"), table: contactTable)
        let messageContactIDColumn = SQLColumn(SQLLiteral.string("contact_id"), table: messageTable)
        let currentUserIDNumeric = SQLLiteral.numeric("\(currentUserID)")
        
        let createdAtLiteral = SQLLiteral.string("created_at")
        let messageCreatedAtColumn = SQLColumn(createdAtLiteral, table: messageTable)
        let contactCreatedAtColumn = SQLColumn(createdAtLiteral, table: contactTable)
        let maxMessageCreatedAtFunction = SQLFunction("max", args: messageCreatedAtColumn)
        let ifNullCreatedAtFunction = SQLFunction("ifnull", args: maxMessageCreatedAtFunction, contactCreatedAtColumn)
        let lastUpdate = "last_update"
        
        return try await sqlDatabase().select()
            .column(SQLColumn(SQLLiteral.all, table: contactTable))
            .column(ifNullCreatedAtFunction, as: lastUpdate)
            .from(contactTable)
            .join(
                messageTable,
                method: SQLJoinMethod.left,
                on: contactIDColumn,
                .equal,
                messageContactIDColumn
            )
            .groupBy(contactIDColumn)
            .having(lastUpdate, lessThan: before)
            .having(SQLColumn(SQLLiteral.string("user_id1"), table: contactTable), .equal, currentUserIDNumeric)
            .orHaving(SQLColumn(SQLLiteral.string("user_id2"), table: contactTable), .equal, currentUserIDNumeric)
            .orderBy(lastUpdate, .descending)
            .limit(limit)
            .all()
            .map(decodeToContact)
    }
    
    private func sqlDatabase() throws(Error) -> SQLDatabase {
        guard let sql = database as? SQLDatabase else { throw .databaseConversion }
        
        return sql
    }
    
    private func decodeToContact(_ row: SQLRow) throws -> Contact {
        try row.decode(fluentModel: Contact.self)
    }
}

private extension SQLSelectBuilder {
    func having(_ column: String, lessThan date: Date?) -> SQLSelectBuilder {
        guard let date else { return self }
        
        return having(column, .lessThan, date)
    }
}
