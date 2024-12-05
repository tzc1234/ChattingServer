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
    
    func create(_ contact: Contact) async throws {
        try await contact.create(on: database)
    }
    
    func update(_ contact: Contact) async throws {
        try await contact.update(on: database)
    }
    
    func findBy(id: Int, userID: Int) async throws -> Contact? {
        try await Contact.query(on: database)
            .filter(by: userID)
            .filter(\.$id == id)
            .with(\.$blockedBy)
            .first()
    }
    
    func getUser1From(_ contact: Contact) async throws -> User {
        try await contact.$user1.get(on: database)
    }
    
    func getUser2From(_ contact: Contact) async throws -> User {
        try await contact.$user2.get(on: database)
    }
    
    func lastUpdateFrom(_ contact: Contact) async throws -> Date? {
        try await contact.$messages.query(on: database).max(\.$createdAt) ?? contact.createdAt
    }
    
    func unreadMessagesCountFor(userID: Int, _ contact: Contact) async throws -> Int {
        try await contact.$messages.query(on: database)
            .filter(\.$isRead == false)
            .filter(\.$sender.$id != userID)
            .count()
    }
}

private extension SQLSelectBuilder {
    func having(_ column: String, lessThan date: Date?) -> SQLSelectBuilder {
        guard let date else { return self }
        
        return having(column, .lessThan, date)
    }
}

extension QueryBuilder<Contact> {
    func filter(by userID: Int) -> Self {
        group(.or, { group in
            group.filter(\.$user1.$id == userID).filter(\.$user2.$id == userID)
        })
    }
}
