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
    
    func getContacts(for userID: Int, before: Date?, limit: Int) async throws -> [Contact] {
        let contactTable = SQLQualifiedTable(Contact.schema, space: Contact.space)
        let messageTable = SQLQualifiedTable(Message.schema, space: Message.space)
        
        let contactAllColumns = SQLColumn(SQLLiteral.all, table: contactTable)
        let contactIDColumn = SQLColumn(SQLLiteral.string("id"), table: contactTable)
        let messageContactIDColumn = SQLColumn(SQLLiteral.string("contact_id"), table: messageTable)
        let userIDNumeric = SQLLiteral.numeric("\(userID)")
        
        let createdAtLiteral = SQLLiteral.string("created_at")
        let messageCreatedAtColumn = SQLColumn(createdAtLiteral, table: messageTable)
        let contactCreatedAtColumn = SQLColumn(createdAtLiteral, table: contactTable)
        let maxMessageCreatedAtFunction = SQLFunction("max", args: messageCreatedAtColumn)
        let maxMessageCreatedAtFallbackToContactCreatedAtFunction = SQLFunction("ifnull",
            args: maxMessageCreatedAtFunction, contactCreatedAtColumn
        )
        let lastUpdate = "last_update"
        let contactUserID1Column = SQLColumn(SQLLiteral.string("user_id1"), table: contactTable)
        let contactUserID2Column = SQLColumn(SQLLiteral.string("user_id2"), table: contactTable)
        
        return try await sqlDatabase().select()
            .column(contactAllColumns)
            .column(maxMessageCreatedAtFallbackToContactCreatedAtFunction, as: lastUpdate)
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
            .having(contactUserID1Column, .equal, userIDNumeric)
            .orHaving(contactUserID2Column, .equal, userIDNumeric)
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
    
    func isContactExited(id: Int, withUserID userID: Int) async throws -> Bool {
        try await Contact.query(on: database)
            .filter(by: userID)
            .filter(\.$id == id)
            .count() > 0
    }
    
    func getUser1For(_ contact: Contact) async throws -> User {
        try await contact.$user1.get(on: database)
    }
    
    func getUser2For(_ contact: Contact) async throws -> User {
        try await contact.$user2.get(on: database)
    }
    
    func lastUpdateFor(_ contact: Contact) async throws -> Date? {
        try await contact.$messages.query(on: database).max(\.$createdAt) ?? contact.createdAt
    }
    
    func unreadMessagesCountFor(_ contact: Contact, senderIsNot userID: Int) async throws -> Int {
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
