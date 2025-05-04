import Foundation
import Fluent
import SQLKit

actor MessageRepository {
    enum MessageID {
        case before(Int)
        case after(Int)
    }
    
    struct Metadata: Decodable {
        let previousID: Int?
        let nextID: Int?
        
        enum CodingKeys: String, CodingKey {
            case previousID = "previous_id"
            case nextID = "next_id"
        }
    }
    
    private let database: Database
    
    init(database: Database) {
        self.database = database
    }
    
    enum Error: Swift.Error {
        case databaseConversion
        case metadataNotFound
    }
    
    func getMessages(contactID: ContactID,
                     userID: UserID,
                     messageID: MessageID?,
                     limit: Int) async throws -> [Message] {
        if messageID == nil,
           let firstUnreadMessageID = try await firstUnreadMessageID(contactID: contactID, senderIDIsNot: userID) {
            return try await getMessagesWith(
                firstUnreadMessageID: firstUnreadMessageID,
                contactID: contactID,
                limit: limit
            )
        }
        
        return try await sqlDatabase()
            .select()
            .column(SQLLiteral.all)
            .from(
                messageSubquery(
                    contactID: contactID,
                    userID: userID,
                    messageID: messageID,
                    limit: limit
                )
            )
            .orderBy("id", .ascending)
            .all()
            .map(decodeToMessage)
    }
    
    private func messageSubquery(contactID: ContactID,
                                 userID: UserID,
                                 messageID: MessageID?,
                                 limit: Int) async throws -> SQLSubquery {
        var messageSubquery = SQLSubqueryBuilder()
            .column(SQLLiteral.all)
            .from("messages")
            .where("contact_id", .equal, contactID)
        
        messageSubquery = switch messageID {
        case let .before(id):
            messageSubquery
                .where("id", .lessThan, id)
                .orderBy("id", .descending)
        case let .after(id):
            messageSubquery
                .where("id", .greaterThan, id)
                .orderBy("id", .ascending)
        case .none:
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
                    message_id_count_derived_from_middle AS (
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
                            LIMIT \(bind: limit) - (SELECT count FROM message_id_count_derived_from_middle)
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
                WHERE id BETWEEN ifnull((SELECT id FROM lower_bound_message_id), \(bind: firstUnreadMessageID))
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
    
    func getMetadata(from beginMessageID: Int, to endMessageID: Int, contactID: Int) async throws -> Metadata {
        let sql: SQLQueryString = """
            SELECT m1.previous_id, m2.next_id FROM (
                SELECT max(id) AS previous_id, ifnull(contact_id, \(bind: contactID)) AS contact_id FROM messages
                WHERE id < \(bind: beginMessageID)
                AND contact_id = \(bind: contactID)
            ) AS m1
            JOIN (
                SELECT min(id) AS next_id, ifnull(contact_id, \(bind: contactID)) AS contact_id FROM messages
                WHERE id > \(bind: endMessageID)
                AND contact_id = \(bind: contactID)
            ) AS m2
            ON m1.contact_id = m2.contact_id
        """
        
        guard let metadata = try await sqlDatabase()
            .raw(sql)
            .first()?
            .decode(model: Metadata.self) else {
            throw Error.metadataNotFound
        }
        
        return metadata
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
