import Fluent
import Vapor
import SQLKit

struct ContactController: RouteCollection {
    private var defaultLimit: Int { 20 }
    private let avatarDirectoryPath: @Sendable () -> (String)
    
    init(avatarDirectoryPath: @escaping @Sendable () -> String) {
        self.avatarDirectoryPath = avatarDirectoryPath
    }
    
    func boot(routes: RoutesBuilder) throws {
        let protected = routes.grouped("contacts")
            .grouped(AccessTokenGuardMiddleware(), UserAuthenticator())
        
        protected.get(use: index)
        protected.post(use: create)
        
        protected.group(":contact_id") { routes in
            routes.patch("block", use: block)
            routes.patch("unblock", use: unblock)
        }
    }
    
    @Sendable
    private func index(req: Request) async throws -> ContactsResponse {
        let indexRequest = try req.query.decode(ContactIndexRequest.self)
        let currentUserID = try req.auth.require(Payload.self).userID
        return try await contactsResponse(
            for: currentUserID,
            before: indexRequest.before,
            limit: indexRequest.limit,
            req: req
        )
    }
    
    private func contactsResponse(for currentUserID: Int,
                                  before: Date? = nil,
                                  limit: Int? = nil,
                                  req: Request) async throws -> ContactsResponse {
        guard let sql = req.db as? SQLDatabase else {
            throw ContactError.databaseError
        }
        
        let contactTable = SQLQualifiedTable(Contact.schema, space: Contact.space)
        let messageTable = SQLQualifiedTable(Message.schema, space: Message.space)
        
        let contactIDColumn = SQLColumn(SQLLiteral.string("id"), table: contactTable)
        let currentUserIDNumeric = SQLLiteral.numeric("\(currentUserID)")
        
        let createdAtLiteral = SQLLiteral.string("created_at")
        let messageCreatedAtColumn = SQLColumn(createdAtLiteral, table: messageTable)
        let contactCreatedAtColumn = SQLColumn(createdAtLiteral, table: contactTable)
        let maxMessageCreatedAtFunction = SQLFunction("max", args: messageCreatedAtColumn)
        let ifNullCreatedAtFunction = SQLFunction("ifnull", args: maxMessageCreatedAtFunction, contactCreatedAtColumn)
        
        var query = sql.select()
            .column(SQLColumn(SQLLiteral.all, table: contactTable))
            .column(ifNullCreatedAtFunction, as: "last_update")
            .from(contactTable)
            .join(
                messageTable,
                method: SQLJoinMethod.left,
                on: contactIDColumn,
                .equal,
                SQLColumn(SQLLiteral.string("contact_id"), table: messageTable)
            )
            .groupBy(contactIDColumn)
        
        before.map { query = query.having("last_update", .lessThan, $0) }
        
        query = query
            .having(SQLColumn(SQLLiteral.string("user_id1"), table: contactTable), .equal, currentUserIDNumeric)
            .orHaving(SQLColumn(SQLLiteral.string("user_id2"), table: contactTable), .equal, currentUserIDNumeric)
            .orderBy("last_update", .descending)
            .limit(limit ?? defaultLimit)
        
        let contacts = try await query.all().map { try $0.decode(fluentModel: Contact.self) }
        return try await contacts.toResponse(
            currentUserID: currentUserID,
            req: req,
            avatarDirectoryPath: avatarDirectoryPath()
        )
    }
    
    @Sendable
    private func create(req: Request) async throws -> ContactResponse {
        let currentUserID = try req.auth.require(Payload.self).userID
        let contactRequest = try req.content.decode(ContactRequest.self)
        let contact = try await newContact(for: currentUserID, with: contactRequest.responderEmail, on: req.db)
        return try await contact.toResponse(
            currentUserID: currentUserID,
            req: req,
            avatarDirectoryPath: avatarDirectoryPath()
        )
    }
    
    private func newContact(for currentUserID: Int,
                            with responderEmail: String,
                            on db: Database) async throws -> Contact {
        guard let responder = try await User.query(on: db)
            .filter(\.$email == responderEmail)
            .first(), let responderID = try? responder.requireID()
        else {
            throw ContactError.responderNotFound
        }
        
        guard currentUserID != responderID else {
            throw ContactError.responderSameAsCurrentUser
        }
        
        return try await saveNewContact(with: currentUserID, and: responderID, on: db)
    }
    
    private func saveNewContact(with currentUserID: Int,
                                and responderID: Int,
                                on db: Database) async throws -> Contact {
        let contact = if currentUserID < responderID {
            Contact(userID1: currentUserID, userID2: responderID)
        } else {
            Contact(userID1: responderID, userID2: currentUserID)
        }
        try await contact.save(on: db)
        return contact
    }
    
    @Sendable
    private func block(req: Request) async throws -> ContactResponse {
        let contactID = try extractContactID(from: req.parameters)
        let currentUserID = try req.auth.require(Payload.self).userID
        
        guard let contact = try await getContact(for: currentUserID, contactID: contactID, req: req) else {
            throw ContactError.contactNotFound
        }
        
        guard contact.blockedBy == nil else {
            throw ContactError.contactAlreadyBlocked
        }
        
        contact.$blockedBy.id = currentUserID
        try await contact.update(on: req.db)
        
        return try await contact.toResponse(
            currentUserID: currentUserID,
            req: req,
            avatarDirectoryPath: avatarDirectoryPath()
        )
    }
    
    @Sendable func unblock(req: Request) async throws -> ContactResponse {
        let contactID = try extractContactID(from: req.parameters)
        let currentUserID = try req.auth.require(Payload.self).userID
        
        guard let contact = try await getContact(for: currentUserID, contactID: contactID, req: req) else {
            throw ContactError.contactNotFound
        }
        
        guard contact.blockedBy != nil else {
            throw ContactError.contactIsNotBlocked
        }
        
        guard contact.$blockedBy.id == currentUserID else {
            throw ContactError.contactIsNotBlockedByCurrentUser
        }
        
        contact.$blockedBy.id = nil
        try await contact.update(on: req.db)
        
        return try await contact.toResponse(
            currentUserID: currentUserID,
            req: req,
            avatarDirectoryPath: avatarDirectoryPath()
        )
    }
    
    private func extractContactID(from parameters: Parameters) throws -> Int {
        guard let contactIDString = parameters.get("contact_id"), let contactID = Int(contactIDString) else {
            throw ContactError.contactIDInvalid
        }
        
        return contactID
    }
    
    private func getContact(for currentUserID: Int, contactID: Int, req: Request) async throws -> Contact? {
        try await Contact.query(on: req.db)
            .filter(by: currentUserID)
            .filter(\.$id == contactID)
            .with(\.$blockedBy)
            .first()
    }
}

private extension Contact {
    func toResponse(currentUserID: Int, req: Request, avatarDirectoryPath: String) async throws -> ContactResponse {
        guard let lastUpdate = try await lastUpdate(db: req.db) else {
            throw ContactError.databaseError
        }
        
        return try ContactResponse(
            id: requireID(),
            responder: await getResponder(currentUserID: currentUserID, on: req.db)
                .toResponse(
                    app: req.application,
                    avatarDirectoryPath: avatarDirectoryPath
                ),
            blockedByUserID: $blockedBy.id,
            unreadMessageCount: await unreadMessagesCount(currentUserID: currentUserID, db: req.db),
            lastUpdate: lastUpdate
        )
    }
    
    private func getResponder(currentUserID: Int, on db: Database) async throws -> User {
        if $user1.id != currentUserID {
            try await $user1.get(on: db)
        } else {
            try await $user2.get(on: db)
        }
    }
}

private extension [Contact] {
    func toResponse(currentUserID: Int, req: Request, avatarDirectoryPath: String) async throws -> ContactsResponse {
        var contactResponses = [ContactResponse]()
        for contact in self {
            contactResponses.append(try await contact.toResponse(
                currentUserID: currentUserID,
                req: req,
                avatarDirectoryPath: avatarDirectoryPath
            ))
        }
        return ContactsResponse(contacts: contactResponses)
    }
}
