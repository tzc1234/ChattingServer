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
        let beforeLastUpdate: SQLQueryString = before.map { "AND last_update < \(bind: $0.timeIntervalSince1970)" } ?? ""
        let sql: SQLQueryString = """
            SELECT c.*, ifnull(max(m.created_at), c.created_at) AS last_update
            FROM contacts c
            LEFT JOIN messages m ON m.contact_id = c.id
            GROUP BY c.id
            HAVING (c.user_id1 = \(bind: userID) OR c.user_id2 = \(bind: userID))
            \(beforeLastUpdate)
            ORDER BY last_update DESC
            LIMIT \(bind: limit)
        """
        
        return try await sqlDatabase()
            .raw(sql)
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
    
    func createBy(userID: Int, anotherUserID: Int) async throws -> Contact {
        let contact = if userID < anotherUserID {
            Contact(userID1: userID, userID2: anotherUserID)
        } else {
            Contact(userID1: anotherUserID, userID2: userID)
        }
        try await contact.create(on: database)
        return contact
    }
    
    func update(_ contact: Contact, blockedByUserID: Int?) async throws {
        contact.$blockedBy.id = blockedByUserID
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
    
    func responderFor(_ contact: Contact, by userID: Int) async throws -> User {
        if contact.$user1.id == userID {
            return try await contact.$user2.get(on: database)
        }
        
        return try await contact.$user1.get(on: database)
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
    
    func lastMessageFor(_ contact: Contact, senderIsNot userID: Int) async throws -> Message? {
        if let firstUnreadMessage = try await firstUnreadMessage(contact, senderIsNot: userID) {
            return firstUnreadMessage
        }
        
        return try await contact.$messages.query(on: database)
            .sort(\.$createdAt, .descending)
            .first()
    }
    
    private func firstUnreadMessage(_ contact: Contact, senderIsNot userID: Int) async throws -> Message? {
        try await contact.$messages.query(on: database)
            .filter(\.$isRead == false)
            .filter(\.$sender.$id != userID)
            .first()
    }
}

private extension SQLSelectBuilder {
    func having(_ column: String, lessThan date: Date?) -> SQLSelectBuilder {
        guard let date else { return self }
        
        return having(column, .lessThan, date)
    }
}

private extension QueryBuilder<Contact> {
    func filter(by userID: Int) -> Self {
        group(.or, { group in
            group.filter(\.$user1.$id == userID).filter(\.$user2.$id == userID)
        })
    }
}
