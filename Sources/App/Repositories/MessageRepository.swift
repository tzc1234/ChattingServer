import Foundation
import Fluent
import SQLKit

actor MessageRepository {
    private let database: Database
    
    init(database: Database) {
        self.database = database
    }
    
    enum Error: Swift.Error {
        case databaseConversion
    }
    
    func getMessages(contactID: ContactID,
                     userID: UserID,
                     beforeMessageId: Int?,
                     afterMessageId: Int?,
                     limit: Int) async throws -> [Message] {
        if beforeMessageId == nil && afterMessageId == nil,
            let firstUnreadMessageID = try await firstUnreadMessageID(contactID: contactID, senderIDIsNot: userID) {
            return try await getMessagesWith(
                firstUnreadMessageID: firstUnreadMessageID,
                contactID: contactID,
                limit: limit
            )
        }
        
        return try await sqlDatabase().select()
            .column(SQLLiteral.all)
            .from(messageSubquery(
                contactID: contactID,
                userID: userID,
                beforeMessageId: beforeMessageId,
                afterMessageId: afterMessageId,
                limit: limit
            ))
            .orderBy("id", .ascending)
            .all()
            .map(decodeToMessage)
    }
    
    private func messageSubquery(contactID: ContactID,
                                 userID: UserID,
                                 beforeMessageId: Int?,
                                 afterMessageId: Int?,
                                 limit: Int) async throws -> SQLSubquery {
        var messageSubquery = SQLSubqueryBuilder()
            .column(SQLLiteral.all)
            .from("messages")
            .where("contact_id", .equal, contactID)
        
        messageSubquery = if let beforeMessageId {
            messageSubquery
                .where("id", .lessThan, beforeMessageId)
                .orderBy("id", .descending)
        } else if let afterMessageId {
            messageSubquery
                .where("id", .greaterThan, afterMessageId)
                .orderBy("id", .ascending)
        } else {
            messageSubquery
                .orderBy("id", .descending)
        }
        
        return messageSubquery.limit(limit).query
    }
    
    private func getMessagesWith(firstUnreadMessageID: Int, contactID: ContactID, limit: Int) async throws -> [Message] {
        let middle = limit / 2 + 1
        let contactIDClause = "AND contact_id = \(contactID)"
        let maxMessageID = """
            SELECT max(id) AS id, count(id) AS count FROM (
                SELECT id FROM messages
                WHERE id >= \(firstUnreadMessageID)
                \(contactIDClause)
                LIMIT \(middle)
            )
        """
        let minMessageID = """
            SELECT min(id) AS id, count(id) AS count FROM (
                SELECT id FROM messages
                WHERE id < \(firstUnreadMessageID)
                \(contactIDClause)
                ORDER BY id DESC
                LIMIT \(limit) - (SELECT count FROM max_message_id)
            )
        """
        let updatedMaxMessageID = """
            SELECT max(id) AS id FROM (
                SELECT id FROM messages
                WHERE id >= \(firstUnreadMessageID)
                \(contactIDClause)
                LIMIT \(limit) - (SELECT count FROM min_message_id)
            )
        """
        let withClause = """
            WITH max_message_id AS (\(maxMessageID)), min_message_id AS (\(minMessageID)),
            updated_max_message_id AS (\(updatedMaxMessageID))
        """
        let sql = """
            \(withClause)
            SELECT * FROM messages
            WHERE id BETWEEN (SELECT id FROM min_message_id)
            AND (SELECT id FROM updated_max_message_id)
            ORDER BY id ASC
        """
        
        return try await sqlDatabase()
            .raw("\(unsafeRaw: sql)")
            .all()
            .map(decodeToMessage)
    }
    
    private func firstUnreadMessageID(contactID: ContactID, senderIDIsNot userID: UserID) async throws -> Int? {
        try await Message.query(on: database)
            .filter(\.$contact.$id == contactID)
            .filter(\.$sender.$id != userID)
            .filter(\.$isRead == false)
            .first()?
            .id
    }
    
    private func decodeToMessage(_ row: SQLRow) throws -> Message {
        try row.decode(fluentModel: Message.self)
    }
    
    private func sqlDatabase() throws(Error) -> SQLDatabase {
        guard let sql = database as? SQLDatabase else { throw .databaseConversion }
        
        return sql
    }
    
    func updateUnreadMessageToRead(contactID: ContactID, userID: UserID, untilMessageID: Int) async throws {
        try await Message.query(on: database)
            .filter(\.$id <= untilMessageID)
            .filter(\.$contact.$id == contactID)
            .filter(\.$sender.$id != userID)
            .filter(\.$isRead == false)
            .set(\.$isRead, to: true)
            .update()
    }
    
    func create(_ message: Message) async throws {
        try await message.create(on: database)
    }
}
