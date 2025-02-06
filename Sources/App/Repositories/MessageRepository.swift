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
        let sql = SQLQueryString.build {
            SQLQueryString.withClause {
                SQLQueryString("""
                    message_id_count_from_middle AS (
                        SELECT count(id) AS count FROM (
                            SELECT id FROM messages
                            WHERE id >= \(bind: firstUnreadMessageID)
                            AND contact_id = \(bind: contactID)
                            LIMIT \(bind: middle)
                        )
                    )
                """)
                SQLQueryString("""
                    lower_bound_message_id AS (
                        SELECT min(id) AS id, count(id) AS count FROM (
                            SELECT id FROM messages
                            WHERE id < \(bind: firstUnreadMessageID)
                            AND contact_id = \(bind: contactID)
                            ORDER BY id DESC
                            LIMIT \(bind: limit) - (SELECT count FROM message_id_count_from_middle)
                        )
                    )
                """)
                SQLQueryString("""
                    upper_bound_message_id AS (
                        SELECT max(id) AS id FROM (
                            SELECT id FROM messages
                            WHERE id >= \(bind: firstUnreadMessageID)
                            AND contact_id = \(bind: contactID)
                            LIMIT \(bind: limit) - (SELECT count FROM lower_bound_message_id)
                        )
                    )
                """)
            }
            
            SQLQueryString("""
                SELECT * FROM messages
                WHERE id BETWEEN ifnull((SELECT id FROM lower_bound_message_id), 1)
                AND (SELECT id FROM upper_bound_message_id)
                AND contact_id = \(bind: contactID)
                ORDER BY id ASC
            """)
        }
        
        return try await sqlDatabase()
            .raw(sql)
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

extension SQLQueryString {
    static func build(@SQLQueryStringBuilder sql: () -> [SQLQueryString]) -> SQLQueryString {
        sql().joined(separator: "\n")
    }
    
    static func withClause(@SQLQueryStringBuilder sql: () -> [SQLQueryString]) -> SQLQueryString {
        "WITH " + sql().joined(separator: ", ")
    }
}

@resultBuilder
enum SQLQueryStringBuilder {
    static func buildBlock(_ components: SQLQueryString...) -> [SQLQueryString] {
        components
    }
}
