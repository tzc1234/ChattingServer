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
    
    private func decodeToMessage(_ row: SQLRow) throws -> Message {
        try row.decode(fluentModel: Message.self)
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
        } else if let middleMessageID = try await middleMessageID(userID: userID, contactID: contactID, limit: limit) {
            messageSubquery
                .where("id", .greaterThanOrEqual, middleMessageID)
                .orderBy("id", .ascending)
        } else {
            messageSubquery
                .orderBy("id", .descending)
        }
        
        return messageSubquery.limit(limit).query
    }
    
    private func middleMessageID(userID: UserID, contactID: ContactID, limit: Int) async throws -> Int? {
        let middle = limit / 2 + 1
        let middleMessageIDAtLast = SQLSubqueryBuilder()
            .column("id")
            .from("messages")
            .where("id", .lessThanOrEqual, firstUnreadMessageID(userID: userID, contactID: contactID))
            .where("contact_id", .equal, contactID)
            .orderBy("id", .descending)
            .limit(middle)
            .query
        
        let extractMiddleMessageID = try await sqlDatabase().select()
            .column("id")
            .from(middleMessageIDAtLast)
            .orderBy("id", .ascending)
            .limit(1)
            .first()
        
        return try extractMiddleMessageID?.decode(column: "id", inferringAs: Int.self)
    }
    
    private func firstUnreadMessageID(userID: UserID, contactID: ContactID) -> SQLSubquery {
        SQLSubqueryBuilder()
            .column("id")
            .from("messages")
            .where("contact_id", .equal, contactID)
            .where("sender_id", .notEqual, userID)
            .where("is_read", .equal, false)
            .limit(1)
            .query
    }
    
    func updateUnreadMessageToRead(contactID: ContactID, userID: UserID, untilMessageID: Int) async throws {
        try await Message.query(on: database)
            .filter(\.$id <= untilMessageID)
            .filter(\.$contact.$id <= contactID)
            .filter(\.$sender.$id != userID)
            .filter(\.$isRead == false)
            .set(\.$isRead, to: true)
            .update()
    }
    
    private func sqlDatabase() throws(Error) -> SQLDatabase {
        guard let sql = database as? SQLDatabase else { throw .databaseConversion }
        
        return sql
    }
}
